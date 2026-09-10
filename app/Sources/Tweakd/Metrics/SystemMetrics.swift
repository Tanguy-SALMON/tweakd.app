//
//  SystemMetrics.swift
//  tweakd
//
//  Live CPU + memory sampling straight from the Mach kernel — no shelling out.
//  Drives the dashboard gauges and the rolling sparkline.
//

import Foundation
import Combine
import Darwin
import IOKit

struct MetricPoint: Identifiable {
    let id: Int
    let time: Date    // real wall-clock stamp, so the chart is a true time series
    let cpu: Double    // 0...100
    let mem: Double    // 0...100
    let gpu: Double    // 0...100
    let netDown: Double   // KB/s — a rate, not a percentage: no fixed ceiling
    let netUp: Double     // KB/s
    /// Thermal pressure as a 0...3 step (nominal · fair · serious · critical).
    /// Not a continuous measure — it is macOS's own coarse state, plotted as a
    /// staircase rather than a curve.
    let thermal: Double
}

@MainActor
final class SystemMetrics: ObservableObject {

    @Published private(set) var cpuPercent: Double = 0
    @Published private(set) var memUsedBytes: UInt64 = 0
    @Published private(set) var memUsedPercent: Double = 0
    let memTotalBytes: UInt64 = SystemInfo.physicalMemory

    /// Integrated GPU busy time, read from the accelerator's own performance
    /// counters. Unlike `powermetrics` this needs no root, so the gauge works
    /// for every user without a password prompt.
    @Published private(set) var gpuPercent: Double = 0
    @Published private(set) var gpuInUseBytes: UInt64 = 0

    /// Thermal pressure, 0...3. Sampled here rather than in `ThermalMonitor` so
    /// it lands on the same tick as everything else and shares one history buffer.
    @Published private(set) var thermalStep: Double = 0

    static func thermalStep(_ s: ProcessInfo.ThermalState) -> Double {
        switch s {
        case .nominal:  return 0
        case .fair:     return 1
        case .serious:  return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }

    /// Live network throughput, summed across physical interfaces (en*) so a
    /// VPN's utun tunnel isn't double-counted with the Wi-Fi/Ethernet it rides on.
    @Published private(set) var netDownKBps: Double = 0
    @Published private(set) var netUpKBps: Double = 0

    @Published private(set) var history: [MetricPoint] = []
    private var tick = 0
    private let capacity = 90

    private var timer: Timer?
    private var prevTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var prevNetSample: (time: Date, rx: UInt64, tx: UInt64)?

    /// `mach_host_self()` returns a send right that must be released or it leaks a
    /// port user-reference on every call. Grab it once for the process lifetime.
    private static let hostPort = mach_host_self()

    /// Page size is constant for the process — read it once, not every sample.
    private static let pageSize: UInt64 = {
        var s: vm_size_t = 0
        host_page_size(hostPort, &s)
        return UInt64(s)
    }()

    /// How many on-screen views currently need live metrics. Sampling only runs
    /// while this is > 0, so a backgrounded/closed window costs nothing — the
    /// gauges were the app's whole CPU footprint when left running.
    private var subscribers = 0

    /// Call from `.onAppear` of any view that displays metrics.
    func retain() {
        subscribers += 1
        start()
    }

    /// Call from `.onDisappear` of the matching view.
    func release() {
        subscribers = max(0, subscribers - 1)
        if subscribers == 0 { stop() }
    }

    private func start() {
        guard timer == nil else { return }
        prevTicks = nil            // first tick after a gap re-establishes a clean delta
        sample()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    func sample() {
        // Smooth bursty CPU with an exponential moving average so the menu-bar
        // panel and the main window converge on the same stable figure instead
        // of catching different instantaneous spikes.
        let rawCPU = readCPU()
        cpuPercent = cpuPercent == 0 ? rawCPU : cpuPercent + (rawCPU - cpuPercent) * 0.5

        let (used, total) = readMemory()
        memUsedBytes = used
        memUsedPercent = total > 0 ? Double(used) / Double(total) * 100 : 0

        // Same EMA treatment as CPU: the accelerator counters are burstier still,
        // so an unsmoothed line reads as noise rather than load.
        let (rawGPU, gpuBytes) = Self.readGPU()
        gpuPercent = gpuPercent == 0 ? rawGPU : gpuPercent + (rawGPU - gpuPercent) * 0.5
        gpuInUseBytes = gpuBytes

        // Network is read before the history append, not after, so each point
        // carries the throughput sampled at its own timestamp — the sparklines in
        // the Download/Upload tiles would otherwise lag the tile value by a tick.
        let (rx, tx) = readNetworkBytes()
        let now = Date()
        if let prev = prevNetSample {
            let dt = now.timeIntervalSince(prev.time)
            if dt > 0 {
                netDownKBps = Double(rx &- prev.rx) / dt / 1024
                netUpKBps = Double(tx &- prev.tx) / dt / 1024
            }
        }
        prevNetSample = (now, rx, tx)

        // Free: a property read on ProcessInfo, no sampling and no privileges.
        // Deliberately NOT per-cluster MHz — that needs `powermetrics` as root,
        // ~300ms a shot, so putting it on this 1s tick would mean a root process
        // every second and a password prompt whenever admin is locked. Frequency
        // stays on-demand in the thermal card.
        thermalStep = Self.thermalStep(ProcessInfo.processInfo.thermalState)

        history.append(MetricPoint(id: tick, time: now, cpu: cpuPercent,
                                   mem: memUsedPercent, gpu: gpuPercent,
                                   netDown: netDownKBps, netUp: netUpKBps,
                                   thermal: thermalStep))
        if history.count > capacity { history.removeFirst(history.count - capacity) }
        tick += 1
    }

    // MARK: - Mach reads

    private func readCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(Self.hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return cpuPercent }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)

        defer { prevTicks = (user, system, idle, nice) }
        guard let prev = prevTicks else { return 0 }

        let dUser = user &- prev.user
        let dSystem = system &- prev.system
        let dIdle = idle &- prev.idle
        let dNice = nice &- prev.nice
        let dTotal = dUser + dSystem + dIdle + dNice
        guard dTotal > 0 else { return cpuPercent }
        return Double(dUser + dSystem + dNice) / Double(dTotal) * 100
    }

    private func readMemory() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(Self.hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (memUsedBytes, memTotalBytes) }

        let ps = Self.pageSize

        // Activity-Monitor-ish "used": active + wired + compressed.
        let used = (UInt64(stats.active_count)
                    + UInt64(stats.wire_count)
                    + UInt64(stats.compressor_page_count)) * ps
        return (used, memTotalBytes)
    }

    /// Total bytes sent/received across physical network interfaces, straight
    /// from the BSD interface list — no shelling out to `netstat`.
    private func readNetworkBytes() -> (rx: UInt64, tx: UInt64) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(first) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let ifa = cur.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard String(cString: ifa.ifa_name).hasPrefix("en") else { continue }
            guard let dataPtr = ifa.ifa_data else { continue }
            let data = dataPtr.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
            rx += UInt64(data.ifi_ibytes)
            tx += UInt64(data.ifi_obytes)
        }
        return (rx, tx)
    }
}

// MARK: - GPU

extension SystemMetrics {

    /// Busy percentage and in-use GPU memory, from `AGXAccelerator`'s
    /// `PerformanceStatistics` dictionary in the IO registry.
    ///
    /// This is the same counter Activity Monitor and `mactop` show. It is
    /// readable without root, which `powermetrics --samplers gpu_power` is not —
    /// the whole point of using it here is that the gauge never has to prompt.
    ///
    /// Returns `(0, 0)` on anything unexpected rather than throwing: a missing
    /// GPU counter should flatten the chart, not take down sampling for CPU
    /// and memory alongside it.
    nonisolated static func readGPU() -> (percent: Double, inUseBytes: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AGXAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(
                entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            // "Device Utilization %" is the whole-device figure; the separate
            // Renderer/Tiler counters are per-stage and would double-count.
            let percent = (stats["Device Utilization %"] as? NSNumber)?.doubleValue ?? 0
            let bytes = (stats["In use system memory"] as? NSNumber)?.uint64Value ?? 0
            return (min(max(percent, 0), 100), bytes)
        }
        return (0, 0)
    }
}
