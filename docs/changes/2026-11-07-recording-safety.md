Preserve original recordings after export failures and serialize delivery so a drag write cannot race with a hotkey save.

DD-01 and DD-02 exposed failures that could destroy a recording or consume it twice. Clipboard expiry ran only at launch. Shared cleanup could delete another process’s active files.

Masters now survive in recovery storage. A recovery action copies the original without encoding. Each process owns its workspace. Delivery claims the clip before awaiting a write. Clipboard expiry runs every minute and at launch.

The fork uses its own application identity, storage and update repository. Automatic checks default to off. Updates require the expected Developer ID identity, SHA-256 digest and advertised version. Capture startup, downloads and tools have deadlines. Capture has disk, size and duration limits. GIF concurrency considers working memory.

GIF export splits long delays and rejects decoder failures. Packaging discovers the executable path. Releases require an explicit signer and target the captured build commit.

Validation passed:

1. Run `swift test -Xswiftc -warnings-as-errors`: 23 tests pass.
2. Run `python3 -m unittest discover -s Tests -v`: 2 tests pass.
3. Build the universal app and inspect its bundle.
4. Capture the synthetic animation and confirm a playable 1204 by 462 H.264 MP4.

The app launches successfully. Personal builds require a separate Screen Recording grant. No notarized release or valid signed update installation was performed.
