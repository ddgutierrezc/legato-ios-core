import Foundation

public struct LegatoiOSCoreDependencies {
    public let queueManager: LegatoiOSQueueManager
    public let eventEmitter: LegatoiOSEventEmitter
    public let snapshotStore: LegatoiOSSnapshotStore
    public let trackMapper: LegatoiOSTrackMapper
    public let errorMapper: LegatoiOSErrorMapper
    public let stateMachine: LegatoiOSStateMachine
    public let sessionManager: LegatoiOSSessionManager
    public let nowPlayingManager: LegatoiOSNowPlayingManager
    public let remoteCommandManager: LegatoiOSRemoteCommandManager
    public let playbackRuntime: LegatoiOSPlaybackRuntime

    public init(
        queueManager: LegatoiOSQueueManager = LegatoiOSQueueManager(),
        eventEmitter: LegatoiOSEventEmitter = LegatoiOSEventEmitter(),
        snapshotStore: LegatoiOSSnapshotStore = LegatoiOSSnapshotStore(),
        trackMapper: LegatoiOSTrackMapper = LegatoiOSTrackMapper(),
        errorMapper: LegatoiOSErrorMapper = LegatoiOSErrorMapper(),
        stateMachine: LegatoiOSStateMachine = LegatoiOSStateMachine(),
        // Session runtime resolution is centralized in LegatoiOSSessionManager defaults.
        // This keeps plugin-facing composition unchanged while remaining host-safe.
        sessionManager: LegatoiOSSessionManager = LegatoiOSSessionManager(),
        nowPlayingManager: LegatoiOSNowPlayingManager = LegatoiOSNowPlayingManager(),
        remoteCommandManager: LegatoiOSRemoteCommandManager = LegatoiOSRemoteCommandManager(),
        // Canonical runtime default for iOS playback integrity closure.
        // Queue/snapshot mutation authority stays in LegatoiOSPlayerEngine; plugin boundary delegates only.
        playbackRuntime: LegatoiOSPlaybackRuntime = LegatoiOSAVPlayerPlaybackRuntime()
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

}

public struct LegatoiOSCoreComponents {
    public let queueManager: LegatoiOSQueueManager
    public let eventEmitter: LegatoiOSEventEmitter
    public let snapshotStore: LegatoiOSSnapshotStore
    public let trackMapper: LegatoiOSTrackMapper
    public let errorMapper: LegatoiOSErrorMapper
    public let stateMachine: LegatoiOSStateMachine
    public let sessionManager: LegatoiOSSessionManager
    public let nowPlayingManager: LegatoiOSNowPlayingManager
    public let remoteCommandManager: LegatoiOSRemoteCommandManager
    public let playbackRuntime: LegatoiOSPlaybackRuntime
    public let playerEngine: LegatoiOSPlayerEngine

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
        playbackRuntime: LegatoiOSPlaybackRuntime,
        playerEngine: LegatoiOSPlayerEngine
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
        self.playerEngine = playerEngine
    }
}

public enum LegatoiOSCoreFactory {
    public static func make(
        dependencies: LegatoiOSCoreDependencies = LegatoiOSCoreDependencies()
    ) -> LegatoiOSCoreComponents {
        let playerEngine = LegatoiOSPlayerEngine(
            queueManager: dependencies.queueManager,
            eventEmitter: dependencies.eventEmitter,
            snapshotStore: dependencies.snapshotStore,
            trackMapper: dependencies.trackMapper,
            errorMapper: dependencies.errorMapper,
            stateMachine: dependencies.stateMachine,
            sessionManager: dependencies.sessionManager,
            nowPlayingManager: dependencies.nowPlayingManager,
            remoteCommandManager: dependencies.remoteCommandManager,
            playbackRuntime: dependencies.playbackRuntime
        )

        return LegatoiOSCoreComponents(
            queueManager: dependencies.queueManager,
            eventEmitter: dependencies.eventEmitter,
            snapshotStore: dependencies.snapshotStore,
            trackMapper: dependencies.trackMapper,
            errorMapper: dependencies.errorMapper,
            stateMachine: dependencies.stateMachine,
            sessionManager: dependencies.sessionManager,
            nowPlayingManager: dependencies.nowPlayingManager,
            remoteCommandManager: dependencies.remoteCommandManager,
            playbackRuntime: dependencies.playbackRuntime,
            playerEngine: playerEngine
        )
    }
}
