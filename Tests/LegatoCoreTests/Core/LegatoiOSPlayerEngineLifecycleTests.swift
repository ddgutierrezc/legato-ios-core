import XCTest
@testable import LegatoCore

final class LegatoiOSPlayerEngineLifecycleTests: XCTestCase {
    func testInterruptionBeginPausesActivePlaybackAndMarksPausedState() throws {
        let fixture = makeFixture()
        try fixture.engine.setup()
        try fixture.engine.load(tracks: [makeTrack(id: "track-1")], startIndex: 0)
        try fixture.engine.play()

        fixture.sessionRuntime.emit(.interruptionBegan)

        XCTAssertEqual(fixture.playbackRuntime.pauseCallCount, 1)
        XCTAssertEqual(fixture.engine.snapshot().state, .paused)
    }

    func testInterruptionEndShouldResumeReassertsWithoutAutoPlay() throws {
        let fixture = makeFixture()
        try fixture.engine.setup()
        try fixture.engine.load(tracks: [makeTrack(id: "track-1")], startIndex: 0)
        try fixture.engine.play()
        fixture.sessionRuntime.emit(.interruptionBegan)

        let playCallsBeforeEnd = fixture.playbackRuntime.playCallCount
        let transportBeforeEnd = fixture.remoteRuntime.transportCapabilityUpdates.count

        fixture.sessionRuntime.emit(.interruptionEnded(intent: .shouldResume))

        XCTAssertEqual(fixture.playbackRuntime.playCallCount, playCallsBeforeEnd)
        XCTAssertEqual(fixture.engine.snapshot().state, .paused)
        XCTAssertEqual(fixture.remoteRuntime.transportCapabilityUpdates.count, transportBeforeEnd + 1)
    }

    func testInterruptionEndUnknownIntentKeepsPausedWithoutExtraPause() throws {
        let fixture = makeFixture()
        try fixture.engine.setup()
        try fixture.engine.load(tracks: [makeTrack(id: "track-1")], startIndex: 0)
        try fixture.engine.play()
        fixture.sessionRuntime.emit(.interruptionBegan)

        fixture.sessionRuntime.emit(.interruptionEnded(intent: .unknown))

        XCTAssertEqual(fixture.playbackRuntime.pauseCallCount, 1)
        XCTAssertEqual(fixture.engine.snapshot().state, .paused)
    }

    func testRouteLostReasonsPauseActivePlayback() throws {
        for reason in [LegatoiOSRouteChangeReason.oldDeviceUnavailable, .noSuitableRoute] {
            let fixture = makeFixture()
            try fixture.engine.setup()
            try fixture.engine.load(tracks: [makeTrack(id: "track-1")], startIndex: 0)
            try fixture.engine.play()

            fixture.sessionRuntime.emit(.outputRouteLost(reason: reason))

            XCTAssertEqual(fixture.playbackRuntime.pauseCallCount, 1)
            XCTAssertEqual(fixture.engine.snapshot().state, .paused)
        }
    }

    func testRouteAvailableReassertsWithoutAutoResuming() throws {
        let fixture = makeFixture()
        try fixture.engine.setup()
        try fixture.engine.load(tracks: [makeTrack(id: "track-1")], startIndex: 0)
        try fixture.engine.play()
        fixture.sessionRuntime.emit(.outputRouteLost(reason: .oldDeviceUnavailable))

        let playCallsBeforeAvailable = fixture.playbackRuntime.playCallCount
        let transportBeforeAvailable = fixture.remoteRuntime.transportCapabilityUpdates.count

        fixture.sessionRuntime.emit(.outputRouteAvailable(reason: .newDeviceAvailable))

        XCTAssertEqual(fixture.playbackRuntime.playCallCount, playCallsBeforeAvailable)
        XCTAssertEqual(fixture.engine.snapshot().state, .paused)
        XCTAssertEqual(fixture.remoteRuntime.transportCapabilityUpdates.count, transportBeforeAvailable + 1)
    }

    func testReassertPlaybackSurfacesIsNoopWithoutMediaContext() throws {
        let fixture = makeFixture()
        try fixture.engine.setup()

        let metadataUpdatesBefore = fixture.nowPlayingRuntime.metadataUpdates.count
        let progressUpdatesBefore = fixture.nowPlayingRuntime.progressUpdates.count
        let stateUpdatesBefore = fixture.nowPlayingRuntime.stateUpdates.count
        let transportBefore = fixture.remoteRuntime.transportCapabilityUpdates.count

        fixture.engine.reassertPlaybackSurfaces()

        XCTAssertEqual(fixture.nowPlayingRuntime.metadataUpdates.count, metadataUpdatesBefore)
        XCTAssertEqual(fixture.nowPlayingRuntime.progressUpdates.count, progressUpdatesBefore)
        XCTAssertEqual(fixture.nowPlayingRuntime.stateUpdates.count, stateUpdatesBefore)
        XCTAssertEqual(fixture.remoteRuntime.transportCapabilityUpdates.count, transportBefore)
    }

    func testRepeatedReassertDoesNotEmitDuplicatePlaybackStateEvents() throws {
        let fixture = makeFixture()
        try fixture.engine.setup()
        try fixture.engine.load(tracks: [makeTrack(id: "track-1")], startIndex: 0)

        var reassertStateEvents = 0
        _ = fixture.eventEmitter.addListener { event in
            if event.name == .playbackStateChanged {
                reassertStateEvents += 1
            }
        }

        fixture.engine.reassertPlaybackSurfaces()
        fixture.engine.reassertPlaybackSurfaces()

        XCTAssertEqual(reassertStateEvents, 0)
    }

    private func makeFixture() -> LifecycleFixture {
        let playbackRuntime = LifecycleFakePlaybackRuntime()
        let sessionRuntime = LifecycleFakeSessionRuntime()
        let nowPlayingRuntime = LifecycleSpyNowPlayingRuntime()
        let remoteRuntime = LifecycleSpyRemoteRuntime()
        let eventEmitter = LegatoiOSEventEmitter()

        let engine = LegatoiOSPlayerEngine(
            queueManager: LegatoiOSQueueManager(),
            eventEmitter: eventEmitter,
            snapshotStore: LegatoiOSSnapshotStore(),
            trackMapper: LegatoiOSTrackMapper(),
            errorMapper: LegatoiOSErrorMapper(),
            stateMachine: LegatoiOSStateMachine(),
            sessionManager: LegatoiOSSessionManager(runtime: sessionRuntime),
            nowPlayingManager: LegatoiOSNowPlayingManager(runtime: nowPlayingRuntime),
            remoteCommandManager: LegatoiOSRemoteCommandManager(runtime: remoteRuntime),
            playbackRuntime: playbackRuntime
        )

        return LifecycleFixture(
            engine: engine,
            playbackRuntime: playbackRuntime,
            sessionRuntime: sessionRuntime,
            nowPlayingRuntime: nowPlayingRuntime,
            remoteRuntime: remoteRuntime,
            eventEmitter: eventEmitter
        )
    }

    private func makeTrack(id: String) -> LegatoiOSTrack {
        LegatoiOSTrack(
            id: id,
            url: "https://example.com/\(id).mp3",
            title: id,
            artist: "Legato",
            album: "Lifecycle Fixture",
            artwork: "https://example.com/artwork-\(id).jpg",
            durationMs: 10_000
        )
    }
}

private struct LifecycleFixture {
    let engine: LegatoiOSPlayerEngine
    let playbackRuntime: LifecycleFakePlaybackRuntime
    let sessionRuntime: LifecycleFakeSessionRuntime
    let nowPlayingRuntime: LifecycleSpyNowPlayingRuntime
    let remoteRuntime: LifecycleSpyRemoteRuntime
    let eventEmitter: LegatoiOSEventEmitter
}

private final class LifecycleFakePlaybackRuntime: LegatoiOSPlaybackRuntime {
    private weak var observer: LegatoiOSPlaybackRuntimeObserver?
    private var runtimeSnapshot = LegatoiOSRuntimeSnapshot(
        stateHint: .ready,
        currentIndex: nil,
        progress: LegatoiOSRuntimeProgress(positionMs: 0, durationMs: nil, bufferedPositionMs: nil)
    )

    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    func configure() {}

    func setObserver(_ observer: LegatoiOSPlaybackRuntimeObserver?) {
        self.observer = observer
    }

    func replaceQueue(items: [LegatoiOSRuntimeTrackSource], startIndex: Int?) throws {
        let index = items.isEmpty ? nil : (startIndex ?? 0)
        runtimeSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: items.isEmpty ? .idle : .ready,
            currentIndex: index,
            progress: LegatoiOSRuntimeProgress(positionMs: 0, durationMs: 10_000, bufferedPositionMs: 0)
        )
        observer?.playbackRuntimeDidUpdateProgress(runtimeSnapshot)
    }

    func selectIndex(_ index: Int) throws {
        runtimeSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: runtimeSnapshot.stateHint,
            currentIndex: index,
            progress: LegatoiOSRuntimeProgress(positionMs: 0, durationMs: 10_000, bufferedPositionMs: 0)
        )
        observer?.playbackRuntimeDidUpdateProgress(runtimeSnapshot)
    }

    func play() throws {
        playCallCount += 1
        runtimeSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: .playing,
            currentIndex: runtimeSnapshot.currentIndex,
            progress: runtimeSnapshot.progress
        )
        observer?.playbackRuntimeDidUpdateProgress(runtimeSnapshot)
    }

    func pause() throws {
        pauseCallCount += 1
        runtimeSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: .paused,
            currentIndex: runtimeSnapshot.currentIndex,
            progress: runtimeSnapshot.progress
        )
        observer?.playbackRuntimeDidUpdateProgress(runtimeSnapshot)
    }

    func stop(resetPosition: Bool) throws {
        runtimeSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: .paused,
            currentIndex: runtimeSnapshot.currentIndex,
            progress: LegatoiOSRuntimeProgress(positionMs: 0, durationMs: runtimeSnapshot.progress.durationMs, bufferedPositionMs: 0)
        )
        observer?.playbackRuntimeDidUpdateProgress(runtimeSnapshot)
    }

    func seek(to positionMs: Int64) throws {
        runtimeSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: runtimeSnapshot.stateHint,
            currentIndex: runtimeSnapshot.currentIndex,
            progress: LegatoiOSRuntimeProgress(
                positionMs: max(0, positionMs),
                durationMs: runtimeSnapshot.progress.durationMs,
                bufferedPositionMs: runtimeSnapshot.progress.bufferedPositionMs
            )
        )
        observer?.playbackRuntimeDidUpdateProgress(runtimeSnapshot)
    }

    func snapshot() -> LegatoiOSRuntimeSnapshot {
        runtimeSnapshot
    }

    func release() {}
}

private final class LifecycleFakeSessionRuntime: LegatoiOSSessionRuntime {
    var onSignal: ((LegatoiOSSessionSignal) -> Void)?

    func configureSession() {}
    func updatePlaybackState(_ state: LegatoiOSPlaybackState) {}
    func releaseSession() {}

    func emit(_ signal: LegatoiOSSessionSignal) {
        onSignal?(signal)
    }
}

private final class LifecycleSpyNowPlayingRuntime: LegatoiOSNowPlayingRuntime {
    private(set) var metadataUpdates: [LegatoiOSNowPlayingMetadata?] = []
    private(set) var progressUpdates: [LegatoiOSProgressUpdate] = []
    private(set) var stateUpdates: [LegatoiOSPlaybackState] = []
    private(set) var clearCount = 0

    func updateMetadata(_ metadata: LegatoiOSNowPlayingMetadata?) {
        metadataUpdates.append(metadata)
    }

    func updateProgress(_ progress: LegatoiOSProgressUpdate) {
        progressUpdates.append(progress)
    }

    func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        stateUpdates.append(state)
    }

    func clear() {
        clearCount += 1
    }
}

private final class LifecycleSpyRemoteRuntime: LegatoiOSRemoteCommandRuntime {
    private(set) var playbackStateUpdates: [LegatoiOSPlaybackState] = []
    private(set) var transportCapabilityUpdates: [LegatoiOSTransportCapabilities] = []

    func bind(dispatch: @escaping (LegatoiOSRemoteCommand) -> Void) {}

    func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        playbackStateUpdates.append(state)
    }

    func updateTransportCapabilities(_ capabilities: LegatoiOSTransportCapabilities) {
        transportCapabilityUpdates.append(capabilities)
    }

    func unbind() {}
}
