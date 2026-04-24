import XCTest
@testable import LegatoCore

final class LegatoiOSRemoteCommandRuntimeTests: XCTestCase {
    func testBindRegistersAllHandlersAndDispatchesCommands() {
        let center = FakeRemoteCommandCenter()
        let runtime = LegatoiOSMediaPlayerRemoteCommandRuntime(commandCenter: center)
        var received: [LegatoiOSRemoteCommand] = []

        runtime.bind { received.append($0) }

        center.play.trigger()
        center.pause.trigger()
        center.next.trigger()
        center.previous.trigger()
        center.position.trigger(positionTimeSeconds: 42.5)

        XCTAssertEqual(received.count, 5)
        if case .play = received[0] {} else { XCTFail("Expected play command") }
        if case .pause = received[1] {} else { XCTFail("Expected pause command") }
        if case .next = received[2] {} else { XCTFail("Expected next command") }
        if case .previous = received[3] {} else { XCTFail("Expected previous command") }

        if case let .seek(positionMs) = received[4] {
            XCTAssertEqual(positionMs, 42_500)
        } else {
            XCTFail("Expected seek command")
        }
    }

    func testUpdateTransportCapabilitiesTogglesNextPreviousSeek() {
        let center = FakeRemoteCommandCenter()
        let runtime = LegatoiOSMediaPlayerRemoteCommandRuntime(commandCenter: center)

        runtime.bind { _ in }
        runtime.updateTransportCapabilities(.init(canSkipNext: false, canSkipPrevious: true, canSeek: false))

        XCTAssertFalse(center.next.isEnabled)
        XCTAssertTrue(center.previous.isEnabled)
        XCTAssertFalse(center.position.isEnabled)
    }

    func testUnbindRemovesRegisteredHandlers() {
        let center = FakeRemoteCommandCenter()
        let runtime = LegatoiOSMediaPlayerRemoteCommandRuntime(commandCenter: center)

        runtime.bind { _ in }
        runtime.unbind()

        XCTAssertEqual(center.play.removeTargetCount, 1)
        XCTAssertEqual(center.pause.removeTargetCount, 1)
        XCTAssertEqual(center.next.removeTargetCount, 1)
        XCTAssertEqual(center.previous.removeTargetCount, 1)
        XCTAssertEqual(center.position.removeTargetCount, 1)
    }
}

private final class FakeRemoteCommandCenter: LegatoiOSRemoteCommandCenter {
    let play = FakeButtonCommand()
    let pause = FakeButtonCommand()
    let next = FakeButtonCommand()
    let previous = FakeButtonCommand()
    let position = FakePositionCommand()

    var playCommand: any LegatoiOSRemoteCommandHandler { play }
    var pauseCommand: any LegatoiOSRemoteCommandHandler { pause }
    var nextTrackCommand: any LegatoiOSRemoteCommandHandler { next }
    var previousTrackCommand: any LegatoiOSRemoteCommandHandler { previous }
    var changePlaybackPositionCommand: any LegatoiOSChangePlaybackPositionCommandHandler { position }
}

private final class FakeButtonCommand: LegatoiOSRemoteCommandHandler {
    var isEnabled: Bool = false
    private var handlerByToken: [UUID: () -> Void] = [:]
    private(set) var removeTargetCount = 0

    @discardableResult
    func addTarget(_ handler: @escaping () -> Void) -> AnyObject {
        let token = UUID()
        handlerByToken[token] = handler
        return token as NSUUID
    }

    func removeTarget(_ token: AnyObject) {
        removeTargetCount += 1
        if let uuid = token as? NSUUID {
            handlerByToken.removeValue(forKey: uuid as UUID)
        }
    }

    func trigger() {
        handlerByToken.values.forEach { $0() }
    }
}

private final class FakePositionCommand: LegatoiOSChangePlaybackPositionCommandHandler {
    var isEnabled: Bool = false
    private var handlerByToken: [UUID: (Double) -> Void] = [:]
    private(set) var removeTargetCount = 0

    @discardableResult
    func addTarget(_ handler: @escaping (Double) -> Void) -> AnyObject {
        let token = UUID()
        handlerByToken[token] = handler
        return token as NSUUID
    }

    func removeTarget(_ token: AnyObject) {
        removeTargetCount += 1
        if let uuid = token as? NSUUID {
            handlerByToken.removeValue(forKey: uuid as UUID)
        }
    }

    func trigger(positionTimeSeconds: Double) {
        handlerByToken.values.forEach { $0(positionTimeSeconds) }
    }
}
