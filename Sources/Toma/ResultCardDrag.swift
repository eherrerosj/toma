import AppKit

/// A format word. The suggested one is semibold; hovering any of them brings it to full contrast.
final class TextButton: NSButton {
    private let text: String
    var emphasized: Bool { didSet { style(hovering: false) } }

    init(_ text: String, emphasized: Bool, target: AnyObject, action: Selector) {
        self.text = text
        self.emphasized = emphasized
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        style(hovering: false)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func style(hovering: Bool) {
        attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: emphasized ? .semibold : .regular),
            .foregroundColor: emphasized || hovering ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ])
    }

    override func mouseEntered(with event: NSEvent) { style(hovering: true) }
    override func mouseExited(with event: NSEvent) { style(hovering: false) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// The thumbnail: a drag source that promises the file, like the screenshot thumbnail.
final class ThumbView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    private weak var owner: ResultCard?
    private var downAt: CGPoint?
    private var delivered = false

    init(frame: CGRect, owner: ResultCard?) {
        self.owner = owner
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, let owner else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        downAt = nil

        let provider = NSFilePromiseProvider(fileType: owner.promisedType, delegate: self)
        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(bounds, contents: snapshot())
        owner.dragBegan()
        beginDraggingSession(with: [item], event: event, source: self)
    }

    /// The first frame of the clip, loaded when the card appears; the drag image.
    var poster: NSImage?

    private func snapshot() -> NSImage {
        if let poster { return poster }
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        NSColor.black.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: bounds.size), xRadius: 6, yRadius: 6).fill()
        image.unlockFocus()
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation == [] { owner?.dragEnded(delivered: false) }
    }

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        MainActor.assumeIsolated { owner?.promisedName ?? tr("Screen Recording") }
    }

    nonisolated func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { .main }

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                                         completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        MainActor.assumeIsolated {
            guard let owner else { return completionHandler(CocoaError(.fileWriteUnknown)) }
            Task {
                do {
                    try await owner.deliver(to: url)
                    owner.dragEnded(delivered: true)
                    completionHandler(nil)
                } catch {
                    owner.dragEnded(delivered: false)
                    completionHandler(error)
                }
            }
        }
    }
}
