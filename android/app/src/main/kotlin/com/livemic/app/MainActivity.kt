package com.livemic.app

import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), LiveAudioEngine.AudioEngineListener {

    companion object {
        private const val METHOD_CHANNEL = "com.livemic.app/audio_control"
        private const val EVENT_CHANNEL = "com.livemic.app/audio_events"
        private const val METER_CHANNEL = "com.livemic.app/audio_level"
    }

    private var eventSink: EventChannel.EventSink? = null
    private var meterSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var audioRouteHelper: AudioRouteHelper
    private var localAudioEngine: LiveAudioEngine? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        localAudioEngine = LiveAudioEngine(applicationContext)
        localAudioEngine?.setListener(this)

        audioRouteHelper = AudioRouteHelper(applicationContext) { routeMap ->
            mainHandler.post {
                eventSink?.success(
                    mapOf(
                        "type" to "routeChange",
                        "route" to routeMap
                    )
                )
            }
        }
        audioRouteHelper.startMonitoring()

        // MethodChannel handler
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startLiveMic" -> {
                        val gain = (call.argument<Double>("gain") ?: 1.0).toFloat()
                        val serviceIntent = Intent(this, MicForegroundService::class.java).apply {
                            action = MicForegroundService.ACTION_START
                            putExtra(MicForegroundService.EXTRA_GAIN, gain)
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }

                        // Attach listener to service engine once active
                        mainHandler.postDelayed({
                            MicForegroundService.instance?.audioEngine?.setListener(this)
                        }, 200)

                        result.success(true)
                    }

                    "stopLiveMic" -> {
                        val service = MicForegroundService.instance
                        if (service != null) {
                            service.stopLiveAudioAndSelf()
                        } else {
                            localAudioEngine?.stop()
                        }
                        result.success(true)
                    }

                    "setGain" -> {
                        val gain = (call.argument<Double>("gain") ?: 1.0).toFloat()
                        MicForegroundService.instance?.audioEngine?.setGain(gain)
                            ?: localAudioEngine?.setGain(gain)
                        result.success(null)
                    }

                    "getAudioRoute" -> {
                        result.success(audioRouteHelper.getCurrentRoute())
                    }

                    "getAvailableInputs" -> {
                        val audioManager = getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
                        val list = mutableListOf<Map<String, Any>>()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val devices = audioManager.getDevices(android.media.AudioManager.GET_DEVICES_INPUTS)
                            for (dev in devices) {
                                val isBuiltIn = dev.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_MIC
                                val name = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) dev.productName.toString() else "Microphone ${dev.id}"
                                list.add(mapOf(
                                    "id" to dev.id.toString(),
                                    "name" to (if (name.isNotBlank()) name else "Microphone"),
                                    "type" to if (isBuiltIn) "builtInMic" else "external",
                                    "isBuiltIn" to isBuiltIn,
                                    "isSelected" to isBuiltIn
                                ))
                            }
                        }
                        if (list.isEmpty()) {
                            list.add(mapOf(
                                "id" to "builtin_default",
                                "name" to "Phone Built-In Microphone",
                                "type" to "builtInMic",
                                "isBuiltIn" to true,
                                "isSelected" to true
                            ))
                        }
                        result.success(list)
                    }

                    "setPreferredInput" -> {
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }

        // EventChannel for lifecycle and state events
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    // Send initial route immediately
                    sink?.success(
                        mapOf(
                            "type" to "routeChange",
                            "route" to audioRouteHelper.getCurrentRoute()
                        )
                    )
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // EventChannel for real-time VU meter levels
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, METER_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    meterSink = sink
                }

                override fun onCancel(arguments: Any?) {
                    meterSink = null
                }
            })
    }

    override fun onResume() {
        super.onResume()
        // Re-attach listener if service was already running in background
        MicForegroundService.instance?.audioEngine?.let { engine ->
            engine.setListener(this)
            if (engine.isEngineActive()) {
                onStateChanged("live")
            }
        }
    }

    override fun onDestroy() {
        audioRouteHelper.stopMonitoring()
        localAudioEngine?.stop()
        super.onDestroy()
    }

    // AudioEngineListener callbacks
    override fun onStateChanged(state: String) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "stateChange",
                    "state" to state
                )
            )
        }
    }

    override fun onLevelChanged(level: Double) {
        mainHandler.post {
            meterSink?.success(level)
        }
    }

    override fun onDiagnosticChanged(diag: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "diagnostic",
                    "diagnostic" to diag
                )
            )
        }
    }

    override fun onError(message: String) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "stateChange",
                    "state" to "error"
                )
            )
            eventSink?.success(
                mapOf(
                    "type" to "diagnostic",
                    "diagnostic" to mapOf("lastError" to message)
                )
            )
        }
    }
}
