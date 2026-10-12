package com.livemic.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build

/**
 * Helper class to inspect and monitor active audio output routing on Android.
 */
class AudioRouteHelper(
    private val context: Context,
    private val onRouteChanged: (Map<String, Any>) -> Unit
) {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var deviceCallback: AudioDeviceCallback? = null
    private var noisyReceiver: BroadcastReceiver? = null

    fun startMonitoring() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            deviceCallback = object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                    onRouteChanged(getCurrentRoute())
                }

                override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                    onRouteChanged(getCurrentRoute())
                }
            }
            audioManager.registerAudioDeviceCallback(deviceCallback, null)
        }

        // Catch audio becoming noisy (e.g. bluetooth / headphones abruptly disconnected)
        noisyReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                    onRouteChanged(getCurrentRoute())
                }
            }
        }
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        context.registerReceiver(noisyReceiver, filter)
    }

    fun stopMonitoring() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && deviceCallback != null) {
            audioManager.unregisterAudioDeviceCallback(deviceCallback)
            deviceCallback = null
        }
        noisyReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: Exception) {}
            noisyReceiver = null
        }
    }

    fun getCurrentRoute(): Map<String, Any> {
        var deviceName = "Phone Speaker"
        var routeType = "speaker"
        var isBluetooth = false
        var isSimultaneousMixSupported = true
        var mixExplanation = "Standard Android media mixing active."

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            for (device in devices) {
                when (device.type) {
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> {
                        val name = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            device.productName.toString()
                        } else {
                            "Bluetooth Audio Device"
                        }
                        deviceName = if (name.isNotBlank()) "$name (Bluetooth A2DP)" else "JBL / Bluetooth Speaker (A2DP)"
                        routeType = "bluetooth_a2dp"
                        isBluetooth = true
                        mixExplanation = "Connected to Bluetooth A2DP speaker. High-fidelity audio with YouTube media mixing enabled."
                        break
                    }
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> {
                        deviceName = "Bluetooth Headset (SCO)"
                        routeType = "bluetooth_sco"
                        isBluetooth = true
                        isSimultaneousMixSupported = false
                        mixExplanation = "Bluetooth SCO active (narrowband voice mode). Simultaneous media mixing may be limited by Android Bluetooth stack."
                    }
                    AudioDeviceInfo.TYPE_WIRED_HEADSET,
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_USB_HEADSET -> {
                        if (!isBluetooth) {
                            deviceName = "Headphones / Aux Output"
                            routeType = "wired"
                            isBluetooth = false
                            mixExplanation = "Wired audio connected. Low latency with full media mixing."
                        }
                    }
                    else -> {}
                }
            }
        } else {
            @Suppress("DEPRECATION")
            if (audioManager.isBluetoothA2dpOn) {
                deviceName = "Bluetooth A2DP Speaker"
                routeType = "bluetooth_a2dp"
                isBluetooth = true
                mixExplanation = "Connected to Bluetooth A2DP audio device."
            } else if (audioManager.isWiredHeadsetOn) {
                deviceName = "Wired Headphones"
                routeType = "wired"
            }
        }

        return mapOf(
            "deviceName" to deviceName,
            "routeType" to routeType,
            "isBluetooth" to isBluetooth,
            "isSimultaneousMixSupported" to isSimultaneousMixSupported,
            "mixExplanation" to mixExplanation
        )
    }
}
