import Foundation
import MLX

/// Caps MLX's Metal buffer cache. The default equals the process memory limit,
/// which on a 16 GB Mac can leave several GB of unused buffers after one job.
public enum MLXRuntime {
    public static let cacheLimitBytes = 512 * 1024 * 1024

    public static func configure() {
        Memory.cacheLimit = cacheLimitBytes
    }

    public static func releaseTemporaries() {
        Memory.clearCache()
    }
}
