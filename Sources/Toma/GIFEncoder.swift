import Foundation
import AVFoundation
import CoreImage

/// Reads the master sequentially and streams a looping GIF through `GIF`.
///
/// SCK writes frames only when the screen changes, so the master has a variable frame rate.
/// The encoder samples it on a fixed 1/fps clock (latest frame at or before each tick); runs of
/// identical samples become one frame with a longer delay, so static screen time costs nothing.
/// Delays are rounded cumulatively, so any fps keeps exact total timing despite 1/100 s units.
nonisolated enum GIFEncoder {
    @concurrent static func encode(_ clip: Clip, policy: GIFPolicy, to url: URL,
                       progress: @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: clip.master)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw TomaError.exportFailed(underlying: "no video track")
        }
        let natural = try await track.load(.naturalSize)
        guard natural.width.isFinite, natural.height.isFinite, natural.width > 0, natural.height > 0,
              (1...1920).contains(policy.maxLongEdge) else { throw TomaError.exportFailed(underlying: "invalid GIF size") }
        let fit = min(1, CGFloat(policy.maxLongEdge) / max(natural.width, natural.height))
        let width = Int((natural.width * fit).rounded()), height = Int((natural.height * fit).rounded())

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? TomaError.exportFailed(underlying: "reader") }
        defer { reader.cancelReading() }

        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let ci = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB, .cacheIntermediates: false])
        func render(_ buffer: CVPixelBuffer) -> GIF.Frame {
            var image = CIImage(cvPixelBuffer: buffer)
            if fit < 1 {
                image = image.clampedToExtent()
                    .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: fit, kCIInputAspectRatioKey: 1])
            }
            var pixels = [UInt32](repeating: 0, count: width * height)
            pixels.withUnsafeMutableBytes {
                ci.render(image, toBitmap: $0.baseAddress!, rowBytes: width * 4,
                          bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: sRGB)
            }
            return GIF.Frame(pixels: pixels, width: width, height: height)
        }

        guard clip.duration.isFinite, clip.duration > 0, clip.duration <= ResourceBudget.maximumDuration + 10,
              (1...60).contains(policy.framesPerSecond), width > 0, height > 0,
              width <= 1920, height <= 1920 else { throw TomaError.exportFailed(underlying: "invalid GIF dimensions or duration") }
        let fps = Double(policy.framesPerSecond)
        let ticks = max(1, Int((clip.duration * fps).rounded(.up)))
        func centiseconds(_ from: Int, _ to: Int) -> Int {
            Int((Double(to) * 100 / fps).rounded()) - Int((Double(from) * 100 / fps).rounded())
        }

        let writer = try GIF.Writer(url: url, width: width, height: height)
        var completed = false
        defer {
            if !completed { writer.abort(); try? FileManager.default.removeItem(at: url) }
        }
        // Deltas are found in order, then encoded in parallel batches.
        var jobs: [(delta: GIF.Delta, cs: Int)] = []
        func flushJobs() async throws {
            let batch = jobs
            jobs = []
            let encoded = await withTaskGroup(of: (Int, Data).self) { group in
                for (i, job) in batch.enumerated() {
                    group.addTask { (i, GIF.encode(job.delta, centiseconds: job.cs)) }
                }
                var out = [Data](repeating: Data(), count: batch.count)
                for await (i, data) in group { out[i] = data }
                return out
            }
            for data in encoded { try writer.append(data) }
        }

        var differ = GIF.Differ()
        var pending: (delta: GIF.Delta, start: Int)?
        var current: CVPixelBuffer?, drawn: CVPixelBuffer?
        var next = output.copyNextSampleBuffer()
        let batchSize = ResourceBudget.gifBatchSize(width: width, height: height,
                                                     processors: ProcessInfo.processInfo.activeProcessorCount)

        for tick in 0..<ticks {
            try Task.checkCancellation()
            let t = Double(tick) / fps
            while let sample = next, sample.presentationTimeStamp.seconds <= t + 0.0001 {
                if let buffer = sample.imageBuffer { current = buffer }
                next = output.copyNextSampleBuffer()
            }
            if current == nil, let sample = next, let buffer = sample.imageBuffer { current = buffer }
            guard let buffer = current, buffer !== drawn else { continue }
            drawn = buffer

            guard let delta = differ.delta(render(buffer)) else { continue }   // nothing visible changed
            if let p = pending { jobs.append((p.delta, centiseconds(p.start, tick))) }
            pending = (delta, tick)
            if jobs.count >= batchSize {
                try await flushJobs()
                progress(Double(tick) / Double(ticks))
            }
        }
        while next != nil {
            try Task.checkCancellation()
            next = output.copyNextSampleBuffer()
        }
        guard reader.status == .completed, pending != nil else {
            throw reader.error ?? TomaError.exportFailed(underlying: "incomplete GIF source")
        }
        if let p = pending { jobs.append((p.delta, max(2, centiseconds(p.start, ticks)))) }
        try await flushJobs()
        try Task.checkCancellation()
        try writer.finish()
        completed = true
        progress(1)
    }
}
