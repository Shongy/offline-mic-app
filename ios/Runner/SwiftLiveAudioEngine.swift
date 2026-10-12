import Foundation
import AVFoundation

protocol SwiftLiveAudioEngineDelegate: AnyObject {
    func onStateChanged(state: String)
    func onLevelChanged(level: Double)
    func onDiagnosticChanged(diagnostic: [String: Any])
    func onRouteChanged(route: [String: Any])
    func onError(message: String)
}

/**
 * Native iOS Live Audio Engine using AVAudioEngine and AVAudioSession.
 * Routes live microphone input directly to the connected Bluetooth (A2DP) speaker
 * or built-in speaker while continuing in background and coexisting with YouTube.
 */
class SwiftLiveAudioEngine: NSObject {

    static let shared = SwiftLiveAudioEngine()

    weak var delegate: SwiftLiveAudioEngineDelegate?

    private var audioEngine: AVAudioEngine?
    private var isRunning = false
    private var isInterrupted = false
    private var currentGain: Float = 1.0

    private var meterThrottleCounter = 0
    private let meterInterval = 3

    override init() {
        super.init()
        setupNotificationObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }

    private func setupNotificationObservers() {
        let center = NotificationCenter.default

        // Handle audio interruptions (phone calls, alarms, Siri)
        center.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Handle route changes (JBL speaker connected/disconnected, headphones plugged/unplugged)
        center.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Handle media services reset (rare system audio daemon restart)
        center.addObserver(
            self,
            selector: #selector(handleMediaServicesReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    // MARK: - Public Controls

    func start(gain: Float = 1.0) -> Bool {
        if isRunning {
            setGain(gain: gain)
            return true
        }

        self.currentGain = min(max(gain, 0.0), 3.0)
        delegate?.onStateChanged(state: "starting")

        do {
            let session = AVAudioSession.sharedInstance()

            // Configure audio session for simultaneous live mic and media playback
            // .mixWithOthers allows YouTube to continue playing audio through the same speaker
            // .allowBluetoothA2DP ensures high-quality A2DP output to JBL speakers without SCO degradation
            // .defaultToSpeaker routes to loudspeaker instead of receiver when no external speaker is attached
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
            )

            // Request low buffer duration for minimal latency (~5ms)
            try session.setPreferredIOBufferDuration(0.005)

            // Prefer phone's built-in microphone for voice capture
            // This prevents the system from downgrading Bluetooth to a mono 8kHz/16kHz headset microphone
            if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try session.setPreferredInput(builtInMic)
            }

            try session.setActive(true, options: [])

            // Build AVAudioEngine graph
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let mainMixer = engine.mainMixerNode

            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Direct hardware wire from input to main mixer
            engine.connect(inputNode, to: mainMixer, format: inputFormat)
            mainMixer.outputVolume = self.currentGain

            // Install tap on input node to compute live VU meter and soft limit
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 512, format: inputFormat) { [weak self] (buffer, time) in
                self?.processAudioBuffer(buffer: buffer)
            }

            try engine.start()

            self.audioEngine = engine
            self.isRunning = true
            self.isInterrupted = false

            delegate?.onStateChanged(state: "live")
            delegate?.onRouteChanged(route: getCurrentRouteInfo())

            let sampleRate = Int(inputFormat.sampleRate)
            delegate?.onDiagnosticChanged(diagnostic: [
                "sampleRate": sampleRate,
                "bufferSize": 512,
                "estimatedLatencyMs": (512.0 / Double(sampleRate)) * 1000.0,
                "isClipping": false
            ])

            return true

        } catch {
            delegate?.onError(message: "Failed to start iOS audio engine: \(error.localizedDescription)")
            delegate?.onStateChanged(state: "error")
            stop()
            return false
        }
    }

    func stop() -> Bool {
        guard isRunning || audioEngine != nil else { return true }

        isRunning = false
        isInterrupted = false

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioEngine = nil
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Ignore deactivation errors during teardown
        }

        delegate?.onLevelChanged(level: 0.0)
        delegate?.onStateChanged(state: "off")
        return true
    }

    func setGain(gain: Float) {
        self.currentGain = min(max(gain, 0.0), 3.0)
        audioEngine?.mainMixerNode.outputVolume = self.currentGain
    }

    func isEngineActive() -> Bool {
        return isRunning
    }

    // MARK: - Audio Processing & VU Meter

    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelSamples = channelData[0]
        let frameCount = Int(buffer.frameLength)
        if frameCount == 0 { return }

        meterThrottleCounter += 1
        if meterThrottleCounter < meterInterval { return }
        meterThrottleCounter = 0

        var sumSquare: Float = 0.0
        var isClipping = false

        for i in 0..<frameCount {
            let sample = channelSamples[i] * self.currentGain
            if abs(sample) >= 0.99 {
                isClipping = true
            }
            sumSquare += sample * sample
        }

        let rms = sqrt(sumSquare / Float(frameCount))
        let clampedRms = Double(min(max(rms, 0.0), 1.0))

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.delegate?.onLevelChanged(level: clampedRms)
            if isClipping {
                self.delegate?.onDiagnosticChanged(diagnostic: ["isClipping": true])
            }
        }
    }

    // MARK: - Route & Interruption Handlers

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch type {
            case .began:
                self.isInterrupted = true
                self.audioEngine?.pause()
                self.delegate?.onStateChanged(state: "interrupted")
            case .ended:
                self.isInterrupted = false
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) && self.isRunning {
                        do {
                            try self.audioEngine?.start()
                            self.delegate?.onStateChanged(state: "live")
                        } catch {
                            self.delegate?.onStateChanged(state: "error")
                        }
                    }
                }
            @unknown default:
                break
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let routeInfo = self.getCurrentRouteInfo()
            self.delegate?.onRouteChanged(route: routeInfo)
        }
    }

    @objc private func handleMediaServicesReset(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isRunning {
                self.stop()
                _ = self.start(gain: self.currentGain)
            }
        }
    }

    func getCurrentRouteInfo() -> [String: Any] {
        let route = AVAudioSession.sharedInstance().currentRoute
        var deviceName = "Phone Speaker"
        var routeType = "speaker"
        var isBluetooth = false
        var isSimultaneousMixSupported = true
        var mixExplanation = "iOS AVAudioSession with .mixWithOthers configured."

        for output in route.outputs {
            switch output.portType {
            case .bluetoothA2DP:
                deviceName = output.portName.isEmpty ? "JBL Bluetooth Speaker (A2DP)" : "\(output.portName) (Bluetooth A2DP)"
                routeType = "bluetooth_a2dp"
                isBluetooth = true
                mixExplanation = "High-fidelity A2DP output active. Coexists with YouTube media via .mixWithOthers session."
            case .bluetoothHFP:
                deviceName = "\(output.portName) (Bluetooth HFP/Handsfree)"
                routeType = "bluetooth_sco"
                isBluetooth = true
                isSimultaneousMixSupported = false
                mixExplanation = "Bluetooth Handsfree profile active. Apple may restrict simultaneous media playback in HFP mode."
            case .headphones:
                deviceName = "Wired Headphones"
                routeType = "wired"
                mixExplanation = "Wired audio connected with simultaneous playback enabled."
            case .builtInSpeaker:
                deviceName = "iPhone Loudspeaker"
                routeType = "speaker"
            default:
                deviceName = output.portName
            }
        }

        return [
            "deviceName": deviceName,
            "routeType": routeType,
            "isBluetooth": isBluetooth,
            "isSimultaneousMixSupported": isSimultaneousMixSupported,
            "mixExplanation": mixExplanation
        ]
    }
}
