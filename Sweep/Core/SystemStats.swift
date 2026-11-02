import Darwin
import Foundation

/// Memory figures matching Activity Monitor's Memory tab.
struct MemoryStats: Sendable {
    let total: Int64
    let app: Int64
    let wired: Int64
    let compressed: Int64
    let cachedFiles: Int64
    let free: Int64

    var used: Int64 { app + wired + compressed }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> MemoryStats? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = Int64(getpagesize())
        let internalPages = Int64(info.internal_page_count)
        let purgeable = Int64(info.purgeable_count)
        return MemoryStats(
            total: Int64(ProcessInfo.processInfo.physicalMemory),
            app: (internalPages - purgeable) * page,
            wired: Int64(info.wire_count) * page,
            compressed: Int64(info.compressor_page_count) * page,
            cachedFiles: (Int64(info.external_page_count) + purgeable) * page,
            free: Int64(info.free_count) * page
        )
    }
}

/// Total CPU load, computed from the difference between two tick samples.
struct CPUSampler: Sendable {
    private var previous: host_cpu_load_info?

    /// Fraction of CPU time spent busy since the previous call (0...1).
    mutating func sample() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        defer { previous = info }
        guard let previous else { return nil }

        let ticks = { (load: host_cpu_load_info) -> (busy: Double, total: Double) in
            let user = Double(load.cpu_ticks.0), system = Double(load.cpu_ticks.1)
            let idle = Double(load.cpu_ticks.2), nice = Double(load.cpu_ticks.3)
            return (user + system + nice, user + system + idle + nice)
        }
        let now = ticks(info), before = ticks(previous)
        let total = now.total - before.total
        return total > 0 ? (now.busy - before.busy) / total : nil
    }
}

/// Capacity of the startup disk.
struct DiskStats: Sendable {
    let total: Int64
    /// Free space including purgeable data macOS can reclaim on demand.
    let available: Int64

    var used: Int64 { total - available }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskStats? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(filePath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return DiskStats(total: Int64(total), available: available)
    }
}
