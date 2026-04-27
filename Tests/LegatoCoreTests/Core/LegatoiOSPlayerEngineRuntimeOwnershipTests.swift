import XCTest
@testable import LegatoCore

final class LegatoiOSPlayerEngineRuntimeOwnershipTests: XCTestCase {
    func testAppendTracksUsesCanonicalRuntimeReplaceQueueAndUpdatesSnapshot() throws {
        let runtime = OwnershipFakePlaybackRuntime()
        let emitter = LegatoiOSEventEmitter()
        let engine = makeEngine(runtime: runtime, emitter: emitter)

        try engine.setup()
        try engine.load(
            tracks: [makeTrack(id: "track-1"), makeTrack(id: "track-2")],
            startIndex: 0
        )

        try engine.appendToQueue([makeTrack(id: "track-3")])

        let snapshot = engine.snapshot()
        XCTAssertEqual(snapshot.queue.items.count, 3)
        XCTAssertEqual(snapshot.currentIndex, 0)
        XCTAssertEqual(runtime.replaceQueueItemsHistory.last?.map(\.id), ["track-1", "track-2", "track-3"])
    }

    func testAddWithStartIndexResolvesAgainstAppendedBatch() throws {
        let runtime = OwnershipFakePlaybackRuntime()
        let emitter = LegatoiOSEventEmitter()
        let engine = makeEngine(runtime: runtime, emitter: emitter)

        try engine.setup()
        try engine.load(
            tracks: [makeTrack(id: "base-1"), makeTrack(id: "base-2")],
            startIndex: 0
        )

        let snapshot = try engine.add(
            tracks: [makeTrack(id: "new-1"), makeTrack(id: "new-2")],
            startIndex: 1
        )

        XCTAssertEqual(snapshot.queue.items.map { $0.id }, ["base-1", "base-2", "new-1", "new-2"])
        XCTAssertEqual(snapshot.currentIndex, 3)
        XCTAssertEqual(snapshot.currentTrack?.id, "new-2")
        XCTAssertEqual(runtime.replaceQueueStartIndexes.last ?? nil, 3)
    }

    func testRemoveTrackNormalizesToCanonicalFlowAndMovesRuntimeIndex() throws {
        let runtime = OwnershipFakePlaybackRuntime()
        let emitter = LegatoiOSEventEmitter()
        let engine = makeEngine(runtime: runtime, emitter: emitter)

        try engine.setup()
        try engine.load(
            tracks: [makeTrack(id: "track-1"), makeTrack(id: "track-2"), makeTrack(id: "track-3")],
            startIndex: 1
        )

        let snapshot = try engine.removeFromQueue(at: 1)

        XCTAssertEqual(snapshot.queue.items.map(\.id), ["track-1", "track-3"])
        XCTAssertEqual(snapshot.currentIndex, 1)
        XCTAssertEqual(snapshot.currentTrack?.id, "track-3")
        XCTAssertEqual(runtime.replaceQueueStartIndexes.last, 1)
    }

    func testResetQueueClearsCanonicalStateAndRuntimeQueue() throws {
        let runtime = OwnershipFakePlaybackRuntime()
        let emitter = LegatoiOSEventEmitter()
        let engine = makeEngine(runtime: runtime, emitter: emitter)

        try engine.setup()
        try engine.load(tracks: [makeTrack(id: "track-1")], startIndex: 0)

        let snapshot = try engine.resetQueue()

        XCTAssertEqual(snapshot.state, .idle)
        XCTAssertEqual(snapshot.queue.items.count, 0)
        XCTAssertNil(snapshot.currentIndex)
        XCTAssertEqual(runtime.replaceQueueItemsHistory.last?.count, 0)
    }

    func testSkipToIndexRejectsOutOfBoundsAndDoesNotMutateQueue() throws {
        let runtime = OwnershipFakePlaybackRuntime()
        let emitter = LegatoiOSEventEmitter()
        let engine = makeEngine(runtime: runtime, emitter: emitter)

        try engine.setup()
        try engine.load(tracks: [makeTrack(id: "track-1"), makeTrack(id: "track-2")], startIndex: 0)

        XCTAssertThrowsError(try engine.skipTo(index: 9)) { error in
            guard let mapped = error as? LegatoiOSError else {
                return XCTFail("Expected LegatoiOSError")
            }
            XCTAssertEqual(mapped.code, .invalidIndex)
        }

        XCTAssertEqual(engine.snapshot().currentIndex, 0)
        XCTAssertEqual(runtime.selectIndexHistory, [])
    }

    func testSkipToIndexProjectsQueueTrackAndStateThroughEngine() throws {
        let runtime = OwnershipFakePlaybackRuntime()
        let emitter = LegatoiOSEventEmitter()
        let engine = makeEngine(runtime: runtime, emitter: emitter)

        try engine.setup()
        try engine.load(
            tracks: [makeTrack(id: "track-1"), makeTrack(id: "track-2"), makeTrack(id: "track-3")],
            startIndex: 0
        )

        try engine.skipTo(index: 2)

        let snapshot = engine.snapshot()
        XCTAssertEqual(snapshot.currentIndex, 2)
        XCTAssertEqual(snapshot.currentTrack?.id, "track-3")
        XCTAssertEqual(runtime.selectIndexHistory.last, 2)
    }

    private func makeEngine(runtime: OwnershipFakePlaybackRuntime, emitter: LegatoiOSEventEmitter) -> LegatoiOSPlayerEngine {
        LegatoiOSPlayerEngine(
            queueManager: LegatoiOSQueueManager(),
            eventEmitter: emitter,
            snapshotStore: LegatoiOSSnapshotStore(),
            trackMapper: LegatoiOSTrackMapper(),
            errorMapper: LegatoiOSErrorMapper(),
            stateMachine: LegatoiOSStateMachine(),
            sessionManager: LegatoiOSSessionManager(runtime: OwnershipFakeSessionRuntime()),
            nowPlayingManager: LegatoiOSNowPlayingManager(runtime: OwnershipFakeNowPlayingRuntime()),
            remoteCommandManager: LegatoiOSRemoteCommandManager(runtime: OwnershipFakeRemoteRuntime()),
            playbackRuntime: runtime
        )
    }

    private func makeTrack(id: String) -> LegatoiOSTrack {
        LegatoiOSTrack(
            id: id,
            url: "https://example.com/\(id).mp3",
            title: id,
            artist: "Legato",
            durationMs: 1_000
        )
    }
}

private final class OwnershipFakePlaybackRuntime: LegatoiOSPlaybackRuntime {
    private weak var observer: LegatoiOSPlaybackRuntimeObserver?
    private var runtimeSnapshot = LegatoiOSRuntimeSnapshot(
        stateHint: .ready,
        currentIndex: nil,
        progress: LegatoiOSRuntimeProgress(positionMs: 0, durationMs: 1_000, bufferedPositionMs: 0)
    )

    private(set) var replaceQueueItemsHistory: [[LegatoiOSRuntimeTrackSource]] = []
    private(set) var replaceQueueStartIndexes: [Int?] = []
    private(set) var selectIndexHistory: [Int] = []

    func configure() {}

    func setObserver(_ observer: LegatoiOSPlaybackRuntimeObserver?) {
        self.observer = observer
    }

    func replaceQueue(items: [LegatoiOSRuntimeTrackSource], startIndex: Int?) throws {
        replaceQueueItemsHistory.append(items)
        replaceQueueStartIndexes.append(startIndex)

        if items.isEmpty {
            runtimeSnapshot = LegatoiOSRuntimeSnapshot(
                stateHint: .idle,
                currentIndex: nil,
                progress: LegatoiOSRuntimeProgress(positionMs: 0, durationMs: nil, bufferedPositionMs: nil)
            )
        } else {
            let resolved = startIndex ?? 0
            runtimeSnapshot = LegatoiOSRuntimeSnapshot(
                stateHint: .ready,
                currentIndex: resolved,
                progress: LegatoiOSRuntimeProgress(positionMs: 0, durationMs: 1_000, bufferedPositionMs: 0)
            )
        }

        observer?.playbackRuntimeDidUpdateProgress(runtimeSnapshot)
    }

    func selectIndex(_ index: Int) throws {
        selectIndexHistory.append(index)
        runtimeSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: .ready,
            currentIndex: index,
            progress: LegatoiOSRuntimeProgress(positionMs: 0, durationMs: 1_000, bufferedPositionMs: 0)
        )
        observer?.playbackRuntimeDidUpdateProgress(runtimeSnapshot)
    }

    func play() throws {
        runtimeSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: .playing,
            currentIndex: runtimeSnapshot.currentIndex,
            progress: runtimeSnapshot.progress
        )
        observer?.playbackRuntimeDidUpdateProgress(runtimeSnapshot)
    }

    func pause() throws {
        runtimeSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: .paused,
            currentIndex: runtimeSnapshot.currentIndex,
            progress: runtimeSnapshot.progress
        )
        observer?.playbackRuntimeDidUpdateProgress(runtimeSnapshot)
    }

    func stop(resetPosition: Bool) throws {
        let position: Int64 = resetPosition ? 0 : runtimeSnapshot.progress.positionMs
        runtimeSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: .paused,
            currentIndex: runtimeSnapshot.currentIndex,
            progress: LegatoiOSRuntimeProgress(
                positionMs: position,
                durationMs: runtimeSnapshot.progress.durationMs,
                bufferedPositionMs: runtimeSnapshot.progress.bufferedPositionMs
            )
        )
        observer?.playbackRuntimeDidUpdateProgress(runtimeSnapshot)
    }

    func seek(to positionMs: Int64) throws {
        runtimeSnapshot = LegatoiOSRuntimeSnapshot(
            stateHint: .playing,
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

    func release() {
        runtimeSnapshot = LegatoiOSRuntimeSnapshot()
    }
}

private final class OwnershipFakeSessionRuntime: LegatoiOSSessionRuntime {
    var onSignal: ((LegatoiOSSessionSignal) -> Void)?

    func configureSession() {}
    func updatePlaybackState(_ state: LegatoiOSPlaybackState) {}
    func releaseSession() {}
}

private final class OwnershipFakeNowPlayingRuntime: LegatoiOSNowPlayingRuntime {
    func updateMetadata(_ metadata: LegatoiOSNowPlayingMetadata?) {}
    func updateProgress(_ progress: LegatoiOSProgressUpdate) {}
    func updatePlaybackState(_ state: LegatoiOSPlaybackState) {}
    func clear() {}
}

private final class OwnershipFakeRemoteRuntime: LegatoiOSRemoteCommandRuntime {
    func bind(dispatch: @escaping (LegatoiOSRemoteCommand) -> Void) {}
    func updatePlaybackState(_ state: LegatoiOSPlaybackState) {}
    func updateTransportCapabilities(_ capabilities: LegatoiOSTransportCapabilities) {}
    func unbind() {}
}
