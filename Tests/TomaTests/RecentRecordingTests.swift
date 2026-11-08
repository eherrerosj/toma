import Foundation
import Testing
@testable import Toma

@Suite struct RecentRecordingTests {
    @Test func reopensIndependentOriginalAndReplacesOnlyAfterSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "toma-recent-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = RecordingStorage(root: root)
        let recent = RecentRecording(storage: storage)
        let region = try #require(ScreenRegion(dragged: CGRect(x: 0, y: 0, width: 64, height: 64),
                                              displayFrame: CGRect(x: 0, y: 0, width: 64, height: 64), scale: 1, displayID: 1))
        let master = try storage.newMasterURL()
        try Data("original".utf8).write(to: master)
        let clip = Clip(master: master, duration: 2, region: region)
        #expect(!recent.isAvailable)
        try await recent.remember(clip)
        try FileManager.default.removeItem(at: master)
        let reopened = try await recent.reopen()
        #expect(reopened.master != master)
        #expect(reopened.region == region)
        #expect(reopened.duration == 2)
        #expect(try Data(contentsOf: reopened.master) == Data("original".utf8))
        try FileManager.default.removeItem(at: reopened.master)
        await #expect(throws: (any Error).self) { try await recent.remember(clip) }
        #expect(recent.isAvailable)
        let next = try storage.newMasterURL()
        try Data("next".utf8).write(to: next)
        let replacement = Clip(master: next, duration: 3, region: region)
        try await recent.remember(replacement)
        let loaded = try await recent.reopen()
        #expect(try Data(contentsOf: loaded.master) == Data("next".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: recent.folder.path).filter { $0.hasSuffix("mp4") }.count == 1)
        try recent.forget(ifMatching: clip)
        #expect(recent.isAvailable)
        try recent.forget(ifMatching: replacement)
        #expect(!recent.isAvailable)
    }
}
