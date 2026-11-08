import AppKit
import ServiceManagement

/// Renders session state and forwards menu actions to Toma.
final class StatusItem: NSObject {
    /// Set once by Toma. Called for "Record Region" and for any click while recording.
    var onPress: () -> Void = {}
    var onRecordWindow: () -> Void = {}

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let updater: Updater
    private var ticker: Timer?
    private var phase: Toma.Phase = .idle

    init(updater: Updater) {
        self.updater = updater
        super.init()
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
    }

    func render(_ phase: Toma.Phase) {
        self.phase = phase
        ticker?.invalidate()
        ticker = nil
        guard let button = item.button else { return }
        button.appearsDisabled = false
        button.title = ""
        button.toolTip = nil
        button.imagePosition = .imageOnly

        switch phase {
        case .idle:
            button.image = symbol("rectangle.dashed", "Toma")
        case .busy, .reviewing:
            button.image = symbol("rectangle.dashed", "Toma")
            button.appearsDisabled = true
        case .saving(let progress):
            button.image = ring(progress)
            button.toolTip = tr("Cancel Export")
        case .recording(_, let since):
            button.image = symbol("stop.fill", tr("Stop Recording"), size: 9)
            button.imagePosition = .imageLeading
            let update: @MainActor @Sendable () -> Void = { [weak button] in
                guard let button else { return }
                let elapsed = Int((ContinuousClock.now - since).components.seconds)
                button.attributedTitle = NSAttributedString(
                    string: String(format: " %d:%02d", elapsed / 60, elapsed % 60),
                    attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)])
            }
            update()
            let timer = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { update() } }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
    }

    @objc private func clicked() {
        switch phase {
        case .idle: showMenu()
        case .recording, .saving: onPress()
        case .busy, .reviewing: break
        }
    }

    var onReopen: (() -> Void)?

    func showMenu() {
        guard let button = item.button else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        switch updater.state {
        case .idle:
            break
        case .available(let update):
            menu.addItem(item(tr("Update to Toma %@…", update.version), #selector(installUpdate)))
            menu.addItem(.separator())
        case .installing:
            menu.addItem(item(tr("Installing update…"), nil))
            menu.addItem(.separator())
        }

        let record = item(tr("Record Region"), #selector(record), key: "4")
        record.keyEquivalentModifierMask = [.option, .shift, .command]
        if case .installing = updater.state { record.isEnabled = false }
        menu.addItem(record)
        let window = item(tr("Record Window…"), #selector(recordWindow))
        if case .installing = updater.state { window.isEnabled = false }
        menu.addItem(window)
        let reopen = item(tr("Reopen Last Recording"), #selector(reopenLast))
        reopen.isEnabled = RecentRecording(storage: Library.storage).isAvailable
        if case .installing = updater.state { reopen.isEnabled = false }
        menu.addItem(reopen)
        menu.addItem(.separator())

        addPreferences(to: menu)

        menu.addItem(.separator())
        let login = item(tr("Open at Login"), #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item(tr("Show Recoverable Recordings"), #selector(showRecovery)))
        let automatic = item(tr("Check for Updates Automatically"), #selector(toggleAutomaticUpdates))
        automatic.state = Preferences.automaticUpdates ? .on : .off
        menu.addItem(automatic)
        menu.addItem(item(tr("Check for Updates…"), #selector(checkForUpdates)))
        menu.addItem(NSMenuItem(title: tr("Quit Toma"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    func item(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = action != nil
        return item
    }

    /// A brief checkmark after copying to the clipboard: the only confirmation, and it's enough.
    func flash() {
        guard let button = item.button else { return }
        button.image = symbol("checkmark", tr("Copied"))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self else { return }
            render(phase)
        }
    }

    @objc private func toggleAutomaticUpdates() { Preferences.automaticUpdates.toggle() }

    @objc private func showRecovery() { Library.showRecovery() }

    @objc private func record() { onPress() }

    @objc private func installUpdate() {
        Task { await updater.install() }
    }

    /// Asks now instead of waiting for the daily check, and answers in one alert either way.
    @objc private func checkForUpdates() {
        Task {
            let reached = await updater.check()
            NSApp.activate()
            let alert = NSAlert()
            if !reached {
                alert.messageText = tr("Couldn't check for updates.")
            } else if case .available(let update) = updater.state {
                alert.messageText = tr("Toma %@ is available.", update.version)
                alert.addButton(withTitle: tr("Update"))
                alert.addButton(withTitle: tr("Later"))
                if alert.runModal() == .alertFirstButtonReturn { await updater.install() }
                return
            } else {
                alert.messageText = tr("Toma is up to date.")
                alert.informativeText = tr("You have version %@.", updater.currentVersion)
            }
            alert.runModal()
        }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        try? service.status == .enabled ? service.unregister() : service.register()
    }

    private func symbol(_ name: String, _ description: String, size: CGFloat = 14) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
        image?.isTemplate = true
        return image
    }

    /// A thin ring with a filled arc: the only progress Toma ever shows.
    private func ring(_ progress: Double) -> NSImage {
        let image = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let track = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            track.lineWidth = 1.5
            NSColor.black.withAlphaComponent(0.25).setStroke()
            track.stroke()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: 6, startAngle: 90, endAngle: 90 - 360 * max(0.02, progress), clockwise: true)
            arc.lineWidth = 1.5
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = tr("Saving GIF")
        return image
    }
}
