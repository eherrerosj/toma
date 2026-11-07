import AppKit
import Testing
@testable import Toma

@Suite struct ResultCardTests {
    @Test func hotkeyCannotConsumeClipDuringDelivery() async throws {
        let entered = OneShot<Bool>()
        let release = OneShot<Bool>()
        let region = try #require(ScreenRegion(dragged: CGRect(x: 0, y: 0, width: 64, height: 64),
                                              displayFrame: CGRect(x: 0, y: 0, width: 64, height: 64), scale: 1, displayID: 1))
        let clip = Clip(master: URL(fileURLWithPath: "/unused.mp4"), duration: 1, region: region)
        let card = ResultCard(clip, suggesting: .mp4, write: { _, _, _ in
            entered.resolve(true)
            _ = await release.value
        })
        let delivery = Task { try await card.deliver(to: URL(fileURLWithPath: "/unused-destination.mp4")) }
        _ = await entered.value
        #expect(!card.commit())
        #expect(card.selection == nil)
        release.resolve(true)
        try await delivery.value
        #expect(card.selection == .delivered)
        #expect(!card.commit())
    }
}
