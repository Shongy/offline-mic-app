package com.livemic.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Foreground service to keep the live microphone engine running uninterrupted
 * in the background, even when user switches to YouTube or locks the screen.
 */
class MicForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "live_mic_service_channel"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "com.livemic.app.ACTION_START"
        const val ACTION_STOP = "com.livemic.app.ACTION_STOP"
        const val EXTRA_GAIN = "extra_gain"

        var instance: MicForegroundService? = null
            private set
    }

    inner class LocalBinder : Binder() {
        fun getService(): MicForegroundService = this@MicForegroundService
    }

    private val binder = LocalBinder()
    private var wakeLock: PowerManager.WakeLock? = null
    lateinit var audioEngine: LiveAudioEngine
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        audioEngine = LiveAudioEngine(applicationContext)

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "LiveMicApp::MicWakeLock"
        )

        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopLiveAudioAndSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val gain = intent.getFloatExtra(EXTRA_GAIN, 1.0f)
                startForegroundWithNotification()
                if (!wakeLock?.isHeld!!) {
                    wakeLock?.acquire(3 * 60 * 60 * 1000L) // Safe 3h max safety timeout
                }
                audioEngine.start(gain)
            }
        }
        return START_STICKY
    }

    private fun startForegroundWithNotification() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = Intent(this, MicForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Live Microphone Active")
            .setContentText("Streaming live voice to speaker in background")
            .setSmallIcon(R.drawable.ic_mic_notification)
            .setContentIntent(openPendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(R.drawable.ic_mic_notification, "Stop Mic", stopPendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = getString(R.string.channel_name)
            val descriptionText = getString(R.string.channel_description)
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun stopLiveAudioAndSelf() {
        audioEngine.stop()
        if (wakeLock?.isHeld == true) {
            try {
                wakeLock?.release()
            } catch (_: Exception) {}
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        audioEngine.stop()
        if (wakeLock?.isHeld == true) {
            try {
                wakeLock?.release()
            } catch (_: Exception) {}
        }
        instance = null
        super.onDestroy()
    }
}
