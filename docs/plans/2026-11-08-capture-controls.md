Toma will add five capture controls in separate commits on main. Each iteration includes regression tests, code review and local validation.

1. Reopen Last Recording retains one original in private local storage. Reopening creates an independent recovery copy and holds the thumbnail open. Discarding a fresh capture removes its retained copy. Replacement publishes new metadata before removing the previous original.
2. Thumbnail Auto-Save offers 6 seconds, 15 seconds, or Never. Format selection and reopened previews continue to require an explicit action.
3. Trim opens a native preview with start/end controls. Apply changes the export range without changing the original. Cancel preserves the previous range. Save, Copy and drag share the same range.
4. Record Window uses the macOS content picker and ScreenCaptureKit's window filter. It records the chosen window rather than its initial screen rectangle.
5. Countdown offers immediate recording or a three-second delay. Escape cancels before capture starts.

Existing recording recovery, export cancellation, format selection, audio, privacy and update checks must keep working. Tests use synthetic media and private pasteboards. Native UI checks use a synthetic test app/window. Installation happens after all iterations pass, avoiding repeated changes to the installed app's ad hoc signature.

Completed iterations:

| Addition | Validation |
| --- | --- |
| Reopen Last Recording | Independent copies, safe replacement, native MP4 clipboard copy. |
| Thumbnail Auto-Save | Timed and manual decisions, format hold, native preference persistence. |
| Trim | MP4, HEVC, GIF, audio timing, prepared-cache invalidation, native five-second clipboard export. |
| Record Window | Picker cancellation, geometry, live synthetic capture and title-bar drag. |
| Countdown | Tick order, cancellation, native completion and Escape, native preference persistence. |

The final local suite passes 41 Swift tests. Both release-script tests pass. No external packages were added. Each feature has a separate commit and a description in docs/changes. The timeout test has an additional correction commit because its initial fixed sleep raced concurrent test work.
