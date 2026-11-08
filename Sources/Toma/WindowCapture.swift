import AppKit
@preconcurrency import ScreenCaptureKit

// Window geometry is content-local; a window can be larger than its current display.
enum WindowCapture {
    static func geometry(size: CGSize, scale: CGFloat, displayID: CGDirectDisplayID) -> ScreenRegion? {
        guard size.width.isFinite, size.height.isFinite, scale.isFinite,
              size.width >= 8, size.height >= 8, scale > 0, scale <= 4,
              size.width * scale <= 16_384, size.height * scale <= 16_384 else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        return ScreenRegion(dragged: bounds, displayFrame: bounds, scale: scale, displayID: displayID)
    }
}

final class WindowPicker: NSObject, SCContentSharingPickerObserver {
    private let finished = OneShot<Bool>()
    private var filter: SCContentFilter?
    private var failure: String?
    private var resolved = false

    static func select() async throws -> SCContentFilter? {
        let observer = WindowPicker()
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = .singleWindow
        configuration.allowsChangingSelectedContent = false
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? AppIdentity.bundleIdentifier]
        picker.defaultConfiguration = configuration
        picker.add(observer)
        picker.isActive = true
        defer { picker.remove(observer) }
        picker.present(using: .window)
        _ = await observer.finished.value
        if let failure = observer.failure { throw TomaError.streamFailed(underlying: failure) }
        return observer.filter
    }

    static func deactivate() { SCContentSharingPicker.shared.isActive = false }

    private func finish(filter: SCContentFilter? = nil, failure: String? = nil) {
        guard !resolved else { return }
        resolved = true
        self.filter = filter
        self.failure = failure
        finished.resolve(true)
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in self.finish(filter: filter) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in self.finish(failure: error.localizedDescription) }
    }
}
