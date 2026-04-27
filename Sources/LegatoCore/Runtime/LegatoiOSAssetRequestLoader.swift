import AVFoundation
import Foundation

public struct LegatoiOSRequestEvidenceRecord: Sendable {
    public let runtime: String
    public let trackId: String
    public let requestURL: String
    public let requestHeaders: [String: String]

    public init(runtime: String, trackId: String, requestURL: String, requestHeaders: [String: String]) {
        self.runtime = runtime
        self.trackId = trackId
        self.requestURL = requestURL
        self.requestHeaders = requestHeaders
    }
}

public protocol LegatoiOSRequestEvidenceSink {
    func record(_ record: LegatoiOSRequestEvidenceRecord)
}

public final class LegatoiOSNoOpRequestEvidenceSink: LegatoiOSRequestEvidenceSink {
    public init() {}
    public func record(_ record: LegatoiOSRequestEvidenceRecord) {}
}

public final class LegatoiOSRecordingRequestEvidenceSink: LegatoiOSRequestEvidenceSink {
    private let lock = NSLock()
    private var mutableRecords: [LegatoiOSRequestEvidenceRecord] = []

    public init() {}

    public var records: [LegatoiOSRequestEvidenceRecord] {
        lock.lock()
        defer { lock.unlock() }
        return mutableRecords
    }

    public func record(_ record: LegatoiOSRequestEvidenceRecord) {
        lock.lock()
        mutableRecords.append(record)
        lock.unlock()
    }
}

public protocol LegatoiOSAssetRequestLoaderFactory {
    func make(
        trackId: String,
        headers: [String: String],
        evidenceSink: LegatoiOSRequestEvidenceSink
    ) -> LegatoiOSAssetRequestLoaderContext
}

public protocol LegatoiOSAssetRequestLoaderContext: AnyObject {
    var trackId: String { get }
    func makePlayerItem(url: URL) throws -> AVPlayerItem
    func dispose()
}

public final class LegatoiOSDefaultAssetRequestLoaderFactory: LegatoiOSAssetRequestLoaderFactory {
    public init() {}

    public func make(
        trackId: String,
        headers: [String: String],
        evidenceSink: LegatoiOSRequestEvidenceSink
    ) -> LegatoiOSAssetRequestLoaderContext {
        LegatoiOSAssetRequestLoaderContextImpl(trackId: trackId, headers: headers, evidenceSink: evidenceSink)
    }
}

private final class LegatoiOSAssetRequestLoaderContextImpl: NSObject, LegatoiOSAssetRequestLoaderContext, AVAssetResourceLoaderDelegate {
    let trackId: String
    private let headers: [String: String]
    private let evidenceSink: LegatoiOSRequestEvidenceSink

    init(trackId: String, headers: [String: String], evidenceSink: LegatoiOSRequestEvidenceSink) {
        self.trackId = trackId
        self.headers = headers
        self.evidenceSink = evidenceSink
        super.init()
    }

    func makePlayerItem(url: URL) throws -> AVPlayerItem {
        let proxiedURL = LegatoiOSAssetRequestProxyURL.wrap(url)
        let asset = AVURLAsset(url: proxiedURL)
        asset.resourceLoader.setDelegate(self, queue: .main)
        return AVPlayerItem(asset: asset)
    }

    func dispose() {}

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let incomingURL = loadingRequest.request.url,
              let targetURL = LegatoiOSAssetRequestProxyURL.unwrap(incomingURL)
        else {
            loadingRequest.finishLoading(with: LegatoiOSError(code: .playbackFailed, message: "Invalid proxied URL"))
            return true
        }

        evidenceSink.record(
            LegatoiOSRequestEvidenceRecord(
                runtime: "ios",
                trackId: trackId,
                requestURL: targetURL.absoluteString,
                requestHeaders: headers
            )
        )

        var request = URLRequest(url: targetURL)
        headers.forEach { key, value in request.setValue(value, forHTTPHeaderField: key) }

        URLSession.shared.dataTask(with: request) { [weak loadingRequest] data, response, error in
            guard let loadingRequest else {
                return
            }

            if let error {
                loadingRequest.finishLoading(with: error)
                return
            }

            if let response {
                loadingRequest.response = response
            }

            if let data {
                loadingRequest.dataRequest?.respond(with: data)
            }
            loadingRequest.finishLoading()
        }.resume()

        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        loadingRequest.finishLoading(with: LegatoiOSError(code: .playbackFailed, message: "Resource loading cancelled"))
    }
}

private enum LegatoiOSAssetRequestProxyURL {
    private static let scheme = "legato-proxy"
    private static let targetQueryKey = "target"

    static func wrap(_ url: URL) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "request"
        components.path = "/asset"
        components.queryItems = [
            URLQueryItem(name: targetQueryKey, value: url.absoluteString),
        ]

        return components.url ?? url
    }

    static func unwrap(_ url: URL) -> URL? {
        guard url.scheme == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encodedTarget = components.queryItems?.first(where: { $0.name == targetQueryKey })?.value,
              let target = URL(string: encodedTarget)
        else {
            return nil
        }

        return target
    }
}
