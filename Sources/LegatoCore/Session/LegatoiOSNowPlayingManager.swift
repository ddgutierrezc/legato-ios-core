import Foundation

public final class LegatoiOSNowPlayingManager {
    private let runtime: LegatoiOSNowPlayingRuntime

    public init(runtime: LegatoiOSNowPlayingRuntime = LegatoiOSMediaPlayerNowPlayingRuntime()) {
        self.runtime = runtime
    }

    public func updateMetadata(_ metadata: LegatoiOSNowPlayingMetadata?) {
        runtime.updateMetadata(metadata)
    }

    public func updateProgress(_ progress: LegatoiOSProgressUpdate) {
        runtime.updateProgress(progress)
    }

    public func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        runtime.updatePlaybackState(state)
    }

    public func clear() {
        runtime.clear()
    }
}
