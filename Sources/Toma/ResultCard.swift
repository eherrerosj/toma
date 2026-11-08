import AppKit
import AVFoundation

/// Untouched cards auto-save. Choosing a format keeps the card open for an explicit action.
final class ResultCard {
    enum Choice: Sendable, Equatable {
        case save(Format)
        case copy(Format)
        case discard
        /// Already written somewhere by a drag-out; nothing left to do.
        case delivered
    }

    private(set) var clip: Clip
    private(set) var selectedFormat: Format
    private var awaitingAction = false
    private let write: (Clip, Format, URL) async throws -> Void
    private var delivering = false
    private var editing = false
    private let editor: (Clip) async -> TrimEditor.Decision
    private(set) var selection: Choice?
    private let decided = OneShot<Choice>()
    private var panel: NSPanel?
    private var timeout: Task<Void, Never>?
    private var hovering = false
    private var dragging = false
    private var swipe: CGFloat = 0

    private let autoSaveAfter: Duration?

    init(_ clip: Clip, suggesting suggested: Format, autoSaveAfter: Duration? = Preferences.thumbnailTimeout.delay,
         editor: @escaping (Clip) async -> TrimEditor.Decision = { await TrimEditor.edit($0) },
         write: @escaping (Clip, Format, URL) async throws -> Void = { clip, format, url in
             try await Library.save(clip, as: format, to: url)
         }) {
        self.clip = clip
        self.selectedFormat = suggested
        self.editor = editor
        self.write = write
        self.autoSaveAfter = autoSaveAfter
    }

    /// Shows the card and resolves exactly once; the window is gone before it returns.
    func choice() async -> Choice {
        show()
        let choice = await decided.value
        hide(sliding: choice != .discard)
        return choice
    }

    /// The Save button, swipe and recording shortcut share the same selected-format action.
    @discardableResult
    func commit() -> Bool {
        guard !editing, !dragging, !delivering, selection == nil else { return false }
        resolve(.save(selectedFormat))
        return true
    }

    private func resolve(_ choice: Choice) {
        guard !editing, !delivering, selection == nil else { return }
        selection = choice
        timeout?.cancel()
        decided.resolve(choice)
    }

    func restartTimeout() {
        timeout?.cancel()
        guard !editing, !hovering, !dragging, !delivering, !awaitingAction, selection == nil else { return }
        guard let delay = autoSaveAfter else { return }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    // MARK: window

    private func show() {
        let pixel = clip.region.pixelSize
        let aspect = CGFloat(pixel.width) / CGFloat(pixel.height)
        let maxThumb = CGSize(width: 240, height: 160)
        var thumb = CGSize(width: maxThumb.width, height: maxThumb.width / aspect)
        if thumb.height > maxThumb.height { thumb = CGSize(width: maxThumb.height * aspect, height: maxThumb.height) }
        thumb.width = max(thumb.width, 204)            // room for the format row
        thumb.height = max(thumb.height, 60)

        let pad: CGFloat = 6, bar: CGFloat = 32
        let size = CGSize(width: thumb.width + 2 * pad, height: thumb.height + pad + bar)

        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let card = CardView(frame: CGRect(origin: .zero, size: size), owner: self)
        card.build(thumb: CGRect(x: pad, y: bar, width: thumb.width, height: thumb.height),
                   bar: CGRect(x: 0, y: 0, width: size.width, height: bar),
                   clip: clip, suggested: selectedFormat)
        panel.contentView = card
        self.panel = panel

        let screen = NSScreen.with(displayID: clip.region.displayID) ?? NSScreen.main!
        let resting = CGPoint(x: screen.visibleFrame.maxX - size.width - 16, y: screen.visibleFrame.minY + 16)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrameOrigin(reduceMotion ? resting : CGPoint(x: screen.visibleFrame.maxX + 8, y: resting.y))
        panel.alphaValue = reduceMotion ? 0 : 1
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(CGRect(origin: resting, size: size), display: true)
            panel.animator().alphaValue = 1
        }
        restartTimeout()
    }

    private func hide(sliding: Bool) {
        guard let panel else { return }
        self.panel = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if sliding && !reduceMotion {
                panel.animator().setFrame(panel.frame.offsetBy(dx: panel.frame.width + 24, dy: 0), display: true)
            }
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                (panel.contentView as? CardView)?.stop()
                panel.orderOut(nil)
            }
        }
    }

    // MARK: input from the card view

    func hover(_ inside: Bool) {
        hovering = inside
        restartTimeout()
    }

    func picked(_ format: Format) {
        guard !editing, !delivering, !dragging, selection == nil else { return }
        selectedFormat = format
        awaitingAction = true
        restartTimeout()
        (panel?.contentView as? CardView)?.select(format)
    }

    func edit() async {
        guard !editing, !delivering, !dragging, selection == nil, clip.duration >= 0.1 else { return }
        editing = true
        awaitingAction = true
        restartTimeout()
        let decision = await editor(clip)
        if case .apply(let range) = decision {
            clip.trim = range
            (panel?.contentView as? CardView)?.updatePreview(clip)
        }
        editing = false
    }

    func copy() { resolve(.copy(selectedFormat)) }
    func discard() { resolve(.discard) }

    func scrolled(_ deltaX: CGFloat) {
        swipe += deltaX
        if swipe < -40 || swipe > 40 { commit() }   // either direction reads as "away"
    }

    func dragBegan() {
        dragging = true
        restartTimeout()
    }

    func dragEnded(delivered: Bool) {
        dragging = false
        if !delivered { restartTimeout() }
    }

    /// Called by the file promise: write the clip at exactly `url`.
    func deliver(to url: URL) async throws {
        guard !editing, !delivering, selection == nil else { throw CocoaError(.fileWriteUnknown) }
        delivering = true
        timeout?.cancel()
        do {
            try await write(clip, selectedFormat, url)
            delivering = false
            resolve(.delivered)
        } catch {
            delivering = false
            throw error
        }
    }

    internal var promisedName: String { "\(Library.fileName()).\(selectedFormat.fileExtension)" }
    internal var promisedType: String { selectedFormat.type.identifier }
}
