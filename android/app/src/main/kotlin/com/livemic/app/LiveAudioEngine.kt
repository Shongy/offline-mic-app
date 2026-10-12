package com.livemic.app

import android.content.Context
import android.media.*
import android.os.Build
import android.os.Process
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * Native Android live low-latency audio engine.
 * Streams PCM from phone microphone to output (Bluetooth A2DP / speaker)
 * without saving or recording audio data to disk.
 */
class LiveAudioEngine(private val context: Context) {

    companion object {
        private const val TAG = "LiveAudioEngine"
        private const val DEFAULT_SAMPLE_RATE = 48000
        private const val FALLBACK_SAMPLE_RATE = 44100
    }

    interface AudioEngineListener {
        fun onStateChanged(state: String)
        fun onLevelChanged(level: Double)
        fun onDiagnosticChanged(diag: Map<String, Any>)
        fun onError(message: String)
    }

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var listener: AudioEngineListener? = null

    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var streamingThread: Thread? = null

    private val isRunning = AtomicBoolean(false)
    private var currentGain: Float = 1.0f

    private var sampleRate: Int = DEFAULT_SAMPLE_RATE
    private var bufferFrameSize: Int = 256

    private var audioFocusRequest: AudioFocusRequest? = null
    private var isInterrupted = false

    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        Log.d(TAG, "Audio focus changed: $focusChange")
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                // Permanent loss (e.g. phone call)
                isInterrupted = true
                listener?.onStateChanged("interrupted")
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                // Temporary loss (e.g. ringtone, phone call)
                isInterrupted = true
                listener?.onStateChanged("interrupted")
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                // Media / YouTube playback alongside mic. Keep playing and mixing!
                isInterrupted = false
                listener?.onStateChanged("live")
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                // Focus regained
                if (isInterrupted && isRunning.get()) {
                    isInterrupted = false
                    listener?.onStateChanged("live")
                }
            }
        }
    }

    fun setListener(listener: AudioEngineListener?) {
        this.listener = listener
    }

    fun setGain(gain: Float) {
        this.currentGain = gain.coerceIn(0.0f, 3.0f)
    }

    fun isEngineActive(): Boolean = isRunning.get()

    @Synchronized
    fun start(gain: Float = 1.0f): Boolean {
        if (isRunning.get()) {
            setGain(gain)
            return true
        }

        this.currentGain = gain.coerceIn(0.0f, 3.0f)
        listener?.onStateChanged("starting")

        try {
            requestAudioFocus()

            // Determine optimal sample rate & buffer sizes
            sampleRate = determineSampleRate()

            val minRecBuf = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            val minTrackBuf = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            if (minRecBuf <= 0 || minTrackBuf <= 0) {
                listener?.onError("Hardware does not support low latency PCM audio format")
                listener?.onStateChanged("error")
                return false
            }

            // Target low latency chunk (e.g. 256 to 512 frames, approx 5.3ms to 10.6ms at 48kHz)
            bufferFrameSize = 256
            val recordBufferSize = maxOf(minRecBuf, bufferFrameSize * 2 * 4)
            val trackBufferSize = maxOf(minTrackBuf, bufferFrameSize * 2 * 4)

            // Setup AudioRecord: built-in mic
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                recordBufferSize
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                listener?.onError("Failed to initialize AudioRecord native hardware")
                listener?.onStateChanged("error")
                release()
                return false
            }

            // Setup AudioTrack: configured for media output with low latency
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()

            val audioFormat = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()

            audioTrack = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                AudioTrack.Builder()
                    .setAudioAttributes(audioAttributes)
                    .setAudioFormat(audioFormat)
                    .setBufferSizeInBytes(trackBufferSize)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                AudioTrack(
                    AudioManager.STREAM_MUSIC,
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    trackBufferSize,
                    AudioTrack.MODE_STREAM
                )
            }

            if (audioTrack?.state != AudioTrack.STATE_INITIALIZED) {
                listener?.onError("Failed to initialize AudioTrack output hardware")
                listener?.onStateChanged("error")
                release()
                return false
            }

            audioRecord?.startRecording()
            audioTrack?.play()

            isRunning.set(true)
            isInterrupted = false

            // Report initial diagnostics
            val estLatency = (bufferFrameSize.toDouble() / sampleRate.toDouble()) * 2000.0
            listener?.onDiagnosticChanged(
                mapOf(
                    "sampleRate" to sampleRate,
                    "bufferSize" to bufferFrameSize,
                    "estimatedLatencyMs" to estLatency,
                    "isClipping" to false
                )
            )

            // Start streaming thread
            streamingThread = Thread(::streamLoop, "LiveAudioStreamingThread").apply {
                priority = Thread.MAX_PRIORITY
                start()
            }

            listener?.onStateChanged("live")
            Log.i(TAG, "Live audio engine started successfully at $sampleRate Hz")
            return true

        } catch (e: Exception) {
            Log.e(TAG, "Error starting live audio engine", e)
            listener?.onError("Failed to start audio engine: ${e.message}")
            listener?.onStateChanged("error")
            release()
            return false
        }
    }

    private fun streamLoop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)

        val readBuffer = ShortArray(bufferFrameSize)
        val writeBuffer = ShortArray(bufferFrameSize)

        var meterThrottleCounter = 0
        val meterInterval = 4 // Emits meter update roughly every 20-30ms

        while (isRunning.get()) {
            val record = audioRecord ?: break
            val track = audioTrack ?: break

            if (isInterrupted) {
                // If interrupted (e.g. phone call), sleep briefly and don't block
                Thread.sleep(10)
                continue
            }

            val readCount = record.read(readBuffer, 0, bufferFrameSize)
            if (readCount > 0) {
                val gain = currentGain
                var sumSquare = 0.0
                var clippingOccurred = false

                // Process digital gain and apply soft-clipping saturation limiter
                for (i in 0 until readCount) {
                    val sample = readBuffer[i]
                    val amplified = sample.toFloat() * gain

                    // Soft limiter: cubic smooth saturation when approaching boundaries
                    val limitedSample = when {
                        amplified > 32760f -> {
                            clippingOccurred = true
                            32767
                        }
                        amplified < -32760f -> {
                            clippingOccurred = true
                            -32768
                        }
                        else -> amplified.toInt()
                    }

                    writeBuffer[i] = limitedSample.toShort()

                    // Normalized float for RMS level computation
                    val norm = limitedSample / 32768.0
                    sumSquare += norm * norm
                }

                // Write directly to audio output (Bluetooth A2DP / Speaker)
                track.write(writeBuffer, 0, readCount)

                // Calculate RMS level for UI VU meter
                meterThrottleCounter++
                if (meterThrottleCounter >= meterInterval) {
                    meterThrottleCounter = 0
                    val rms = sqrt(sumSquare / readCount).coerceIn(0.0, 1.0)
                    listener?.onLevelChanged(rms)

                    if (clippingOccurred) {
                        listener?.onDiagnosticChanged(
                            mapOf(
                                "sampleRate" to sampleRate,
                                "bufferSize" to bufferFrameSize,
                                "isClipping" to true
                            )
                        )
                    }
                }
            } else if (readCount < 0) {
                Log.w(TAG, "AudioRecord read returned error code: $readCount")
                Thread.sleep(5)
            }
        }

        Log.i(TAG, "Live streaming loop exited cleanly")
    }

    @Synchronized
    fun stop(): Boolean {
        if (!isRunning.get()) return true

        isRunning.set(false)
        try {
            streamingThread?.interrupt()
            streamingThread?.join(500)
        } catch (_: InterruptedException) {}
        streamingThread = null

        release()
        abandonAudioFocus()

        listener?.onLevelChanged(0.0)
        listener?.onStateChanged("off")
        Log.i(TAG, "Live audio engine stopped cleanly")
        return true
    }

    private fun release() {
        try {
            audioRecord?.apply {
                if (recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    stop()
                }
                release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing AudioRecord", e)
        }
        audioRecord = null

        try {
            audioTrack?.apply {
                if (playState == AudioTrack.PLAYSTATE_PLAYING) {
                    stop()
                }
                release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing AudioTrack", e)
        }
        audioTrack = null
    }

    private fun requestAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val playbackAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()

            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(playbackAttributes)
                .setAcceptsDelayedFocusGain(true)
                .setOnAudioFocusChangeListener(focusChangeListener)
                .build()

            audioFocusRequest?.let { audioManager.requestAudioFocus(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            )
        }
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let {
                audioManager.abandonAudioFocusRequest(it)
                audioFocusRequest = null
            }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusChangeListener)
        }
    }

    private fun determineSampleRate(): Int {
        // Attempt 48000 Hz, fallback to 44100 Hz if unsupported
        val testBuf48 = AudioRecord.getMinBufferSize(
            DEFAULT_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        return if (testBuf48 > 0) DEFAULT_SAMPLE_RATE else FALLBACK_SAMPLE_RATE
    }
}
