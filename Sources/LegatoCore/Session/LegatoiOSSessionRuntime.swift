import Foundation

public enum LegatoiOSInterruptionResumeIntent: Equatable {
    case shouldResume
    case shouldNotResume
    case unknown
}

public enum LegatoiOSRouteChangeReason: Equatable {
    case oldDeviceUnavailable
    case noSuitableRoute
    case newDeviceAvailable
}

public enum LegatoiOSSessionSignal: Equatable {
    case interruptionBegan
    case interruptionEnded(intent: LegatoiOSInterruptionResumeIntent)
    case outputRouteLost(reason: LegatoiOSRouteChangeReason)
    case outputRouteAvailable(reason: LegatoiOSRouteChangeReason)
    case runtimeError(message: String)
}

/// Seam for AVAudioSession-facing runtime integration.
public protocol LegatoiOSSessionRuntime: AnyObject {
    var onSignal: ((LegatoiOSSessionSignal) -> Void)? { get set }
    func configureSession()
    func updatePlaybackState(_ state: LegatoiOSPlaybackState)
    func releaseSession()
}

public final class LegatoiOSNoopSessionRuntime: LegatoiOSSessionRuntime {
    public var onSignal: ((LegatoiOSSessionSignal) -> Void)?

    public init() {}

    public func configureSession() {
        // Intentionally no-op. AVAudioSession activation/interruption wiring is pending.
    }

    public func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        // Intentionally no-op.
    }

    public func releaseSession() {
        // Intentionally no-op.
    }
}

public final class LegatoiOSAVAudioSessionRuntime: LegatoiOSSessionRuntime {
    public var onSignal: ((LegatoiOSSessionSignal) -> Void)? {
        didSet {
            runtime.onSignal = onSignal
        }
    }

    private let runtime: any LegatoiOSSessionRuntime

    /// Milestone 1 scope guard: Session runtime extraction only.
    /// No changes in Now Playing / Remote Command / AVPlayer adapters.
    public init() {
        runtime = LegatoiOSSessionRuntimeFactory.makeDefault()
        runtime.onSignal = onSignal
    }

    public func configureSession() {
        runtime.configureSession()
    }

    public func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        runtime.updatePlaybackState(state)
    }

    public func releaseSession() {
        runtime.releaseSession()
    }
}
