import XCTest
@testable import LegatoCore

final class LegatoiOSQueueManagerTests: XCTestCase {
    func testReplaceQueueThrowsInvalidIndexWhenStartIndexIsOutOfBounds() {
        let queueManager = LegatoiOSQueueManager()
        let tracks = [makeTrack(id: "track-1"), makeTrack(id: "track-2")]

        XCTAssertThrowsError(try queueManager.replaceQueue(tracks, startIndex: 5)) { error in
            guard let queueError = error as? LegatoiOSError else {
                return XCTFail("Expected LegatoiOSError")
            }

            XCTAssertEqual(queueError.code, .invalidIndex)
        }
    }

    func testReplaceQueueThrowsInvalidIndexWhenEmptyQueueHasStartIndex() {
        let queueManager = LegatoiOSQueueManager()

        XCTAssertThrowsError(try queueManager.replaceQueue([], startIndex: 0)) { error in
            guard let queueError = error as? LegatoiOSError else {
                return XCTFail("Expected LegatoiOSError")
            }

            XCTAssertEqual(queueError.code, .invalidIndex)
        }
    }

    func testMoveToNextReturnsNilWhenQueueIsEmpty() {
        let queueManager = LegatoiOSQueueManager()

        XCTAssertNil(queueManager.moveToNext())
    }

    func testMoveToPreviousReturnsNilWhenQueueIsEmpty() {
        let queueManager = LegatoiOSQueueManager()

        XCTAssertNil(queueManager.moveToPrevious())
    }

    func testMoveToNextReturnsNilAtQueueBoundary() throws {
        let queueManager = LegatoiOSQueueManager()
        let tracks = [makeTrack(id: "track-1"), makeTrack(id: "track-2")]
        _ = try queueManager.replaceQueue(tracks, startIndex: 1)

        XCTAssertNil(queueManager.moveToNext())
        XCTAssertEqual(queueManager.getQueueSnapshot().currentIndex, 1)
    }

    private func makeTrack(id: String) -> LegatoiOSTrack {
        LegatoiOSTrack(id: id, url: "https://example.com/\(id).mp3")
    }
}
