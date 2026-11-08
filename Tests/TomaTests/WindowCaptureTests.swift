import Foundation
import Testing
@testable import Toma

@Suite struct WindowCaptureTests {
    @Test func windowGeometryKeepsWholeWindowAtEvenNativeDimensions() throws {
        let region = try #require(WindowCapture.geometry(size: CGSize(width: 1201, height: 801), scale: 2, displayID: 42))
        #expect(region.pixelSize.width == 2402)
        #expect(region.pixelSize.height == 1602)
        #expect(region.displayID == 42)
        let odd = try #require(WindowCapture.geometry(size: CGSize(width: 301, height: 201), scale: 1, displayID: 42))
        #expect(odd.pixelSize.width % 2 == 0)
        #expect(odd.pixelSize.height % 2 == 0)
    }

    @Test func rejectsInvalidWindowGeometry() {
        for size in [CGSize.zero, CGSize(width: Double.nan, height: 10), CGSize(width: 20, height: Double.infinity)] {
            #expect(WindowCapture.geometry(size: size, scale: 2, displayID: 1) == nil)
        }
        #expect(WindowCapture.geometry(size: CGSize(width: 100, height: 100), scale: 0, displayID: 1) == nil)
    }
}
