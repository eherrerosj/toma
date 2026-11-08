<h1 align="center">
  <img src="https://raw.githubusercontent.com/eherrerosj/toma/main/docs/assets/toma-hero.svg" alt="Toma: ⇧⌘4, but for video. Record a region of your Mac screen. MP4, HEVC or GIF." width="100%">
</h1>

<div align="center">

**⇧⌘4, but for video.**
Record a region of your Mac screen and save it as MP4, HEVC or GIF. Nothing else.

[![Version](https://img.shields.io/github/v/release/eherrerosj/toma?label=version&color=2383E2)](https://github.com/eherrerosj/toma/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-26%2B-37352F)](https://github.com/eherrerosj/toma/releases/latest)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138)](https://swift.org)
[![License](https://img.shields.io/github/license/eherrerosj/toma?label=license&color=787774)](LICENSE)

[Original website](https://toma.felipebasurto.com) ·
[Download](https://github.com/eherrerosj/toma/releases/latest/download/Toma.dmg) ·
[Architecture](docs/arquitectura.md) ·
[Changelog](CHANGELOG.md)

</div>

This is Enrique Herreros’s personal fork of [Felipe Basurto’s Toma](https://github.com/felipebasurto/toma).
The app is named **Toma Personal** and uses its own preferences, recording storage and update feed.

Toma lives in the menu bar. You press a shortcut, draw a rectangle, and it records. There is
no settings window, no account and no editor. It records a region of your screen and saves it well.

## Install

Build this fork from source using the steps below. This change does not publish a notarized personal release.
A local build produces **Toma Personal.app**, so it can coexist with the original Toma.

Requires macOS 26 or later and Xcode 26 with Swift 6.2 or later. The app supports Apple silicon and Intel.
Grant Screen Recording permission to Toma Personal before recording. The interface follows the system language (English or Spanish).

Automatic update checks are **off by default**. Use **Check for Updates…** for a manual check, or enable
**Check for Updates Automatically** in the menu. Both use releases from `eherrerosj/toma`.
Checks report a failure until that repository has a suitable personal release.

## Usage

<p align="center">
  <img src="docs/assets/tarjeta.png" alt="The Toma thumbnail after recording: the looping clip, its duration, and the MP4, HEVC and GIF formats, with a copy button." width="380">
</p>

| | |
|---|---|
| <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>4</kbd> | Start: drag a region. Recording begins as soon as you let go. |
| <kbd>Space</kbd> while dragging | Move the region. |
| <kbd>⇧</kbd> while dragging | Lock an axis. |
| <kbd>⌥</kbd> while dragging | Grow from the centre. |
| <kbd>Esc</kbd> | Cancel the selection. |
| <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>4</kbd> again, or **■ 0:07** in the bar | Stop recording. |

When it ends, a thumbnail appears at the bottom right, like screenshots do:

- **MP4 · HEVC · GIF**: select the format. The thumbnail stays open so you can choose an action.
- **Save** (the download icon): saves the selected format to your chosen folder.
- **Copy**: puts the selected format on the clipboard, ready to paste into Slack, Mail or WhatsApp.
- **Drag**: drop the thumbnail into any app or folder in the selected format.
- **Do nothing**: an untouched thumbnail auto-saves after 6 s. Selecting a format pauses that automatic save.
- **×**: discards the recording.

Choose **Reopen Last Recording** from the menu bar to copy or export it again. Toma keeps one original locally in its private `Recent` folder until the next recording replaces it. Reopened thumbnails stay open until you choose an action. Discarding a new recording removes its recent copy.

If you press the shortcut while the thumbnail is on screen, Toma saves the recording and starts another.

## Formats

| | What for | 4 s of scrolling text, 1120 × 720 |
|---|---|---|
| **MP4** | H.264, works everywhere | 0.46 MB |
| **HEVC** | Half the size, ideal on Apple devices and modern browsers | 0.25 MB |
| **GIF** | Animation without a player, for READMEs, chats and docs | Sharp or light |

Toma first records an original and re-encodes it with a bitrate that scales with the region size.
MP4 and HEVC use compression settings supported on Apple silicon and Intel. The format you usually pick starts
encoding while you look at the thumbnail, so saving it is immediate.

The GIF uses a custom encoder built for screens. Each frame only stores what changed, and interface
colours stay exact. Gradients are smoothed out without banding.

## Options

In the menu bar, each one shows its current value:

- **Save to**: a folder of your choice, or the same one screenshots use (default).
- **GIF size**: *Sharp* (up to 1920 px, 20 fps) or *Light* (640 px, 15 fps).
- **Sound**: no sound, the Mac's sound, or the Mac's sound and your microphone.
- **Open at login**.

## Privacy and recovery

Recordings and exports stay on your Mac. The desktop app has no analytics or recording upload feature.
It contacts GitHub only for a manual update check or when automatic update checks are enabled.
Downloads also contact GitHub’s release asset servers. macOS can contact Apple during signature and notarization assessment.

Original recordings live in `~/Library/Application Support/io.github.eherrerosj.toma/Recovery`.
A successful save or copy removes its original. Discard also removes it. A failed export keeps the original
across restarts. Choose **Show Recoverable Recordings** in the menu to find it. Remove unwanted recovered files in Finder.
**Save Original…** copies the MP4 without encoding when the destination or encoder fails.

Clipboard copies use `~/Library/Caches/io.github.eherrerosj.toma/Clipboard`. They expire after 24 hours.
The app checks expiration every minute while it runs and at launch. If the app is closed, expired copies
remain until the next launch or operating-system cache cleanup. Other apps can retain copies pasted into them.

Toma’s own process is excluded from its screen capture. Capture stops at one hour, 4 GiB of master data,
or less than 256 MiB free disk space. The disk and size checks run once per second.
GIF encoding uses at most four jobs and estimates each job’s working memory within a 128 MiB batch budget.
One full-size frame can exceed that estimate; the budget is a concurrency limit, not a process RSS guarantee.
Click the progress icon, or press the recording shortcut, to cancel an export and keep its original for recovery.

The landing website requests Google Fonts and GitHub release metadata. This fork removes the upstream analytics
script. Download-click analytics are disabled in the checked-in configuration and require separate setup.

## Build from source

You need Xcode 26 (Swift 6.2). There are no dependencies.

```bash
git clone https://github.com/eherrerosj/toma.git
cd toma
./build.sh        # → Toma Personal.app
./build.sh dmg    # → Toma Personal.app and Toma.dmg
```

Local builds use an ad hoc signature. Set `SIGNING_IDENTITY` explicitly to use your own development certificate.
A stable certificate keeps the Screen Recording grant across rebuilds. Never rely on certificate selection order.
Personal releases require `SIGNING_IDENTITY`, `SIGNING_TEAM` and a notarytool profile (`NOTARY_PROFILE`, default `toma`).
The release script verifies the personal GitHub account, pins the built commit and requires notarization.
No release is published by the build command alone.

Run `swift test` for the media and regression suite. Run `python3 -m unittest discover -s Tests -v` for release-script tests.
Run `python3 scripts/check-bundle.py` after building to check identity, resources, signatures and both architectures.

## How it's built

The Swift code stays in one executable module. Tests cover pure logic and synthetic media through real Apple encoders:

| File | What it knows |
|---|---|
| `Toma.swift` | The state (a state machine with one verb: `toggle()`) and the history of a recording. |
| `Region.swift` | Coordinates: a region can only exist if it can be recorded exactly as drawn. |
| `Recording.swift` | ScreenCaptureKit and permissions. |
| `Library.swift` | Folders, names, formats and re-encoding. |
| `GIF.swift` | The GIF encoder. |
| `Overlay.swift`, `ResultCard.swift`, `StatusItem.swift` | The interface. |

The reasoning behind each decision is in [docs/arquitectura.md](docs/arquitectura.md).

## License

[MIT](LICENSE). Made by [Felipe Basurto](https://felipebasurto.com).
