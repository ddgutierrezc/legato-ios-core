import XCTest
@testable import LegatoCore

final class LegatoiOSNowPlayingManagerTests: XCTestCase {
    func testUpdatePlaybackStateForwardsStateToRuntime() {
        let runtime = SpyNowPlayingRuntime()
        let manager = LegatoiOSNowPlayingManager(runtime: runtime)

        manager.updatePlaybackState(.paused)

        XCTAssertEqual(runtime.receivedStates, [.paused])
    }
}

private final class SpyNowPlayingRuntime: LegatoiOSNowPlayingRuntime {
    private(set) var receivedStates: [LegatoiOSPlaybackState] = []

    func updateMetadata(_ metadata: LegatoiOSNowPlayingMetadata?) {}

    func updateProgress(_ progress: LegatoiOSProgressUpdate) {}

    func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        receivedStates.append(state)
    }

    func clear() {}
}
