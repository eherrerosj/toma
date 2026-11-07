Finish the DD fixes with atomic export delivery, accurate privacy text and automatic macOS checks on both supported architectures.

The privacy promises did not match update traffic or retained files. A final move across volumes could expose a partial export. Delivery now stages beside its destination and preserves an existing destination. Cancelling an export also clears the queued recording.

Tests cover final delivery and mixing two synthetic audio tracks into one AAC track for MP4 and HEVC. GitHub Actions runs tests and inspects the universal bundle on `macos-26` and `macos-26-intel`. Repository permissions are read-only.

The README, both landing languages, FAQ data and architecture document explain the personal identity, update checks, retained originals, expiry, capture limits and signing requirements. Downloads use `eherrerosj/toma`. The fork removes the upstream analytics script. Version 1.3.1 and the changelog record these changes. The completion record maps all 14 high and medium findings to fixes and checks.

Local validation passes:

1. Run `swift test -Xswiftc -warnings-as-errors`: 25 tests pass.
2. Run `python3 -m unittest discover -s Tests -v`: 2 tests pass.
3. Parse both landing files and their FAQ data.

The earlier live synthetic recording passed. CI awaits this push. No signed release or valid signed update installation was performed.
