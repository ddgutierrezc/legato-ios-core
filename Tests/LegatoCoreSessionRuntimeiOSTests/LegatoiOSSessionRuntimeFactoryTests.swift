import XCTest
@testable import LegatoCore

final class LegatoiOSSessionRuntimeFactoryTests: XCTestCase {
    func testMakeDefaultReturnsNoopRuntimeOnNonIOSHosts() {
        let runtime = LegatoiOSSessionRuntimeFactory.makeDefault()

        #if os(iOS)
        XCTAssertFalse(runtime is LegatoiOSNoopSessionRuntime)
        #else
        XCTAssertTrue(runtime is LegatoiOSNoopSessionRuntime)
        #endif
    }

    func testSessionManagerDefaultUsesFactoryResolvedRuntime() {
        let manager = LegatoiOSSessionManager()
        let runtime = extractRuntime(from: manager)

        #if os(iOS)
        XCTAssertFalse(runtime is LegatoiOSNoopSessionRuntime)
        #else
        XCTAssertTrue(runtime is LegatoiOSNoopSessionRuntime)
        #endif
    }

    func testCoreDependencyDefaultsUseFactoryResolvedSessionManager() {
        let dependencies = LegatoiOSCoreDependencies()
        let runtime = extractRuntime(from: dependencies.sessionManager)

        #if os(iOS)
        XCTAssertFalse(runtime is LegatoiOSNoopSessionRuntime)
        #else
        XCTAssertTrue(runtime is LegatoiOSNoopSessionRuntime)
        #endif
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
