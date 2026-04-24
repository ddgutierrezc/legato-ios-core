import Foundation

public final class LegatoiOSSnapshotStore {
    private let lock = NSLock()
    private var playbackSnapshot: LegatoiOSPlaybackSnapshot = LegatoiOSSnapshotStore.emptySnapshot

    public init() {}

    public func getPlaybackSnapshot() -> LegatoiOSPlaybackSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return playbackSnapshot
    }

    public func replacePlaybackSnapshot(_ snapshot: LegatoiOSPlaybackSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        playbackSnapshot = snapshot
    }

    public func updatePlaybackSnapshot(
        _ transform: (LegatoiOSPlaybackSnapshot) -> LegatoiOSPlaybackSnapshot
    ) {
        lock.lock()
        defer { lock.unlock() }
        playbackSnapshot = transform(playbackSnapshot)
    }

    public static var emptySnapshot: LegatoiOSPlaybackSnapshot {
        LegatoiOSPlaybackSnapshot(
            state: .idle,
            currentTrack: nil,
            currentIndex: nil,
            positionMs: 0,
            durationMs: nil,
            bufferedPositionMs: nil,
            queue: LegatoiOSQueueSnapshot(items: [], currentIndex: nil)
        )
    }
}
