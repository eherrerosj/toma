import AppKit
@preconcurrency import ScreenCaptureKit
import AVFoundation
import Synchronization

/// Everything Toma knows about ScreenCaptureKit and TCC lives here and nowhere else.
/// Public surface: `ensureAccess()`, `start(_:)`, `stop()`, `clip`. Callers never see
/// SCStream, SCContentFilter, configurations, delegates, or the temp file's location policy.
///
/// Records straight to an MP4 "master" with SCRecordingOutput (H.264, native pixels, up to
/// 60 fps, sRGB, cursor visible, sound per Preferences.audio). The master is the single source every export
/// derives from; nothing else is captured or buffered.
final class Recording {
    /// Pre-flight before the overlay ever appears, so the user never drags a region only to
    /// be told it can't be recorded. Returns true only when capture will actually work right now.
    static func ensureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        // The first ask shows the system prompt and registers Toma in Settings; that prompt is
        // enough. Later asks get our alert, because macOS applies the grant only after a relaunch.
        let asked = "permisoSolicitado"
        guard UserDefaults.standard.bool(forKey: asked) else {
            UserDefaults.standard.set(true, forKey: asked)
            CGRequestScreenCaptureAccess()
            return false
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = tr("Toma needs permission to record the screen.")
        alert.informativeText = tr("Turn it on in Settings › Privacy & Security › Screen Recording, then reopen Toma.")
        alert.addButton(withTitle: tr("Open Settings"))
        alert.addButton(withTitle: tr("Quit"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        NSApp.terminate(nil)
        return false
    }

    /// Starts capturing `region`. Returns once the file is being written, so the
    /// menu-bar timer starts at the real start of the file.
    ///
    /// Toma's own app is excluded from the filter — this, not window sharingType, is what keeps
    /// the veil, frame and card out of the video.
    static func start(_ region: ScreenRegion) async throws(TomaError) -> Recording {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw .permissionDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw .displayUnavailable
        }
        let me = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.sourceRect = region.sourceRect
        (config.width, config.height) = region.pixelSize
        config.scalesToFit = false
        config.captureResolution = .best
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        let audio = Preferences.audio
        config.capturesAudio = audio != .none
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = audio == .systemAndMicrophone
        config.sampleRate = 48_000
        config.channelCount = 2
        config.colorSpaceName = CGColorSpace.sRGB
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6

        let master: URL
        do { master = try Library.storage.newMasterURL() }
        catch { throw .streamFailed(underlying: error.localizedDescription) }

        do {
            let available = try ResourceBudget.availableBytes(at: master.deletingLastPathComponent())
            guard available >= ResourceBudget.minimumFreeBytes else { throw TomaError.streamFailed(underlying: "low disk space") }
        } catch { throw .streamFailed(underlying: error.localizedDescription) }

        let sink = RecordingSink()
        let output = SCRecordingOutputConfiguration()
        output.outputURL = master
        output.videoCodecType = .h264
        output.outputFileType = .mp4

        let stream = SCStream(filter: filter, configuration: config, delegate: sink)
        let recordingOutput = SCRecordingOutput(configuration: output, delegate: sink)
        do { try stream.addRecordingOutput(recordingOutput) }
        catch { throw .streamFailed(underlying: error.localizedDescription) }
        let captureStarted = OneShot<Outcome>()
        let startup = Task {
            do {
                try await stream.startCapture()
                if Task.isCancelled { try? await stream.stopCapture() }
                captureStarted.resolve(.ok)
            } catch { captureStarted.resolve(.failed(error.localizedDescription)) }
        }
        do {
            if case .failed(let reason) = try await captureStarted.wait(timeout: .seconds(10)) {
                throw TomaError.streamFailed(underlying: reason)
            }
            if case .failed(let reason) = try await sink.started.wait(timeout: .seconds(10)) {
                throw TomaError.streamFailed(underlying: reason)
            }
        } catch {
            startup.cancel()
            Task { try? await stream.stopCapture() }
            throw .streamFailed(underlying: error.localizedDescription)
        }
        return Recording(stream: stream, output: recordingOutput, sink: sink, master: master, region: region)
    }

    /// Requests the end of the recording. Idempotent and non-blocking: the first call stops the
    /// stream, later calls do nothing. The result arrives through `clip`.
    ///
    /// The file is finalized by removing the recording output first, then stopping the stream.
    /// If neither call settles within a few seconds, the recording is closed with whatever
    /// reached the disk, so the menu bar can never stay stuck on the timer.
    func stop() {
        guard !stopRequested else { return }
        stopRequested = true
        watchdog?.cancel()
        let stream = self.stream, output = self.output, sink = self.sink
        Task {
            try? stream.removeRecordingOutput(output)
            do { try await stream.stopCapture() } catch { sink.streamEnded() }
        }
        Task {
            try? await Task.sleep(for: .seconds(5))
            sink.streamEnded()          // no-op when the recording already finished
        }
    }

    /// The finished master, available once the file is finalized — after `stop()`, or after the
    /// system ended the stream (display unplugged, user hit the system "stop sharing" control).
    /// Throws only if nothing playable was written. Awaiting it twice returns the same Clip.
    var clip: Clip {
        get async throws(TomaError) {
            if let finished { return try finished.get() }
            let outcome = await sink.finished.value
            let result: Result<Clip, TomaError>
            if case .failed(let reason) = outcome, !FileManager.default.fileExists(atPath: master.path) {
                result = .failure(.streamFailed(underlying: reason))
            } else if let duration = try? await AVURLAsset(url: master).load(.duration), duration.seconds > 0 {
                result = .success(Clip(master: master, duration: duration.seconds, region: region))
            } else {
                result = .failure(.streamFailed(underlying: "empty file"))
            }
            watchdog?.cancel()
            finished = result
            return try result.get()
        }
    }

    private let stream: SCStream
    private let output: SCRecordingOutput
    private let sink: RecordingSink
    private let master: URL
    private let region: ScreenRegion
    private var watchdog: Task<Void, Never>?
    private(set) var limitReason: String?
    private var stopRequested = false
    private var finished: Result<Clip, TomaError>?

    private init(stream: SCStream, output: SCRecordingOutput, sink: RecordingSink, master: URL, region: ScreenRegion) {
        self.stream = stream
        self.output = output
        self.sink = sink
        self.master = master
        self.region = region
        let began = ContinuousClock.now
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                let elapsed = Double((ContinuousClock.now - began).components.seconds)
                do {
                    let size = (try FileManager.default.attributesOfItem(atPath: master.path)[.size] as? NSNumber)?.int64Value ?? 0
                    let available = try ResourceBudget.availableBytes(at: master.deletingLastPathComponent())
                    if let reason = ResourceBudget.stopReason(elapsed: elapsed, bytes: size, available: available) {
                        limitReason = reason
                        stop()
                        return
                    }
                } catch {
                    limitReason = "Recording stopped because its storage became unavailable."
                    stop()
                    return
                }
            }
        }
    }

    isolated deinit { watchdog?.cancel() }
}

/// A finished recording, not yet saved anywhere the user can see.
/// Invariant: `master` is a finalized, playable MP4 in Toma's recovery folder; Library consumes it
/// exactly once (save, copy or discard).
nonisolated struct Clip: Sendable {
    let master: URL
    /// Seconds.
    let duration: Double
    let region: ScreenRegion
    var trim: ClipTrim? = nil
    var exportDuration: Double { trim?.duration ?? duration }
}

nonisolated enum Outcome: Sendable {
    case ok
    case failed(String)
}

/// Private bridge from ScreenCaptureKit's delegate callbacks (arbitrary queues) to async.
private nonisolated final class RecordingSink: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, Sendable {
    let started = OneShot<Outcome>()
    let finished = OneShot<Outcome>()

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        started.resolve(.ok)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        started.resolve(.failed(error.localizedDescription))
        finished.resolve(.failed(error.localizedDescription))
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finished.resolve(.ok)
    }

    /// The system ended the stream (display gone, "stop sharing", permission revoked).
    /// SCRecordingOutput finalizes on its own; give it a moment, then settle with what exists.
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        started.resolve(.failed(error.localizedDescription))
        streamEnded()
    }

    func streamEnded() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [finished] in
            finished.resolve(.ok)
        }
    }
}
