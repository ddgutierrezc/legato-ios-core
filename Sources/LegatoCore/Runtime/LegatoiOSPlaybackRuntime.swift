import AVFoundation
import Foundation

/// Runtime seam for AVPlayer-backed integration.
///
/// The core calls this protocol for runtime operations while preserving canonical
/// Legato state/event semantics outside the platform adapter.
public protocol LegatoiOSPlaybackRuntime {
    func configure()
    func setObserver(_ observer: LegatoiOSPlaybackRuntimeObserver?)
    func replaceQueue(items: [LegatoiOSRuntimeTrackSource], startIndex: Int?) throws
    func selectIndex(_ index: Int) throws
    func play() throws
    func pause() throws
    func stop(resetPosition: Bool) throws
    func seek(to positionMs: Int64) throws
    func snapshot() -> LegatoiOSRuntimeSnapshot
    func release()
}

public protocol LegatoiOSPlaybackRuntimeObserver: AnyObject {
    func playbackRuntimeDidUpdateProgress(_ snapshot: LegatoiOSRuntimeSnapshot)
    func playbackRuntimeDidReachTrackEnd(_ snapshot: LegatoiOSRuntimeSnapshot)
}

public struct LegatoiOSRuntimeTrackSource {
    public let id: String
    public let url: String
    public let headers: [String: String]
    public let type: LegatoiOSTrackType?

    public init(id: String, url: String, headers: [String: String], type: LegatoiOSTrackType?) {
        self.id = id
        self.url = url
        self.headers = headers
        self.type = type
    }
}

public struct LegatoiOSRuntimeProgress {
    public let positionMs: Int64
    public let durationMs: Int64?
    public let bufferedPositionMs: Int64?

    public init(positionMs: Int64, durationMs: Int64?, bufferedPositionMs: Int64?) {
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.bufferedPositionMs = bufferedPositionMs
    }
}

public struct LegatoiOSRuntimeSnapshot {
    public let stateHint: LegatoiOSPlaybackState?
    public let currentIndex: Int?
    public let progress: LegatoiOSRuntimeProgress

    public init(
        stateHint: LegatoiOSPlaybackState? = nil,
        currentIndex: Int? = nil,
        progress: LegatoiOSRuntimeProgress = LegatoiOSRuntimeProgress(positionMs: 0, durationMs: nil, bufferedPositionMs: nil)
    ) {
        self.stateHint = stateHint
        self.currentIndex = currentIndex
        self.progress = progress
    }
}

/// Minimal in-memory fallback runtime.
///
/// This intentionally does not play audio. It only keeps deterministic runtime-facing state.
public final class LegatoiOSNoopPlaybackRuntime: LegatoiOSPlaybackRuntime {
    private var currentIndex: Int?
    private var trackCount: Int = 0
    private var progress = LegatoiOSRuntimeProgress(positionMs: 0, durationMs: nil, bufferedPositionMs: nil)

    public init() {}

    public func configure() {
        // Intentionally no-op. AVPlayer object graph wiring is pending.
    }

    public func setObserver(_ observer: LegatoiOSPlaybackRuntimeObserver?) {
        // Intentionally no-op.
    }

    public func replaceQueue(items: [LegatoiOSRuntimeTrackSource], startIndex: Int?) throws {
        trackCount = items.count
        if items.isEmpty {
            currentIndex = nil
        } else if let startIndex, items.indices.contains(startIndex) {
            currentIndex = startIndex
        } else {
            currentIndex = 0
        }
        progress = LegatoiOSRuntimeProgress(positionMs: 0, durationMs: nil, bufferedPositionMs: nil)
    }

    public func selectIndex(_ index: Int) throws {
        guard index >= 0, index < trackCount else {
            return
        }
        currentIndex = index
        progress = LegatoiOSRuntimeProgress(positionMs: 0, durationMs: nil, bufferedPositionMs: nil)
    }

    public func play() throws {
        // Intentionally no-op. AVPlayer adapter should call player.play().
    }

    public func pause() throws {
        // Intentionally no-op. AVPlayer adapter should call player.pause().
    }

    public func stop(resetPosition: Bool) throws {
        if resetPosition {
            progress = LegatoiOSRuntimeProgress(positionMs: 0, durationMs: nil, bufferedPositionMs: nil)
        }
    }

    public func seek(to positionMs: Int64) throws {
        progress = LegatoiOSRuntimeProgress(positionMs: max(0, positionMs), durationMs: progress.durationMs, bufferedPositionMs: progress.bufferedPositionMs)
    }

    public func snapshot() -> LegatoiOSRuntimeSnapshot {
        LegatoiOSRuntimeSnapshot(currentIndex: currentIndex, progress: progress)
    }

    public func release() {
        currentIndex = nil
        trackCount = 0
        progress = LegatoiOSRuntimeProgress(positionMs: 0, durationMs: nil, bufferedPositionMs: nil)
    }
}

/// AVPlayer-backed runtime for foreground audible playback.
///
/// This adapter intentionally keeps scope minimal for MVP:
/// - single active AVPlayerItem selected by index
/// - no background playback behavior
/// - no interruptions/remote command orchestration
public final class LegatoiOSAVPlayerPlaybackRuntime: LegatoiOSPlaybackRuntime {
    private let player: AVPlayer
    private var trackSources: [LegatoiOSRuntimeTrackSource] = []
    private var currentIndex: Int?
    private weak var observer: LegatoiOSPlaybackRuntimeObserver?
    private var periodicTimeObserverToken: Any?
    private var playbackEndedObserverToken: NSObjectProtocol?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var currentItemStatusObservation: NSKeyValueObservation?
    private var didEmitEndForCurrentItem = false
    private var didReceivePlayForCurrentItem = false

    public init(player: AVPlayer = AVPlayer()) {
        self.player = player
    }

    public func configure() {
        installPeriodicTimeObserverIfNeeded()
        installPlaybackEndedObserverIfNeeded()
        installPlayerSignalObserversIfNeeded()
    }

    public func setObserver(_ observer: LegatoiOSPlaybackRuntimeObserver?) {
        self.observer = observer
    }

    public func replaceQueue(items: [LegatoiOSRuntimeTrackSource], startIndex: Int?) throws {
        trackSources = items

        guard !items.isEmpty else {
            currentIndex = nil
            player.replaceCurrentItem(with: nil)
            didEmitEndForCurrentItem = false
            didReceivePlayForCurrentItem = false
            publishSnapshotUpdate()
            return
        }

        let nextIndex: Int
        if let startIndex, items.indices.contains(startIndex) {
            nextIndex = startIndex
        } else {
            nextIndex = 0
        }

        try loadItem(at: nextIndex)
    }

    public func selectIndex(_ index: Int) throws {
        guard trackSources.indices.contains(index) else {
            return
        }

        try loadItem(at: index)
    }

    public func play() throws {
        guard player.currentItem != nil else {
            throw LegatoiOSError(code: .playbackFailed, message: "No active AVPlayer item to play")
        }
        didReceivePlayForCurrentItem = true
        player.play()
    }

    public func pause() throws {
        player.pause()
    }

    public func stop(resetPosition: Bool) throws {
        player.pause()
        guard resetPosition else {
            return
        }

        player.seek(to: .zero)
        didEmitEndForCurrentItem = false
        didReceivePlayForCurrentItem = false
    }

    public func seek(to positionMs: Int64) throws {
        let clamped = max(0, positionMs)
        let seconds = Double(clamped) / 1000
        let target = CMTime(seconds: seconds, preferredTimescale: 1000)
        player.seek(to: target)
        didEmitEndForCurrentItem = false
    }

    public func snapshot() -> LegatoiOSRuntimeSnapshot {
        let item = player.currentItem
        let duration = durationMs(for: item)
        let rawPosition = positionMs(for: item)
        let position = normalizedPositionMs(rawPosition, durationMs: duration)
        let stateHint = stateHint(for: item)
        let bufferedPosition = normalizedBufferedPositionMs(
            bufferedPositionMs(for: item),
            stateHint: stateHint,
            durationMs: duration,
            positionMs: position
        )

        return LegatoiOSRuntimeSnapshot(
            stateHint: stateHint,
            currentIndex: currentIndex,
            progress: LegatoiOSRuntimeProgress(
                positionMs: position,
                durationMs: duration,
                bufferedPositionMs: bufferedPosition
            )
        )
    }

    public func release() {
        if let periodicTimeObserverToken {
            player.removeTimeObserver(periodicTimeObserverToken)
            self.periodicTimeObserverToken = nil
        }

        if let playbackEndedObserverToken {
            NotificationCenter.default.removeObserver(playbackEndedObserverToken)
            self.playbackEndedObserverToken = nil
        }

        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        currentItemStatusObservation?.invalidate()
        currentItemStatusObservation = nil

        observer = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        trackSources = []
        currentIndex = nil
        didEmitEndForCurrentItem = false
        didReceivePlayForCurrentItem = false
    }

    private func loadItem(at index: Int) throws {
        guard trackSources.indices.contains(index) else {
            throw LegatoiOSError(code: .invalidIndex, message: "Requested runtime index is out of bounds")
        }

        let source = trackSources[index]
        guard let url = URL(string: source.url), url.scheme != nil else {
            throw LegatoiOSError(code: .invalidURL, message: "Track URL is invalid: \(source.url)")
        }

        // Keep the audible-playback MVP on public AVFoundation APIs only.
        // Demo smoke URLs currently do not require custom headers.
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        player.replaceCurrentItem(with: item)
        currentIndex = index
        didEmitEndForCurrentItem = false
        didReceivePlayForCurrentItem = false
        publishSnapshotUpdate()
    }

    private func installPeriodicTimeObserverIfNeeded() {
        guard periodicTimeObserverToken == nil else {
            return
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 1000)
        periodicTimeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.player.timeControlStatus == .playing else {
                return
            }

            self.publishProgressUpdate()
        }
    }

    private func installPlaybackEndedObserverIfNeeded() {
        guard playbackEndedObserverToken == nil else {
            return
        }

        playbackEndedObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let endedItem = notification.object as? AVPlayerItem,
                  let currentItem = self.player.currentItem,
                  endedItem === currentItem,
                  !self.didEmitEndForCurrentItem
            else {
                return
            }

            self.didEmitEndForCurrentItem = true
            let snapshot = self.snapshot()
            self.observer?.playbackRuntimeDidReachTrackEnd(snapshot)
            self.publishSnapshotUpdate()
        }
    }

    private func installPlayerSignalObserversIfNeeded() {
        guard timeControlStatusObservation == nil,
              currentItemObservation == nil
        else {
            return
        }

        timeControlStatusObservation = player.observe(\AVPlayer.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            self?.publishSnapshotUpdate()
        }

        currentItemObservation = player.observe(\AVPlayer.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            guard let self else {
                return
            }

            self.observeCurrentItemStatus(player.currentItem)
            self.publishSnapshotUpdate()
        }
    }

    private func observeCurrentItemStatus(_ item: AVPlayerItem?) {
        currentItemStatusObservation?.invalidate()
        currentItemStatusObservation = nil

        guard let item else {
            return
        }

        currentItemStatusObservation = item.observe(\AVPlayerItem.status, options: [.initial, .new]) { [weak self] _, _ in
            self?.publishSnapshotUpdate()
        }
    }

    private func publishProgressUpdate() {
        observer?.playbackRuntimeDidUpdateProgress(snapshot())
    }

    private func publishSnapshotUpdate() {
        observer?.playbackRuntimeDidUpdateProgress(snapshot())
    }

    private func stateHint(for item: AVPlayerItem?) -> LegatoiOSPlaybackState? {
        guard let item else {
            return .idle
        }

        switch item.status {
        case .unknown:
            return .loading
        case .failed:
            return .error
        case .readyToPlay:
            break
        @unknown default:
            return .error
        }

        if didEmitEndForCurrentItem || isAtTrackEnd(item) {
            return .ended
        }

        if player.timeControlStatus == .playing {
            return .playing
        }

        if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            return .buffering
        }

        if didReceivePlayForCurrentItem {
            return .paused
        }

        return .ready
    }

    private func positionMs(for item: AVPlayerItem?) -> Int64 {
        guard item != nil else {
            return 0
        }

        return milliseconds(from: player.currentTime()) ?? 0
    }

    private func durationMs(for item: AVPlayerItem?) -> Int64? {
        guard let item else {
            return nil
        }

        return milliseconds(from: item.duration)
    }

    private func bufferedPositionMs(for item: AVPlayerItem?) -> Int64? {
        guard let item,
              let loaded = item.loadedTimeRanges.first?.timeRangeValue
        else {
            return nil
        }

        return milliseconds(from: CMTimeAdd(loaded.start, loaded.duration))
    }

    private func normalizedPositionMs(_ positionMs: Int64, durationMs: Int64?) -> Int64 {
        guard let durationMs else {
            return max(0, positionMs)
        }

        return min(max(0, positionMs), max(0, durationMs))
    }

    private func normalizedBufferedPositionMs(
        _ bufferedPositionMs: Int64?,
        stateHint: LegatoiOSPlaybackState?,
        durationMs: Int64?,
        positionMs: Int64
    ) -> Int64? {
        if stateHint == .ended {
            return durationMs
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

    private func isAtTrackEnd(_ item: AVPlayerItem) -> Bool {
        guard let durationMs = durationMs(for: item), durationMs > 0 else {
            return false
        }

        let positionMs = positionMs(for: item)
        return positionMs >= durationMs
    }

    private func milliseconds(from time: CMTime) -> Int64? {
        guard time.isValid else {
            return nil
        }

        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, !seconds.isNaN else {
            return nil
        }

        return Int64(max(0, seconds * 1000))
    }
}
