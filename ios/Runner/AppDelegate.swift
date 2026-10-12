import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate, SwiftLiveAudioEngineDelegate {

    private static let METHOD_CHANNEL = "com.livemic.app/audio_control"
    private static let EVENT_CHANNEL = "com.livemic.app/audio_events"
    private static let METER_CHANNEL = "com.livemic.app/audio_level"

    private var eventSink: FlutterEventSink?
    private var meterSink: FlutterEventSink?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        let audioEngine = SwiftLiveAudioEngine.shared
        audioEngine.delegate = self

        // MethodChannel setup
        let methodChannel = FlutterMethodChannel(
            name: AppDelegate.METHOD_CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )

        methodChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "startLiveMic":
                let args = call.arguments as? [String: Any]
                let gain = Float((args?["gain"] as? Double) ?? 1.0)
                audioEngine.ensurePermissionAndStart(gain: gain) { success, errorMsg in
                    result(success)
                }

            case "stopLiveMic":
                let success = audioEngine.stop()
                result(success)

            case "setGain":
                let args = call.arguments as? [String: Any]
                let gain = Float((args?["gain"] as? Double) ?? 1.0)
                audioEngine.setGain(gain: gain)
                result(nil)

            case "getAudioRoute":
                result(audioEngine.getCurrentRouteInfo())

            case "getAvailableInputs":
                result(audioEngine.getAvailableInputs())

            case "setPreferredInput":
                let args = call.arguments as? [String: Any]
                let uid = (args?["uid"] as? String) ?? (args?["id"] as? String) ?? ""
                let success = audioEngine.setPreferredInput(uid: uid)
                result(success)

            case "requestMicrophonePermission":
                if #available(iOS 17.0, *) {
                    AVAudioApplication.requestRecordPermission { granted in
                        DispatchQueue.main.async { result(granted) }
                    }
                } else {
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        DispatchQueue.main.async { result(granted) }
                    }
                }

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // EventChannel for lifecycle and route events
        let eventChannel = FlutterEventChannel(
            name: AppDelegate.EVENT_CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )
        eventChannel.setStreamHandler(AudioEventStreamHandler(owner: self))

        // EventChannel for real-time VU meter
        let meterChannel = FlutterEventChannel(
            name: AppDelegate.METER_CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )
        meterChannel.setStreamHandler(AudioMeterStreamHandler(owner: self))

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - SwiftLiveAudioEngineDelegate

    func onStateChanged(state: String) {
        eventSink?([
            "type": "stateChange",
            "state": state
        ])
    }

    func onLevelChanged(level: Double) {
        meterSink?(level)
    }

    func onDiagnosticChanged(diagnostic: [String: Any]) {
        eventSink?([
            "type": "diagnostic",
            "diagnostic": diagnostic
        ])
    }

    func onRouteChanged(route: [String: Any]) {
        eventSink?([
            "type": "routeChange",
            "route": route
        ])
    }

    func onError(message: String) {
        eventSink?([
            "type": "stateChange",
            "state": "error"
        ])
        eventSink?([
            "type": "diagnostic",
            "diagnostic": ["lastError": message]
        ])
    }

    fileprivate func setEventSink(_ sink: FlutterEventSink?) {
        self.eventSink = sink
        if let sink = sink {
            sink([
                "type": "routeChange",
                "route": SwiftLiveAudioEngine.shared.getCurrentRouteInfo()
            ])
        }
    }

    fileprivate func setMeterSink(_ sink: FlutterEventSink?) {
        self.meterSink = sink
    }
}

private class AudioEventStreamHandler: NSObject, FlutterStreamHandler {
    weak var owner: AppDelegate?

    init(owner: AppDelegate) {
        self.owner = owner
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        owner?.setEventSink(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        owner?.setEventSink(nil)
        return nil
    }
}

private class AudioMeterStreamHandler: NSObject, FlutterStreamHandler {
    weak var owner: AppDelegate?

    init(owner: AppDelegate) {
        self.owner = owner
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        owner?.setMeterSink(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        owner?.setMeterSink(nil)
        return nil
    }
}
