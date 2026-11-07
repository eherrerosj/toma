import Foundation
import Testing
@testable import Toma

@Suite(.serialized) struct StorageTests {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("toma-storage-test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func launchDoesNotRemoveRecoverableMastersOrAnotherWorkspace() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = RecordingStorage(root: root)
        let master = try first.newMasterURL()
        try Data("original recording".utf8).write(to: master)
        try FileManager.default.createDirectory(at: first.scratch, withIntermediateDirectories: true)
        let active = first.scratch.appendingPathComponent("active.mp4")
        try Data([1]).write(to: active)
        let second = RecordingStorage(root: root)
        try second.expireClipboard(now: .now)
        #expect(first.scratch != second.scratch)
        #expect(try Data(contentsOf: master) == Data("original recording".utf8))
        #expect(FileManager.default.fileExists(atPath: active.path))
    }

    @Test func clipboardExpiryUsesCopyCompletionTime() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStorage(root: root)
        try FileManager.default.createDirectory(at: store.clipboard, withIntermediateDirectories: true)
        let expired = store.clipboard.appendingPathComponent("old.mp4")
        let fresh = store.clipboard.appendingPathComponent("new.mp4")
        try Data([1]).write(to: expired)
        try Data([2]).write(to: fresh)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-86_401)], ofItemAtPath: expired.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-100)], ofItemAtPath: fresh.path)
        try store.expireClipboard(now: now)
        #expect(!FileManager.default.fileExists(atPath: expired.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test func rescueCopiesTheMasterWithoutEncodingAndNeverOverwrites() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStorage(root: root)
        let master = try store.newMasterURL()
        let bytes = Data("not an encodable movie; rescue must only copy".utf8)
        try bytes.write(to: master)
        let destination = root.appendingPathComponent("rescued.mp4")
        try store.rescue(master, to: destination)
        #expect(try Data(contentsOf: destination) == bytes)
        #expect(FileManager.default.fileExists(atPath: master.path))
        #expect(throws: (any Error).self) { try store.rescue(master, to: destination) }
        #expect(try Data(contentsOf: destination) == bytes)
    }
    @Test func finalDeliveryIsAtomicAndDoesNotOverwriteAnExistingFile() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStorage(root: root)
        let encoded = root.appendingPathComponent("encoded.mp4")
        let destination = root.appendingPathComponent("existing.mp4")
        try Data([1, 2, 3]).write(to: encoded)
        try Data([9]).write(to: destination)
        #expect(throws: (any Error).self) { try store.deliver(encoded, to: destination) }
        #expect(try Data(contentsOf: destination) == Data([9]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".toma-delivery-") })
        let fresh = root.appendingPathComponent("fresh.mp4")
        try Data([1, 2, 3]).write(to: encoded)
        try store.deliver(encoded, to: fresh)
        #expect(try Data(contentsOf: fresh) == Data([1, 2, 3]))
        #expect(!FileManager.default.fileExists(atPath: encoded.path))
    }

}
