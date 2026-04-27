import Foundation
import LegatoCore

#if canImport(AVFAudio) && os(iOS)
import AVFAudio
#endif

internal func legatoShouldActivateSession(for state: LegatoiOSPlaybackState) -> Bool {
    switch state {
    case .loading, .ready, .playing, .paused, .buffering:
        return true
    case .idle, .ended, .error:
        return false
    }
}

internal enum LegatoiOSAVAudioSessionRawValue {
    static let interruptionTypeEnded: UInt = 0
    static let interruptionTypeBegan: UInt = 1
    static let interruptionOptionShouldResume: UInt = 1 << 0
    static let routeReasonNewDeviceAvailable: UInt = 1
    static let routeReasonOldDeviceUnavailable: UInt = 2
    static let routeReasonNoSuitableRoute: UInt = 7
}

internal func legatoExtractInterruptionSignal(typeRaw: UInt, optionsRaw: UInt?) -> LegatoiOSSessionSignal? {
    switch typeRaw {
    case LegatoiOSAVAudioSessionRawValue.interruptionTypeBegan:
        return .interruptionBegan
    case LegatoiOSAVAudioSessionRawValue.interruptionTypeEnded:
        let intent: LegatoiOSInterruptionResumeIntent
        if let optionsRaw {
            let shouldResume = (optionsRaw & LegatoiOSAVAudioSessionRawValue.interruptionOptionShouldResume) != 0
            intent = shouldResume ? .shouldResume : .shouldNotResume
        } else {
            intent = .unknown
        }
        return .interruptionEnded(intent: intent)
    default:
        return nil
    }
}

internal func legatoExtractRouteSignal(reasonRaw: UInt) -> LegatoiOSSessionSignal? {
    switch reasonRaw {
    case LegatoiOSAVAudioSessionRawValue.routeReasonOldDeviceUnavailable:
        return .outputRouteLost(reason: .oldDeviceUnavailable)
    case LegatoiOSAVAudioSessionRawValue.routeReasonNoSuitableRoute:
        return .outputRouteLost(reason: .noSuitableRoute)
    case LegatoiOSAVAudioSessionRawValue.routeReasonNewDeviceAvailable:
        return .outputRouteAvailable(reason: .newDeviceAvailable)
    default:
        return nil
    }
}

#if canImport(AVFAudio) && os(iOS)
public final class LegatoiOSAVAudioSessionRuntime: NSObject, LegatoiOSSessionRuntime {
    public var onSignal: ((LegatoiOSSessionSignal) -> Void)?

    private let audioSession: AVAudioSession
    private let notificationCenter: NotificationCenter

    private var isConfigured = false
    private var isSessionActive = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    public override init() {
        self.audioSession = .sharedInstance()
        self.notificationCenter = .default
        super.init()
    }

    public init(
        audioSession: AVAudioSession = .sharedInstance(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.audioSession = audioSession
        self.notificationCenter = notificationCenter
        super.init()
    }

    public func configureSession() {
        guard !isConfigured else {
            return
        }

        do {
            try audioSession.setCategory(.playback, mode: .default, options: [])
            registerNotificationsIfNeeded()
            isConfigured = true
        } catch {
            onSignal?(.runtimeError(message: "Failed to configure AVAudioSession: \(error.localizedDescription)"))
        }
    }

    public func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        setSessionActive(legatoShouldActivateSession(for: state))
    }

    public func releaseSession() {
        removeObservers()
        setSessionActive(false)
        isConfigured = false
    }

    private func setSessionActive(_ shouldBeActive: Bool) {
        guard shouldBeActive != isSessionActive else {
            return
        }

        do {
            if shouldBeActive {
                try audioSession.setActive(true)
            } else {
                try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            }
            isSessionActive = shouldBeActive
        } catch {
            let action = shouldBeActive ? "activate" : "deactivate"
            onSignal?(.runtimeError(message: "Failed to \(action) AVAudioSession: \(error.localizedDescription)"))
        }
    }

    private func registerNotificationsIfNeeded() {
        if interruptionObserver == nil {
            interruptionObserver = notificationCenter.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: audioSession,
                queue: nil
            ) { [weak self] notification in
                self?.handleInterruptionNotification(notification)
            }
        }

        if routeChangeObserver == nil {
            routeChangeObserver = notificationCenter.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: audioSession,
                queue: nil
            ) { [weak self] notification in
                self?.handleRouteChangeNotification(notification)
            }
        }
    }

    private func handleInterruptionNotification(_ notification: Notification) {
        guard let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else {
            return
        }

        let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
        if let signal = legatoExtractInterruptionSignal(typeRaw: typeRaw, optionsRaw: optionsRaw) {
            onSignal?(signal)
        }
    }

    private func handleRouteChangeNotification(_ notification: Notification) {
        guard let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else {
            return
        }

        if let signal = legatoExtractRouteSignal(reasonRaw: reasonRaw) {
            onSignal?(signal)
        }
    }

    private func removeObservers() {
        if let interruptionObserver {
            notificationCenter.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }

        if let routeChangeObserver {
            notificationCenter.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
    }
}
#else
public final class LegatoiOSAVAudioSessionRuntime: NSObject, LegatoiOSSessionRuntime {
    public var onSignal: ((LegatoiOSSessionSignal) -> Void)?

    public override init() {
        super.init()
    }

    public func configureSession() {
        // Host-safe no-op fallback.
    }

    public func updatePlaybackState(_ state: LegatoiOSPlaybackState) {
        _ = legatoShouldActivateSession(for: state)
    }

    public func releaseSession() {
        // Host-safe no-op fallback.
    }
}
#endif
