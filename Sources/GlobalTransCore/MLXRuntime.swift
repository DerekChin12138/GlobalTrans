import Darwin
import Foundation
import MLX

/// Recycles MLX Metal buffers in a bounded pool so unload can actually free them.
///
/// `cacheLimit = 0` hands every unique buffer to the Metal driver, which does not
/// return those heaps to the process after `clearCache()`. A 256 MB pool keeps
/// inference temporaries tracked as `cacheMemory` so `releaseAll()` can drop them.
public enum MLXRuntime {
    public static let cacheLimitBytes = 256 * 1_048_576

    public static func configure() {
        Memory.cacheLimit = cacheLimitBytes
    }

    public static func releaseTemporaries() {
        Stream.gpu.synchronize()
        Memory.cacheLimit = 0
        Memory.clearCache()
        Memory.cacheLimit = cacheLimitBytes
    }

    public static func releaseAll() {
        Stream.gpu.synchronize()
        Memory.cacheLimit = 0
        Memory.clearCache()
        Stream.gpu.synchronize()
        Memory.clearCache()
        malloc_zone_pressure_relief(nil, 0)
        // Leave the limit at 0 until the next job calls configure().
    }

    public static func probe() -> MemorySnapshot {
        Stream.gpu.synchronize()
        let vm = processVM()
        return MemorySnapshot(
            mlxActive: Memory.activeMemory,
            mlxCache: Memory.cacheMemory,
            mlxPeak: Memory.peakMemory,
            footprint: vm.footprint,
            external: vm.external,
            internalBytes: vm.internalBytes,
            resident: vm.resident,
            compressed: vm.compressed
        )
    }
}

public struct MemorySnapshot: Sendable, CustomStringConvertible {
    public var mlxActive: Int
    public var mlxCache: Int
    public var mlxPeak: Int
    public var footprint: Int
    public var external: Int
    public var internalBytes: Int
    public var resident: Int
    public var compressed: Int

    public var description: String {
        "RAM \(Self.mb(footprint)) · ext \(Self.mb(external)) · MLX \(Self.mb(mlxActive))+\(Self.mb(mlxCache))"
    }

    private static func mb(_ bytes: Int) -> String {
        String(format: "%.0fMB", Double(max(bytes, 0)) / 1_048_576)
    }
}

private struct ProcessVM {
    var footprint: Int
    var external: Int
    var internalBytes: Int
    var resident: Int
    var compressed: Int
}

private func processVM() -> ProcessVM {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else {
        return ProcessVM(footprint: 0, external: 0, internalBytes: 0, resident: 0, compressed: 0)
    }
    return ProcessVM(
        footprint: Int(info.phys_footprint),
        external: Int(info.external),
        internalBytes: Int(info.internal),
        resident: Int(info.resident_size),
        compressed: Int(info.compressed)
    )
}
