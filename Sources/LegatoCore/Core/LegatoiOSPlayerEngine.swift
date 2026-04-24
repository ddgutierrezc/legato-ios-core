import Foundation

public final class LegatoiOSPlayerEngine: LegatoiOSPlaybackRuntimeObserver {
    private static let previousRestartThresholdMs: Int64 = 3_000

    private let queueManager: LegatoiOSQueueManager
    private let eventEmitter: LegatoiOSEventEmitter
    private let snapshotStore: LegatoiOSSnapshotStore
    private let trackMapper: LegatoiOSTrackMapper
    private let errorMapper: LegatoiOSErrorMapper
    private let stateMachine: LegatoiOSStateMachine
    private let sessionManager: LegatoiOSSessionManager
    private let nowPlayingManager: LegatoiOSNowPlayingManager
    private let remoteCommandManager: LegatoiOSRemoteCommandManager
    private let playbackRuntime: LegatoiOSPlaybackRuntime

    private struct ProgressEmissionToken: Equatable {
        let trackId: String?
        let currentIndex: Int?
        let positionMs: Int64
        let durationMs: Int64?
        let bufferedPositionMs: Int64?
    }

    private var isSetup = false
    private var lastProgressEmission: ProgressEmissionToken?
    private var sessionSignalListenerID: UUID?

    public init(
        queueManager: LegatoiOSQueueManager,
        eventEmitter: LegatoiOSEventEmitter,
        snapshotStore: LegatoiOSSnapshotStore,
        trackMapper: LegatoiOSTrackMapper,
        errorMapper: LegatoiOSErrorMapper,
        stateMachine: LegatoiOSStateMachine,
        sessionManager: LegatoiOSSessionManager,
        nowPlayingManager: LegatoiOSNowPlayingManager,
        remoteCommandManager: LegatoiOSRemoteCommandManager,
        playbackRuntime: LegatoiOSPlaybackRuntime
    ) {
        self.queueManager = queueManager
        self.eventEmitter = eventEmitter
        self.snapshotStore = snapshotStore
        self.trackMapper = trackMapper
        self.errorMapper = errorMapper
        self.stateMachine = stateMachine
        self.sessionManager = sessionManager
        self.nowPlayingManager = nowPlayingManager
        self.remoteCommandManager = remoteCommandManager
        self.playbackRuntime = playbackRuntime
    }

    public func setup() throws {
        if isSetup {
            return
        }

        registerSessionSignalListenerIfNeeded()
        sessionManager.configureSession()
        remoteCommandManager.bind(handler: onRemoteCommand)
        remoteCommandManager.updateTransportCapabilities(
            LegatoiOSTransportCapabilitiesProjector.fromSnapshot(snapshotStore.getPlaybackSnapshot())
        )
        playbackRuntime.configure()
        playbackRuntime.setObserver(self)
        isSetup = true
    }

    public func load(tracks: [LegatoiOSTrack], startIndex: Int? = nil) throws {
        try guardSetup()

        do {
            let mappedTracks = try trackMapper.mapContractTracks(tracks)
            let queueSnapshot = try queueManager.replaceQueue(mappedTracks, startIndex: startIndex)
            try playbackRuntime.replaceQueue(items: mappedTracks.map(toRuntimeTrackSource), startIndex: startIndex)
            let runtimeSnapshot = playbackRuntime.snapshot()
            let currentTrack = queueManager.getCurrentTrack()
            let currentState = snapshotStore.getPlaybackSnapshot().state
            let loadingState = stateMachine.reduce(current: currentState, event: .prepare)

            let snapshot = LegatoiOSPlaybackSnapshot(
                state: loadingState,
                currentTrack: currentTrack,
                currentIndex: runtimeSnapshot.currentIndex ?? queueSnapshot.currentIndex,
                positionMs: runtimeSnapshot.progress.positionMs,
                durationMs: runtimeSnapshot.progress.durationMs ?? currentTrack?.durationMs,
                bufferedPositionMs: runtimeSnapshot.progress.bufferedPositionMs,
                queue: queueSnapshot
            )

            snapshotStore.replacePlaybackSnapshot(snapshot)
            publishQueueAndTrack(snapshot)
            if loadingState != currentState {
                publishState(snapshot.state)
            }
            publishMetadata(snapshot.currentTrack)
            publishProgress(snapshot)
            refreshSnapshotFromRuntime(publishProgressEvent: true)
        } catch {
            publishPlatformFailure(error)
            throw error
        }
    }

    public func play() throws {
        try guardSetup()
        try performRuntimeOperation {
            try playbackRuntime.play()
        }
        refreshSnapshotFromRuntime(publishProgressEvent: true)
    }

    public func pause() throws {
        try guardSetup()
        try performRuntimeOperation {
            try playbackRuntime.pause()
        }
        refreshSnapshotFromRuntime(publishProgressEvent: true)
    }

    public func stop() throws {
        try guardSetup()
        try performRuntimeOperation {
            try playbackRuntime.stop(resetPosition: true)
        }
        refreshSnapshotFromRuntime(publishProgressEvent: true)
    }

    public func seek(to positionMs: Int64) throws {
        try guardSetup()
        try performRuntimeOperation {
            try playbackRuntime.seek(to: positionMs)
        }
        refreshSnapshotFromRuntime(publishProgressEvent: true)
    }

    public func skipToNext() throws {
        try guardSetup()
        guard let movedIndex = queueManager.moveToNext() else {
            emitEndedAtQueueBoundaryIfNeeded()
            return
        }

        try performRuntimeOperation {
            try playbackRuntime.selectIndex(movedIndex)
        }

        let runtimeSnapshot = playbackRuntime.snapshot()
        let track = queueManager.getCurrentTrack()
        applyRuntimeSnapshot(
            runtimeSnapshot,
            currentTrackOverride: track,
            currentIndexFallback: movedIndex,
            queueOverride: queueManager.getQueueSnapshot()
        )

        let snapshot = snapshotStore.getPlaybackSnapshot()
        publishQueueAndTrack(snapshot)
        publishMetadata(track)
        publishProgress(snapshot)
    }

    public func skipToPrevious() throws {
        try guardSetup()
        let currentSnapshot = snapshotStore.getPlaybackSnapshot()
        guard let currentIndex = currentSnapshot.currentIndex else {
            return
        }

        if currentSnapshot.positionMs > Self.previousRestartThresholdMs {
            try seek(to: 0)
            return
        }

        if currentIndex <= 0 {
            try seek(to: 0)
            return
        }

        guard let movedIndex = queueManager.moveToPrevious() else {
            return
        }

        try performRuntimeOperation {
            try playbackRuntime.selectIndex(movedIndex)
        }

        let runtimeSnapshot = playbackRuntime.snapshot()
        let track = queueManager.getCurrentTrack()
        applyRuntimeSnapshot(
            runtimeSnapshot,
            currentTrackOverride: track,
            currentIndexFallback: movedIndex,
            queueOverride: queueManager.getQueueSnapshot()
        )

        let snapshot = snapshotStore.getPlaybackSnapshot()
        publishQueueAndTrack(snapshot)
        publishMetadata(track)
        publishProgress(snapshot)
    }

    public func snapshot() -> LegatoiOSPlaybackSnapshot {
        snapshotStore.getPlaybackSnapshot()
    }

    public func release() {
        guard isSetup else {
            return
        }

        removeSessionSignalListenerIfNeeded()
        remoteCommandManager.unbind()
        playbackRuntime.setObserver(nil)
        playbackRuntime.release()
        nowPlayingManager.clear()
        sessionManager.releaseSession()
        isSetup = false
        lastProgressEmission = nil
    }

    public func playbackRuntimeDidUpdateProgress(_ snapshot: LegatoiOSRuntimeSnapshot) {
        guard isSetup else {
            return
        }

        applyRuntimeSnapshot(snapshot)
        publishProgress(snapshotStore.getPlaybackSnapshot())
    }

    public func playbackRuntimeDidReachTrackEnd(_ snapshot: LegatoiOSRuntimeSnapshot) {
        guard isSetup else {
            return
        }

        if let movedIndex = queueManager.moveToNext() {
            do {
                try performRuntimeOperation {
                    try playbackRuntime.selectIndex(movedIndex)
                    try playbackRuntime.play()
                }
            } catch {
                return
            }

            let runtimeSnapshot = normalizedAutoAdvanceRuntimeSnapshot(
                playbackRuntime.snapshot(),
                expectedIndex: movedIndex
            )
            let track = queueManager.getCurrentTrack()
            applyRuntimeSnapshot(
                runtimeSnapshot,
                currentTrackOverride: track,
                currentIndexFallback: movedIndex,
                queueOverride: queueManager.getQueueSnapshot()
            )

            let updatedSnapshot = snapshotStore.getPlaybackSnapshot()
            publishQueueAndTrack(updatedSnapshot)
            publishMetadata(track)
            publishProgress(updatedSnapshot)
            return
        }

        applyRuntimeSnapshot(snapshot)
        transition(event: .trackEnded)

        let endedSnapshot = snapshotStore.getPlaybackSnapshot()
        publishProgress(endedSnapshot)
        nowPlayingManager.clear()
        eventEmitter.emit(name: .playbackEnded, payload: .playbackEnded(snapshot: endedSnapshot))
    }

    private func toRuntimeTrackSource(_ track: LegatoiOSTrack) -> LegatoiOSRuntimeTrackSource {
        LegatoiOSRuntimeTrackSource(id: track.id, url: track.url, headers: track.headers, type: track.type)
    }

    private func guardSetup() throws {
        guard isSetup else {
            let error = errorMapper.playerNotSetup()
            eventEmitter.emit(name: .playbackError, payload: .playbackError(error: error))
            throw error
        }
    }

    @discardableResult
    private func transition(event: LegatoiOSStateInput) -> Bool {
        let previous = snapshotStore.getPlaybackSnapshot()
        let next = stateMachine.reduce(current: previous.state, event: event)
        guard next != previous.state else {
            return false
        }

        snapshotStore.updatePlaybackSnapshot {
            LegatoiOSPlaybackSnapshot(
                state: next,
                currentTrack: $0.currentTrack,
                currentIndex: $0.currentIndex,
                positionMs: $0.positionMs,
                durationMs: $0.durationMs,
                bufferedPositionMs: $0.bufferedPositionMs,
                queue: $0.queue
            )
        }

        publishState(next)
        return true
    }

    private func publishQueueAndTrack(_ snapshot: LegatoiOSPlaybackSnapshot) {
        eventEmitter.emit(name: .playbackQueueChanged, payload: .queueChanged(snapshot: snapshot.queue))
        eventEmitter.emit(
            name: .playbackActiveTrackChanged,
            payload: .activeTrackChanged(track: snapshot.currentTrack, index: snapshot.currentIndex)
        )
    }

    private func publishState(_ state: LegatoiOSPlaybackState) {
        eventEmitter.emit(name: .playbackStateChanged, payload: .playbackStateChanged(state: state))
        sessionManager.updatePlaybackState(state)
        remoteCommandManager.updatePlaybackState(state)
        nowPlayingManager.updatePlaybackState(state)
    }

    private func publishProgress(_ snapshot: LegatoiOSPlaybackSnapshot) {
        let emissionToken = ProgressEmissionToken(
            trackId: snapshot.currentTrack?.id,
            currentIndex: snapshot.currentIndex,
            positionMs: snapshot.positionMs,
            durationMs: snapshot.durationMs,
            bufferedPositionMs: snapshot.bufferedPositionMs
        )

        guard emissionToken != lastProgressEmission else {
            return
        }

        lastProgressEmission = emissionToken

        let progress = LegatoiOSProgressUpdate(
            positionMs: snapshot.positionMs,
            durationMs: snapshot.durationMs,
            bufferedPositionMs: snapshot.bufferedPositionMs
        )

        eventEmitter.emit(
            name: .playbackProgress,
            payload: .playbackProgress(
                positionMs: progress.positionMs,
                durationMs: progress.durationMs,
                bufferedPositionMs: progress.bufferedPositionMs
            )
        )
        nowPlayingManager.updateProgress(progress)
    }

    private func publishMetadata(_ track: LegatoiOSTrack?) {
        let metadata = track.map {
            LegatoiOSNowPlayingMetadata(
                trackId: $0.id,
                title: $0.title,
                artist: $0.artist,
                album: $0.album,
                artwork: $0.artwork,
                durationMs: $0.durationMs
            )
        }

        nowPlayingManager.updateMetadata(metadata)
    }

    private func refreshSnapshotFromRuntime(publishProgressEvent: Bool) {
        applyRuntimeSnapshot(playbackRuntime.snapshot())
        if publishProgressEvent {
            publishProgress(snapshotStore.getPlaybackSnapshot())
        }
    }

    private func applyRuntimeSnapshot(
        _ runtimeSnapshot: LegatoiOSRuntimeSnapshot,
        currentTrackOverride: LegatoiOSTrack? = nil,
        currentIndexFallback: Int? = nil,
        queueOverride: LegatoiOSQueueSnapshot? = nil
    ) {
        let previousSnapshot = snapshotStore.getPlaybackSnapshot()
        if let stateHint = runtimeSnapshot.stateHint,
           shouldApplyRuntimeStateHint(stateHint, runtimeSnapshot: runtimeSnapshot, previousSnapshot: previousSnapshot) {
            applyRuntimeStateHint(stateHint)
        }

        snapshotStore.updatePlaybackSnapshot { previous in
            let resolvedTrack = currentTrackOverride ?? previous.currentTrack
            let resolvedDuration = runtimeSnapshot.progress.durationMs ?? resolvedTrack?.durationMs ?? previous.durationMs
            let normalizedPosition = normalizedPositionMs(
                runtimeSnapshot.progress.positionMs,
                durationMs: resolvedDuration,
                stateHint: runtimeSnapshot.stateHint
            )
            let normalizedBufferedPosition = normalizedBufferedPositionMs(
                runtimeSnapshot.progress.bufferedPositionMs,
                durationMs: resolvedDuration,
                positionMs: normalizedPosition,
                stateHint: runtimeSnapshot.stateHint
            )
            return LegatoiOSPlaybackSnapshot(
                state: previous.state,
                currentTrack: resolvedTrack,
                currentIndex: runtimeSnapshot.currentIndex ?? currentIndexFallback ?? previous.currentIndex,
                positionMs: normalizedPosition,
                durationMs: resolvedDuration,
                bufferedPositionMs: normalizedBufferedPosition,
                queue: queueOverride ?? previous.queue
            )
        }

        remoteCommandManager.updateTransportCapabilities(
            LegatoiOSTransportCapabilitiesProjector.fromSnapshot(snapshotStore.getPlaybackSnapshot())
        )
    }

    private func shouldApplyRuntimeStateHint(
        _ stateHint: LegatoiOSPlaybackState,
        runtimeSnapshot: LegatoiOSRuntimeSnapshot,
        previousSnapshot: LegatoiOSPlaybackSnapshot
    ) -> Bool {
        if stateHint == previousSnapshot.state {
            return false
        }

        guard previousSnapshot.state == .ended,
              stateHint != .ended
        else {
            return true
        }

        let runtimeIndex = runtimeSnapshot.currentIndex ?? previousSnapshot.currentIndex
        guard runtimeIndex == previousSnapshot.currentIndex else {
            return true
        }

        let positionMs = max(0, runtimeSnapshot.progress.positionMs)
        if let durationMs = runtimeSnapshot.progress.durationMs ?? previousSnapshot.durationMs,
           positionMs >= max(0, durationMs) {
            return false
        }

        return positionMs < previousSnapshot.positionMs
    }

    private func applyRuntimeStateHint(_ stateHint: LegatoiOSPlaybackState) {
        let currentState = snapshotStore.getPlaybackSnapshot().state

        switch stateHint {
        case .idle:
            transition(event: .reset)
        case .loading:
            transition(event: .prepare)
        case .ready:
            transition(event: .prepared)
        case .playing:
            if !transition(event: .play) {
                if currentState == .loading || currentState == .idle {
                    transition(event: .prepared)
                    transition(event: .play)
                }
            }
        case .paused:
            if !transition(event: .pause) {
                if currentState == .loading || currentState == .idle {
                    transition(event: .prepared)
                    transition(event: .play)
                    transition(event: .pause)
                }
            }
        case .buffering:
            if !transition(event: .bufferingStarted) {
                if currentState == .loading || currentState == .idle {
                    transition(event: .prepared)
                    transition(event: .play)
                    transition(event: .bufferingStarted)
                }
            }
        case .ended:
            if !transition(event: .trackEnded) {
                transition(event: .prepared)
                transition(event: .play)
                transition(event: .trackEnded)
            }
        case .error:
            transition(event: .fail)
        }
    }

    private func normalizedAutoAdvanceRuntimeSnapshot(
        _ runtimeSnapshot: LegatoiOSRuntimeSnapshot,
        expectedIndex: Int
    ) -> LegatoiOSRuntimeSnapshot {
        guard runtimeSnapshot.stateHint == .ended,
              (runtimeSnapshot.currentIndex ?? expectedIndex) == expectedIndex
        else {
            return runtimeSnapshot
        }

        return LegatoiOSRuntimeSnapshot(
            stateHint: .playing,
            currentIndex: runtimeSnapshot.currentIndex,
            progress: LegatoiOSRuntimeProgress(
                positionMs: 0,
                durationMs: runtimeSnapshot.progress.durationMs,
                bufferedPositionMs: 0
            )
        )
    }

    private func normalizedPositionMs(
        _ positionMs: Int64,
        durationMs: Int64?,
        stateHint: LegatoiOSPlaybackState?
    ) -> Int64 {
        let normalizedPosition = max(0, positionMs)
        guard let durationMs else {
            return normalizedPosition
        }

        let clampedDuration = max(0, durationMs)
        if stateHint == .ended {
            return clampedDuration
        }

        return min(normalizedPosition, clampedDuration)
    }

    private func normalizedBufferedPositionMs(
        _ bufferedPositionMs: Int64?,
        durationMs: Int64?,
        positionMs: Int64,
        stateHint: LegatoiOSPlaybackState?
    ) -> Int64? {
        if stateHint == .ended {
            return durationMs.map { max(0, $0) }
        }

        guard let bufferedPositionMs else {
            return nil
        }

        var normalized = max(0, bufferedPositionMs)
        if let durationMs {
            normalized = min(normalized, max(0, durationMs))
        }

        normalized = max(normalized, positionMs)
        return normalized
    }

    private func publishPlatformFailure(_ error: Error) {
        let mapped = errorMapper.map(error)
        let previous = snapshotStore.getPlaybackSnapshot()
        let next = stateMachine.reduce(current: previous.state, event: .fail)

        snapshotStore.updatePlaybackSnapshot {
            LegatoiOSPlaybackSnapshot(
                state: next,
                currentTrack: $0.currentTrack,
                currentIndex: $0.currentIndex,
                positionMs: $0.positionMs,
                durationMs: $0.durationMs,
                bufferedPositionMs: $0.bufferedPositionMs,
                queue: $0.queue
            )
        }

        eventEmitter.emit(name: .playbackError, payload: .playbackError(error: mapped))
        publishState(next)
    }

    private func registerSessionSignalListenerIfNeeded() {
        guard sessionSignalListenerID == nil else {
            return
        }

        sessionSignalListenerID = sessionManager.addSignalListener { [weak self] signal in
            self?.handleSessionSignal(signal)
        }
    }

    private func removeSessionSignalListenerIfNeeded() {
        guard let sessionSignalListenerID else {
            return
        }

        sessionManager.removeSignalListener(sessionSignalListenerID)
        self.sessionSignalListenerID = nil
    }

    private func handleSessionSignal(_ signal: LegatoiOSSessionSignal) {
        switch signal {
        case .outputRouteRemoved, .interruptionBegan:
            pausePlaybackForSessionSignal()
        case .interruptionEnded(let shouldResume):
            if !shouldResume {
                pausePlaybackForSessionSignal()
            }
            // Conservative behavior: interruption end with shouldResume=true does not auto-resume.
        case .runtimeError(let message):
            publishSessionRuntimeError(message)
        }
    }

    private func pausePlaybackForSessionSignal() {
        guard isSetup else {
            return
        }

        let currentState = snapshotStore.getPlaybackSnapshot().state
        guard currentState == .playing || currentState == .buffering else {
            return
        }

        do {
            try playbackRuntime.pause()
        } catch {
            publishPlatformFailure(error)
            return
        }

        transition(event: .pause)
        refreshSnapshotFromRuntime(publishProgressEvent: true)
    }

    private func publishSessionRuntimeError(_ message: String) {
        let mapped = LegatoiOSError(code: .platformError, message: message)
        eventEmitter.emit(name: .playbackError, payload: .playbackError(error: mapped))
    }

    private func performRuntimeOperation(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            publishPlatformFailure(error)
            throw error
        }
    }

    private func onRemoteCommand(_ command: LegatoiOSRemoteCommand) {
        switch command {
        case .play:
            try? play()
            eventEmitter.emit(name: .remotePlay, payload: .remotePlay)
        case .pause:
            try? pause()
            eventEmitter.emit(name: .remotePause, payload: .remotePause)
        case .next:
            try? skipToNext()
            eventEmitter.emit(name: .remoteNext, payload: .remoteNext)
        case .previous:
            try? skipToPrevious()
            eventEmitter.emit(name: .remotePrevious, payload: .remotePrevious)
        case .seek(let positionMs):
            try? seek(to: positionMs)
            eventEmitter.emit(name: .remoteSeek, payload: .remoteSeek(positionMs: positionMs))
        }
    }

    private func emitEndedAtQueueBoundaryIfNeeded() {
        let snapshot = snapshotStore.getPlaybackSnapshot()
        guard let currentIndex = snapshot.currentIndex else {
            return
        }

        let items = snapshot.queue.items
        guard !items.isEmpty, currentIndex == items.count - 1 else {
            return
        }

        transition(event: .trackEnded)
        let endedSnapshot = snapshotStore.getPlaybackSnapshot()
        remoteCommandManager.updateTransportCapabilities(
            LegatoiOSTransportCapabilitiesProjector.fromSnapshot(endedSnapshot)
        )
        nowPlayingManager.clear()
        eventEmitter.emit(name: .playbackEnded, payload: .playbackEnded(snapshot: endedSnapshot))
    }
}
