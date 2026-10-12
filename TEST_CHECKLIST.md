# Live Microphone App: Physical Device Test Checklist & Verification Matrix

This test checklist is specifically crafted for senior mobile audio validation using physical test devices (Android and iPhone) paired with an external Bluetooth speaker (e.g., JBL Flip 5/6, JBL Charge, or JBL Xtreme).

---

## Pre-Test Setup
1. **Device Preparation**:
   - Charge phone and JBL Bluetooth speaker.
   - Place JBL speaker at least **2 meters (6–7 feet)** away from the phone to avoid initial acoustic feedback loops.
   - Pair the phone with the JBL speaker in system Bluetooth Settings and verify connection.
2. **App Permissions**:
   - Install the app and ensure Microphone permission is granted.
   - On Android 13+, ensure Notification permission is allowed for the Foreground Service notification.

---

## Test Cases

### Test Case 1: Microphone to JBL Speaker (Solo Playback)
* **Objective**: Confirm direct low-latency audio transmission from phone mic to JBL speaker with no background apps.
* **Steps**:
  1. Open Live Mic Pro.
  2. Verify route card displays: `"JBL [Model] (Bluetooth A2DP)"`.
  3. Ensure Mic Gain is at default `1.0x (0 dB)`.
  4. Tap **MIC ON**.
  5. Speak into the bottom of the phone.
* **Expected Result**:
  - Voice is heard clearly through the JBL speaker with minimal perceptible delay (~10–25ms).
  - The VU meter responds dynamically to voice amplitude.
  - No digital distortion or clipping occurs.
* **Pass/Fail**: `[  ]`

---

### Test Case 2: Microphone Remains Active When Switching to YouTube
* **Objective**: Verify that background execution keeps live mic audio streaming when leaving the app.
* **Steps**:
  1. With **MIC ON** and audio streaming, press the Home button or swipe up to send the app to background.
  2. Open the YouTube app.
  3. Speak into the phone without playing a video yet.
* **Expected Result**:
  - **Android**: Persistent notification `"Live Microphone Active"` is visible in the status bar with Foreground Service type `microphone`. Voice continues streaming uninterrupted.
  - **iOS**: Background audio indicator appears in the Dynamic Island / status bar. Voice continues streaming without stuttering or termination.
* **Pass/Fail**: `[  ]`

---

### Test Case 3: YouTube and Live Microphone Simultaneous Playback
* **Objective**: Verify audio mixing when YouTube media plays concurrently with live voice through the JBL speaker.
* **Steps**:
  1. While in YouTube with the microphone streaming in the background, start playing any music video or talk show.
  2. Speak continuously into the phone mic while video audio plays.
* **Platform-Specific Expected Behavior**:
  - **iOS**:
    - Because the app configures `AVAudioSession.CategoryOptions.mixWithOthers` and `.allowBluetoothA2DP`, iOS will mix both audio streams into the JBL speaker output simultaneously.
    - If YouTube pauses the audio session on certain legacy iOS versions, the app detects `interruptionNotification` and reports `Interrupted` on the UI.
  - **Android**:
    - Because the app uses `AudioAttributes.USAGE_MEDIA` with `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`, Android's audio HAL mixes both streams. YouTube will either duck (lower slightly) or mix simultaneously through the JBL speaker.
* **Pass/Fail**: `[  ]`

---

### Test Case 4: Bluetooth Disconnection While Microphone is Active
* **Objective**: Verify app stability and route adaptation when the JBL speaker is powered off or goes out of range.
* **Steps**:
  1. With **MIC ON**, turn off the physical JBL speaker via its power button.
  2. Observe phone behavior.
* **Expected Result**:
  - The app receives `ACTION_AUDIO_BECOMING_NOISY` (Android) or `AVAudioSession.routeChangeNotification` with reason `oldDeviceUnavailable` (iOS).
  - The app automatically transitions the output route back to the Phone Speaker.
  - The UI updates route card to `"Phone Speaker"` with an orange acoustic feedback warning.
  - Audio capture does not crash.
* **Pass/Fail**: `[  ]`

---

### Test Case 5: Speaker Reconnection and Return to Mic App
* **Objective**: Verify recovery when reconnecting to the Bluetooth speaker.
* **Steps**:
  1. Turn the JBL speaker back on and wait for Bluetooth to auto-connect.
  2. Open / bring Live Mic Pro back to foreground.
* **Expected Result**:
  - Route monitor detects `TYPE_BLUETOOTH_A2DP` / `AVAudioSession.Port.bluetoothA2DP`.
  - Route card automatically updates back to `"JBL ... (Bluetooth A2DP)"`.
  - Sound output immediately resumes routing through the JBL speaker.
* **Pass/Fail**: `[  ]`

---

### Test Case 6: Screen Lock / Device Sleep
* **Objective**: Verify that locking the phone does not suspend the audio streaming thread.
* **Steps**:
  1. With **MIC ON** and audio streaming to the JBL speaker, press the power button to lock the screen.
  2. Keep speaking into the phone for 60 seconds while the phone screen is completely black.
* **Expected Result**:
  - **Android**: The `PARTIAL_WAKE_LOCK` and Foreground Service prevent CPU sleep. Voice continues streaming without stuttering or dropouts.
  - **iOS**: The `audio` UIBackgroundModes keeps `AVAudioEngine` running in the audio render thread. Audio continues smoothly.
* **Pass/Fail**: `[  ]`

---

### Test Case 7: Phone Call Interruption and Recovery
* **Objective**: Verify system priority and clean resumption when a higher-priority interruption occurs.
* **Steps**:
  1. With **MIC ON**, place a phone call to the test device.
  2. Answer the phone call.
  3. End the phone call.
* **Expected Result**:
  - Live microphone streaming immediately pauses when the call rings/answers (`AUDIOFOCUS_LOSS` on Android, `interruptionNotification.began` on iOS).
  - UI displays status `"Interrupted (Call/Focus)"`.
  - Once the call terminates, the engine safely resumes if allowed by OS, or cleanly permits the user to toggle **MIC ON** without app restart.
* **Pass/Fail**: `[  ]`

---

### Test Case 8: Clean Termination (MIC OFF)
* **Objective**: Verify immediate release of audio hardware, wake locks, and foreground notification.
* **Steps**:
  1. Tap **MIC OFF** in the app or tap **"Stop Mic"** in the Android notification bar.
* **Expected Result**:
  - Live audio capture stops immediately.
  - Audio buffers and native handles (`AudioRecord`, `AudioTrack`, `AVAudioEngine`) are completely freed.
  - Foreground notification is dismissed immediately.
  - Battery drain drops to zero.
* **Pass/Fail**: `[  ]`
