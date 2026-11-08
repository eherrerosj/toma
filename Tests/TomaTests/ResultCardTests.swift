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
        card.picked(.gif)
        card.copy()
        #expect(card.selectedFormat == .mp4)
        #expect(card.selection == nil)
        release.resolve(true)
        try await delivery.value
        #expect(card.selection == .delivered)
        #expect(!card.commit())
    }
    private func clip() throws -> Clip {
        let region = try #require(ScreenRegion(dragged: CGRect(x: 0, y: 0, width: 64, height: 64),
                                              displayFrame: CGRect(x: 0, y: 0, width: 64, height: 64), scale: 1, displayID: 1))
        return Clip(master: URL(fileURLWithPath: "/unused.mp4"), duration: 1, region: region)
    }

    @Test(arguments: Format.allCases)
    func selectingFormatKeepsCardOpenAndCopyUsesThatFormat(format: Format) throws {
        let card = ResultCard(try clip(), suggesting: .mp4)
        card.picked(format)
        #expect(card.selection == nil)
        card.copy()
        #expect(card.selection == .copy(format))
    }

    @Test func selectedFormatCanStillBeSavedExplicitly() throws {
        let card = ResultCard(try clip(), suggesting: .mp4)
        card.picked(.gif)
        #expect(card.commit())
        #expect(card.selection == .save(.gif))
    }

    @Test func draggingUsesTheSelectedFormat() async throws {
        var written: Format?
        let card = ResultCard(try clip(), suggesting: .mp4, write: { _, format, _ in written = format })
        card.picked(.hevc)
        try await card.deliver(to: URL(fileURLWithPath: "/unused.mov"))
        #expect(written == .hevc)
        #expect(card.selection == .delivered)
    }

    @Test func choosingAFormatHoldsTheCardPastItsAutoSaveDelay() async throws {
        let card = ResultCard(try clip(), suggesting: .mp4, autoSaveAfter: .milliseconds(10))
        card.picked(.gif)
        card.restartTimeout()
        try await Task.sleep(for: .milliseconds(40))
        #expect(card.selection == nil)
        #expect(card.selectedFormat == .gif)
        card.copy()
        #expect(card.selection == .copy(.gif))
    }

    @Test func untouchedCardSavesButManualCardWaits() async throws {
        let timed = ResultCard(try clip(), suggesting: .mp4, autoSaveAfter: .milliseconds(10))
        let manual = ResultCard(try clip(), suggesting: .gif, autoSaveAfter: nil)
        timed.restartTimeout()
        manual.restartTimeout()
        let deadline = ContinuousClock.now + .seconds(2)
        while timed.selection == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(timed.selection == .save(.mp4))
        #expect(manual.selection == nil)
        #expect(manual.commit())
        #expect(manual.selection == .save(.gif))
    }

    @Test func timeoutPreferencesHaveBoundedDelays() {
        #expect(Preferences.ThumbnailTimeout.sixSeconds.delay == .seconds(6))
        #expect(Preferences.ThumbnailTimeout.fifteenSeconds.delay == .seconds(15))
        #expect(Preferences.ThumbnailTimeout.never.delay == nil)
    }

    @Test func editingBlocksDeliveryAndAppliesOneSharedRange() async throws {
        let entered = OneShot<Bool>()
        let finish = OneShot<TrimEditor.Decision>()
        let range = try #require(ClipTrim(start: 0.2, end: 0.8, duration: 1))
        var written: ClipTrim?
        let card = ResultCard(try clip(), suggesting: .mp4, editor: { _ in
            entered.resolve(true)
            return await finish.value
        }, write: { clip, _, _ in written = clip.trim })
        let edit = Task { await card.edit() }
        _ = await entered.value
        #expect(!card.commit())
        card.copy()
        #expect(card.selection == nil)
        await #expect(throws: (any Error).self) { try await card.deliver(to: URL(fileURLWithPath: "/unused.mp4")) }
        finish.resolve(.apply(range))
        await edit.value
        #expect(card.clip.trim == range)
        try await card.deliver(to: URL(fileURLWithPath: "/unused.mp4"))
        #expect(written == range)
    }

    @Test func cancellingTrimKeepsPreviousRange() async throws {
        let card = ResultCard(try clip(), suggesting: .mp4, editor: { _ in .cancel })
        await card.edit()
        #expect(card.clip.trim == nil)
        #expect(card.selection == nil)
        card.copy()
        #expect(card.selection == .copy(.mp4))
    }

}
