# Due diligence remediation

The changes address all 14 high and medium findings in the 7 November 2026 report. The app now preserves failed recordings, serializes exports and uses a separate personal identity. Updates validate the full signing identity and release metadata. Automated tests cover the identified failures.

| Finding | Change | Main verification |
|---|---|---|
| DD-01 | Original masters survive failures and restarts. Recovery copies bypass encoding. Final delivery stages beside its destination. | Storage tests and failed-destination media test. |
| DD-02 | Drag delivery claims the card before awaiting a write. The library rejects competing consumption. | Gated drag/hotkey regression test. |
| DD-03 | Personal bundle ID, recovery/cache paths, app name, release feed and download links. | Bundle inspection and feed tests. |
| DD-04 | Required digest, HTTPS paths, Developer ID application requirement, all-slice checks, Gatekeeper assessment and exact version. | Invalid-feed and signing-rejection tests. |
| DD-05 | Clipboard expiry runs every minute and at launch. | Controlled-clock file expiry test. |
| DD-06 | Privacy text explains update traffic, retained masters and actual clipboard expiry. Automatic checks default to off. | Both landing languages and structured data checks. |
| DD-07 | Each process owns a unique workspace. Startup preserves masters and other workspaces. | Two-store isolation test. |
| DD-08 | Swift regression/media suite, release-script tests and macOS CI for Apple silicon and Intel. | Local tests and the committed workflow. |
| DD-09 | GIF holds split into valid delay chunks. | Independent ImageIO duration checks at the 16-bit boundary. |
| DD-10 | GIF export requires successful reader completion. | Truncated-movie regression test that failed without the fix. |
| DD-11 | Capture disk, duration and size limits; bounded GIF concurrency; export cancellation. | Resource-policy tests and cancelled media export. |
| DD-12 | Capture callback deadlines, cancellable media waits and terminated subprocesses. | Missing-callback, cancellation and hung-tool tests. |
| DD-13 | Explicit release signer and captured build SHA, verified against the embedded bundle commit. | Isolated release-script test. |
| DD-14 | Build output discovery uses SwiftPM. | Successful local universal bundle build and inspection. |

Local validation includes 25 Swift tests with compiler warnings treated as errors and 2 release-script tests. Synthetic integration tests exercise MP4, HEVC, GIF and clipboard delivery. A two-track synthetic audio fixture exports as one AAC track in MP4 and HEVC.

A live screen test recorded only the local synthetic animation. The app showed its result card and saved a playable 1204 by 462 H.264 MP4 lasting 30.89 seconds. Saving removed the original from recovery storage. The local app also launched successfully.

A valid signed update installation and notarized personal release still require the owner's Developer ID and notary credentials. This work does not publish a release. Real microphone capture, display unplugging and storage exhaustion on a test volume remain manual checks. The 7 low-priority audit findings remain outside this remediation scope.
