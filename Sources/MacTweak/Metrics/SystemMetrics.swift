//
//  SystemMetrics.swift
//  MacTweak
//
//  Live CPU + memory sampling straight from the Mach kernel — no shelling out.
//  Drives the dashboard gauges and the rolling sparkline.
//

import Foundation
import Combine
import Darwin

struct MetricPoint: Identifiable {
    let id: Int
    let cpu: Double   // 0...100
    let mem: Double   // 0...100
}

@MainActor
final class SystemMetrics: ObservableObject {

    @Published private(set) var cpuPercent: Double = 0
    @Published private(set) var memUsedBytes: UInt64 = 0
    @Published private(set) var memUsedPercent: Double = 0
    let memTotalBytes: UInt64 = SystemInfo.physicalMemory

    @Published private(set) var history: [MetricPoint] = []
    private var tick = 0
    private let capacity = 90

    private var timer: Timer?
    private var prevTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    func start() {
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
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

        history.append(MetricPoint(id: tick, cpu: cpuPercent, mem: memUsedPercent))
        if history.count > capacity { history.removeFirst(history.count - capacity) }
        tick += 1
    }

    // MARK: - Mach reads

    private func readCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
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
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (memUsedBytes, memTotalBytes) }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = UInt64(pageSize)

        // Activity-Monitor-ish "used": active + wired + compressed.
        let used = (UInt64(stats.active_count)
                    + UInt64(stats.wire_count)
                    + UInt64(stats.compressor_page_count)) * ps
        return (used, memTotalBytes)
    }
}
