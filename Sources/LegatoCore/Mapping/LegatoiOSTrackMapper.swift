import Foundation

public final class LegatoiOSTrackMapper {
    public init() {}

    public func mapContractTrack(_ track: LegatoiOSTrack) throws -> LegatoiOSTrack {
        guard !track.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LegatoiOSError(code: .loadFailed, message: "track.id must be a non-empty string")
        }

        guard !track.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LegatoiOSError(code: .invalidURL, message: "track.url must be a non-empty string")
        }

        return track
    }

    public func mapContractTracks(_ tracks: [LegatoiOSTrack]) throws -> [LegatoiOSTrack] {
        try tracks.map(mapContractTrack)
    }
}
