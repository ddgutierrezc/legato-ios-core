import Foundation

public enum LegatoiOSPlaybackState: String {
    case idle
    case loading
    case ready
    case playing
    case paused
    case buffering
    case ended
    case error
}

public enum LegatoiOSTrackType: String {
    case file
    case progressive
    case hls
    case dash
}

public struct LegatoiOSTrack {
    public let id: String
    public let url: String
    public let title: String?
    public let artist: String?
    public let album: String?
    public let artwork: String?
    public let durationMs: Int64?
    public let headers: [String: String]
    public let type: LegatoiOSTrackType?

    public init(
        id: String,
        url: String,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        artwork: String? = nil,
        durationMs: Int64? = nil,
        headers: [String: String] = [:],
        type: LegatoiOSTrackType? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.durationMs = durationMs
        self.headers = headers
        self.type = type
    }
}

public enum LegatoiOSErrorCode: String {
    case playerNotSetup = "player_not_setup"
    case invalidIndex = "invalid_index"
    case emptyQueue = "empty_queue"
    case noActiveTrack = "no_active_track"
    case invalidURL = "invalid_url"
    case loadFailed = "load_failed"
    case playbackFailed = "playback_failed"
    case seekFailed = "seek_failed"
    case unsupportedOperation = "unsupported_operation"
    case platformError = "platform_error"
}

public struct LegatoiOSError: Error {
    public let code: LegatoiOSErrorCode
    public let message: String
    public let details: Any?

    public init(code: LegatoiOSErrorCode, message: String, details: Any? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}

public struct LegatoiOSQueueSnapshot {
    public let items: [LegatoiOSTrack]
    public let currentIndex: Int?

    public init(items: [LegatoiOSTrack], currentIndex: Int?) {
        self.items = items
        self.currentIndex = currentIndex
    }
}

public struct LegatoiOSPlaybackSnapshot {
    public let state: LegatoiOSPlaybackState
    public let currentTrack: LegatoiOSTrack?
    public let currentIndex: Int?
    public let positionMs: Int64
    public let durationMs: Int64?
    public let bufferedPositionMs: Int64?
    public let queue: LegatoiOSQueueSnapshot

    public init(
        state: LegatoiOSPlaybackState,
        currentTrack: LegatoiOSTrack?,
        currentIndex: Int?,
        positionMs: Int64,
        durationMs: Int64?,
        bufferedPositionMs: Int64?,
        queue: LegatoiOSQueueSnapshot
    ) {
        self.state = state
        self.currentTrack = currentTrack
        self.currentIndex = currentIndex
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.bufferedPositionMs = bufferedPositionMs
        self.queue = queue
    }
}

public struct LegatoiOSTransportCapabilities: Equatable {
    public let canSkipNext: Bool
    public let canSkipPrevious: Bool
    public let canSeek: Bool

    public init(canSkipNext: Bool, canSkipPrevious: Bool, canSeek: Bool) {
        self.canSkipNext = canSkipNext
        self.canSkipPrevious = canSkipPrevious
        self.canSeek = canSeek
    }
}

public struct LegatoiOSNowPlayingMetadata {
    public let trackId: String
    public let title: String?
    public let artist: String?
    public let album: String?
    public let artwork: String?
    public let durationMs: Int64?

    public init(
        trackId: String,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        artwork: String? = nil,
        durationMs: Int64? = nil
    ) {
        self.trackId = trackId
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.durationMs = durationMs
    }
}

public struct LegatoiOSProgressUpdate {
    public let positionMs: Int64
    public let durationMs: Int64?
    public let bufferedPositionMs: Int64?

    public init(positionMs: Int64, durationMs: Int64?, bufferedPositionMs: Int64?) {
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.bufferedPositionMs = bufferedPositionMs
    }
}

public enum LegatoiOSRemoteCommand {
    case play
    case pause
    case next
    case previous
    case seek(positionMs: Int64)
}

public enum LegatoiOSEventName: String {
    case playbackStateChanged = "playback-state-changed"
    case playbackActiveTrackChanged = "playback-active-track-changed"
    case playbackQueueChanged = "playback-queue-changed"
    case playbackProgress = "playback-progress"
    case playbackEnded = "playback-ended"
    case playbackError = "playback-error"
    case remotePlay = "remote-play"
    case remotePause = "remote-pause"
    case remoteNext = "remote-next"
    case remotePrevious = "remote-previous"
    case remoteSeek = "remote-seek"
}

public enum LegatoiOSEventPayload {
    case playbackStateChanged(state: LegatoiOSPlaybackState)
    case activeTrackChanged(track: LegatoiOSTrack?, index: Int?)
    case queueChanged(snapshot: LegatoiOSQueueSnapshot)
    case playbackProgress(positionMs: Int64, durationMs: Int64?, bufferedPositionMs: Int64?)
    case playbackEnded(snapshot: LegatoiOSPlaybackSnapshot)
    case playbackError(error: LegatoiOSError)
    case remotePlay
    case remotePause
    case remoteNext
    case remotePrevious
    case remoteSeek(positionMs: Int64)
}

public struct LegatoiOSEvent {
    public let name: LegatoiOSEventName
    public let payload: LegatoiOSEventPayload?

    public init(name: LegatoiOSEventName, payload: LegatoiOSEventPayload? = nil) {
        self.name = name
        self.payload = payload
    }
}
