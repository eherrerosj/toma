Use portable bitrate settings for MP4 and HEVC to prevent an export crash on Intel Macs.

The `macos-26-intel` CI job crashed because its H.264 encoder rejects the inherited Quality property. Apple documents `AVVideoQualityKey` as a JPEG setting.

The exporter now scales its bitrate with the region size, between 250 kbit/s and 32 Mbit/s. It validates those settings before creating the writer input. Formats, dimensions and audio mixing stay the same. File sizes can differ on Apple silicon because rate control changed.

All 25 local Swift tests pass with compiler warnings treated as errors. The suite exports both formats with synthetic video and two audio tracks. Both CI architectures will run again after this push.
