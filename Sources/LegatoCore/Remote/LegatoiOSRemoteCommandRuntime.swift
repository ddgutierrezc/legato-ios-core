import Foundation

/// Seam for MPRemoteCommandCenter integration.
public protocol LegatoiOSRemoteCommandRuntime {
    func bind(dispatch: @escaping (LegatoiOSRemoteCommand) -> Void)
    func updatePlaybackState(_ state: LegatoiOSPlaybackState)
    func updateTransportCapabilities(_ capabilities: LegatoiOSTransportCapabilities)
    func unbind()
}

public protocol LegatoiOSRemoteCommandCenter {
    var playCommand: LegatoiOSRemoteCommandHandler { get }
    var pauseCommand: LegatoiOSRemoteCommandHandler { get }
    var nextTrackCommand: LegatoiOSRemoteCommandHandler { get }
    var previousTrackCommand: LegatoiOSRemoteCommandHandler { get }
    var changePlaybackPositionCommand: LegatoiOSChangePlaybackPositionCommandHandler { get }
}

public protocol LegatoiOSRemoteCommandHandler: AnyObject {
    var isEnabled: Bool { get set }

    @discardableResult
    func addTarget(_ handler: @escaping () -> Void) -> AnyObject

    func removeTarget(_ token: AnyObject)
}

public protocol LegatoiOSChangePlaybackPositionCommandHandler: AnyObject {
    var isEnabled: Bool { get set }

    @discardableResult
    func addTarget(_ handler: @escaping (_ positionTimeSeconds: Double) -> Void) -> AnyObject

    func removeTarget(_ token: AnyObject)
}

public final class LegatoiOSMediaPlayerRemoteCommandRuntime: LegatoiOSRemoteCommandRuntime {
    private let commandCenter: LegatoiOSRemoteCommandCenter
    private var bindings: [Binding] = []

    private struct Binding {
        let command: LegatoiOSRemoteCommandHandler
        let token: AnyObject
    }

    private struct PositionBinding {
        let command: LegatoiOSChangePlaybackPositionCommandHandler
        let token: AnyObject
    }

    private var positionBinding: PositionBinding?

    public init(commandCenter: LegatoiOSRemoteCommandCenter = LegatoiOSLiveRemoteCommandCenter()) {
        self.commandCenter = commandCenter
    }

    public func bind(dispatch: @escaping (LegatoiOSRemoteCommand) -> Void) {
        unbind()

        bindings = [
            bind(commandCenter.playCommand) { dispatch(.play) },
            bind(commandCenter.pauseCommand) { dispatch(.pause) },
            bind(commandCenter.nextTrackCommand) { dispatch(.next) },
            bind(commandCenter.previousTrackCommand) { dispatch(.previous) }
        ]

        let token = commandCenter.changePlaybackPositionCommand.addTarget { positionTimeSeconds in
            let ms = max(0, Int64((positionTimeSeconds * 1_000.0).rounded()))
            dispatch(.seek(positionMs: ms))
        }
        positionBinding = PositionBinding(command: commandCenter.changePlaybackPositionCommand, token: token)
    }

    public func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        commandCenter.playCommand.isEnabled = state != .playing && state != .buffering
        commandCenter.pauseCommand.isEnabled = state == .playing || state == .buffering
    }

    public func updateTransportCapabilities(_ capabilities: LegatoiOSTransportCapabilities) {
        commandCenter.nextTrackCommand.isEnabled = capabilities.canSkipNext
        commandCenter.previousTrackCommand.isEnabled = capabilities.canSkipPrevious
        commandCenter.changePlaybackPositionCommand.isEnabled = capabilities.canSeek
    }

    public func unbind() {
        bindings.forEach { $0.command.removeTarget($0.token) }
        bindings.removeAll()

        if let positionBinding {
            positionBinding.command.removeTarget(positionBinding.token)
            self.positionBinding = nil
        }
    }

    private func bind(_ command: LegatoiOSRemoteCommandHandler, handler: @escaping () -> Void) -> Binding {
        let token = command.addTarget(handler)
        return Binding(command: command, token: token)
    }
}

public final class LegatoiOSNoopRemoteCommandRuntime: LegatoiOSRemoteCommandRuntime {
    public init() {}

    public func bind(dispatch: @escaping (LegatoiOSRemoteCommand) -> Void) {
        // Intentionally no-op. Real runtime should register command targets and forward with dispatch(...).
    }

    public func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        // Intentionally no-op.
    }

    public func updateTransportCapabilities(_ capabilities: LegatoiOSTransportCapabilities) {
        // Intentionally no-op.
    }

    public func unbind() {
        // Intentionally no-op.
    }
}

#if canImport(MediaPlayer) && os(iOS)
import MediaPlayer

public final class LegatoiOSLiveRemoteCommandCenter: LegatoiOSRemoteCommandCenter {
    private let commandCenter: MPRemoteCommandCenter

    public init(commandCenter: MPRemoteCommandCenter = .shared()) {
        self.commandCenter = commandCenter
    }

    public var playCommand: LegatoiOSRemoteCommandHandler {
        LegatoiOSLiveRemoteCommand(command: commandCenter.playCommand)
    }

    public var pauseCommand: LegatoiOSRemoteCommandHandler {
        LegatoiOSLiveRemoteCommand(command: commandCenter.pauseCommand)
    }

    public var nextTrackCommand: LegatoiOSRemoteCommandHandler {
        LegatoiOSLiveRemoteCommand(command: commandCenter.nextTrackCommand)
    }

    public var previousTrackCommand: LegatoiOSRemoteCommandHandler {
        LegatoiOSLiveRemoteCommand(command: commandCenter.previousTrackCommand)
    }

    public var changePlaybackPositionCommand: LegatoiOSChangePlaybackPositionCommandHandler {
        LegatoiOSLiveChangePlaybackPositionCommand(command: commandCenter.changePlaybackPositionCommand)
    }
}

private final class LegatoiOSLiveRemoteCommand: LegatoiOSRemoteCommandHandler {
    private let command: MPRemoteCommand

    init(command: MPRemoteCommand) {
        self.command = command
    }

    var isEnabled: Bool {
        get { command.isEnabled }
        set { command.isEnabled = newValue }
    }

    @discardableResult
    func addTarget(_ handler: @escaping () -> Void) -> AnyObject {
        command.addTarget { _ in
            handler()
            return .success
        } as AnyObject
    }

    func removeTarget(_ token: AnyObject) {
        command.removeTarget(token)
    }
}

private final class LegatoiOSLiveChangePlaybackPositionCommand: LegatoiOSChangePlaybackPositionCommandHandler {
    private let command: MPChangePlaybackPositionCommand

    init(command: MPChangePlaybackPositionCommand) {
        self.command = command
    }

    var isEnabled: Bool {
        get { command.isEnabled }
        set { command.isEnabled = newValue }
    }

    @discardableResult
    func addTarget(_ handler: @escaping (Double) -> Void) -> AnyObject {
        command.addTarget { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            handler(positionEvent.positionTime)
            return .success
        } as AnyObject
    }

    func removeTarget(_ token: AnyObject) {
        command.removeTarget(token)
    }
}
#else
public final class LegatoiOSLiveRemoteCommandCenter: LegatoiOSRemoteCommandCenter {
    public init() {}

    public var playCommand: LegatoiOSRemoteCommandHandler { NoopRemoteCommand() }
    public var pauseCommand: LegatoiOSRemoteCommandHandler { NoopRemoteCommand() }
    public var nextTrackCommand: LegatoiOSRemoteCommandHandler { NoopRemoteCommand() }
    public var previousTrackCommand: LegatoiOSRemoteCommandHandler { NoopRemoteCommand() }
    public var changePlaybackPositionCommand: LegatoiOSChangePlaybackPositionCommandHandler {
        NoopChangePlaybackPositionCommand()
    }
}

private final class NoopRemoteCommand: LegatoiOSRemoteCommandHandler {
    var isEnabled: Bool = false

    @discardableResult
    func addTarget(_ handler: @escaping () -> Void) -> AnyObject { NSObject() }

    func removeTarget(_ token: AnyObject) {}
}

private final class NoopChangePlaybackPositionCommand: LegatoiOSChangePlaybackPositionCommandHandler {
    var isEnabled: Bool = false

    @discardableResult
    func addTarget(_ handler: @escaping (Double) -> Void) -> AnyObject { NSObject() }

    func removeTarget(_ token: AnyObject) {}
}
#endif
