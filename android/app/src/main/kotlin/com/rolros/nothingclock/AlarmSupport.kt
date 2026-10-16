package com.rolros.nothingclock

import android.app.AlarmManager
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

object FlutterPrefs {
    private fun prefs(context: Context) =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    fun onceFired(context: Context, id: Int) {
        prefs(context).edit().putBoolean("flutter.once_fired_$id", true).apply()
    }

    fun timerCompleted(context: Context) {
        val p = prefs(context)
        if (p.getString("flutter.t_state", "idle") == "running") {
            p.edit().putString("flutter.t_state", "completed").remove("flutter.t_end_ms").apply()
        }
    }

    fun timerStopped(context: Context) {
        prefs(context).edit()
            .putString("flutter.t_state", "idle")
            .remove("flutter.t_end_ms")
            .remove("flutter.t_paused_remaining")
            .remove("flutter.t_active_id")
            .apply()
    }

    fun timerSnoozed(context: Context, seconds: Long, endMs: Long) {
        prefs(context).edit()
            .putString("flutter.t_state", "running")
            .putLong("flutter.t_total", seconds)
            .putLong("flutter.t_end_ms", endMs)
            .remove("flutter.t_paused_remaining")
            .apply()
    }

    fun language(context: Context): String =
        prefs(context).getString("flutter.app_language", "system") ?: "system"
}

object AlarmStrings {
    private fun es(context: Context): Boolean {
        val choice = FlutterPrefs.language(context)
        val code = if (choice == "system") Locale.getDefault().language else choice
        return code == "es"
    }

    fun alarm(c: Context) = if (es(c)) "Alarma" else "Alarm"
    fun timer(c: Context) = if (es(c)) "Temporizador" else "Timer"
    fun timesUp(c: Context) = if (es(c)) "¡Tiempo!" else "Time's up"
    fun stop(c: Context) = if (es(c)) "APAGAR" else "STOP"
    fun snooze(c: Context, minutes: Int) =
        if (es(c)) "POSPONER $minutes MIN" else "SNOOZE $minutes MIN"
    fun missed(c: Context) = if (es(c)) "Alarma perdida" else "Missed alarm"
    fun fsiTitle(c: Context) =
        if (es(c)) "Permitir alarmas a pantalla completa" else "Allow full-screen alarms"
    fun fsiMessage(c: Context) =
        if (es(c)) "Para que la pantalla de la alarma salga con el móvil apagado, permite las notificaciones a pantalla completa en el siguiente ajuste."
        else "To show the alarm screen when the display is off, allow full-screen notifications in the next setting."
    fun ok(c: Context) = if (es(c)) "Abrir ajustes" else "Open settings"
    fun later(c: Context) = if (es(c)) "Más tarde" else "Later"
    fun bedtime(c: Context) = if (es(c)) "Hora de dormir" else "Bedtime"
    fun bedtimeNow(c: Context) =
        if (es(c)) "Es hora de irse a dormir" else "Time to wind down and sleep"
    fun bedtimeSoon(c: Context, minutes: String) =
        if (es(c)) "Dormir en $minutes min" else "Bedtime in $minutes min"
}

object AlarmScheduler {
    private const val PREFS = "native_alarms"
    private const val KEY = "alarms"
    const val ACTION_FIRE = "com.rolros.nothingclock.ALARM_FIRE"

    private fun piFlags(): Int {
        var f = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) f = f or PendingIntent.FLAG_IMMUTABLE
        return f
    }

    private fun firePendingIntent(
        context: Context, id: Int, kind: String, label: String, repeat: Boolean
    ): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            putExtra("id", id)
            putExtra("kind", kind)
            putExtra("label", label)
            putExtra("repeat", repeat)
        }
        return PendingIntent.getBroadcast(context, id, intent, piFlags())
    }

    private fun load(context: Context): JSONArray {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, "[]") ?: "[]"
        return try { JSONArray(raw) } catch (e: Exception) { JSONArray() }
    }

    private fun save(context: Context, arr: JSONArray) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, arr.toString()).apply()
    }

    private fun store(
        context: Context, id: Int, time: Long, kind: String, label: String, repeat: Boolean
    ) {
        val arr = load(context)
        val out = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.getInt("id") != id) out.put(o)
        }
        out.put(
            JSONObject()
                .put("id", id)
                .put("time", time)
                .put("kind", kind)
                .put("label", label)
                .put("repeat", repeat)
        )
        save(context, out)
    }

    fun remove(context: Context, id: Int) {
        val arr = load(context)
        val out = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.getInt("id") != id) out.put(o)
        }
        save(context, out)
    }

    fun storedTime(context: Context, id: Int): Long? {
        val arr = load(context)
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.getInt("id") == id) return o.getLong("time")
        }
        return null
    }

    fun nextWeek(time: Long): Long {
        val c = Calendar.getInstance()
        c.timeInMillis = time
        c.add(Calendar.DAY_OF_YEAR, 7)
        return c.timeInMillis
    }

    fun schedule(
        context: Context, id: Int, triggerAt: Long, kind: String, label: String, repeat: Boolean
    ) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val show = PendingIntent.getActivity(
            context, id, Intent(context, MainActivity::class.java), piFlags()
        )
        am.setAlarmClock(
            AlarmManager.AlarmClockInfo(triggerAt, show),
            firePendingIntent(context, id, kind, label, repeat)
        )
        store(context, id, triggerAt, kind, label, repeat)
    }

    fun cancel(context: Context, id: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = firePendingIntent(context, id, "alarm", "", false)
        am.cancel(pi)
        pi.cancel()
        remove(context, id)
    }

    fun rescheduleAll(context: Context) {
        val arr = load(context)
        val now = System.currentTimeMillis()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val id = o.getInt("id")
            var time = o.getLong("time")
            val repeat = o.getBoolean("repeat")
            if (time <= now) {
                if (!repeat) {
                    remove(context, id)
                    continue
                }
                while (time <= now) time = nextWeek(time)
            }
            schedule(context, id, time, o.getString("kind"), o.getString("label"), repeat)
        }
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        val kind = intent.getStringExtra("kind") ?: "alarm"
        val label = intent.getStringExtra("label") ?: ""
        val repeat = intent.getBooleanExtra("repeat", false)

        if (repeat) {
            val stored = AlarmScheduler.storedTime(context, id) ?: System.currentTimeMillis()
            var next = AlarmScheduler.nextWeek(stored)
            val now = System.currentTimeMillis()
            while (next <= now) next = AlarmScheduler.nextWeek(next)
            AlarmScheduler.schedule(context, id, next, kind, label, true)
        } else {
            AlarmScheduler.remove(context, id)
            if (kind == "timer") {
                FlutterPrefs.timerCompleted(context)
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.cancel(AlarmNotifier.TIMER_RUNNING_ID)
            } else if (id >= 0) {
                FlutterPrefs.onceFired(context, id)
            }
        }
        val pending = goAsync()
        when (kind) {
            "bedtime" -> {
                AlarmNotifier.showInfo(
                    context, id, AlarmStrings.bedtime(context), AlarmStrings.bedtimeNow(context)
                )
                HaClient.trigger(context, "bedtime") { pending.finish() }
            }
            "bedtime_reminder" -> {
                AlarmNotifier.showInfo(
                    context, id, AlarmStrings.bedtime(context), AlarmStrings.bedtimeSoon(context, label)
                )
                pending.finish()
            }
            else -> {
                AlarmNotifier.ring(context, id, kind, label)
                if (kind == "sleep") {
                    HaClient.trigger(context, "wake") { pending.finish() }
                } else {
                    pending.finish()
                }
            }
        }
    }
}

class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        val kind = intent.getStringExtra("kind") ?: "alarm"
        val label = intent.getStringExtra("label") ?: ""
        val pending = goAsync()
        when (intent.action) {
            AlarmNotifier.ACTION_STOP -> AlarmNotifier.stop(context, id, kind) { pending.finish() }
            AlarmNotifier.ACTION_SNOOZE -> {
                AlarmNotifier.snooze(context, id, kind, label)
                pending.finish()
            }
            else -> pending.finish()
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AlarmScheduler.rescheduleAll(context)
    }
}

object AlarmNotifier {
    const val CHANNEL_ID = "alarm_native_v1"
    const val RING_CHANNEL_ID = "alarm_ring_v1"
    const val MISSED_CHANNEL_ID = "alarm_missed_v1"
    const val ACTION_STOP = "com.rolros.nothingclock.ALARM_STOP"
    const val ACTION_SNOOZE = "com.rolros.nothingclock.ALARM_SNOOZE"
    const val ACTION_DISMISSED = "com.rolros.nothingclock.RING_DISMISSED"
    const val ACTION_RING = "com.rolros.nothingclock.ALARM_RING"
    const val TIMER_RUNNING_ID = 4243

    private fun piFlags(): Int {
        var f = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) f = f or PendingIntent.FLAG_IMMUTABLE
        return f
    }

    private fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val ch = NotificationChannel(CHANNEL_ID, "Alarms (sound)", NotificationManager.IMPORTANCE_HIGH)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            ch.setSound(Settings.System.DEFAULT_ALARM_ALERT_URI, attrs)
            ch.enableVibration(true)
            ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            nm.createNotificationChannel(ch)
        }

        if (nm.getNotificationChannel(RING_CHANNEL_ID) == null) {
            val ch = NotificationChannel(RING_CHANNEL_ID, "Alarms", NotificationManager.IMPORTANCE_HIGH)
            ch.setSound(null, null)
            ch.enableVibration(false)
            ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            nm.createNotificationChannel(ch)
        }

        if (nm.getNotificationChannel(MISSED_CHANNEL_ID) == null) {
            val ch = NotificationChannel(MISSED_CHANNEL_ID, "Missed alarms", NotificationManager.IMPORTANCE_DEFAULT)
            nm.createNotificationChannel(ch)
        }
    }

    fun ringIntent(context: Context, id: Int, kind: String, label: String): Intent {
        val cal = Calendar.getInstance()
        val timeText = if (kind == "timer") "00:00" else String.format(
            Locale.US, "%02d:%02d", cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE)
        )
        return Intent(context, RingActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_NO_USER_ACTION
            putExtra("ring_id", id)
            putExtra("ring_kind", kind)
            putExtra("ring_time", timeText)
            putExtra("ring_label", label)
        }
    }

    fun buildNotification(
        context: Context, id: Int, kind: String, label: String,
        channelId: String, insistent: Boolean
    ): Notification {
        ensureChannels(context)
        val isTimer = kind == "timer"
        val title = if (label.isNotEmpty()) label
        else if (isTimer) AlarmStrings.timer(context) else AlarmStrings.alarm(context)
        val cal = Calendar.getInstance()
        val text = if (isTimer) AlarmStrings.timesUp(context) else String.format(
            Locale.US, "%02d:%02d", cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE)
        )
        val snoozeMinutes = if (isTimer) 1 else 10

        val ringPi = PendingIntent.getActivity(
            context, id, ringIntent(context, id, kind, label), piFlags()
        )

        val stopIntent = Intent(context, AlarmActionReceiver::class.java).apply {
            action = ACTION_STOP
            putExtra("id", id)
            putExtra("kind", kind)
            putExtra("label", label)
        }
        val stopPi = PendingIntent.getBroadcast(context, id, stopIntent, piFlags())

        val snoozeIntent = Intent(context, AlarmActionReceiver::class.java).apply {
            action = ACTION_SNOOZE
            putExtra("id", id)
            putExtra("kind", kind)
            putExtra("label", label)
        }
        val snoozePi = PendingIntent.getBroadcast(context, id, snoozeIntent, piFlags())

        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId)
        else Notification.Builder(context)

        if (Build.VERSION.SDK_INT < 26) {
            builder.setPriority(Notification.PRIORITY_MAX)
            if (insistent) {
                builder.setSound(Settings.System.DEFAULT_ALARM_ALERT_URI, AudioManager.STREAM_ALARM)
            }
        }

        builder.setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(text)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(ringPi)
            .setFullScreenIntent(ringPi, true)
            .addAction(0, AlarmStrings.snooze(context, snoozeMinutes), snoozePi)
            .addAction(0, AlarmStrings.stop(context), stopPi)

        val n = builder.build()
        if (insistent) n.flags = n.flags or Notification.FLAG_INSISTENT
        return n
    }

    /** Punto de entrada cuando salta una alarma o un timer. */
    fun ring(context: Context, id: Int, kind: String, label: String) {
        ensureChannels(context)

        // Pantalla apagada o bloqueada: lanzar la pantalla completa directamente.
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (!pm.isInteractive || km.isKeyguardLocked) {
                context.startActivity(ringIntent(context, id, kind, label))
            }
        } catch (e: Exception) {
        }

        // Servicio temporal en primer plano: sonido + vibración en bucle + notificación.
        try {
            val intent = Intent(context, AlarmRingService::class.java).apply {
                putExtra("id", id)
                putExtra("kind", kind)
                putExtra("label", label)
            }
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
            else context.startService(intent)
        } catch (e: Exception) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(id, buildNotification(context, id, kind, label, CHANNEL_ID, true))
        }
    }

    fun showInfo(context: Context, id: Int, title: String, text: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "sleep_info_v1"
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(channelId) == null) {
            nm.createNotificationChannel(
                NotificationChannel(channelId, "Sleep time", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val open = PendingIntent.getActivity(
            context, id, Intent(context, MainActivity::class.java), piFlags()
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId)
        else Notification.Builder(context)
        builder.setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(open)
        nm.notify(id, builder.build())
    }

    fun showMissed(context: Context, id: Int, kind: String, label: String) {
        ensureChannels(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val title = if (label.isNotEmpty()) label
        else if (kind == "timer") AlarmStrings.timer(context) else AlarmStrings.alarm(context)
        val open = PendingIntent.getActivity(
            context, id, Intent(context, MainActivity::class.java), piFlags()
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, MISSED_CHANNEL_ID)
        else Notification.Builder(context)
        builder.setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(AlarmStrings.missed(context))
            .setAutoCancel(true)
            .setContentIntent(open)
        nm.notify(id, builder.build())
    }

    private fun stopRingingService(context: Context, id: Int) {
        context.stopService(Intent(context, AlarmRingService::class.java))
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(id)
        context.sendBroadcast(Intent(ACTION_DISMISSED).setPackage(context.packageName))
    }

    fun stop(context: Context, id: Int, kind: String, done: (() -> Unit)? = null) {
        stopRingingService(context, id)
        if (kind == "timer") FlutterPrefs.timerStopped(context)
        if (kind == "sleep") HaClient.trigger(context, "awake", done) else done?.invoke()
    }

    fun snooze(context: Context, id: Int, kind: String, label: String) {
        stopRingingService(context, id)
        if (kind == "timer") {
            val end = System.currentTimeMillis() + 60000L
            FlutterPrefs.timerSnoozed(context, 60L, end)
            AlarmScheduler.schedule(context, id, end, "timer", label, false)
        } else {
            val snoozeId = if (id < 0) id else -id - 1
            AlarmScheduler.schedule(
                context, snoozeId, System.currentTimeMillis() + 600000L, "alarm", label, false
            )
        }
    }
}
