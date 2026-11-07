import Foundation
import AppKit

/// A failed export leaves its original in durable recovery storage.
enum Library {
    static var storage = RecordingStorage.live
    private static var consuming: Set<URL> = []
    private static var housekeeping: Task<Void, Never>?

    /// The format the result card pre-selects. Written only by `save` (the last format the user
    /// actually saved), so there is no setting to manage: using GIF once makes GIF the default.
    static var preferredFormat: Format {
        Format(rawValue: UserDefaults.standard.string(forKey: "formato") ?? "") ?? .mp4
    }

    /// The folder the user chose, else `com.apple.screencapture location` (⇧⌘5 › Options),
    /// else the Desktop.
    static var destination: URL {
        let fm = FileManager.default
        func isFolder(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        if let chosen = Preferences.folder, isFolder(chosen) { return chosen }
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            if isFolder(url) { return url }
        }
        return fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// The name a recording made now gets, without extension:
    /// "Screen Recording 2026-10-15 at 21.03.12" (Spanish: "Grabación de pantalla 2026-10-15 a las 21.03.12"),
    /// mirroring Apple's screenshots.
    static func fileName(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = tr("yyyy-MM-dd 'at' HH.mm.ss")
        return tr("Screen Recording %@", f.string(from: date))
    }

    /// Starts encoding the clip in `format` in the background while the user is still looking at
    /// the card, so the likely choice saves (nearly) instantly. Calling it again is a no-op.
    static func prepare(_ clip: Clip, as format: Format) {
        guard format != .gif, prepared[clip.master] == nil else { return }
        try? storage.createPrivateDirectory(storage.scratch)
        let target = storage.scratch.appending(path: "\(UUID().uuidString).\(format.fileExtension)")
        prepared[clip.master] = (format, Task.detached(priority: .userInitiated) {
            do {
                try await Transcoder.run(clip.master, to: target, format: format, progress: { _ in })
                return target
            } catch {
                try? FileManager.default.removeItem(at: target)
                throw error
            }
        })
    }

    /// Turns the clip into a user-visible file and consumes the master.
    /// `to` is an exact destination (a drag-out file promise); nil means `destination` with a
    /// fresh name. Never overwrites; a partial file never appears.
    @discardableResult
    static func save(_ clip: Clip, as format: Format, to exact: URL? = nil,
                     progress: @escaping @Sendable (Double) -> Void = { _ in },
                     retainingMaster: Bool = false) async throws(TomaError) -> URL {
        guard consuming.insert(clip.master).inserted else { throw .exportFailed(underlying: "clip already in use") }
        defer { consuming.remove(clip.master) }
        let url = exact ?? uniqueURL(in: destination, base: fileName(), ext: format.fileExtension)
        var encoded: URL?
        do {
            let output = try await encode(clip, as: format, progress: progress)
            encoded = output
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: output, to: url)
        } catch {
            if let encoded { try? FileManager.default.removeItem(at: encoded) }
            throw .exportFailed(underlying: "\(error)")
        }
        if !retainingMaster { try? FileManager.default.removeItem(at: clip.master) }
        UserDefaults.standard.set(format.rawValue, forKey: "formato")
        return url
    }

    /// Puts the clip on the clipboard as a file, ready to paste into Slack, Mail or Finder.
    /// The file lives in Toma's cache (cleared after a day), so copying doesn't clutter the folder.
    static func copy(_ clip: Clip, as format: Format,
                     progress: @escaping @Sendable (Double) -> Void = { _ in },
                     pasteboard: NSPasteboard = .general) async throws(TomaError) {
        let folder = clipboardFolder
        do { try storage.createPrivateDirectory(folder) }
        catch { throw .exportFailed(underlying: "\(error)") }
        let url = try await save(clip, as: format, to: uniqueURL(in: folder, base: fileName(), ext: format.fileExtension),
                                 progress: progress, retainingMaster: true)
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([url as NSURL]) else { throw .exportFailed(underlying: "clipboard write failed") }
        await discard(clip)
    }

    static func discard(_ clip: Clip) async {
        guard consuming.insert(clip.master).inserted else { return }
        defer { consuming.remove(clip.master) }
        await discardPrepared(clip)
        try? FileManager.default.removeItem(at: clip.master)
    }

    static func removeOwnedWorkspace() {
        try? FileManager.default.removeItem(at: storage.scratch)
    }

    static func removeLeftovers() {
        // Masters are recovery files, not disposable launch leftovers.
        try? storage.expireClipboard(now: .now)
    }

    static func startHousekeeping() {
        guard housekeeping == nil else { return }
        removeLeftovers()
        housekeeping = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                removeLeftovers()
            }
        }
    }

    static func showRecovery() {
        try? storage.createPrivateDirectory(storage.recovery)
        NSWorkspace.shared.open(storage.recovery)
    }

    static func rescue(_ clip: Clip, to url: URL) throws {
        try storage.rescue(clip.master, to: url)
    }

    // MARK: private

    private static var prepared: [URL: (Format, Task<URL, any Error>)] = [:]

    private static var clipboardFolder: URL { storage.clipboard }

    /// A finished file in scratch, encoded as `format`, reusing a prepared encode when it matches.
    private static func encode(_ clip: Clip, as format: Format,
                               progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if let (preparedFormat, task) = prepared[clip.master] {
            if preparedFormat == format {
                prepared[clip.master] = nil
                let result = await withTaskCancellationHandler {
                    await task.result
                } onCancel: { task.cancel() }
                if case .success(let url) = result { return url }
                try Task.checkCancellation()
            } else {
                await discardPrepared(clip)
            }
        }
        try storage.createPrivateDirectory(storage.scratch)
        let target = storage.scratch.appending(path: "\(UUID().uuidString).\(format.fileExtension)")
        do {
            switch format {
            case .gif:
                try await GIFEncoder.encode(clip, policy: Preferences.gifSize.policy, to: target, progress: progress)
            case .mp4, .hevc:
                try await Transcoder.run(clip.master, to: target, format: format, progress: progress)
            }
            return target
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    private static func discardPrepared(_ clip: Clip) async {
        guard let (_, task) = prepared.removeValue(forKey: clip.master) else { return }
        task.cancel()
        if let url = try? await task.value { try? FileManager.default.removeItem(at: url) }
    }

    private static func uniqueURL(in folder: URL, base: String, ext: String) -> URL {
        var url = folder.appending(path: "\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}

/// The few numbers that decide whether a GIF looks good *and* stays shareable.
nonisolated struct GIFPolicy: Sendable {
    /// GIF delays are in 1/100 s; the encoder rounds cumulatively, so any rate keeps exact timing.
    var framesPerSecond: Int
    /// Longest edge in pixels; larger captures are downscaled (Lanczos) to fit.
    var maxLongEdge: Int
}
