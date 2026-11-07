# Toma Personal architecture

Toma Personal records a selected region and exports it as MP4, HEVC or GIF. Its original recording survives a failed export and restart. The app uses the `io.github.eherrerosj.toma` identity and the `eherrerosj/toma` release feed.

## Session ownership

`Toma` owns the session phases: idle, busy, recording, reviewing and saving. The menu and welcome window forward actions to that session. `ScreenRegion` establishes display bounds, coordinate conversion and even pixel dimensions before capture starts.

`Recording` owns ScreenCaptureKit and the permission check. It excludes the app's process from screen capture. System sound and microphone capture follow the user's menu setting. Startup waits have deadlines. Stop requests are idempotent; the recording output finalizes the master before review.

The result card offers save, copy, discard and drag delivery. Drag delivery claims its operation before awaiting storage. It blocks competing decisions until the write finishes. The library also claims each master during consumption. A cancelled or failed drag leaves the card available for another action.

## Files and recovery

`RecordingStorage` owns three locations:

| Location | Contents | Removal |
|---|---|---|
| Application Support, personal bundle ID, `Recovery` | Original MP4 recordings. | After successful save/copy or explicit discard. Failed originals remain across restarts. |
| Caches, personal bundle ID, `Clipboard` | Files placed on the clipboard. | After 24 hours, checked every minute while running and at launch. |
| Temporary directory, personal bundle ID, process UUID | Encoded intermediates. | On export failure or normal process exit. Other processes' workspaces are untouched. |

The recovery and clipboard directories use private permissions. Startup never deletes recovery files. The menu opens the recovery folder. An export error offers a direct copy of the original MP4, without another encoder call. The recovery copy stages beside its destination and does not overwrite an existing file.

A crash before the capture output finalizes can still leave an unplayable MP4. Preserving that file does not repair it. A closed app cannot enforce clipboard expiry until it runs again. Other apps can retain files the user pastes into them.

## Media exports

`Transcoder` uses AVFoundation to make MP4 or HEVC video. Its average bitrate scales with the region size, from 250 kbit/s to 32 Mbit/s. It validates the settings before creating a writer input. The JPEG quality key is excluded because Intel H.264 encoders reject it with an Objective-C exception. It mixes system and microphone tracks into one AAC track. It checks reader/writer completion and supports task cancellation while waiting for encoder capacity. Writer finalization has a deadline.

`GIFEncoder` reads sequential frames and batches independent changed regions through `GIF`. It requires successful reader completion before accepting the export. A decoder failure removes the incomplete GIF and keeps its master. The GIF writer splits holds that exceed the format's 16-bit delay field.

Sharp GIF exports have a maximum long edge of 1920 pixels at 20 fps. Light exports use 640 pixels at 15 fps. Concurrency uses a working-memory estimate with a 128 MiB batch budget and a maximum of four jobs. This estimate does not guarantee a process RSS ceiling.

Capture stops at one hour, a 4 GiB master, or less than 256 MiB free disk space. Disk and file size checks run once per second. Export cancellation leaves the original available for recovery.

## Updates and releases

Automatic update checks default to off. A manual check, or an enabled automatic check, reads the personal repository's release feed. The parser requires stable numeric versions, the expected HTTPS release paths and a 64-character SHA-256 digest.

Updates download at most 32 MiB, use HTTPS redirects only on the allowed GitHub hosts and have a resource deadline. The digest is computed in chunks. The staged application must satisfy the expected Apple trust anchor, Developer ID Application certificate class, team and application identifier across all binary slices. Gatekeeper assessment must also succeed. The staged version must equal the advertised version and exceed the current version.

A private, unique staging directory protects the replacement. The helper rechecks its signing requirement immediately before the swap. It restores the old app when the replacement move or launch request fails. Ad hoc local builds cannot supply a trusted update identity. A valid Developer ID and notarized personal release remain necessary for a complete signed update rehearsal.

`ToolRunner` drains bounded subprocess output and terminates a tool when it times out or its task is cancelled. Capture callbacks use cancellable one-shot waits. Capture and update installation cannot start concurrently.

The build script discovers the SwiftPM output directory. Local builds default to ad hoc signing. Releases require an explicit signing identity and team. The release script pins the full build commit, checks the embedded commit and targets that commit when publishing through the personal GitHub account.

## Validation

`Tests/TomaTests` covers screen-region invariants, long GIF holds, damaged media, all export formats, clipboard writes, original recovery, expiry, delivery races, resource policies, callback deadlines, subprocess deadlines and update trust rejection. Media tests use synthetic pixels and audio through real Apple encoders. They do not request screen or microphone access.

`Tests/test_release.py` runs the release script with isolated command stubs. It checks the personal account/repository and the built commit target. `scripts/check-bundle.py` checks bundle identity, resources, both architectures and code signatures.

GitHub Actions runs the tests and builds the universal app on macOS 26 Apple silicon and Intel. Local UI testing uses a synthetic animation confined to the selected recording region. Permission prompts, real microphones and a valid signed update require separate runtime checks.
