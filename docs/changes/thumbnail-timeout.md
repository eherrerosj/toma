Thumbnail Auto-Save now lets users choose 6 seconds, 15 seconds, or Never.

The fixed six-second timeout made untouched previews disappear before users were ready. The menu now stores the selected delay. Never requires Save, Copy, drag, discard, or the recording shortcut to finish the preview.

The default remains six seconds. Hovering pauses the timer. Selecting a format and reopening the last recording still hold the thumbnail open.

Validation covers automatic saving, manual saving, configured delays and format selection past the timeout. The initial fixed-delay test raced concurrent work. It now waits for the decision with a two-second deadline. All 32 Swift tests pass with compiler warnings treated as errors. Review kept the timer in ResultCard and the persisted choice in Preferences, with no new scheduling layer.

This changes thumbnail behavior only. Existing saved preferences without this setting use the six-second default.
