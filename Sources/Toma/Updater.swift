import AppKit

/// Updates require the personal app's Developer ID identity and a matching release digest.
final class Updater {
    enum State {
        case idle
        case available(Update)
        case installing
    }

    private(set) var state: State = .idle
    let currentVersion: String

    var canInstall: () -> Bool = { true }
    private var checking = false
    private var checkingTask: Task<Void, Never>?
    private static let lastCheckKey = "ultimaBusquedaActualizaciones"
    private static let interval: TimeInterval = 24 * 3600

    /// A plain `swift run` has no bundle version; then there is nothing to compare, so no updates.
    init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Checks shortly after launch and then whenever a day has passed. Toma can run for weeks
    /// without a restart, so this wakes hourly instead of checking once at launch.
    func startChecking() {
        guard !currentVersion.isEmpty else { return }
        guard checkingTask == nil else { return }
        checkingTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            while !Task.isCancelled {
                guard let self else { return }
                let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
                if Preferences.automaticUpdates, Date.now.timeIntervalSince(last) >= Self.interval { await self.check() }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    /// Asks GitHub for the latest release and updates `state`. Returns false if the lookup failed.
    @discardableResult
    func check() async -> Bool {
        guard !currentVersion.isEmpty, !checking else { return false }
        if case .installing = state { return true }
        checking = true
        defer { checking = false }

        var request = URLRequest(url: UpdateFeed.latest, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Toma/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard data.count <= 1_048_576 else { return false }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let update = UpdateFeed.parse(data) else { return false }
            UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey)
            state = UpdateFeed.isNewer(update.version, than: currentVersion) ? .available(update) : .idle
            return true
        } catch {
            return false
        }
    }

    /// Downloads, verifies and swaps in the available update, then relaunches. Quits Toma on
    /// success; on any failure it falls back to the release page and stays available.
    func install() async {
        guard case .available(let update) = state, canInstall() else { return }
        state = .installing
        let app = Bundle.main.bundleURL
        do {
            let staged = try await Self.stage(update, over: app, current: currentVersion)
            try Self.swapAndRelaunch(staged, over: app)
            NSApp.terminate(nil)
        } catch {
            state = .available(update)
            NSWorkspace.shared.open(update.page)
        }
    }

    // MARK: staging

    nonisolated private struct Staged: Sendable {
        let app: URL
        let scratch: URL
        let container: URL
        let requirement: String
    }

    nonisolated private enum Failure: Error {
        case notWritable, notNewer
    }

    /// Downloads the DMG and leaves the verified new app next to the old one, ready to swap.
    nonisolated private static func stage(_ update: Update, over app: URL, current: String) async throws -> Staged {
        let fm = FileManager.default
        let folder = app.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: folder.path) else { throw Failure.notWritable }

        let scratch = fm.temporaryDirectory.appending(path: "\(AppIdentity.bundleIdentifier)-update-\(UUID())", directoryHint: .isDirectory)
        let container = folder.appending(path: ".toma-update-\(UUID())", directoryHint: .isDirectory)
        let staged = container.appending(path: AppIdentity.bundleName, directoryHint: .isDirectory)
        let mount = scratch.appending(path: "mount", directoryHint: .isDirectory)
        var mounted = false
        do {
            let team = try UpdateTrust.signingTeam(of: app)
            let requirement = try UpdateTrust.requirement(team: team)
            try fm.createDirectory(at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try fm.createDirectory(at: mount, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try fm.createDirectory(at: container, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let dmg = scratch.appending(path: "Toma.dmg")
            try await BoundedDownload.copy(update.dmg, to: dmg)
            try UpdateTrust.checkDigest(of: dmg, expected: update.sha256)

            try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen",
                                               "-mountpoint", mount.path, dmg.path])
            mounted = true
            try await run("/usr/bin/ditto", [mount.appending(path: AppIdentity.bundleName).path, staged.path])
            try await run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
            mounted = false

            try UpdateTrust.verify(staged, team: team)
            try await run("/usr/sbin/spctl", ["--assess", "--type", "execute", staged.path])
            let version = Bundle(url: staged)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            guard version == update.version, UpdateFeed.isNewer(version, than: current) else { throw Failure.notNewer }
            return Staged(app: staged, scratch: scratch, container: container, requirement: requirement)
        } catch {
            if mounted { _ = try? await run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }
            try? fm.removeItem(at: container)
            try? fm.removeItem(at: scratch)
            throw error
        }
    }

    /// Runs a tool to completion and returns its combined output; throws on a non-zero exit.
    @discardableResult
    nonisolated private static func run(_ tool: String, _ arguments: [String]) async throws -> String {
        try await ToolRunner.run(tool, arguments)
    }

    // MARK: swap

    /// A detached shell outlives Toma: it waits for this process to exit, swaps the bundle (undoing
    /// the swap if the second move fails), and opens the result. A running app cannot replace itself.
    private static func swapAndRelaunch(_ staged: Staged, over app: URL) throws {
        let script = """
        pid=$1; app=$2; new=$3; scratch=$4; container=$5; requirement=$6
        old="$app.backup-$(basename "$container")"
        n=0
        while kill -0 "$pid" 2>/dev/null; do
          n=$((n + 1))
          if [ "$n" -gt 100 ]; then rm -rf "$container" "$scratch"; exit 1; fi
          sleep 0.2
        done
        if /usr/bin/codesign --verify --deep --strict --all-architectures -R "$requirement" "$new"; then
          if mv "$app" "$old"; then
            if mv "$new" "$app"; then
              if open "$app"; then rm -rf "$old"; else
                mv "$app" "$container/failed.app"
                mv "$old" "$app"
                open "$app"
              fi
            else
              mv "$old" "$app"
              open "$app"
            fi
          fi
        else
          open "$app"
        fi
        rm -rf "$container" "$scratch"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier),
                             app.path, staged.app.path, staged.scratch.path, staged.container.path, staged.requirement]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
