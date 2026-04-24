import Foundation

public enum LegatoiOSTransportCapabilitiesProjector {
    public static func fromSnapshot(_ snapshot: LegatoiOSPlaybackSnapshot) -> LegatoiOSTransportCapabilities {
        if snapshot.state == .ended {
            return LegatoiOSTransportCapabilities(canSkipNext: false, canSkipPrevious: false, canSeek: false)
        }

        let queueItems = snapshot.queue.items
        guard !queueItems.isEmpty else {
            return LegatoiOSTransportCapabilities(canSkipNext: false, canSkipPrevious: false, canSeek: false)
        }

        let resolvedIndex = snapshot.currentIndex ?? snapshot.queue.currentIndex
        guard let index = resolvedIndex, queueItems.indices.contains(index) else {
            return LegatoiOSTransportCapabilities(canSkipNext: false, canSkipPrevious: false, canSeek: false)
        }

        return LegatoiOSTransportCapabilities(
            canSkipNext: index < queueItems.count - 1,
            canSkipPrevious: index > 0,
            canSeek: true
        )
    }
}
