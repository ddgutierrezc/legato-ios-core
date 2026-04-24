import XCTest
@testable import LegatoCore

final class LegatoiOSSessionManagerTests: XCTestCase {
    func testDefaultManagerUsesNoopRuntimeOnNonIOSHosts() {
        let manager = LegatoiOSSessionManager()
        let runtime = extractRuntime(from: manager)

        #if os(iOS)
        XCTAssertFalse(runtime is LegatoiOSNoopSessionRuntime)
        #else
        XCTAssertTrue(runtime is LegatoiOSNoopSessionRuntime)
        #endif
    }

    func testRuntimeSignalsAreForwardedToRegisteredListeners() {
        let runtime = FakeSessionRuntime()
        let manager = LegatoiOSSessionManager(runtime: runtime)
        let expectation = expectation(description: "manager forwards runtime signal")

        _ = manager.addSignalListener { signal in
            if case .outputRouteRemoved = signal {
                expectation.fulfill()
            }
        }

        runtime.emit(.outputRouteRemoved)

        wait(for: [expectation], timeout: 0.1)
    }

    private func extractRuntime(from manager: LegatoiOSSessionManager) -> Any {
        guard let runtime = Mirror(reflecting: manager)
            .children
            .first(where: { $0.label == "runtime" })?
            .value
        else {
            XCTFail("Expected LegatoiOSSessionManager runtime storage")
            return LegatoiOSNoopSessionRuntime()
        }

        return runtime
    }
}

private final class FakeSessionRuntime: LegatoiOSSessionRuntime {
    var onSignal: ((LegatoiOSSessionSignal) -> Void)?

    func configureSession() {}
    func updatePlaybackState(_ state: LegatoiOSPlaybackState) {}
    func releaseSession() {}

    func emit(_ signal: LegatoiOSSessionSignal) {
        onSignal?(signal)
    }
}
