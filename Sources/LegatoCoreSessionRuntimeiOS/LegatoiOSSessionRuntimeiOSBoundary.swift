import Foundation
import LegatoCore

/// Placeholder boundary target for the iOS-only Session runtime split.
/// Milestone 1 scope guard: this target only hosts Session runtime extraction.
/// Now Playing, Remote Command, and AVPlayer adapters remain unchanged.
internal enum LegatoiOSSessionRuntimeiOSBoundary {
    static func makeHostSafePlaceholder() -> any LegatoiOSSessionRuntime {
        LegatoiOSNoopSessionRuntime()
    }
}
