import Foundation

nonisolated struct RecordingStorage: Sendable {
    let recovery: URL
    let clipboard: URL
    let scratch: URL

    static let live = RecordingStorage(
        support: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        cache: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
        temporary: FileManager.default.temporaryDirectory
    )

    init(root: URL) {
        self.init(support: root, cache: root, temporary: root)
    }

    private init(support: URL, cache: URL, temporary: URL) {
        recovery = support.appending(path: "\(AppIdentity.bundleIdentifier)/Recovery", directoryHint: .isDirectory)
        clipboard = cache.appending(path: "\(AppIdentity.bundleIdentifier)/Clipboard", directoryHint: .isDirectory)
        scratch = temporary.appending(path: "\(AppIdentity.bundleIdentifier)/\(UUID())", directoryHint: .isDirectory)
    }

    func newMasterURL() throws -> URL {
        try createPrivateDirectory(recovery)
        return recovery.appending(path: "\(UUID()).mp4")
    }

    func createPrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    func expireClipboard(now: Date) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: clipboard.path) else { return }
        for file in try fm.contentsOfDirectory(at: clipboard, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) {
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            if values.isRegularFile == true, let date = values.contentModificationDate,
               date <= now.addingTimeInterval(-86_400) {
                try fm.removeItem(at: file)
            }
        }
    }

    func deliver(_ encoded: URL, to destination: URL) throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appending(path: ".toma-delivery-\(UUID())")
        defer { try? fm.removeItem(at: staging) }
        try fm.moveItem(at: encoded, to: staging)
        try fm.moveItem(at: staging, to: destination)
    }

    // Copy beside the destination first so an interrupted rescue never exposes a partial final file.
    func rescue(_ master: URL, to destination: URL) throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appending(path: ".toma-rescue-\(UUID()).mp4")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: master, to: staging)
        try fm.moveItem(at: staging, to: destination)
    }
}
