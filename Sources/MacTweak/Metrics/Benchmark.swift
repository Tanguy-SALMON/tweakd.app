//
//  Benchmark.swift
//  MacTweak
//
//  Small, honest micro-benchmarks so you can measure the gain from a tweak.
//  Run a baseline, apply tweaks, run again — the Benchmark view diffs them.
//  Scores are normalized so higher is always better.
//

import Foundation

struct BenchmarkResult: Identifiable, Equatable {
    let id: Int
    let label: String
    let singleCore: Double     // Mops/s
    let multiCore: Double      // Mops/s
    let memoryBandwidth: Double // MB/s
    let disk: Double            // MB/s

    /// A single blended figure of merit.
    var overall: Double {
        // Weighted, scaled into a friendly ~0–2000 range.
        singleCore * 4 + multiCore * 1.5 + memoryBandwidth * 0.02 + disk * 0.05
    }
}

/// Defeats the optimizer so timed loops actually run.
enum BenchSink { nonisolated(unsafe) static var value: Double = 0 }

@MainActor
final class BenchmarkEngine: ObservableObject {
    @Published private(set) var results: [BenchmarkResult] = []
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentTask: String = ""
    private var counter = 0

    var latest: BenchmarkResult? { results.last }
    var baseline: BenchmarkResult? { results.first }

    func run(label: String) async {
        guard !isRunning else { return }
        isRunning = true
        progress = 0
        defer { isRunning = false; currentTask = "" }

        currentTask = "Single-core CPU"
        let sc = await Task.detached(priority: .userInitiated) { Bench.singleCore() }.value
        progress = 0.25

        currentTask = "Multi-core CPU"
        let mc = await Task.detached(priority: .userInitiated) { Bench.multiCore() }.value
        progress = 0.5

        currentTask = "Memory bandwidth"
        let mb = await Task.detached(priority: .userInitiated) { Bench.memoryBandwidth() }.value
        progress = 0.75

        currentTask = "Disk I/O"
        let dk = await Task.detached(priority: .userInitiated) { Bench.disk() }.value
        progress = 1

        counter += 1
        results.append(BenchmarkResult(id: counter, label: label,
                                       singleCore: sc, multiCore: mc,
                                       memoryBandwidth: mb, disk: dk))
    }

    func clear() { results.removeAll() }

    func nextLabel() -> String {
        switch results.count {
        case 0: return "Baseline"
        case 1: return "After tweaks"
        default: return "Run \(results.count + 1)"
        }
    }
}

// MARK: - Workloads (pure, run off the main actor)

enum Bench {

    private static func seconds(_ block: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000
    }

    static func singleCore() -> Double {
        let iterations = 30_000_000
        var acc = 0.0
        let secs = seconds {
            var x = 1.0
            for i in 1...iterations {
                x = (x + Double(i)).squareRoot()
                acc += x.truncatingRemainder(dividingBy: 7.0)
            }
        }
        BenchSink.value += acc
        return secs > 0 ? Double(iterations) / secs / 1_000_000 : 0
    }

    static func multiCore() -> Double {
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let perCore = 15_000_000
        let total = perCore * cores
        let partials = UnsafeMutableBufferPointer<Double>.allocate(capacity: cores)
        partials.initialize(repeating: 0)
        defer { partials.deallocate() }

        let secs = seconds {
            DispatchQueue.concurrentPerform(iterations: cores) { c in
                var x = Double(c + 1)
                var acc = 0.0
                for i in 1...perCore {
                    x = (x + Double(i)).squareRoot()
                    acc += x.truncatingRemainder(dividingBy: 7.0)
                }
                partials[c] = acc
            }
        }
        BenchSink.value += partials.reduce(0, +)
        return secs > 0 ? Double(total) / secs / 1_000_000 : 0
    }

    static func memoryBandwidth() -> Double {
        let bytes = 256 * 1024 * 1024
        let count = bytes / MemoryLayout<Int>.stride
        let src = UnsafeMutableBufferPointer<Int>.allocate(capacity: count)
        let dst = UnsafeMutableBufferPointer<Int>.allocate(capacity: count)
        src.initialize(repeating: 0x5A5A5A5A)
        dst.initialize(repeating: 0)
        defer { src.deallocate(); dst.deallocate() }

        let passes = 6
        let secs = seconds {
            for _ in 0..<passes {
                memcpy(dst.baseAddress!, src.baseAddress!, bytes)
            }
        }
        BenchSink.value += Double(dst[0])
        let movedMB = Double(bytes * passes) / (1024 * 1024)
        return secs > 0 ? movedMB / secs : 0
    }

    static func disk() -> Double {
        let sizeMB = 128
        let bytes = sizeMB * 1024 * 1024
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mactweak-bench-\(getpid()).bin")
        let data = Data(count: bytes)
        defer { try? FileManager.default.removeItem(at: url) }

        var writeSecs = 0.0, readSecs = 0.0
        do {
            writeSecs = seconds {
                try? data.write(to: url, options: .atomic)
            }
            readSecs = seconds {
                if let fh = try? FileHandle(forReadingFrom: url) {
                    let read = try? fh.readToEnd()
                    BenchSink.value += Double(read?.count ?? 0)
                    try? fh.close()
                }
            }
        }
        let totalSecs = writeSecs + readSecs
        guard totalSecs > 0 else { return 0 }
        return Double(sizeMB * 2) / totalSecs   // MB/s over write+read
    }
}
