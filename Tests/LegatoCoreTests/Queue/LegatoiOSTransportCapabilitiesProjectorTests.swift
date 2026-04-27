import XCTest
@testable import LegatoCore

final class LegatoiOSTransportCapabilitiesProjectorTests: XCTestCase {
    func testProjectsProgressiveAsSeekableWhenActiveAndNotEnded() {
        let snapshot = makeSnapshot(
            state: .playing,
            tracks: [makeTrack(id: "track-1", type: .progressive)],
            currentIndex: 0,
            durationMs: 120_000,
            isSeekableHint: nil
        )

        XCTAssertEqual(
            LegatoiOSTransportCapabilities(canSkipNext: false, canSkipPrevious: false, canSeek: true),
            LegatoiOSTransportCapabilitiesProjector.fromSnapshot(snapshot)
        )
    }

    func testProjectsHlsAsNonSeekableWhenFiniteEvidenceIsMissing() {
        let snapshot = makeSnapshot(
            state: .playing,
            tracks: [makeTrack(id: "track-hls", type: .hls)],
            currentIndex: 0,
            durationMs: nil,
            isSeekableHint: nil
        )

        XCTAssertEqual(
            LegatoiOSTransportCapabilities(canSkipNext: false, canSkipPrevious: false, canSeek: false),
            LegatoiOSTransportCapabilitiesProjector.fromSnapshot(snapshot)
        )
    }

    func testProjectsHlsAsSeekableOnlyWhenFiniteDurationAndRuntimeHintArePresent() {
        let snapshot = makeSnapshot(
            state: .playing,
            tracks: [makeTrack(id: "track-hls", type: .hls)],
            currentIndex: 0,
            durationMs: 180_000,
            isSeekableHint: true
        )

        XCTAssertEqual(
            LegatoiOSTransportCapabilities(canSkipNext: false, canSkipPrevious: false, canSeek: true),
            LegatoiOSTransportCapabilitiesProjector.fromSnapshot(snapshot)
        )
    }

    private func makeSnapshot(
        state: LegatoiOSPlaybackState,
        tracks: [LegatoiOSTrack],
        currentIndex: Int?,
        durationMs: Int64?,
        isSeekableHint: Bool?
    ) -> LegatoiOSPlaybackSnapshot {
        LegatoiOSPlaybackSnapshot(
            state: state,
            currentTrack: currentIndex.flatMap { tracks.indices.contains($0) ? tracks[$0] : nil },
            currentIndex: currentIndex,
            positionMs: 0,
            durationMs: durationMs,
            isSeekableHint: isSeekableHint,
            bufferedPositionMs: nil,
            queue: LegatoiOSQueueSnapshot(items: tracks, currentIndex: currentIndex)
        )
    }

    private func makeTrack(id: String, type: LegatoiOSTrackType) -> LegatoiOSTrack {
        LegatoiOSTrack(id: id, url: "https://example.com/\(id).mp3", type: type)
    }
}
