import Foundation
import Darwin
import PerformanceDomain

/// Read-only adapters. No subprocesses, permissions changes, file scans, or process actions.
public struct MacPerformanceSampler: PerformanceSampler {
    public init() {}

    public func readSystem() async -> RawSystemSample {
        await Task.detached(priority: .utility) { Self.systemSample() }.value
    }

    public func readProcesses() async -> RawProcessSample {
        await Task.detached(priority: .utility) { Self.processSample() }.value
    }

    public func readStartupVolume() async -> VolumeSnapshot {
        await Task.detached(priority: .utility) { Self.volumeSample() }.value
    }

    private static func systemSample() -> RawSystemSample {
        let date = Date()
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var cpu = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        let ticks: Metric<CPUTickValues>
        if cpuResult == KERN_SUCCESS {
            ticks = .measured(.init(user: UInt64(cpu.cpu_ticks.0), system: UInt64(cpu.cpu_ticks.1),
                                    idle: UInt64(cpu.cpu_ticks.2), nice: UInt64(cpu.cpu_ticks.3)), at: date, source: "host_statistics")
        } else {
            ticks = .unavailable(.failed, source: "host_statistics", reason: "系统CPU计数读取失败（\(cpuResult)）")
        }

        var vm = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let memoryResult = withUnsafeMutablePointer(to: &vm) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        let used: Metric<UInt64>
        if memoryResult == KERN_SUCCESS && pageResult == KERN_SUCCESS {
            let pages = UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            let (bytes, overflow) = pages.multipliedReportingOverflow(by: UInt64(pageSize))
            used = overflow ? .unavailable(.failed, source: "host_statistics64:active+wired+compressed", reason: "内存计量溢出")
                : .measured(bytes, at: date, source: "host_statistics64:active+wired+compressed")
        } else {
            used = .unavailable(.failed, source: "host_statistics64:active+wired+compressed", reason: "系统内存读取失败")
        }
        // Internal sysctl pressure codes differ from notification flags across OS versions.
        // Do not manufacture a pressure percentage from used/total or guess the mapping.
        let pressure: Metric<MemoryPressure> = .unavailable(.unsupported, source: "memory-pressure",
                                                          reason: "当前版本未验证系统压力等级来源；使用量不代表压力")
        return .init(ticks: ticks, memoryUsedBytes: used,
                     memoryTotalBytes: .measured(ProcessInfo.processInfo.physicalMemory, at: date, source: "physicalMemory"), pressure: pressure)
    }

    private static func processSample() -> RawProcessSample {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let hint = proc_listallpids(nil, 0)
        var capacity = min(65_536, max(256, Int(hint) + 256))
        var ids: [Int32] = []
        var issue: String?
        for _ in 0..<4 {
            var buffer = [Int32](repeating: 0, count: capacity)
            let found = buffer.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
            if found < 0 { issue = "进程列表读取失败"; break }
            ids = Array(buffer.prefix(min(Int(found), capacity))).filter { $0 > 0 }
            if found < capacity { issue = nil; break }
            if capacity == 65_536 { issue = "进程列表超出采集上限，覆盖不完整"; break }
            capacity = min(65_536, capacity * 2)
            issue = "进程列表在采样时变化，覆盖可能不完整"
        }
        var rows: [RawProcess] = []
        rows.reserveCapacity(ids.count)
        for pid in ids {
            var usage = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &usage) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            let usageError = errno
            var nameBytes = [CChar](repeating: 0, count: 1024)
            let length = nameBytes.withUnsafeMutableBytes { proc_name(pid, $0.baseAddress, UInt32($0.count)) }
            let name = length > 0 ? String(decoding: nameBytes.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self).trimmingCharacters(in: .controlCharacters) : "进程 \(pid)"
            if result == 0 {
                // XNU fill_task_rusage obtains task_power_info's Mach absolute CPU times.
                // Convert exactly once here; Core receives nanoseconds, never Mach ticks.
                let total = Double(usage.ri_user_time) + Double(usage.ri_system_time)
                let ns = timebase.denom > 0 ? total * Double(timebase.numer) / Double(timebase.denom) : .nan
                let identity = usage.ri_proc_start_abstime > 0 ? ProcessIdentity(pid: pid, startToken: usage.ri_proc_start_abstime) : nil
                let date = Date()
                rows.append(.init(pid: pid, identity: identity, name: name,
                                  cpuNanoseconds: ns.isFinite && ns >= 0 && ns < Double(UInt64.max) ? UInt64(ns) : nil,
                                  residentBytes: .measured(usage.ri_resident_size, at: date, source: "proc_pid_rusage"),
                                  footprintBytes: .measured(usage.ri_phys_footprint, at: date, source: "proc_pid_rusage")))
            } else {
                let denied = usageError == EPERM || usageError == EACCES
                let reason = denied ? "进程访问受限" : "进程已退出或采集失败"
                let quality: MetricQuality = denied ? .permissionDenied : .unknown
                rows.append(.init(pid: pid, identity: nil, name: name, cpuNanoseconds: nil,
                                  residentBytes: .unavailable(quality, source: "proc_pid_rusage", reason: reason),
                                  footprintBytes: .unavailable(quality, source: "proc_pid_rusage", reason: reason)))
            }
        }
        let monotonic = Double(mach_absolute_time()) * Double(timebase.numer) / Double(max(1, timebase.denom))
        return .init(processes: rows, monotonicNanoseconds: UInt64(monotonic), sampledAt: Date(), issue: issue)
    }

    private static func volumeSample() -> VolumeSnapshot {
        let path = FileManager.default.fileExists(atPath: "/System/Volumes/Data") ? "/System/Volumes/Data" : "/"
        let url = URL(fileURLWithPath: path)
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeUUIDStringKey])
            guard let available = values.volumeAvailableCapacity, let total = values.volumeTotalCapacity,
                  available >= 0, total > 0 else { throw CocoaError(.fileReadUnknown) }
            return .init(volumeID: values.volumeUUIDString,
                         availableBytes: .measured(UInt64(available), at: Date(), source: "volumeAvailableCapacity"),
                         totalBytes: .measured(UInt64(total), at: Date(), source: "volumeTotalCapacity"))
        } catch {
            return .init(volumeID: nil,
                         availableBytes: .unavailable(.failed, source: "volumeAvailableCapacity", reason: "启动卷空间读取失败"),
                         totalBytes: .unavailable(.failed, source: "volumeTotalCapacity", reason: "启动卷容量读取失败"))
        }
    }
}
