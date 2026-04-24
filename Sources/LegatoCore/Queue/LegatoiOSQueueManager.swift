import Foundation

public final class LegatoiOSQueueManager {
    private let lock = NSLock()
    private var queueSnapshot: LegatoiOSQueueSnapshot = LegatoiOSQueueSnapshot(items: [], currentIndex: nil)

    public init() {}

    public func replaceQueue(_ tracks: [LegatoiOSTrack], startIndex: Int? = nil) throws -> LegatoiOSQueueSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let resolvedStartIndex = try resolveStartIndex(tracks: tracks, startIndex: startIndex)
        queueSnapshot = LegatoiOSQueueSnapshot(items: tracks, currentIndex: resolvedStartIndex)
        return queueSnapshot
    }

    public func addToQueue(_ tracks: [LegatoiOSTrack]) -> LegatoiOSQueueSnapshot {
        lock.lock()
        defer { lock.unlock() }

        if !tracks.isEmpty {
            queueSnapshot = LegatoiOSQueueSnapshot(
                items: queueSnapshot.items + tracks,
                currentIndex: queueSnapshot.currentIndex
            )
        }

        return queueSnapshot
    }

    public func getQueueSnapshot() -> LegatoiOSQueueSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return queueSnapshot
    }

    public func moveToNext() -> Int? {
        lock.lock()
        defer { lock.unlock() }

        guard !queueSnapshot.items.isEmpty else {
            return nil
        }

        if queueSnapshot.currentIndex == nil {
            queueSnapshot = LegatoiOSQueueSnapshot(items: queueSnapshot.items, currentIndex: 0)
            return 0
        }

        guard let current = queueSnapshot.currentIndex else {
            return nil
        }

        let next = current + 1
        guard next < queueSnapshot.items.count else {
            return nil
        }

        queueSnapshot = LegatoiOSQueueSnapshot(items: queueSnapshot.items, currentIndex: next)
        return next
    }

    public func moveToPrevious() -> Int? {
        lock.lock()
        defer { lock.unlock() }

        guard let current = queueSnapshot.currentIndex else {
            return nil
        }

        let previous = current - 1
        guard previous >= 0 else {
            return nil
        }

        queueSnapshot = LegatoiOSQueueSnapshot(items: queueSnapshot.items, currentIndex: previous)
        return previous
    }

    public func getCurrentTrack() -> LegatoiOSTrack? {
        lock.lock()
        defer { lock.unlock() }

        guard let current = queueSnapshot.currentIndex, queueSnapshot.items.indices.contains(current) else {
            return nil
        }

        return queueSnapshot.items[current]
    }

    public func getNextTrack() -> LegatoiOSTrack? {
        lock.lock()
        defer { lock.unlock() }

        guard let current = queueSnapshot.currentIndex else {
            return nil
        }

        let next = current + 1
        guard queueSnapshot.items.indices.contains(next) else {
            return nil
        }

        return queueSnapshot.items[next]
    }

    public func getPreviousTrack() -> LegatoiOSTrack? {
        lock.lock()
        defer { lock.unlock() }

        guard let current = queueSnapshot.currentIndex else {
            return nil
        }

        let previous = current - 1
        guard queueSnapshot.items.indices.contains(previous) else {
            return nil
        }

        return queueSnapshot.items[previous]
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        queueSnapshot = LegatoiOSQueueSnapshot(items: [], currentIndex: nil)
    }

    private func resolveStartIndex(tracks: [LegatoiOSTrack], startIndex: Int?) throws -> Int? {
        if tracks.isEmpty {
            if startIndex != nil {
                throw LegatoiOSError(
                    code: .invalidIndex,
                    message: "startIndex must be nil when queue is empty"
                )
            }
            return nil
        }

        let resolvedStartIndex = startIndex ?? 0
        guard tracks.indices.contains(resolvedStartIndex) else {
            throw LegatoiOSError(
                code: .invalidIndex,
                message: "startIndex must be within queue bounds"
            )
        }

        return resolvedStartIndex
    }
}
