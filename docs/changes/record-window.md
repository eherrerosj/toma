Record Window lets users capture a chosen window without drawing a region around it.

Region capture records fixed screen coordinates. Moving a window can reveal surrounding content or move the intended content outside the recording. The new menu action uses the macOS single-window picker and its window-specific filter. The recording follows the selected window. It excludes its shadow and preserves the existing audio choices, export formats and recovery behavior.

The region shortcut keeps its existing behavior. Picker cancellation returns to idle without creating a recording. The picker cannot change the selected content during a session. Capture uses the window's native scale with even output dimensions. Moving or resizing a window keeps the initial output dimensions.

All 39 Swift tests pass with compiler warnings treated as errors. Window geometry tests cover large windows, Retina scaling, even dimensions and invalid input. Both release-script tests pass. Native picker opening and cancellation pass. The user selected the synthetic target through the picker. The resulting H.264 video is 1200 × 664 and 117.03 seconds long. Early and late frames contain only the target window. A title-bar drag exercised capture while moving the target.

Review reused the existing recording startup, output and resource-limit path for both capture modes. The new code adds no upload or background capture behavior.
