import Foundation

internal enum LegatoiOSSessionRuntimeFactory {
    static func makeDefault() -> any LegatoiOSSessionRuntime {
        #if os(iOS)
        let className = "LegatoCoreSessionRuntimeiOS.LegatoiOSAVAudioSessionRuntime"
        if
            let runtimeType = NSClassFromString(className) as? NSObject.Type,
            let runtime = runtimeType.init() as? LegatoiOSSessionRuntime
        {
            return runtime
        }
        #endif

        return LegatoiOSNoopSessionRuntime()
    }
}
