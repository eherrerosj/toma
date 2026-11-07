import Foundation
import ImageIO
import Testing
@testable import Toma

@Suite struct GIFTests {
    @Test(arguments: [65_535, 65_536, 70_000])
    func longHoldsPreserveTheirDuration(centiseconds: Int) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("toma-test-\(UUID()).gif")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try GIF.Writer(url: url, width: 2, height: 2)
        let frame = GIF.Frame(pixels: Array(repeating: 0xff0000ff, count: 4), width: 2, height: 2)
        try writer.append(GIF.encode(GIF.Delta(frame: frame, x: 0, y: 0, width: 2, height: 2, changed: nil),
                                     centiseconds: centiseconds))
        try writer.finish()
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        var total = 0.0
        for i in 0..<CGImageSourceGetCount(source) {
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any])
            let gif = try #require(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
            total += try #require(gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            #expect(CGImageSourceCreateImageAtIndex(source, i, nil) != nil)
        }
        #expect(abs(total - Double(centiseconds) / 100) < 0.001)
    }
}
