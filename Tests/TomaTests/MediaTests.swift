import AppKit
import AVFoundation
import ImageIO
import Testing
@testable import Toma

@Suite(.serialized) struct MediaTests {
    func movie(in folder: URL) async throws -> URL {
        let url = folder.appendingPathComponent("fixture-\(UUID()).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
            AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 1],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for i in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixel = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixel, [])
            let ptr = try #require(CVPixelBufferGetBaseAddress(pixel))
            memset(ptr, Int32((i * 17) % 255), CVPixelBufferGetDataSize(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            #expect(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(i), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }

    func clip(_ url: URL) throws -> Clip {
        let region = try #require(ScreenRegion(dragged: CGRect(x: 0, y: 0, width: 64, height: 64),
                                              displayFrame: CGRect(x: 0, y: 0, width: 64, height: 64), scale: 1, displayID: 1))
        return Clip(master: url, duration: 2, region: region)
    }

    @Test func exportsAllFormatsAndRetainsMasterAfterFailedMove() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("toma-media-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalStore = Library.storage
        Library.storage = RecordingStorage(root: root)
        defer { Library.storage = originalStore; try? FileManager.default.removeItem(at: root) }
        let fixture = try await movie(in: root)
        for format in Format.allCases {
            let master = try Library.storage.newMasterURL()
            try FileManager.default.copyItem(at: fixture, to: master)
            let destination = root.appendingPathComponent("export.\(format.fileExtension)")
            try await Library.save(clip(master), as: format, to: destination)
            #expect(!FileManager.default.fileExists(atPath: master.path))
            if format == .gif {
                let source = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
                #expect(CGImageSourceGetCount(source) > 0)
                #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
            } else {
                let asset = AVURLAsset(url: destination)
                #expect(try await asset.load(.duration).seconds > 1.8)
                #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
            }
        }
        let master = try Library.storage.newMasterURL()
        try FileManager.default.copyItem(at: fixture, to: master)
        await #expect(throws: (any Error).self) {
            try await Library.save(clip(master), as: .mp4, to: root.appendingPathComponent("missing/recording.mp4"))
        }
        #expect(FileManager.default.fileExists(atPath: master.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: Library.storage.scratch.path).isEmpty)
    }

    @Test func truncatedMediaCannotBecomeASuccessfulFrozenGIF() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("toma-truncated-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalStore = Library.storage
        Library.storage = RecordingStorage(root: root)
        defer { Library.storage = originalStore; try? FileManager.default.removeItem(at: root) }
        let source = try await movie(in: root)
        let data = try Data(contentsOf: source)
        var offset = 0
        var cut: Int?
        while offset + 8 < data.count {
            var size = data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
            var header = 8
            if size == 1, offset + 16 <= data.count {
                size = data[offset + 8..<offset + 16].reduce(0) { ($0 << 8) | Int($1) }
                header = 16
            }
            if size == 0 { size = data.count - offset }
            guard size >= header, offset + size <= data.count else { break }
            if String(decoding: data[offset + 4..<offset + 8], as: UTF8.self) == "mdat" {
                cut = offset + header + (size - header) / 2
                break
            }
            offset += size
        }
        let master = try Library.storage.newMasterURL()
        try data.prefix(try #require(cut)).write(to: master)
        let target = root.appendingPathComponent("broken.gif")
        await #expect(throws: (any Error).self) { try await Library.save(clip(master), as: .gif, to: target) }
        #expect(FileManager.default.fileExists(atPath: master.path))
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }
    @Test func copyingUsesAPrivatePasteboardAndCancellationPreservesTheMaster() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("toma-copy-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalStore = Library.storage
        Library.storage = RecordingStorage(root: root)
        defer { Library.storage = originalStore; try? FileManager.default.removeItem(at: root) }
        let fixture = try await movie(in: root)
        let master = try Library.storage.newMasterURL()
        try FileManager.default.copyItem(at: fixture, to: master)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try await Library.copy(clip(master), as: .mp4, pasteboard: board)
        #expect(board.readObjects(forClasses: [NSURL.self])?.count == 1)
        #expect(!FileManager.default.fileExists(atPath: master.path))
        let interrupted = try Library.storage.newMasterURL()
        try FileManager.default.copyItem(at: fixture, to: interrupted)
        let recording = try clip(interrupted)
        let task = Task { try await Library.save(recording, as: .gif, to: root.appendingPathComponent("cancelled.gif")) }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(FileManager.default.fileExists(atPath: interrupted.path))
    }

    @Test func systemAndMicrophoneTracksExportAsOneAACTrack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("toma-audio-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let video = AVURLAsset(url: try await movie(in: root))
        let soundURL = root.appendingPathComponent("tone.caf")
        try writeTone(to: soundURL)
        let sound = AVURLAsset(url: soundURL)
        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: CMTime(value: 19, timescale: 10))
        let videoTrack = try #require(try await video.loadTracks(withMediaType: .video).first)
        let audioTrack = try #require(try await sound.loadTracks(withMediaType: .audio).first)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: videoTrack, at: .zero)
        for _ in 0..<2 {
            try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
                .insertTimeRange(range, of: audioTrack, at: .zero)
        }
        let session = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        let master = root.appendingPathComponent("two-audio-tracks.mov")
        try await session.export(to: master, as: .mov)
        for format in [Format.mp4, .hevc] {
            let target = root.appendingPathComponent("mixed.\(format.fileExtension)")
            try await Transcoder.run(master, to: target, format: format, progress: { _ in })
            let result = AVURLAsset(url: target)
            let tracks = try await result.loadTracks(withMediaType: .audio)
            #expect(tracks.count == 1)
            let descriptions = try await #require(tracks.first).load(.formatDescriptions)
            #expect(descriptions.first.map { CMFormatDescriptionGetMediaSubType($0) } == kAudioFormatMPEG4AAC)
            #expect(try await result.load(.duration).seconds > 1.8)
        }
        let trimmed = root.appending(path: "trimmed-audio.mp4")
        let trim = try #require(ClipTrim(start: 0.4, end: 1.4, duration: 1.9))
        try await Transcoder.run(master, to: trimmed, format: .mp4, trim: trim, progress: { _ in })
        let result = AVURLAsset(url: trimmed)
        #expect(try await result.loadTracks(withMediaType: .audio).count == 1)
        #expect(abs(try await result.load(.duration).seconds - 1) < 0.07)
    }

    private func writeTone(to url: URL) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let samples = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
        samples.frameLength = samples.frameCapacity
        let channel = try #require(samples.floatChannelData?.pointee)
        for i in 0..<Int(samples.frameLength) { channel[i] = Float(sin(Double(i) * 2 * .pi * 440 / 48_000)) * 0.05 }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: samples)
    }

    @Test func trimmingInvalidatesAnAlreadyPreparedFullExport() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "toma-prepared-trim-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = Library.storage
        Library.storage = RecordingStorage(root: root)
        defer { Library.storage = previous; try? FileManager.default.removeItem(at: root) }
        let source = try await movie(in: root)
        var selected = try clip(source)
        Library.prepare(selected, as: .mp4)
        let range = try #require(ClipTrim(start: 0.4, end: 1.4, duration: selected.duration))
        selected.trim = range
        let destination = root.appending(path: "trimmed.mp4")
        try await Library.save(selected, as: .mp4, to: destination)
        #expect(abs(try await AVURLAsset(url: destination).load(.duration).seconds - 1) < 0.07)
    }

}
