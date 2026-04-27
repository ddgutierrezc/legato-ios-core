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

    func testSnapshotDefaultsSeekableHintToNilWhenRuntimeCannotProveSeekability() throws {
        let runtime = LegatoiOSAVPlayerPlaybackRuntime(player: AVPlayer())
        runtime.configure()
        try runtime.replaceQueue(items: [makeSource(id: "track-1")], startIndex: 0)

        XCTAssertNil(runtime.snapshot().progress.isSeekableHint)
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

    func testHeaderBearingTrackUsesAssetRequestLoaderContext() throws {
        let player = AVPlayer()
        let factory = AssetRequestLoaderFactorySpy()
        let runtime = LegatoiOSAVPlayerPlaybackRuntime(
            player: player,
            assetRequestLoaderFactory: factory,
            requestEvidenceSink: LegatoiOSRecordingRequestEvidenceSink()
        )
        runtime.configure()

        try runtime.replaceQueue(items: [makeSource(id: "track-auth", headers: ["Authorization": "Bearer track-auth"])], startIndex: 0)

        XCTAssertEqual(factory.createdContexts.count, 1)
        XCTAssertEqual(factory.createdContexts.first?.trackId, "track-auth")
        XCTAssertEqual(factory.createdContexts.first?.headers["Authorization"], "Bearer track-auth")
        XCTAssertEqual(runtime.activeRequestLoaderTrackId, "track-auth")
    }

    func testNoHeaderTrackKeepsPlainAssetPathAndDisposesPreviousLoaderContext() throws {
        let player = AVPlayer()
        let factory = AssetRequestLoaderFactorySpy()
        let runtime = LegatoiOSAVPlayerPlaybackRuntime(
            player: player,
            assetRequestLoaderFactory: factory,
            requestEvidenceSink: LegatoiOSRecordingRequestEvidenceSink()
        )
        runtime.configure()

        try runtime.replaceQueue(items: [makeSource(id: "track-auth", headers: ["Authorization": "Bearer track-auth"])], startIndex: 0)
        let firstContext = try XCTUnwrap(factory.createdContexts.first)
        try runtime.replaceQueue(items: [makeSource(id: "track-public", headers: [:])], startIndex: 0)

        XCTAssertEqual(factory.createdContexts.count, 1)
        XCTAssertTrue(firstContext.didDispose)
        XCTAssertNil(runtime.activeRequestLoaderTrackId)
    }

    func testQueueTransitionBetweenAuthenticatedTracksDisposesPreviousContextAndKeepsHeadersDistinct() throws {
        let player = AVPlayer()
        let factory = AssetRequestLoaderFactorySpy()
        let runtime = LegatoiOSAVPlayerPlaybackRuntime(
            player: player,
            assetRequestLoaderFactory: factory,
            requestEvidenceSink: LegatoiOSRecordingRequestEvidenceSink()
        )
        runtime.configure()

        try runtime.replaceQueue(items: [makeSource(id: "track-auth-a", headers: ["Authorization": "Bearer A"])], startIndex: 0)
        let firstContext = try XCTUnwrap(factory.createdContexts.first)
        try runtime.replaceQueue(items: [makeSource(id: "track-auth-b", headers: ["Authorization": "Bearer B"])], startIndex: 0)
        let secondContext = try XCTUnwrap(factory.createdContexts.last)

        XCTAssertEqual(factory.createdContexts.count, 2)
        XCTAssertTrue(firstContext.didDispose)
        XCTAssertEqual(secondContext.headers["Authorization"], "Bearer B")
        XCTAssertEqual(runtime.activeRequestLoaderTrackId, "track-auth-b")
    }

    private func makeSource(id: String, headers: [String: String] = [:]) -> LegatoiOSRuntimeTrackSource {
        LegatoiOSRuntimeTrackSource(
            id: id,
            url: "https://samplelib.com/mp3/sample-12s.mp3",
            headers: headers,
            type: .progressive
        )
    }

    private func runMainLoopPulse() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

private final class AssetRequestLoaderFactorySpy: LegatoiOSAssetRequestLoaderFactory {
    private(set) var createdContexts: [AssetRequestLoaderContextSpy] = []

    func make(trackId: String, headers: [String : String], evidenceSink: LegatoiOSRequestEvidenceSink) -> LegatoiOSAssetRequestLoaderContext {
        let context = AssetRequestLoaderContextSpy(trackId: trackId, headers: headers)
        createdContexts.append(context)
        return context
    }
}

private final class AssetRequestLoaderContextSpy: LegatoiOSAssetRequestLoaderContext {
    let trackId: String
    let headers: [String: String]
    private(set) var didDispose = false

    init(trackId: String, headers: [String: String]) {
        self.trackId = trackId
        self.headers = headers
    }

    func makePlayerItem(url: URL) throws -> AVPlayerItem {
        AVPlayerItem(url: url)
    }

    func dispose() {
        didDispose = true
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
