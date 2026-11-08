import AppKit
import AVKit

final class TrimEditor: NSObject, NSWindowDelegate {
    enum Decision: Sendable {
        case cancel
        case apply(ClipTrim?)
    }

    private let clip: Clip
    private let decided = OneShot<Decision>()
    private let window: NSWindow
    private let player: AVPlayer
    private let start: NSSlider
    private let end: NSSlider
    private let summary = NSTextField(labelWithString: "")

    static func edit(_ clip: Clip) async -> Decision {
        let editor = TrimEditor(clip)
        NSApp.activate()
        editor.window.center()
        editor.window.makeKeyAndOrderFront(nil)
        let result = await editor.decided.value
        editor.player.pause()
        editor.window.orderOut(nil)
        return result
    }

    private init(_ clip: Clip) {
        self.clip = clip
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 620, height: 440),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        player = AVPlayer(url: clip.master)
        start = NSSlider(value: clip.trim?.start ?? 0, minValue: 0, maxValue: clip.duration, target: nil, action: nil)
        end = NSSlider(value: clip.trim?.end ?? clip.duration, minValue: 0, maxValue: clip.duration, target: nil, action: nil)
        super.init()
        window.title = tr("Trim Recording")
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = window.contentView!
        let preview = AVPlayerView(frame: CGRect(x: 16, y: 142, width: 588, height: 282))
        preview.player = player
        preview.controlsStyle = .inline
        content.addSubview(preview)
        for (slider, title, y) in [(start, tr("Start (seconds)"), CGFloat(109)), (end, tr("End (seconds)"), CGFloat(77))] {
            let label = NSTextField(labelWithString: title)
            label.frame = CGRect(x: 16, y: y, width: 130, height: 22)
            content.addSubview(label)
            slider.frame = CGRect(x: 150, y: y, width: 450, height: 22)
            slider.setAccessibilityLabel(title)
            slider.target = self
            slider.action = #selector(changed(_:))
            content.addSubview(slider)
        }
        summary.frame = CGRect(x: 16, y: 44, width: 580, height: 22)
        summary.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        content.addSubview(summary)
        let reset = NSButton(title: tr("Reset"), target: self, action: #selector(resetRange))
        reset.frame = CGRect(x: 16, y: 8, width: 90, height: 30)
        let cancel = NSButton(title: tr("Cancel"), target: self, action: #selector(cancel))
        cancel.frame = CGRect(x: 400, y: 8, width: 90, height: 30)
        cancel.keyEquivalent = "\u{1b}"
        let apply = NSButton(title: tr("Apply Trim"), target: self, action: #selector(apply))
        apply.frame = CGRect(x: 494, y: 8, width: 110, height: 30)
        apply.keyEquivalent = "\r"
        for button in [reset, cancel, apply] { content.addSubview(button) }
        updateSummary()
        player.seek(to: CMTime(seconds: start.doubleValue, preferredTimescale: 60_000))
    }

    @objc private func changed(_ slider: NSSlider) {
        if slider === start { start.doubleValue = min(start.doubleValue, end.doubleValue - 0.1) }
        else { end.doubleValue = max(end.doubleValue, start.doubleValue + 0.1) }
        player.pause()
        player.seek(to: CMTime(seconds: slider.doubleValue, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
        updateSummary()
    }

    private func updateSummary() {
        summary.stringValue = tr("Start %@ s · End %@ s · Length %@ s",
                                 String(format: "%.2f", start.doubleValue), String(format: "%.2f", end.doubleValue),
                                 String(format: "%.2f", end.doubleValue - start.doubleValue))
    }

    @objc private func resetRange() {
        start.doubleValue = 0
        end.doubleValue = clip.duration
        changed(start)
    }

    @objc private func cancel() { decided.resolve(.cancel) }
    @objc private func apply() {
        guard let range = ClipTrim(start: start.doubleValue, end: end.doubleValue, duration: clip.duration) else { return }
        decided.resolve(.apply(range.start == 0 && range.end == clip.duration ? nil : range))
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
}
