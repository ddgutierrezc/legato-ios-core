import AVFoundation
import XCTest
@testable import LegatoCore

final class LegatoiOSAVPlayerPlaybackRuntimeTests: XCTestCase {
    func testReplaceQueueSetsInitialIndexAndClearsOnEmptyQueue() throws {
        let runtime = LegatoiOSAVPlayerPlaybackRuntime(player: AVPlayer())
        runtime.configure()

        try runtime.replaceQueue(items: [makeSource(id: "track-1")], startIndex: 0)
        XCTAssertEqual(runtime.snapshot().currentIndex, 0)

        try runtime.replaceQueue(items: [], startIndex: nil)
        let emptySnapshot = runtime.snapshot()
        XCTAssertNil(emptySnapshot.currentIndex)
        XCTAssertEqual(emptySnapshot.stateHint, .idle)
    }

    func testSeekClampsNegativePositionAndStopResetsPosition() throws {
        let runtime = LegatoiOSAVPlayerPlaybackRuntime(player: AVPlayer())
        runtime.configure()
        try runtime.replaceQueue(items: [makeSource(id: "track-1")], startIndex: 0)

        try runtime.seek(to: -1_500)
        XCTAssertGreaterThanOrEqual(runtime.snapshot().progress.positionMs, 0)

        try runtime.stop(resetPosition: true)
        XCTAssertEqual(runtime.snapshot().progress.positionMs, 0)
    }

    func testProgressObserverReceivesUpdatesAfterQueueMutation() throws {
        let runtime = LegatoiOSAVPlayerPlaybackRuntime(player: AVPlayer())
        let observer = RuntimeObserverSpy()
        runtime.setObserver(observer)
        runtime.configure()

        try runtime.replaceQueue(items: [makeSource(id: "track-1")], startIndex: 0)

        XCTAssertGreaterThan(observer.progressSnapshots.count, 0)

        let updateCountBeforeClear = observer.progressSnapshots.count
        try runtime.replaceQueue(items: [], startIndex: nil)
        XCTAssertGreaterThan(observer.progressSnapshots.count, updateCountBeforeClear)
    }

    func testTrackEndNotificationEmitsSingleEndCallbackPerCurrentItem() throws {
        let player = AVPlayer()
        let runtime = LegatoiOSAVPlayerPlaybackRuntime(player: player)
        let observer = RuntimeObserverSpy()
        runtime.setObserver(observer)
        runtime.configure()

        try runtime.replaceQueue(items: [makeSource(id: "track-1")], startIndex: 0)
        try runtime.play()

        guard let currentItem = player.currentItem else {
            return XCTFail("Expected AVPlayer item after replaceQueue")
        }

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: currentItem)
        runMainLoopPulse()

        XCTAssertEqual(observer.trackEndSnapshots.count, 1)
        XCTAssertEqual(observer.trackEndSnapshots.first?.currentIndex, 0)
    }

    private func makeSource(id: String) -> LegatoiOSRuntimeTrackSource {
        LegatoiOSRuntimeTrackSource(
            id: id,
            url: "https://samplelib.com/mp3/sample-12s.mp3",
            headers: [:],
            type: .progressive
        )
    }

    private func runMainLoopPulse() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

private final class RuntimeObserverSpy: LegatoiOSPlaybackRuntimeObserver {
    private(set) var progressSnapshots: [LegatoiOSRuntimeSnapshot] = []
    private(set) var trackEndSnapshots: [LegatoiOSRuntimeSnapshot] = []

    func playbackRuntimeDidUpdateProgress(_ snapshot: LegatoiOSRuntimeSnapshot) {
        progressSnapshots.append(snapshot)
    }

    func playbackRuntimeDidReachTrackEnd(_ snapshot: LegatoiOSRuntimeSnapshot) {
        trackEndSnapshots.append(snapshot)
    }
}
