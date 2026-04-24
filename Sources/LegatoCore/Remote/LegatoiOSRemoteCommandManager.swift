import Foundation

public final class LegatoiOSRemoteCommandManager {
    private let runtime: LegatoiOSRemoteCommandRuntime
    private var commandHandler: ((LegatoiOSRemoteCommand) -> Void)?

    public init(runtime: LegatoiOSRemoteCommandRuntime = LegatoiOSMediaPlayerRemoteCommandRuntime()) {
        self.runtime = runtime
    }

    public func bind(handler: @escaping (LegatoiOSRemoteCommand) -> Void) {
        commandHandler = handler
        runtime.bind(dispatch: dispatch)
    }

    public func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        runtime.updatePlaybackState(state)
    }

    public func updateTransportCapabilities(_ capabilities: LegatoiOSTransportCapabilities) {
        runtime.updateTransportCapabilities(capabilities)
    }

    public func unbind() {
        runtime.unbind()
        commandHandler = nil
    }

    internal func dispatch(_ command: LegatoiOSRemoteCommand) {
        commandHandler?(command)
    }
}
