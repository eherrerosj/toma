import Foundation

nonisolated enum ResourceBudget {
    static let minimumFreeBytes: Int64 = 256 * 1024 * 1024
    static let maximumRecordingBytes: Int64 = 4 * 1024 * 1024 * 1024
    static let maximumDuration: Double = 3600

    static func availableBytes(at url: URL) throws -> Int64 {
        let values = try FileManager.default.attributesOfFileSystem(forPath: url.path)
        guard let bytes = values[.systemFreeSize] as? NSNumber else { throw CocoaError(.fileReadUnknown) }
        return bytes.int64Value
    }

    static func stopReason(elapsed: Double, bytes: Int64, available: Int64) -> String? {
        if available < minimumFreeBytes { return "Recording stopped because free disk space is low." }
        if bytes >= maximumRecordingBytes { return "Recording stopped at the 4 GB safety limit." }
        if elapsed >= maximumDuration { return "Recording stopped at the one-hour safety limit." }
        return nil
    }

    static func gifBatchSize(width: Int, height: Int, processors: Int) -> Int {
        let bytesPerJob = max(1, width * height) * 32 + 8 * 1024 * 1024
        let memoryLimit = max(1, (128 * 1024 * 1024) / bytesPerJob)
        return max(1, min(4, processors, memoryLimit))
    }
}
