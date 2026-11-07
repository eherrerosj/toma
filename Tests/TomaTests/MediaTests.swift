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

}
