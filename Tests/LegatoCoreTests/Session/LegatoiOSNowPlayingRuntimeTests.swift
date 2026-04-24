import XCTest
@testable import LegatoCore

#if canImport(MediaPlayer) && os(iOS)
import MediaPlayer
#endif

final class LegatoiOSNowPlayingRuntimeTests: XCTestCase {
    func testUpdatePlaybackStatePlayingWritesPlaybackRateOne() {
        let center = FakeNowPlayingInfoCenter()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(infoCenter: center)

        runtime.updatePlaybackState(.playing)

        XCTAssertEqual(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.playbackRate] as? Double, 1.0)
        XCTAssertEqual(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.defaultPlaybackRate] as? Double, 1.0)
    }

    func testUpdatePlaybackStateNonPlayingWritesPlaybackRateZero() {
        let center = FakeNowPlayingInfoCenter()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(infoCenter: center)

        let nonPlayingStates: [LegatoiOSPlaybackState] = [
            .idle,
            .loading,
            .ready,
            .paused,
            .buffering,
            .ended,
            .error
        ]

        for state in nonPlayingStates {
            runtime.updatePlaybackState(state)
            XCTAssertEqual(
                center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.playbackRate] as? Double,
                0.0,
                "Expected playbackRate = 0.0 for state \(state)"
            )
            XCTAssertEqual(
                center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.defaultPlaybackRate] as? Double,
                1.0,
                "Expected defaultPlaybackRate = 1.0 for state \(state)"
            )
        }
    }

    func testNowPlayingInfoKeysMapToExpectedMediaPlayerPayloadKeys() {
        #if canImport(MediaPlayer) && os(iOS)
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.title, MPMediaItemPropertyTitle)
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.artist, MPMediaItemPropertyArtist)
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.album, MPMediaItemPropertyAlbumTitle)
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.duration, MPMediaItemPropertyPlaybackDuration)
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.elapsedTime, MPNowPlayingInfoPropertyElapsedPlaybackTime)
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.playbackRate, MPNowPlayingInfoPropertyPlaybackRate)
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.defaultPlaybackRate, MPNowPlayingInfoPropertyDefaultPlaybackRate)
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.artwork, MPMediaItemPropertyArtwork)
        #else
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.title, "title")
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.artist, "artist")
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.album, "albumTitle")
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.duration, "playbackDuration")
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.elapsedTime, "elapsedPlaybackTime")
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.playbackRate, "playbackRate")
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.defaultPlaybackRate, "defaultPlaybackRate")
        XCTAssertEqual(LegatoiOSNowPlayingInfoKey.artwork, "artwork")
        #endif
    }

    func testUpdateMetadataRotatesActiveArtworkToken() {
        let center = FakeNowPlayingInfoCenter()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(
            infoCenter: center,
            artworkLoader: FakeArtworkLoader()
        )

        runtime.updateMetadata(
            .init(
                trackId: "track-1",
                title: "Song",
                artist: "Artist",
                album: "Album",
                durationMs: 90_000
            )
        )
        let firstToken = runtime.activeArtworkToken

        runtime.updateMetadata(
            .init(
                trackId: "track-2",
                title: "Song 2",
                artist: "Artist",
                album: "Album",
                durationMs: 90_000
            )
        )

        XCTAssertNotNil(firstToken)
        XCTAssertNotEqual(firstToken, runtime.activeArtworkToken)
    }

    func testUpdateMetadataNilClearsActiveArtworkToken() {
        let center = FakeNowPlayingInfoCenter()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(
            infoCenter: center,
            artworkLoader: FakeArtworkLoader()
        )

        runtime.updateMetadata(
            .init(
                trackId: "track-1",
                title: "Song",
                artist: "Artist",
                album: "Album",
                durationMs: 90_000
            )
        )

        runtime.updateMetadata(nil)

        XCTAssertNil(runtime.activeArtworkToken)
    }

    func testUpdateMetadataWritesTextFieldsAndDuration() {
        let center = FakeNowPlayingInfoCenter()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(infoCenter: center)

        runtime.updateMetadata(
            .init(
                trackId: "track-1",
                title: "Song",
                artist: "Artist",
                album: "Album",
                durationMs: 90_000
            )
        )

        let info = center.nowPlayingInfo
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.trackIdentifier] as? String, "track-1")
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.title] as? String, "Song")
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.artist] as? String, "Artist")
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.album] as? String, "Album")
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.duration] as? Double, 90)
    }

    func testUpdateProgressWritesElapsedAndUpdatesDurationWhenPresent() {
        let center = FakeNowPlayingInfoCenter()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(infoCenter: center)

        runtime.updateProgress(.init(positionMs: 15_500, durationMs: 120_000, bufferedPositionMs: nil))

        let info = center.nowPlayingInfo
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.elapsedTime] as? Double, 15.5)
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.duration] as? Double, 120)
    }

    func testPauseResumeKeepsElapsedPositionAndDefaultPlaybackRate() {
        let center = FakeNowPlayingInfoCenter()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(infoCenter: center)

        runtime.updateProgress(.init(positionMs: 45_000, durationMs: 120_000, bufferedPositionMs: nil))
        runtime.updatePlaybackState(.paused)

        XCTAssertEqual(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.elapsedTime] as? Double, 45)
        XCTAssertEqual(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.playbackRate] as? Double, 0.0)
        XCTAssertEqual(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.defaultPlaybackRate] as? Double, 1.0)

        runtime.updatePlaybackState(.playing)

        XCTAssertEqual(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.elapsedTime] as? Double, 45)
        XCTAssertEqual(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.playbackRate] as? Double, 1.0)
        XCTAssertEqual(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.defaultPlaybackRate] as? Double, 1.0)
    }

    func testUpdatePlaybackStateRestoresCoherentPayloadWhenInfoCenterIsClearedExternally() {
        let center = FakeNowPlayingInfoCenter()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(infoCenter: center)

        runtime.updateMetadata(
            .init(
                trackId: "track-1",
                title: "Song",
                artist: "Artist",
                album: "Album",
                durationMs: 120_000
            )
        )
        runtime.updateProgress(.init(positionMs: 45_000, durationMs: 120_000, bufferedPositionMs: nil))

        center.nowPlayingInfo = nil
        runtime.updatePlaybackState(.paused)

        let info = center.nowPlayingInfo
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.title] as? String, "Song")
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.duration] as? Double, 120)
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.elapsedTime] as? Double, 45)
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.playbackRate] as? Double, 0.0)
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.defaultPlaybackRate] as? Double, 1.0)
    }

    func testUpdatePlaybackStateRestoresElapsedWhenInfoCenterPayloadBecomesPartial() {
        let center = FakeNowPlayingInfoCenter()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(infoCenter: center)

        runtime.updateProgress(.init(positionMs: 45_000, durationMs: 120_000, bufferedPositionMs: nil))
        runtime.updatePlaybackState(.paused)

        center.nowPlayingInfo = [LegatoiOSNowPlayingInfoKey.title: "Song"]
        runtime.updatePlaybackState(.playing)

        let info = center.nowPlayingInfo
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.elapsedTime] as? Double, 45)
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.duration] as? Double, 120)
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.playbackRate] as? Double, 1.0)
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.defaultPlaybackRate] as? Double, 1.0)
    }

    func testClearRemovesNowPlayingInfo() {
        let center = FakeNowPlayingInfoCenter()
        center.nowPlayingInfo = [LegatoiOSNowPlayingInfoKey.title: "Song"]
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(infoCenter: center)

        runtime.clear()

        XCTAssertNil(center.nowPlayingInfo)
    }

    // MARK: - Artwork Tests

    func testUpdateMetadataWritesTextFieldsImmediatelyWithoutWaitingForArtwork() {
        let center = FakeNowPlayingInfoCenter()
        let loader = FakeArtworkLoader()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(
            infoCenter: center,
            artworkLoader: loader,
            artworkDispatch: { $0() }
        )

        runtime.updateMetadata(
            .init(
                trackId: "track-1",
                title: "Song",
                artist: "Artist",
                album: "Album",
                artwork: "https://example.com/art.jpg",
                durationMs: 90_000
            )
        )

        let info = center.nowPlayingInfo
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.title] as? String, "Song")
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.artist] as? String, "Artist")
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.album] as? String, "Album")
        XCTAssertEqual(info?[LegatoiOSNowPlayingInfoKey.duration] as? Double, 90)
        XCTAssertNil(info?[LegatoiOSNowPlayingInfoKey.artwork])
    }

    func testUpdateMetadataPublishesArtworkOnFetchSuccess() {
        let center = FakeNowPlayingInfoCenter()
        let loader = FakeArtworkLoader()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(
            infoCenter: center,
            artworkLoader: loader,
            artworkDispatch: { $0() }
        )

        runtime.updateMetadata(
            .init(
                trackId: "track-1",
                title: "Song",
                artwork: "https://example.com/art.jpg",
                durationMs: 90_000
            )
        )

        loader.completeFirst(with: .success(makeValidImageData()))

        XCTAssertNotNil(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.artwork])
    }

    func testUpdateMetadataWithMissingArtworkUrlClearsPreviousArtwork() {
        let center = FakeNowPlayingInfoCenter()
        let loader = FakeArtworkLoader()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(
            infoCenter: center,
            artworkLoader: loader,
            artworkDispatch: { $0() }
        )

        runtime.updateMetadata(
            .init(
                trackId: "track-1",
                title: "Song",
                artwork: "https://example.com/art.jpg",
                durationMs: 90_000
            )
        )
        loader.completeFirst(with: .success(makeValidImageData()))
        XCTAssertNotNil(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.artwork])

        runtime.updateMetadata(
            .init(
                trackId: "track-2",
                title: "Song 2",
                artwork: nil,
                durationMs: 90_000
            )
        )
        XCTAssertNil(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.artwork])
    }

    func testUpdateMetadataWithInvalidArtworkUrlClearsPreviousArtwork() {
        let center = FakeNowPlayingInfoCenter()
        let loader = FakeArtworkLoader()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(
            infoCenter: center,
            artworkLoader: loader,
            artworkDispatch: { $0() }
        )

        runtime.updateMetadata(
            .init(
                trackId: "track-1",
                title: "Song",
                artwork: "https://example.com/art.jpg",
                durationMs: 90_000
            )
        )
        loader.completeFirst(with: .success(makeValidImageData()))
        XCTAssertNotNil(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.artwork])

        runtime.updateMetadata(
            .init(
                trackId: "track-2",
                title: "Song 2",
                artwork: "not a url",
                durationMs: 90_000
            )
        )
        XCTAssertNil(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.artwork])
    }

    func testStaleArtworkFetchIsIgnored() {
        let center = FakeNowPlayingInfoCenter()
        let loader = FakeArtworkLoader()
        let runtime = LegatoiOSMediaPlayerNowPlayingRuntime(
            infoCenter: center,
            artworkLoader: loader,
            artworkDispatch: { $0() }
        )

        runtime.updateMetadata(
            .init(
                trackId: "track-1",
                title: "Song",
                artwork: "https://example.com/art1.jpg",
                durationMs: 90_000
            )
        )
        XCTAssertEqual(loader.requests.count, 1)

        runtime.updateMetadata(
            .init(
                trackId: "track-2",
                title: "Song 2",
                artwork: "https://example.com/art2.jpg",
                durationMs: 90_000
            )
        )
        XCTAssertEqual(loader.requests.count, 2)

        loader.completeFirst(with: .success(makeValidImageData()))
        XCTAssertNil(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.artwork])

        loader.completeFirst(with: .success(makeValidImageData()))
        XCTAssertNotNil(center.nowPlayingInfo?[LegatoiOSNowPlayingInfoKey.artwork])
    }
}

private final class FakeNowPlayingInfoCenter: LegatoiOSNowPlayingInfoCenter {
    var nowPlayingInfo: [String: Any]?
}

private final class FakeArtworkLoader: LegatoiOSArtworkLoader {
    private(set) var requests: [(url: URL, completion: (Result<Data, Error>) -> Void)] = []

    func loadArtworkData(from url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        requests.append((url, completion))
    }

    func completeFirst(with result: Result<Data, Error>) {
        guard !requests.isEmpty else { return }
        let request = requests.removeFirst()
        request.completion(result)
    }

    func completeAll(with result: Result<Data, Error>) {
        for request in requests {
            request.completion(result)
        }
        requests.removeAll()
    }
}

private func makeValidImageData() -> Data {
    #if canImport(UIKit) && os(iOS)
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
    let image = renderer.image { ctx in
        UIColor.red.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return image.pngData()!
    #else
    // macOS compilation fallback — runtime stores raw Data when UIKit is unavailable
    return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    #endif
}
