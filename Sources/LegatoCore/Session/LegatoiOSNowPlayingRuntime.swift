import Foundation

#if canImport(UIKit) && os(iOS)
import UIKit
#endif

#if canImport(MediaPlayer) && os(iOS)
import MediaPlayer
#endif

/// Seam for MPNowPlayingInfoCenter integration.
public protocol LegatoiOSNowPlayingRuntime {
    func updateMetadata(_ metadata: LegatoiOSNowPlayingMetadata?)
    func updateProgress(_ progress: LegatoiOSProgressUpdate)
    func updatePlaybackState(_ state: LegatoiOSPlaybackState)
    func clear()
}

public protocol LegatoiOSNowPlayingInfoCenter: AnyObject {
    var nowPlayingInfo: [String: Any]? { get set }
}

public protocol LegatoiOSArtworkLoader {
    func loadArtworkData(from url: URL, completion: @escaping (Result<Data, Error>) -> Void)
}

public final class LegatoiOSURLSessionArtworkLoader: LegatoiOSArtworkLoader {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func loadArtworkData(from url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        session.dataTask(with: url) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            completion(.success(data))
        }.resume()
    }
}

public enum LegatoiOSNowPlayingInfoKey {
    public static let trackIdentifier = "legato.track.id"

    #if canImport(MediaPlayer) && os(iOS)
    public static let title = MPMediaItemPropertyTitle
    public static let artist = MPMediaItemPropertyArtist
    public static let album = MPMediaItemPropertyAlbumTitle
    public static let duration = MPMediaItemPropertyPlaybackDuration
    public static let elapsedTime = MPNowPlayingInfoPropertyElapsedPlaybackTime
    public static let playbackRate = MPNowPlayingInfoPropertyPlaybackRate
    public static let defaultPlaybackRate = MPNowPlayingInfoPropertyDefaultPlaybackRate
    public static let artwork = MPMediaItemPropertyArtwork
    #else
    public static let title = "title"
    public static let artist = "artist"
    public static let album = "albumTitle"
    public static let duration = "playbackDuration"
    public static let elapsedTime = "elapsedPlaybackTime"
    public static let playbackRate = "playbackRate"
    public static let defaultPlaybackRate = "defaultPlaybackRate"
    public static let artwork = "artwork"
    #endif
}

public final class LegatoiOSMediaPlayerNowPlayingRuntime: LegatoiOSNowPlayingRuntime {
    private let infoCenter: LegatoiOSNowPlayingInfoCenter
    private let artworkLoader: LegatoiOSArtworkLoader
    private let artworkDispatch: (@escaping () -> Void) -> Void
    private var projectedNowPlayingInfo: [String: Any]
    internal private(set) var activeArtworkToken: UUID?

    public init(
        infoCenter: LegatoiOSNowPlayingInfoCenter = LegatoiOSLiveNowPlayingInfoCenter(),
        artworkLoader: LegatoiOSArtworkLoader = LegatoiOSURLSessionArtworkLoader(),
        artworkDispatch: @escaping (@escaping () -> Void) -> Void = { block in DispatchQueue.main.async(execute: block) }
    ) {
        self.infoCenter = infoCenter
        self.artworkLoader = artworkLoader
        self.artworkDispatch = artworkDispatch
        projectedNowPlayingInfo = infoCenter.nowPlayingInfo ?? [:]
    }

    public func updateMetadata(_ metadata: LegatoiOSNowPlayingMetadata?) {
        guard let metadata else {
            activeArtworkToken = nil
            clear()
            return
        }

        let token = UUID()
        activeArtworkToken = token

        var info = projectedNowPlayingInfo
        info[LegatoiOSNowPlayingInfoKey.trackIdentifier] = metadata.trackId
        info[LegatoiOSNowPlayingInfoKey.title] = metadata.title
        info[LegatoiOSNowPlayingInfoKey.artist] = metadata.artist
        info[LegatoiOSNowPlayingInfoKey.album] = metadata.album

        if let durationMs = metadata.durationMs {
            info[LegatoiOSNowPlayingInfoKey.duration] = Self.seconds(fromMs: durationMs)
        } else {
            info.removeValue(forKey: LegatoiOSNowPlayingInfoKey.duration)
        }

        info[LegatoiOSNowPlayingInfoKey.defaultPlaybackRate] = Self.defaultPlaybackRate

        // Remove any previous artwork so stale images don't persist across track changes
        info.removeValue(forKey: LegatoiOSNowPlayingInfoKey.artwork)

        publish(info)

        if let artworkUrlString = metadata.artwork, let artworkUrl = URL(string: artworkUrlString) {
            artworkLoader.loadArtworkData(from: artworkUrl) { [weak self] result in
                self?.artworkDispatch {
                    self?.applyArtworkResult(result, for: token)
                }
            }
        }
    }

    public func updateProgress(_ progress: LegatoiOSProgressUpdate) {
        var info = projectedNowPlayingInfo
        info[LegatoiOSNowPlayingInfoKey.elapsedTime] = Self.seconds(fromMs: progress.positionMs)
        info[LegatoiOSNowPlayingInfoKey.defaultPlaybackRate] = Self.defaultPlaybackRate

        if let durationMs = progress.durationMs {
            info[LegatoiOSNowPlayingInfoKey.duration] = Self.seconds(fromMs: durationMs)
        }

        publish(info)
    }

    public func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        var info = projectedNowPlayingInfo
        info[LegatoiOSNowPlayingInfoKey.defaultPlaybackRate] = Self.defaultPlaybackRate
        info[LegatoiOSNowPlayingInfoKey.playbackRate] = state == .playing ? Self.defaultPlaybackRate : 0.0
        publish(info)
    }

    public func clear() {
        activeArtworkToken = nil
        projectedNowPlayingInfo.removeAll()
        infoCenter.nowPlayingInfo = nil
    }

    private func applyArtworkResult(_ result: Result<Data, Error>, for token: UUID) {
        guard activeArtworkToken == token else {
            return
        }

        switch result {
        case .success(let data):
            guard let artwork = Self.createMediaItemArtwork(from: data) else {
                return
            }
            var info = projectedNowPlayingInfo
            info[LegatoiOSNowPlayingInfoKey.artwork] = artwork
            publish(info)
        case .failure:
            break
        }
    }

    private func publish(_ info: [String: Any]) {
        projectedNowPlayingInfo = info
        infoCenter.nowPlayingInfo = info
    }

    private static func createMediaItemArtwork(from data: Data) -> Any? {
        #if canImport(UIKit) && os(iOS)
        guard let image = UIImage(data: data) else { return nil }

        // Downsample to a bounded size suitable for lock screen / control center
        let maxDimension: CGFloat = 800
        let finalImage: UIImage
        if image.size.width > maxDimension || image.size.height > maxDimension {
            let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
            let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            finalImage = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }
        } else {
            finalImage = image
        }

        return MPMediaItemArtwork(boundsSize: finalImage.size) { _ in finalImage }
        #else
        return data
        #endif
    }

    private static func seconds(fromMs value: Int64) -> Double {
        Double(max(0, value)) / 1_000.0
    }

    private static let defaultPlaybackRate: Double = 1.0
}

public final class LegatoiOSNoopNowPlayingRuntime: LegatoiOSNowPlayingRuntime {
    public init() {}

    public func updateMetadata(_ metadata: LegatoiOSNowPlayingMetadata?) {
        // Intentionally no-op. MPNowPlayingInfoCenter mapping is pending.
    }

    public func updateProgress(_ progress: LegatoiOSProgressUpdate) {
        // Intentionally no-op.
    }

    public func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        // Intentionally no-op.
    }

    public func clear() {
        // Intentionally no-op.
    }
}

#if canImport(MediaPlayer) && os(iOS)
import MediaPlayer

public final class LegatoiOSLiveNowPlayingInfoCenter: LegatoiOSNowPlayingInfoCenter {
    private let infoCenter: MPNowPlayingInfoCenter

    public init(infoCenter: MPNowPlayingInfoCenter = .default()) {
        self.infoCenter = infoCenter
    }

    public var nowPlayingInfo: [String: Any]? {
        get { infoCenter.nowPlayingInfo }
        set { infoCenter.nowPlayingInfo = newValue }
    }
}
#else
public final class LegatoiOSLiveNowPlayingInfoCenter: LegatoiOSNowPlayingInfoCenter {
    public var nowPlayingInfo: [String: Any]?

    public init() {}
}
#endif
