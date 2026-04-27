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

    func testInterruptionExtractionMapsBeginAndResumeIntentVariants() {
        XCTAssertEqual(
            legatoExtractInterruptionSignal(typeRaw: 1, optionsRaw: nil),
            .interruptionBegan
        )
        XCTAssertEqual(
            legatoExtractInterruptionSignal(typeRaw: 0, optionsRaw: 1),
            .interruptionEnded(intent: .shouldResume)
        )
        XCTAssertEqual(
            legatoExtractInterruptionSignal(typeRaw: 0, optionsRaw: 0),
            .interruptionEnded(intent: .shouldNotResume)
        )
        XCTAssertEqual(
            legatoExtractInterruptionSignal(typeRaw: 0, optionsRaw: nil),
            .interruptionEnded(intent: .unknown)
        )
    }

    func testInterruptionExtractionIgnoresUnknownType() {
        XCTAssertNil(legatoExtractInterruptionSignal(typeRaw: 99, optionsRaw: nil))
    }

    func testRouteExtractionMapsLostUnavailableAndAvailableReasons() {
        XCTAssertEqual(
            legatoExtractRouteSignal(reasonRaw: 2),
            .outputRouteLost(reason: .oldDeviceUnavailable)
        )
        XCTAssertEqual(
            legatoExtractRouteSignal(reasonRaw: 7),
            .outputRouteLost(reason: .noSuitableRoute)
        )
        XCTAssertEqual(
            legatoExtractRouteSignal(reasonRaw: 1),
            .outputRouteAvailable(reason: .newDeviceAvailable)
        )
    }

    func testRouteExtractionIgnoresUnhandledReason() {
        XCTAssertNil(legatoExtractRouteSignal(reasonRaw: 4))
    }
}
