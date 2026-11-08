import Foundation

nonisolated struct RecentRecording: Sendable {
    let storage: RecordingStorage
    var folder: URL { storage.recovery.deletingLastPathComponent().appending(path: "Recent", directoryHint: .isDirectory) }
    private var index: URL { folder.appending(path: "current.json") }

    private struct Entry: Codable {
        let file: String
        let original: String
        let duration: Double
        let region: ScreenRegion
    }

    var isAvailable: Bool {
        guard let entry = try? read() else { return false }
        return FileManager.default.fileExists(atPath: folder.appending(path: entry.file).path)
    }

    @concurrent func remember(_ clip: Clip) async throws {
        try storage.createPrivateDirectory(folder)
        let previous = try? read()
        let name = "\(UUID()).mp4"
        let target = folder.appending(path: name)
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: target) } }
        try FileManager.default.copyItem(at: clip.master, to: target)
        try Task.checkCancellation()
        let entry = Entry(file: name, original: clip.master.lastPathComponent, duration: clip.duration, region: clip.region)
        try JSONEncoder().encode(entry).write(to: index, options: .atomic)
        published = true
        if let previous { try? FileManager.default.removeItem(at: folder.appending(path: previous.file)) }
    }

    @concurrent func reopen() async throws -> Clip {
        let entry = try read()
        let master = try storage.newMasterURL()
        try FileManager.default.copyItem(at: folder.appending(path: entry.file), to: master)
        return Clip(master: master, duration: entry.duration, region: entry.region)
    }

    func forget(ifMatching clip: Clip) throws {
        let entry = try read()
        guard entry.original == clip.master.lastPathComponent else { return }
        try FileManager.default.removeItem(at: index)
        try FileManager.default.removeItem(at: folder.appending(path: entry.file))
    }

    private func read() throws -> Entry {
        let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: index))
        guard UUID(uuidString: String(entry.file.dropLast(4))) != nil, entry.file.hasSuffix(".mp4"),
              entry.duration.isFinite, entry.duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        return entry
    }
}
