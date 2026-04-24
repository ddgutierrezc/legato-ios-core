import Foundation

public enum LegatoiOSStateInput {
    case prepare
    case prepared
    case play
    case pause
    case bufferingStarted
    case bufferingEnded
    case trackEnded
    case stop
    case fail
    case reset
}

public final class LegatoiOSStateMachine {
    private let allowedTransitions: [LegatoiOSPlaybackState: Set<LegatoiOSPlaybackState>] = [
        .idle: [.loading, .error],
        .loading: [.ready, .idle, .error],
        .ready: [.playing, .loading, .idle, .error],
        .playing: [.paused, .buffering, .ended, .ready, .loading, .idle, .error],
        .paused: [.playing, .buffering, .ready, .loading, .idle, .error],
        .buffering: [.playing, .paused, .ready, .loading, .idle, .error],
        .ended: [.playing, .ready, .loading, .idle, .error],
        .error: [.idle, .loading],
    ]

    public init() {}

    public func canTransition(from: LegatoiOSPlaybackState, to: LegatoiOSPlaybackState) -> Bool {
        allowedTransitions[from]?.contains(to) ?? false
    }

    public func reduce(current: LegatoiOSPlaybackState, event: LegatoiOSStateInput) -> LegatoiOSPlaybackState {
        let candidate: LegatoiOSPlaybackState

        switch event {
        case .prepare:
            candidate = .loading
        case .prepared:
            candidate = .ready
        case .play:
            candidate = .playing
        case .pause:
            candidate = .paused
        case .bufferingStarted:
            candidate = .buffering
        case .bufferingEnded:
            candidate = .playing
        case .trackEnded:
            candidate = .ended
        case .stop:
            candidate = .ready
        case .reset:
            candidate = .idle
        case .fail:
            candidate = .error
        }

        return canTransition(from: current, to: candidate) ? candidate : current
    }
}
