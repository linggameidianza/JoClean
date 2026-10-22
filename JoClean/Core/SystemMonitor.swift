//
//  SystemMonitor.swift
//  JoClean
//

import Foundation
import Darwin

/// Periodically samples CPU, memory and disk usage for the dashboard and menu bar.
@Observable
final class SystemMonitor {
    private(set) var cpuUsage: Double = 0
    private(set) var memoryUsed: UInt64 = 0
    let memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    private(set) var diskTotal: Int64 = 0
    private(set) var diskAvailable: Int64 = 0

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    var diskUsed: Int64 { max(diskTotal - diskAvailable, 0) }
    var diskFraction: Double { diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0 }

    private var previousTicks: SystemStats.CPUTicks?
    private var lastDiskSample: Date?
    private var samplingTask: Task<Void, Never>?

    func start() {
        guard samplingTask == nil else { return }
        refresh()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Samples the system. Values are rounded and only assigned when they change,
    /// because every assignment to an @Observable property re-renders (and re-animates) the UI.
    func refresh() {
        if let ticks = SystemStats.cpuTicks() {
            if let previous = previousTicks {
                let usage = (ticks.usage(since: previous) * 100).rounded() / 100
                if usage != cpuUsage { cpuUsage = usage }
            }
            previousTicks = ticks
        }

        // Memory to the nearest 10 MB, disk to the nearest 100 MB.
        let memory = SystemStats.memoryUsed() / 10_000_000 * 10_000_000
        if memory != memoryUsed { memoryUsed = memory }

        // The "important usage" capacity query costs ~30 ms on the main thread, and free space
        // changes slowly, so only refresh it every 30 seconds.
        if let lastDiskSample, Date.now.timeIntervalSince(lastDiskSample) < 30 { return }
        lastDiskSample = .now
        if let disk = SystemStats.diskCapacity() {
            if disk.total != diskTotal { diskTotal = disk.total }
            let available = disk.available / 100_000_000 * 100_000_000
            if available != diskAvailable { diskAvailable = available }
        }
    }
}

/// Low-level Mach / file system queries.
nonisolated enum SystemStats {
    struct CPUTicks {
        let busy: UInt64
        let total: UInt64

        /// CPU usage between two samples, from 0 to 1.
        func usage(since previous: CPUTicks) -> Double {
            let totalDelta = total &- previous.total
            guard totalDelta > 0 else { return 0 }
            return Double(busy &- previous.busy) / Double(totalDelta)
        }
    }

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // cpu_ticks order: user, system, idle, nice.
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        return CPUTicks(busy: busy, total: busy + idle)
    }

    /// Memory in use, computed the same way as Activity Monitor ("App Memory" + wired + compressed).
    static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let pages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(pageSize)
    }

    static func diskCapacity() -> (total: Int64, available: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(filePath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return (Int64(total), available)
    }

    /// Physical memory footprint of a process, as shown in Activity Monitor.
    static func memoryFootprint(of pid: pid_t) -> UInt64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : 0
    }
}
