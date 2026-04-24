import Foundation

public final class LegatoiOSErrorMapper {
    public init() {}

    public func map(_ error: Error) -> LegatoiOSError {
        LegatoiOSError(code: .platformError, message: String(describing: error), details: error)
    }

    public func playerNotSetup(message: String = "Player is not setup") -> LegatoiOSError {
        LegatoiOSError(code: .playerNotSetup, message: message)
    }
}
