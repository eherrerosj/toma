import AppKit

extension StatusItem {
    func addPreferences(to menu: NSMenu) {
        let folder = NSMenuItem(title: tr("Save To"), action: nil, keyEquivalent: "")
        let folderMenu = NSMenu()
        let current = item(FileManager.default.displayName(atPath: Library.destination.path), nil)
        current.image = NSWorkspace.shared.icon(forFile: Library.destination.path)
        current.image?.size = CGSize(width: 16, height: 16)
        current.state = .on
        folderMenu.addItem(current)
        folderMenu.addItem(.separator())
        folderMenu.addItem(item(tr("Other Folder…"), #selector(chooseFolder)))
        if Preferences.folder != nil {
            folderMenu.addItem(item(tr("Use Screenshots Folder"), #selector(resetFolder)))
        }
        folderMenu.addItem(item(tr("Show in Finder"), #selector(revealFolder)))
        folder.submenu = folderMenu
        menu.addItem(folder)

        let gif = NSMenuItem(title: tr("GIF Size"), action: nil, keyEquivalent: "")
        let gifMenu = NSMenu()
        for size in Preferences.GIFSize.allCases {
            let option = item(size.title, #selector(chooseGIFSize(_:)))
            option.representedObject = size.rawValue
            option.state = Preferences.gifSize == size ? .on : .off
            option.toolTip = size.detail
            option.subtitle = size.detail
            gifMenu.addItem(option)
        }
        gif.submenu = gifMenu
        menu.addItem(gif)

        let timeout = NSMenuItem(title: tr("Thumbnail Auto-Save"), action: nil, keyEquivalent: "")
        let timeoutMenu = NSMenu()
        for choice in Preferences.ThumbnailTimeout.allCases {
            let option = item(choice.title, #selector(chooseThumbnailTimeout(_:)))
            option.representedObject = choice.rawValue
            option.state = Preferences.thumbnailTimeout == choice ? .on : .off
            timeoutMenu.addItem(option)
        }
        timeout.submenu = timeoutMenu
        menu.addItem(timeout)

        let delay = NSMenuItem(title: tr("Start Recording"), action: nil, keyEquivalent: "")
        let delayMenu = NSMenu()
        for choice in Preferences.RecordingDelay.allCases {
            let option = item(choice.title, #selector(chooseRecordingDelay(_:)))
            option.representedObject = choice.rawValue
            option.state = Preferences.recordingDelay == choice ? .on : .off
            delayMenu.addItem(option)
        }
        delay.submenu = delayMenu
        menu.addItem(delay)

        let sound = NSMenuItem(title: tr("Sound"), action: nil, keyEquivalent: "")
        let soundMenu = NSMenu()
        for audio in Preferences.Audio.allCases {
            let option = item(audio.title, #selector(chooseAudio(_:)))
            option.representedObject = audio.rawValue
            option.state = Preferences.audio == audio ? .on : .off
            soundMenu.addItem(option)
        }
        sound.submenu = soundMenu
        menu.addItem(sound)

    }

    @objc func chooseRecordingDelay(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let choice = Preferences.RecordingDelay(rawValue: raw) else { return }
        Preferences.recordingDelay = choice
    }

    @objc func chooseThumbnailTimeout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let choice = Preferences.ThumbnailTimeout(rawValue: raw) else { return }
        Preferences.thumbnailTimeout = choice
    }

    @objc func recordWindow() { onRecordWindow() }

    @objc func reopenLast() { onReopen?() }

    @objc func chooseFolder() { Preferences.chooseFolder() }
    @objc func resetFolder() { Preferences.folder = nil }
    @objc func revealFolder() { NSWorkspace.shared.open(Library.destination) }

    @objc func chooseGIFSize(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let size = Preferences.GIFSize(rawValue: raw) {
            Preferences.gifSize = size
        }
    }

    @objc func chooseAudio(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let audio = Preferences.Audio(rawValue: raw) {
            Preferences.choose(audio)
        }
    }

}
