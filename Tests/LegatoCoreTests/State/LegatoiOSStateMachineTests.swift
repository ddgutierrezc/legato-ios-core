import XCTest
@testable import LegatoCore

final class LegatoiOSStateMachineTests: XCTestCase {
    func testCanTransitionReturnsTrueForAllowedTransition() {
        let stateMachine = LegatoiOSStateMachine()

        XCTAssertTrue(stateMachine.canTransition(from: .idle, to: .loading))
        XCTAssertTrue(stateMachine.canTransition(from: .playing, to: .paused))
    }

    func testCanTransitionReturnsFalseForDisallowedTransition() {
        let stateMachine = LegatoiOSStateMachine()

        XCTAssertFalse(stateMachine.canTransition(from: .idle, to: .playing))
        XCTAssertFalse(stateMachine.canTransition(from: .error, to: .playing))
    }

    func testReduceMovesToMappedStateWhenTransitionAllowed() {
        let stateMachine = LegatoiOSStateMachine()

        XCTAssertEqual(stateMachine.reduce(current: .idle, event: .prepare), .loading)
        XCTAssertEqual(stateMachine.reduce(current: .ready, event: .play), .playing)
    }

    func testReduceKeepsCurrentStateWhenTransitionIsNotAllowed() {
        let stateMachine = LegatoiOSStateMachine()

        XCTAssertEqual(stateMachine.reduce(current: .idle, event: .pause), .idle)
        XCTAssertEqual(stateMachine.reduce(current: .error, event: .trackEnded), .error)
    }
}
