import AVFoundation

nonisolated struct ClipTrim: Sendable, Equatable {
    let start: Double
    let end: Double
    var duration: Double { end - start }
    var timeRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 60_000),
                    end: CMTime(seconds: end, preferredTimescale: 60_000))
    }

    init?(start: Double, end: Double, duration: Double) {
        guard start.isFinite, end.isFinite, duration.isFinite,
              start >= 0, end <= duration, end - start >= 0.1 else { return nil }
        self.start = start
        self.end = end
    }

    // Normalize all tracks to zero once, so video and GIF exports share identical timing.
    static func asset(_ source: URL, trim: ClipTrim?) async throws -> AVAsset {
        let asset = AVURLAsset(url: source)
        guard let trim else { return asset }
        let duration = try await asset.load(.duration).seconds
        guard ClipTrim(start: trim.start, end: trim.end, duration: duration) != nil else {
            throw TomaError.exportFailed(underlying: "invalid trim range")
        }
        let composition = AVMutableComposition()
        for type in [AVMediaType.video, .audio] {
            for track in try await asset.loadTracks(withMediaType: type) {
                let intersection = CMTimeRangeGetIntersection(trim.timeRange, otherRange: try await track.load(.timeRange))
                guard intersection.duration.seconds > 0 else { continue }
                guard let output = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw TomaError.exportFailed(underlying: "could not create trim track")
                }
                try output.insertTimeRange(intersection, of: track, at: intersection.start - trim.timeRange.start)
                if type == .video { output.preferredTransform = try await track.load(.preferredTransform) }
            }
        }
        return composition
    }
}
