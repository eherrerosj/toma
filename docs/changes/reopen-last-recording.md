Toma can reopen the last recording so users can copy it again or export another format.

Closing the thumbnail previously left users searching for files. Saving also consumed the original, preventing another export from that thumbnail.

Toma now retains one original in private local storage. Reopen Last Recording creates an independent recovery copy and opens a thumbnail without an automatic timeout. A new capture replaces the retained original only after its copy and metadata succeed. Discarding a fresh capture removes its recent copy. Reopened previews can be dismissed without deleting the retained original.

Validation covers independent copies, replacement failures, replacement cleanup and discard matching. The 30 Swift tests pass with compiler warnings treated as errors. The native test uses synthetic media and a private pasteboard.

Storage increases by at most one retained original during normal use. Failed exports remain available through Recoverable Recordings. Developer ID signing remains outside this change.
