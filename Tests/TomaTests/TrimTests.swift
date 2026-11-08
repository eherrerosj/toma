import AVFoundation
import Foundation
import ImageIO
import Testing
@testable import Toma

@Suite struct TrimTests {
    @Test func rejectsInvalidRanges() {
        for (start, end) in [(Double.nan, 1.0), (0, Double.infinity), (-1, 1), (1, 1), (2, 1), (0, 3)] {
            #expect(ClipTrim(start: start, end: end, duration: 2) == nil)
        }
        #expect(ClipTrim(start: 0.5, end: 1.5, duration: 2)?.duration == 1)
    }

    @Test func trimmedExportsUseSameRangeAndPreserveOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "toma-trim-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures = MediaTests()
        let source = try await fixtures.movie(in: root)
        let original = try Data(contentsOf: source)
        let clip = try fixtures.clip(source)
        let range = try #require(ClipTrim(start: 0.5, end: 1.5, duration: clip.duration))
        for format in Format.allCases {
            let target = root.appending(path: "trimmed.\(format.fileExtension)")
            if format == .gif {
                let trimmed = Clip(master: source, duration: clip.duration, region: clip.region, trim: range)
                try await GIFEncoder.encode(trimmed, policy: GIFPolicy(framesPerSecond: 10, maxLongEdge: 64), to: target, progress: { _ in })
                let image = try #require(CGImageSourceCreateWithURL(target as CFURL, nil))
                var duration = 0.0
                for i in 0..<CGImageSourceGetCount(image) {
                    let props = try #require(CGImageSourceCopyPropertiesAtIndex(image, i, nil) as? [String: Any])
                    let gif = try #require(props[kCGImagePropertyGIFDictionary as String] as? [String: Any])
                    duration += gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double ?? 0
                }
                #expect(abs(duration - 1) < 0.03)
            } else {
                try await Transcoder.run(source, to: target, format: format, trim: range, progress: { _ in })
                #expect(abs(try await AVURLAsset(url: target).load(.duration).seconds - 1) < 0.07)
            }
        }
        #expect(try Data(contentsOf: source) == original)
    }
}
