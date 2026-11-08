import AppKit
import AVFoundation

/// The card's contents: a looping muted thumbnail and the format row.
final class CardView: NSVisualEffectView {
    private weak var owner: ResultCard?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var closeButton: NSButton?
    private var thumb: ThumbView?
    private var formatButtons: [Format: TextButton] = [:]
    private var saveButton: NSButton?
    private var copyButton: NSButton?
    private var durationBadge: NSTextField?

    init(frame: CGRect, owner: ResultCard) {
        self.owner = owner
        super.init(frame: frame)
        material = .popover
        state = .active
        blendingMode = .behindWindow
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func build(thumb frame: CGRect, bar: CGRect, clip: Clip, suggested: Format) {
        let item = AVPlayerItem(url: clip.master)
        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: item, timeRange: clip.trim?.timeRange ?? .invalid)
        self.player = player

        let thumb = ThumbView(frame: frame, owner: owner)
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6                   // concentric with the card: 12 − 6 pt inset
        thumb.layer?.cornerCurve = .continuous
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
        let video = AVPlayerLayer(player: player)
        video.videoGravity = .resizeAspect
        video.frame = thumb.bounds
        video.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        thumb.layer?.addSublayer(video)
        addSubview(thumb)
        self.thumb = thumb
        player.play()
        loadPoster(clip)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 5
        for (i, format) in Format.allCases.enumerated() {
            if i > 0 { row.addArrangedSubview(label("·", color: .tertiaryLabelColor, size: 12)) }
            let button = TextButton(format.label, emphasized: format == suggested, target: self, action: #selector(pick(_:)))
            button.tag = i
            button.toolTip = format.help
            button.setAccessibilityLabel(tr("Select %@ format", format.label))
            formatButtons[format] = button
            row.addArrangedSubview(button)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let save = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: tr("Save"))!,
                            target: self, action: #selector(saveToFolder))
        save.isBordered = false
        save.contentTintColor = .secondaryLabelColor
        save.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        save.translatesAutoresizingMaskIntoConstraints = false
        addSubview(save)
        saveButton = save

        let copy = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: tr("Copy"))!,
                            target: self, action: #selector(copyToClipboard))
        copy.isBordered = false
        copy.contentTintColor = .secondaryLabelColor
        copy.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        copy.toolTip = tr("Copy %@ to clipboard", suggested.label)
        copy.setAccessibilityLabel(tr("Copy %@ to clipboard", suggested.label))
        copy.translatesAutoresizingMaskIntoConstraints = false
        addSubview(copy)
        copyButton = copy
        select(suggested)

        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: leadingAnchor, constant: bar.midX),
            row.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -bar.midY),
            save.trailingAnchor.constraint(equalTo: copy.leadingAnchor, constant: -5),
            save.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            copy.trailingAnchor.constraint(equalTo: leadingAnchor, constant: frame.maxX - 2),
            copy.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        // Duration, quietly, in the thumbnail's corner: the one number worth knowing.
        let seconds = Int(clip.exportDuration.rounded())
        let badge = label(String(format: "%d:%02d", seconds / 60, seconds % 60), color: .white, size: 10, mono: true)
        durationBadge = badge
        badge.wantsLayer = true
        badge.shadow = { let s = NSShadow(); s.shadowBlurRadius = 3; s.shadowColor = .black.withAlphaComponent(0.6); s.shadowOffset = .zero; return s }()
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge, positioned: .above, relativeTo: thumb)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: frame.minX + 6),
            badge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(frame.minY + 4)),
        ])

        let close = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: tr("Discard"))!,
                             target: self, action: #selector(discard))
        close.isBordered = false
        close.contentTintColor = .white
        close.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        close.frame = CGRect(x: frame.minX + 4, y: frame.maxY - 22, width: 18, height: 18)
        close.isHidden = true
        addSubview(close)
        closeButton = close

        let trim = NSButton(image: NSImage(systemSymbolName: "scissors", accessibilityDescription: tr("Trim Recording"))!,
                            target: self, action: #selector(trimRecording))
        trim.isBordered = false
        trim.contentTintColor = .white
        trim.toolTip = tr("Trim Recording")
        trim.setAccessibilityLabel(tr("Trim Recording"))
        trim.frame = CGRect(x: frame.maxX - 28, y: frame.maxY - 26, width: 24, height: 24)
        trim.isEnabled = clip.duration >= 0.1
        addSubview(trim)

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    private func label(_ text: String, color: NSColor, size: CGFloat, mono: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: .medium) : .systemFont(ofSize: size)
        field.textColor = color
        return field
    }

    func select(_ format: Format) {
        for (choice, button) in formatButtons {
            button.emphasized = choice == format
            button.state = choice == format ? .on : .off
        }
        copyButton?.toolTip = tr("Copy %@ to clipboard", format.label)
        copyButton?.setAccessibilityLabel(tr("Copy %@ to clipboard", format.label))
        saveButton?.toolTip = tr("Save as %@", format.label)
        saveButton?.setAccessibilityLabel(tr("Save as %@", format.label))
    }

    func updatePreview(_ clip: Clip) {
        guard let player else { return }
        looper?.disableLooping()
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: clip.master),
                               timeRange: clip.trim?.timeRange ?? .invalid)
        player.play()
        loadPoster(clip)
        let seconds = Int(clip.exportDuration.rounded())
        durationBadge?.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func loadPoster(_ clip: Clip) {
        guard let thumb else { return }
        Task { [weak thumb] in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.master))
            generator.maximumSize = CGSize(width: 480, height: 320)
            let time = CMTime(seconds: clip.trim?.start ?? 0, preferredTimescale: 60_000)
            guard let (image, _) = try? await generator.image(at: time) else { return }
            thumb?.poster = NSImage(cgImage: image, size: .zero)
        }
    }

    @objc private func trimRecording() { Task { await owner?.edit() } }

    func stop() {
        player?.pause()
        looper = nil
        player = nil
    }

    @objc private func pick(_ sender: NSButton) { owner?.picked(Format.allCases[sender.tag]) }
    @objc private func discard() { owner?.discard() }
    @objc private func copyToClipboard() { owner?.copy() }
    @objc private func saveToFolder() { owner?.commit() }

    override func mouseEntered(with event: NSEvent) { closeButton?.isHidden = false; owner?.hover(true) }
    override func mouseExited(with event: NSEvent) { closeButton?.isHidden = true; owner?.hover(false) }
    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas { owner?.scrolled(event.scrollingDeltaX) }
    }
}

