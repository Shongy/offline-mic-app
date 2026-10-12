# Live Mic Pro — Native Live Microphone to Bluetooth Speaker

A high-performance, low-latency live microphone streaming application built with Flutter and native platform audio engines (**Swift / AVAudioEngine** on iOS and **Kotlin / AudioRecord & AudioTrack** on Android).

Designed specifically for streaming live voice to external Bluetooth speakers (such as JBL Flip, Charge, Xtreme) while maintaining background execution and coexisting with media apps like YouTube.

---

## 1. System Architecture

```
┌────────────────────────────────────────────────────────┐
│                   Flutter UI (Dart)                    │
│   • Big MIC ON / OFF Button    • Real-time VU Meter    │
│   • Audio Route Detection Card • Gain Slider (Safe dB) │
│   • Diagnostics Modal          • Feedback Safety Notice│
└───────────────────────────┬────────────────────────────┘
                            │ MethodChannel & EventChannels
         ┌──────────────────┴──────────────────┐
         ▼                                     ▼
┌──────────────────────────────┐     ┌──────────────────────────────┐
│       Android Native         │     │          iOS Native          │
│   • Foreground Service       │     │   • AVAudioSession           │
│     (type: microphone)       │     │     (.playAndRecord)         │
│   • AudioRecord (Built-in)   │     │     (.mixWithOthers)         │
│   • AudioTrack (Media/A2DP)  │     │     (.allowBluetoothA2DP)    │
│   • AudioFocus (May Duck)    │     │   • AVAudioEngine Node Graph │
│   • Soft-Limiting Saturation │     │   • Built-in Mic Input Lock  │
│   • Device Route Observers   │     │   • Route Change Observers   │
└──────────────────────────────┘     └──────────────────────────────┘
```

---

## 2. Core Audio Engineering Details

### 2.1 Bluetooth A2DP vs SCO (The JBL Speaker Dilemma)
When mobile devices connect to Bluetooth audio accessories, standard operating systems typically offer two Bluetooth profiles:
1. **A2DP (Advanced Audio Distribution Profile)**: High fidelity (44.1 kHz / 48 kHz, 16-bit stereo/mono), designed for music and high quality speakers like JBL. It is output-only.
2. **HFP / SCO (Hands-Free Profile / Synchronous Connection-Oriented)**: Bi-directional, designed for phone calls, but restricted to telephone-grade **8 kHz or 16 kHz narrowband audio**.

**The Senior Engineering Solution Implemented in this App:**
- If an app requests a generic Bluetooth microphone input, the OS will automatically downgrade the entire audio session to 8 kHz HFP/SCO, causing the JBL speaker to sound muffled and terrible.
- **On iOS**: We configure `AVAudioSession.CategoryOptions.allowBluetoothA2DP` and explicitly set `setPreferredInput` to the phone's built-in microphone (`AVAudioSessionPortBuiltInMic`). This routes high-definition 48 kHz audio directly to the JBL speaker via A2DP while capturing crystal-clear voice through the iPhone's bottom microphone.
- **On Android**: We bind `AudioRecord` explicitly to `MediaRecorder.AudioSource.MIC` (built-in microphone) and `AudioTrack` with `AudioAttributes.USAGE_MEDIA` directed to the standard Bluetooth A2DP output stream.

### 2.2 Simultaneous YouTube Playback & Audio Mixing
- **Android**:
  - The engine requests audio focus with `AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`.
  - In Android's AudioFlinger / Audio HAL, streams flagged with `USAGE_MEDIA` are mixed in software/hardware before being transmitted to the Bluetooth stack.
  - When YouTube starts, YouTube takes playback focus; our engine accommodates the focus event without terminating the capture/playback loop, allowing simultaneous playback.
- **iOS**:
  - Configures `AVAudioSession.CategoryOptions.mixWithOthers`.
  - This informs the CoreAudio server that our audio session explicitly permits concurrent audio from other apps (like YouTube).

### 2.3 Acoustic Feedback (The Larsen Effect) Prevention
Acoustic feedback happens when amplified sound from the speaker re-enters the microphone at a gain greater than unity ($G \ge 1$), creating an escalating high-pitched screech.
- **Software Protections**:
  - Digital soft-knee saturation limiter: prevents harsh integer overflow wrap-around clicks when sound exceeds 0 dBFS.
  - Default gain calibrated to `1.0x (0 dB)` safe headroom.
  - Real-time VU meter with visual warning bands (-48 dB to 0 dB).
  - Internal speaker detection warning: reminds users to keep volume low if an external speaker is disconnected.
- **Physical Guidelines**:
  - Maintain at least **2 meters (6–7 feet)** between phone mic and the JBL speaker.
  - Point the bottom of the phone away from the speaker drivers.

### 2.4 Privacy & Local Offline Guarantee
- **100% Offline**: No network permissions or cloud APIs are included or used.
- **Zero Audio Storage**: Microphones samples are processed directly in volatile RAM circular buffers (`ShortArray` / `AVAudioPCMBuffer`) and handed immediately to the audio output queue. No audio files are ever written to disk or logged.
- **Safe Diagnostics**: Diagnostic logs output only numeric sample rates, buffer sizes, and RMS volume levels.

---

## 3. Platform Configuration

### Android Configuration
- **Permissions** in `android/app/src/main/AndroidManifest.xml`:
  - `android.permission.RECORD_AUDIO`: Voice capture.
  - `android.permission.FOREGROUND_SERVICE` & `android.permission.FOREGROUND_SERVICE_MICROPHONE`: Required on Android 14+ (API 34) to run continuous microphone capture in the background.
  - `android.permission.BLUETOOTH_CONNECT`: Bluetooth device routing (Android 12+).
  - `android.permission.WAKE_LOCK`: Keeps CPU active during screen lock.
  - `android.permission.POST_NOTIFICATIONS`: Foreground service notification (Android 13+).
- **Service Type**:
  - `MicForegroundService` declared with `android:foregroundServiceType="microphone"`.
  - Notification bar displays persistent indicator with a "Stop Mic" action.

### iOS Configuration
- **Permissions & Capabilities** in `ios/Runner/Info.plist`:
  - `NSMicrophoneUsageDescription`: Clear rationale provided for App Store compliance.
  - `UIBackgroundModes`: Includes `<string>audio</string>` for persistent background execution.
  - `NSBluetoothAlwaysUsageDescription`: Required for Bluetooth peripheral audio routing.

---

## 4. Setup and Build Instructions

### Prerequisites
1. **Flutter SDK**: Version 3.10.0 or higher.
2. **For Android**:
   - Android Studio / Android SDK Platform 34.
   - Java 17 / JDK 17 (recommended for Gradle 8+).
3. **For iOS**:
   - macOS computer with Xcode 15+.
   - Apple Developer account for physical device signing (required for microphone and background audio capabilities).

### Building and Running on Android
1. Connect your Android device via USB and enable USB Debugging:
   ```bash
   adb devices
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run directly on your connected device:
   ```bash
   flutter run -d <device-id>
   ```
4. Or build release APK:
   ```bash
   flutter build apk --release
   ```

### Building and Running on iOS
*(Requires macOS and Xcode)*
1. Navigate to the iOS folder and install CocoaPods dependencies:
   ```bash
   cd ios
   pod install
   cd ..
   ```
2. Open `ios/Runner.xcworkspace` in Xcode.
3. In **Runner > Signing & Capabilities**:
   - Select your Development Team.
   - Verify that **Background Modes** has **Audio, AirPlay, and Picture in Picture** checked.
4. Run on a physical iPhone (Microphone background execution requires a real hardware device; the iOS Simulator does not emulate Bluetooth A2DP routing accurately):
   ```bash
   flutter run -d <iphone-device-id>
   ```

---

## 5. Troubleshooting & Known OS Quirks

| Symptom | Cause | Solution |
| :--- | :--- | :--- |
| Audio sounds muffled like a phone call | System switched to Bluetooth SCO headset profile. | Ensure phone built-in microphone is selected as input; our app automatically locks to built-in mic to keep A2DP active. |
| High pitched screech when turning mic on | Phone is too close to speaker (Acoustic feedback). | Move phone at least 2 meters away from speaker, or lower gain slider to 0.8x. |
| Microphone stops when screen locks on Android | OS aggressive battery optimization killed service. | Check system settings > Battery > Live Mic Pro > Set to "Unrestricted". The foreground service and wake lock prevent this on standard ROMs. |
| YouTube pauses when Live Mic starts on iOS | Another app holds exclusive audio session without `mixWithOthers`. | Re-start YouTube playback; iOS will mix streams once user taps play in YouTube. |
| Audio drops out during incoming phone call | OS gives absolute priority to cellular calls. | This is intended operating system behavior. When call ends, tap MIC ON to resume. |
