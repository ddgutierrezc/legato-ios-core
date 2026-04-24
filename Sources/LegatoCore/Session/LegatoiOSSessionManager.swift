import Foundation

public final class LegatoiOSSessionManager {
    public typealias SignalListener = (LegatoiOSSessionSignal) -> Void

    private let lock = NSLock()
    private let runtime: LegatoiOSSessionRuntime
    private var listeners: [UUID: SignalListener] = [:]

    public init(runtime: LegatoiOSSessionRuntime? = nil) {
        let resolvedRuntime = runtime ?? LegatoiOSSessionRuntimeFactory.makeDefault()
        self.runtime = resolvedRuntime
        self.runtime.onSignal = { [weak self] signal in
            self?.publish(signal)
        }
    }

    public func configureSession() {
        runtime.configureSession()
    }

    public func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        runtime.updatePlaybackState(state)
    }

    public func releaseSession() {
        runtime.releaseSession()
    }

    @discardableResult
    public func addSignalListener(_ listener: @escaping SignalListener) -> UUID {
        lock.lock()
        defer { lock.unlock() }

        let id = UUID()
        listeners[id] = listener
        return id
    }

    public func removeSignalListener(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        listeners[id] = nil
    }

    private func publish(_ signal: LegatoiOSSessionSignal) {
        lock.lock()
        let snapshot = listeners.values
        lock.unlock()

        for listener in snapshot {
            listener(signal)
        }
    }
}
