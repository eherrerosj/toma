import Foundation
import UniformTypeIdentifiers

/// The things a user can get out of Toma.
nonisolated enum Format: String, CaseIterable, Sendable {
    /// H.264 in MP4: plays everywhere.
    case mp4
    /// HEVC in MOV: same look, about half the size; Apple devices and modern browsers.
    case hevc
    case gif

    var label: String {
        switch self {
        case .mp4: "MP4"
        case .hevc: "HEVC"
        case .gif: "GIF"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4: "mp4"
        case .hevc: "mov"
        case .gif: "gif"
        }
    }

    var type: UTType {
        switch self {
        case .mp4: .mpeg4Movie
        case .hevc: .quickTimeMovie
        case .gif: .gif
        }
    }

    @MainActor var help: String {
        switch self {
        case .mp4: tr("H.264 video · works everywhere")
        case .hevc: tr("HEVC video · half the size, ideal on Apple")
        case .gif: tr("Animated GIF · %@", Preferences.gifSize.title.lowercased())
        }
    }
}

