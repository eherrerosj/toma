import AppKit

// The timer has no capture side effects; callers start recording only after it returns.
enum Countdown {
    static func run(seconds: Int, interval: Duration = .seconds(1), tick: (Int) -> Void) async throws {
        for remaining in stride(from: seconds, through: 1, by: -1) {
            try Task.checkCancellation()
            tick(remaining)
            try await Task.sleep(for: interval)
        }
        try Task.checkCancellation()
    }
}

final class RecordingCountdown: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let label = NSTextField(labelWithString: "")
    private let finished = OneShot<Bool>()
    private var timer: Task<Void, Never>?

    static func wait(seconds: Int, on screen: NSScreen? = nil) async -> Bool {
        guard seconds > 0 else { return true }
        let countdown = RecordingCountdown()
        if let screen {
            let size = countdown.window.frame.size
            countdown.window.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - size.width / 2,
                                                     y: screen.visibleFrame.midY - size.height / 2))
        } else { countdown.window.center() }
        countdown.label.stringValue = tr("Recording starts in %d", seconds)
        NSApp.activate()
        countdown.window.makeKeyAndOrderFront(nil)
        countdown.timer = Task {
            do {
                try await Countdown.run(seconds: seconds) { countdown.label.stringValue = tr("Recording starts in %d", $0) }
                countdown.finished.resolve(true)
            } catch { countdown.finished.resolve(false) }
        }
        let ready = await countdown.finished.value
        countdown.timer?.cancel()
        countdown.window.orderOut(nil)
        return ready
    }

    private override init() {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 140),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = tr("Get Ready")
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        label.frame = CGRect(x: 16, y: 76, width: 288, height: 32)
        label.alignment = .center
        label.font = .systemFont(ofSize: 23, weight: .medium)
        window.contentView!.addSubview(label)
        let cancel = NSButton(title: tr("Cancel"), target: self, action: #selector(cancel))
        cancel.frame = CGRect(x: 110, y: 20, width: 100, height: 32)
        cancel.keyEquivalent = "\u{1b}"
        window.contentView!.addSubview(cancel)
    }

    @objc private func cancel() {
        timer?.cancel()
        finished.resolve(false)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
}
