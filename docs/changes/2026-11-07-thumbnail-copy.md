Keep the thumbnail open after selecting a format so the user can copy that format to the clipboard.

The format buttons previously saved the recording immediately, which closed the thumbnail before the user could press Copy.

Selecting MP4, HEVC or GIF now pauses automatic saving. A separate Save button writes the selected format. Copy, drag, Save, shortcut and swipe actions all use that selection. The selected label is highlighted. Save and Copy accessibility labels and tooltips update with the format. Untouched thumbnails still auto-save after six seconds. Drag delivery still blocks competing actions.

Version 1.3.2 includes updated README, changelog, English and Spanish strings.

Validation passed:

1. Run `swift test -Xswiftc -warnings-as-errors`: 29 tests pass.
2. Check selection followed by Copy, explicit Save, drag delivery, timer retention and the delivery guard.
3. Select GIF in the local UI fixture. Both action labels update and the thumbnail remains open beyond 30 seconds.
