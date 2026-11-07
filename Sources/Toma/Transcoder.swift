import Foundation
import AVFoundation

/// Re-encodes the master into a lighter video. Quality-targeted (not bitrate-targeted) hardware
/// encoding: static screens cost almost nothing, text stays sharp. Measured on a 4 s scrolling
/// test at 1120×720: master 2.5 MB → MP4 ≈ 1.1 MB, HEVC ≈ 0.7 MB. All audio tracks (Mac sound,
/// microphone) are mixed into one AAC track, because many players only play the first track.
nonisolated enum Transcoder {
    @concurrent static func run(_ source: URL, to url: URL, format: Format,
                    progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw TomaError.exportFailed(underlying: "no video track")
        }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        let size = try await video.load(.naturalSize)
        let colors = try await video.load(.formatDescriptions).first.map(colorProperties) ?? [:]

        let reader = try AVAssetReader(asset: asset)
        let videoOut = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOut.alwaysCopiesSampleData = false
        reader.add(videoOut)
        var audioOut: AVAssetReaderAudioMixOutput?
        if !audio.isEmpty {
            let out = AVAssetReaderAudioMixOutput(audioTracks: audio, audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(out)
            audioOut = out
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: format == .hevc ? .mov : .mp4)
        var compression: [String: Any] = [
            AVVideoQualityKey: format == .hevc ? 0.55 : 0.6,
            AVVideoExpectedSourceFrameRateKey: 60,
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
        ]
        if format == .mp4 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: format == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: compression,
        ]
        if !colors.isEmpty { videoSettings[AVVideoColorPropertiesKey] = colors }
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoIn.expectsMediaDataInRealTime = false
        writer.add(videoIn)
        var audioIn: AVAssetWriterInput?
        if audioOut != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioIn = input
        }

        guard reader.startReading(), writer.startWriting() else {
            throw writer.error ?? reader.error ?? TomaError.exportFailed(underlying: "transcode start")
        }
        writer.startSession(atSourceTime: .zero)

        let pump = Pump(reader: reader, writer: writer)
        let videoPair = UncheckedBox((videoOut as AVAssetReaderOutput, videoIn))
        let audioPair = audioOut.flatMap { out in audioIn.map { UncheckedBox((out as AVAssetReaderOutput, $0)) } }
        do {
        try await withTaskCancellationHandler {
            async let v: Void = pump.drain(videoPair, label: "toma.video") { time in
                if duration > 0 { progress(min(1, time / duration)) }
            }
            async let a: Void = {
                if let audioPair { try await pump.drain(audioPair, label: "toma.audio") { _ in } }
            }()
            _ = try await (v, a)
        } onCancel: {
            pump.cancel()
        }
        } catch {
            pump.cancel()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        if Task.isCancelled || reader.status == .cancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        let finished = OneShot<Bool>()
        writer.finishWriting { finished.resolve(true) }
        do { _ = try await finished.wait(timeout: .seconds(30)) }
        catch { pump.cancel(); throw error }
        guard writer.status == .completed, reader.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw writer.error ?? reader.error ?? TomaError.exportFailed(underlying: "transcode")
        }
        progress(1)
    }

    /// The master's colour tags, carried over so the re-encode looks identical.
    private static func colorProperties(_ description: CMFormatDescription) -> [String: String] {
        let pairs: [(CFString, String)] = [
            (kCMFormatDescriptionExtension_ColorPrimaries, AVVideoColorPrimariesKey),
            (kCMFormatDescriptionExtension_TransferFunction, AVVideoTransferFunctionKey),
            (kCMFormatDescriptionExtension_YCbCrMatrix, AVVideoYCbCrMatrixKey),
        ]
        var out: [String: String] = [:]
        for (key, name) in pairs {
            if let value = CMFormatDescriptionGetExtension(description, extensionKey: key) as? String { out[name] = value }
        }
        return out.count == 3 ? out : [:]   // AVFoundation wants all three or none
    }

    private final class Pump: @unchecked Sendable {
        private let reader: AVAssetReader
        private let writer: AVAssetWriter
        init(reader: AVAssetReader, writer: AVAssetWriter) {
            self.reader = reader
            self.writer = writer
        }

        func cancel() { reader.cancelReading(); writer.cancelWriting() }

        func drain(_ box: UncheckedBox<(AVAssetReaderOutput, AVAssetWriterInput)>, label: String,
                   time: @escaping @Sendable (Double) -> Void) async throws {
            let (output, input) = box.value
            defer { input.markAsFinished() }
            while true {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    if reader.status == .completed { return }
                    guard writer.status == .writing, reader.status == .reading else {
                        throw writer.error ?? reader.error ?? CancellationError()
                    }
                    try await Task.sleep(for: .milliseconds(2))
                }
                guard let sample = output.copyNextSampleBuffer() else { return }
                guard input.append(sample) else { throw writer.error ?? TomaError.exportFailed(underlying: "append failed") }
                time(sample.presentationTimeStamp.seconds)
            }
        }
    }
}

private nonisolated struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

