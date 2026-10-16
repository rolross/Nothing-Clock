package com.rolros.nothingclock

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings

class AlarmRingService : Service() {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var ringId = 0
    private var kind = "alarm"
    private var label = ""
    private val timeoutRunnable = Runnable { onTimeout() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ringId = intent?.getIntExtra("id", 0) ?: 0
        kind = intent?.getStringExtra("kind") ?: "alarm"
        label = intent?.getStringExtra("label") ?: ""

        val notification = AlarmNotifier.buildNotification(
            this, ringId, kind, label, AlarmNotifier.RING_CHANNEL_ID, false
        )
        val fgId = if (ringId == 0) 1 else ringId
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(fgId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(fgId, notification)
        }

        acquireWakeLock()
        startSound()
        startVibration()

        handler.removeCallbacks(timeoutRunnable)
        handler.postDelayed(timeoutRunnable, 15 * 60 * 1000L)
        return START_NOT_STICKY
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock?.isHeld == true) return
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nothingclock:ring")
            wakeLock?.acquire(16 * 60 * 1000L)
        } catch (e: Exception) {
        }
    }

    private fun startSound() {
        stopSound()
        val candidates = ArrayList<Uri?>()
        candidates.add(Settings.System.DEFAULT_ALARM_ALERT_URI)
        candidates.add(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
        candidates.add(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
        candidates.add(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))

        for (uri in candidates) {
            if (uri == null) continue
            try {
                val mp = MediaPlayer()
                mp.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                mp.setDataSource(this, uri)
                mp.isLooping = true
                mp.prepare()
                mp.start()
                player = mp
                return
            } catch (e: Exception) {
            }
        }
    }

    private fun stopSound() {
        try {
            player?.stop()
        } catch (e: Exception) {
        }
        try {
            player?.release()
        } catch (e: Exception) {
        }
        player = null
    }

    private fun startVibration() {
        try {
            val vib = if (Build.VERSION.SDK_INT >= 31) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            vibrator = vib
            val pattern = longArrayOf(0, 800, 800)
            if (Build.VERSION.SDK_INT >= 26) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                @Suppress("DEPRECATION")
                vib.vibrate(VibrationEffect.createWaveform(pattern, 0), attrs)
            } else {
                @Suppress("DEPRECATION")
                vib.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
        }
    }

    private fun onTimeout() {
        val id = ringId
        val k = kind
        val l = label
        stopRinging()
        AlarmNotifier.showMissed(applicationContext, id, k, l)
        sendBroadcast(Intent(AlarmNotifier.ACTION_DISMISSED).setPackage(packageName))
    }

    private fun stopRinging() {
        if (Build.VERSION.SDK_INT >= 24) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(timeoutRunnable)
        stopSound()
        try {
            vibrator?.cancel()
        } catch (e: Exception) {
        }
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (e: Exception) {
        }
        super.onDestroy()
    }
}
