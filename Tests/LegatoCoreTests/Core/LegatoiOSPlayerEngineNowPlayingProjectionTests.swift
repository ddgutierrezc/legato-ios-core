import XCTest
@testable import LegatoCore

final class LegatoiOSPlayerEngineNowPlayingProjectionTests: XCTestCase {
    func testRuntimeTrackEndAutoAdvancesToNextTrackWithoutClearingNowPlaying() throws {
        let playbackRuntime = FakePlaybackRuntime()
        let nowPlayingRuntime = SpyNowPlayingRuntime()
        let engine = makeEngine(playbackRuntime: playbackRuntime, nowPlayingRuntime: nowPlayingRuntime)

        try engine.setup()
        try engine.load(
            tracks: [
                LegatoiOSTrack(id: "track-1", url: "https://example.com/1.mp3", durationMs: 100_000),
                LegatoiOSTrack(id: "track-2", url: "https://example.com/2.mp3", durationMs: 200_000)
            ]
        )
        try engine.play()
        let playCallsBeforeEnd = playbackRuntime.playCallCount

        playbackRuntime.emitTrackEnd(positionMs: 100_000, durationMs: 100_000)

        let snapshot = engine.snapshot()
        XCTAssertEqual(snapshot.currentIndex, 1)
        XCTAssertEqual(snapshot.currentTrack?.id, "track-2")
        XCTAssertEqual(snapshot.positionMs, 0)
        XCTAssertEqual(snapshot.durationMs, 200_000)
        XCTAssertEqual(nowPlayingRuntime.receivedMetadata.last??.trackId, "track-2")
        XCTAssertEqual(nowPlayingRuntime.clearCallCount, 0)
        XCTAssertEqual(playbackRuntime.playCallCount, playCallsBeforeEnd + 1)
    }

    func testRuntimeTrackEndAutoAdvanceDoesNotProjectEndedProgressIntoNextTrack() throws {
        let playbackRuntime = FakePlaybackRuntime()
        let nowPlayingRuntime = SpyNowPlayingRuntime()
        let engine = makeEngine(playbackRuntime: playbackRuntime, nowPlayingRuntime: nowPlayingRuntime)

        try engine.setup()
        try engine.load(
            tracks: [
                LegatoiOSTrack(id: "track-1", url: "https://example.com/1.mp3", durationMs: 100_000),
                LegatoiOSTrack(id: "track-2", url: "https://example.com/2.mp3", durationMs: 200_000)
            ]
        )
        try engine.play()

        playbackRuntime.emitTrackEnd(positionMs: 100_000, durationMs: 100_000)

        let snapshot = engine.snapshot()
        XCTAssertEqual(snapshot.currentIndex, 1)
        XCTAssertEqual(snapshot.currentTrack?.id, "track-2")
        XCTAssertEqual(snapshot.positionMs, 0)
        XCTAssertEqual(snapshot.bufferedPositionMs, 0)
        XCTAssertEqual(snapshot.state, .playing)
    }

    func testRuntimeTrackEndOnFinalItemClearsNowPlayingSurface() throws {
        let playbackRuntime = FakePlaybackRuntime()
        let nowPlayingRuntime = SpyNowPlayingRuntime()
        let engine = makeEngine(playbackRuntime: playbackRuntime, nowPlayingRuntime: nowPlayingRuntime)

        try engine.setup()
        try engine.load(
            tracks: [LegatoiOSTrack(id: "track-1", url: "https://example.com/1.mp3", durationMs: 100_000)]
        )
        try engine.play()

        playbackRuntime.emitTrackEnd(positionMs: 100_000, durationMs: 100_000)

        XCTAssertEqual(engine.snapshot().state, .ended)
        XCTAssertEqual(nowPlayingRuntime.receivedStates.last, .ended)
        XCTAssertEqual(nowPlayingRuntime.clearCallCount, 1)
    }

    func testRuntimePlayingTransitionProjectsPlayingStateToNowPlayingManager() throws {
        let playbackRuntime = FakePlaybackRuntime()
        let nowPlayingRuntime = SpyNowPlayingRuntime()
        let engine = makeEngine(playbackRuntime: playbackRuntime, nowPlayingRuntime: nowPlayingRuntime)

        try engine.setup()

        playbackRuntime.emitStateHint(.loading)
        playbackRuntime.emitStateHint(.ready)
        playbackRuntime.emitStateHint(.playing)

        XCTAssertEqual(nowPlayingRuntime.receivedStates.last, .playing)
    }

    func testRuntimePausedBufferingAndEndedTransitionsProjectStateToNowPlayingManager() throws {
        let playbackRuntime = FakePlaybackRuntime()
        let nowPlayingRuntime = SpyNowPlayingRuntime()
        let engine = makeEngine(playbackRuntime: playbackRuntime, nowPlayingRuntime: nowPlayingRuntime)

        try engine.setup()

        playbackRuntime.emitStateHint(.loading)
        playbackRuntime.emitStateHint(.ready)
        playbackRuntime.emitStateHint(.playing)
        playbackRuntime.emitStateHint(.paused)
        XCTAssertEqual(nowPlayingRuntime.receivedStates.last, .paused)

        playbackRuntime.emitStateHint(.buffering)
        XCTAssertEqual(nowPlayingRuntime.receivedStates.last, .buffering)

        playbackRuntime.emitStateHint(.playing)
        playbackRuntime.emitStateHint(.ended)
        XCTAssertEqual(nowPlayingRuntime.receivedStates.last, .ended)

    }

    func testRuntimeErrorTransitionProjectsStateToNowPlayingManager() throws {
        let playbackRuntime = FakePlaybackRuntime()
        let nowPlayingRuntime = SpyNowPlayingRuntime()
        let engine = makeEngine(playbackRuntime: playbackRuntime, nowPlayingRuntime: nowPlayingRuntime)

        try engine.setup()

        playbackRuntime.emitStateHint(.loading)
        playbackRuntime.emitStateHint(.ready)
        playbackRuntime.emitStateHint(.playing)
        playbackRuntime.emitStateHint(.error)

        XCTAssertEqual(nowPlayingRuntime.receivedStates.last, .error)
    }

    private func makeEngine(
        playbackRuntime: FakePlaybackRuntime,
        nowPlayingRuntime: SpyNowPlayingRuntime
    ) -> LegatoiOSPlayerEngine {
        LegatoiOSPlayerEngine(
            queueManager: LegatoiOSQueueManager(),
            eventEmitter: LegatoiOSEventEmitter(),
            snapshotStore: LegatoiOSSnapshotStore(),
            trackMapper: LegatoiOSTrackMapper(),
            errorMapper: LegatoiOSErrorMapper(),
            stateMachine: LegatoiOSStateMachine(),
            sessionManager: LegatoiOSSessionManager(runtime: FakeSessionRuntime()),
            nowPlayingManager: LegatoiOSNowPlayingManager(runtime: nowPlayingRuntime),
            remoteCommandManager: LegatoiOSRemoteCommandManager(runtime: FakeRemoteCommandRuntime()),
            playbackRuntime: playbackRuntime
        )
    }
}

private final class SpyNowPlayingRuntime: LegatoiOSNowPlayingRuntime {
    private(set) var receivedStates: [LegatoiOSPlaybackState] = []
    private(set) var receivedMetadata: [LegatoiOSNowPlayingMetadata?] = []
    private(set) var clearCallCount: Int = 0

    func updateMetadata(_ metadata: LegatoiOSNowPlayingMetadata?) {
        receivedMetadata.append(metadata)
    }

    func updateProgress(_ progress: LegatoiOSProgressUpdate) {}

    func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        receivedStates.append(state)
    }

    func clear() {
        clearCallCount += 1
    }
}

private final class FakePlaybackRuntime: LegatoiOSPlaybackRuntime {
    private weak var observer: LegatoiOSPlaybackRuntimeObserver?
    private var currentSnapshot = LegatoiOSRuntimeSnapshot()
    private(set) var playCallCount: Int = 0

    func configure() {}

    func setObserver(_ observer: LegatoiOSPlaybackRuntimeObserver?) {
        self.observer = observer
    }

    func replaceQueue(items: [LegatoiOSRuntimeTrackSource], startIndex: Int?) throws {
        currentSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: currentSnapshot.stateHint,
            currentIndex: startIndex ?? 0,
            progress: currentSnapshot.progress
        )
    }

    func selectIndex(_ index: Int) throws {
        currentSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: currentSnapshot.stateHint,
            currentIndex: index,
            progress: LegatoiOSRuntimeProgress(positionMs: 0, durationMs: nil, bufferedPositionMs: 0)
        )
    }

    func play() throws {
        playCallCount += 1
    }
    func pause() throws {}
    func stop(resetPosition: Bool) throws {}
    func seek(to positionMs: Int64) throws {}

    func snapshot() -> LegatoiOSRuntimeSnapshot {
        currentSnapshot
    }

    func release() {}

    func emitStateHint(_ state: LegatoiOSPlaybackState) {
        currentSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: state,
            currentIndex: currentSnapshot.currentIndex,
            progress: currentSnapshot.progress
        )
        observer?.playbackRuntimeDidUpdateProgress(currentSnapshot)
    }

    func emitTrackEnd(positionMs: Int64, durationMs: Int64?) {
        currentSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: .ended,
            currentIndex: currentSnapshot.currentIndex,
            progress: LegatoiOSRuntimeProgress(
                positionMs: positionMs,
                durationMs: durationMs,
                bufferedPositionMs: durationMs
            )
        )
        observer?.playbackRuntimeDidReachTrackEnd(currentSnapshot)
    }
}

private final class FakeSessionRuntime: LegatoiOSSessionRuntime {
    var onSignal: ((LegatoiOSSessionSignal) -> Void)?

    func configureSession() {}
    func updatePlaybackState(_ state: LegatoiOSPlaybackState) {}
    func releaseSession() {}
}

private final class FakeRemoteCommandRuntime: LegatoiOSRemoteCommandRuntime {
    func bind(dispatch: @escaping (LegatoiOSRemoteCommand) -> Void) {}
    func updatePlaybackState(_ state: LegatoiOSPlaybackState) {}
    func updateTransportCapabilities(_ capabilities: LegatoiOSTransportCapabilities) {}
    func unbind() {}
}
