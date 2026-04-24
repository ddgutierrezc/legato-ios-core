import XCTest
@testable import LegatoCoreSessionRuntimeiOS
import LegatoCore

final class LegatoiOSAVAudioSessionRuntimeExtractionTests: XCTestCase {
    func testSessionActivationMappingReturnsTrueForPlaying() {
        XCTAssertTrue(legatoShouldActivateSession(for: .playing))
    }

    func testSessionActivationMappingReturnsFalseForIdleAndError() {
        XCTAssertFalse(legatoShouldActivateSession(for: .idle))
        XCTAssertFalse(legatoShouldActivateSession(for: .error))
    }
}
