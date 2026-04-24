import Foundation

public final class LegatoiOSEventEmitter {
    private let lock = NSLock()
    private var listeners: [UUID: (LegatoiOSEvent) -> Void] = [:]

    public init() {}

    public func emit(_ event: LegatoiOSEvent) {
        lock.lock()
        let snapshot = listeners.values
        lock.unlock()

        for listener in snapshot {
            listener(event)
        }
    }

    public func emit(name: LegatoiOSEventName, payload: LegatoiOSEventPayload? = nil) {
        emit(LegatoiOSEvent(name: name, payload: payload))
    }

    @discardableResult
    public func addListener(_ listener: @escaping (LegatoiOSEvent) -> Void) -> UUID {
        lock.lock()
        defer { lock.unlock() }

        let id = UUID()
        listeners[id] = listener
        return id
    }

    public func removeListener(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        listeners[id] = nil
    }
}
