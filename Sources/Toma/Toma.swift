import AppKit

/// Owns capture and review sessions so only one can use the menu bar and result card at a time.
final class Toma {
    enum Phase {
        case idle
        /// Permission check, overlay up, or stream starting. Input is ignored: the overlay
        /// owns Esc/mouse, and a second press must not start a second session.
        case busy
        /// The stream is live. `since` drives the elapsed-time readout in the menu bar.
        case recording(Recording, since: ContinuousClock.Instant)
        /// The result card is on screen; it resolves itself (button, drag or timeout).
        case reviewing(ResultCard)
        /// The chosen file is being written; 0…1.
        case saving(Double)
    }

    private(set) var phase: Phase = .idle {
        didSet { statusItem.render(phase) }
    }
    private let statusItem: StatusItem
    private let updater: Updater
    /// The hotkey was pressed while the card was up: save it and go straight to a new selection.
    private var againAfterSaving = false
    private var sessionTask: Task<Void, Never>?

    init(updater: Updater) {
        self.updater = updater
        statusItem = StatusItem(updater: updater)
        statusItem.onPress = { [unowned self] in toggle() }
        statusItem.onReopen = { [unowned self] in reopenLast() }
        statusItem.render(phase)
    }

    /// idle → start a session; recording → stop it; card up → keep it and start another.
    /// Idempotent per phase: pressing twice while recording stops once (Recording.stop is idempotent).
    func toggle() {
        switch phase {
        case .idle:
            if case .installing = updater.state { return }
            phase = .busy
            runSession { await self.session() }
        case .recording(let recording, _):
            recording.stop()
        case .reviewing(let card):
            if card.commit() { againAfterSaving = true }
        case .saving:
            againAfterSaving = false
            sessionTask?.cancel()
        case .busy:
            break
        }
    }

    private func runSession(_ action: @escaping () async -> Void) {
        sessionTask = Task {
            await action()
            phase = .idle
            if againAfterSaving {
                againAfterSaving = false
                toggle()
            }
        }
    }

    private func reopenLast() {
        guard case .idle = phase else { return }
        if case .installing = updater.state { return }
        phase = .busy
        runSession {
            do {
                let clip = try await RecentRecording(storage: Library.storage).reopen()
                await self.review(clip, reopened: true)
            } catch { self.present(error) }
        }
    }

    /// One capture, start to finish. Every exit path returns to `.idle` (set by `toggle`).
    private func session() async {
        guard Recording.ensureAccess() else { return }
        guard let region = await Overlay.select() else { return }    // Esc / tiny drag = nothing happened

        let recording: Recording
        do { recording = try await Recording.start(region) } catch { return present(error) }
        let frame = Overlay.frame(around: region)
        phase = .recording(recording, since: .now)

        // Resolves after stop() *or* if the system/display ended the stream.
        let clip: Clip
        do { clip = try await recording.clip } catch { frame.close(); return present(error) }
        frame.close()

        if let reason = recording.limitReason {
            let alert = NSAlert()
            alert.messageText = tr(reason)
            alert.runModal()
        }
        do { try await RecentRecording(storage: Library.storage).remember(clip) }
        catch {
            let alert = NSAlert()
            alert.messageText = tr("Couldn't keep a recent copy. You can still save this recording.")
            alert.runModal()
        }
        await review(clip)
    }

    private func review(_ clip: Clip, reopened: Bool = false) async {
        let suggested = Library.preferredFormat
        Library.prepare(clip, as: suggested)                     // likely choice encodes while the card is up
        let card = ResultCard(clip, suggesting: suggested, autoSaveAfter: reopened ? nil : .seconds(6))
        phase = .reviewing(card)
        let choice = await card.choice()

        phase = .saving(0)
        let progress: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor [weak self] in
                if case .saving = self?.phase { self?.phase = .saving(value) }
            }
        }
        do {
            switch choice {
            case .discard:
                if !reopened { try? RecentRecording(storage: Library.storage).forget(ifMatching: clip) }
                await Library.discard(clip)
            case .delivered: break
            case .save(let format): try await Library.save(clip, as: format, progress: progress)
            case .copy(let format):
                try await Library.copy(clip, as: format, progress: progress)
                statusItem.flash()
            }
        } catch {
            recover(clip, after: error)
        }
    }

    private func recover(_ clip: Clip, after error: any Error) {
        let alert = NSAlert()
        alert.messageText = tr("Couldn't save the recording.")
        alert.informativeText = tr("The original is safe in Recoverable Recordings. Save a copy or open that folder to recover it later.")
        alert.addButton(withTitle: tr("Save Original…"))
        alert.addButton(withTitle: tr("Show Recoverable Recordings"))
        alert.addButton(withTitle: tr("Later"))
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.mpeg4Movie]
            panel.nameFieldStringValue = "\(Library.fileName()).mp4"
            if panel.runModal() == .OK, let url = panel.url {
                do { try Library.rescue(clip, to: url) }
                catch { present(error) }
            }
        case .alertSecondButtonReturn: Library.showRecovery()
        default: break
        }
    }

    /// The single place errors become UI: one localized NSAlert, one sentence, one button.
    private func present(_ error: any Error) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = (error as? TomaError)?.message ?? tr("Couldn't record.")
        alert.runModal()
    }
}

/// Every failure the user can see. Messages are localized copy (see Strings.swift), short, no jargon.
nonisolated enum TomaError: Error, Sendable {
    case permissionDenied
    case displayUnavailable
    case streamFailed(underlying: String)
    case exportFailed(underlying: String)

    var message: String {
        switch self {
        case .permissionDenied:   tr("Toma needs permission to record the screen.")
        case .displayUnavailable: tr("The display is no longer available.")
        case .streamFailed:       tr("The recording was interrupted.")
        case .exportFailed:       tr("Couldn't save the recording.")
        }
    }
}
