import AppKit
import Testing
@testable import Toma

@Suite struct RegionTests {
    @Test func acceptedRegionsStayBoundedAndEven() {
        for i in 0..<10_000 {
            let display = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
            let rect = CGRect(x: CGFloat((i * 37) % 2500) - 2300, y: CGFloat((i * 19) % 1600) - 500,
                              width: CGFloat((i * 13) % 2000), height: CGFloat((i * 17) % 1400))
            guard let region = ScreenRegion(dragged: rect, displayFrame: display, scale: i % 2 == 0 ? 1 : 2, displayID: 1) else { continue }
            #expect(display.contains(region.frame))
            #expect(region.pixelSize.width % 2 == 0)
            #expect(region.pixelSize.height % 2 == 0)
        }
    }
}
