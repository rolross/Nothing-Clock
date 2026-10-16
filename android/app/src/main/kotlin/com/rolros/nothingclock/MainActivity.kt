package com.rolros.nothingclock

import android.app.AlarmManager
import android.app.AlertDialog
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CLOCK_EVENT_CHANNEL = "clockEventChannel"
    private val EXACT_ALARM_CHANNEL = "exactAlarmChannel"
    private val NATIVE_ALARM_CHANNEL = "nativeAlarmChannel"
    private var eventSink: EventChannel.EventSink? = null
    private var alarmChannel: MethodChannel? = null
    private var pendingRing: Map<String, Any?>? = null

    private val timeChangerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            eventSink?.success(System.currentTimeMillis())
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readRingIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        maybeAskFullScreenIntent()
    }

    private fun maybeAskFullScreenIntent() {
        if (Build.VERSION.SDK_INT < 34) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.canUseFullScreenIntent()) return
        val prefs = getSharedPreferences("native_alarms", Context.MODE_PRIVATE)
        if (prefs.getBoolean("fsi_asked", false)) return
        prefs.edit().putBoolean("fsi_asked", true).apply()
        AlertDialog.Builder(this)
            .setTitle(AlarmStrings.fsiTitle(this))
            .setMessage(AlarmStrings.fsiMessage(this))
            .setPositiveButton(AlarmStrings.ok(this)) { _, _ ->
                val i = Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:$packageName")
                )
                startActivity(i)
            }
            .setNegativeButton(AlarmStrings.later(this), null)
            .show()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readRingIntent(intent)
        val ring = pendingRing
        if (ring != null) {
            alarmChannel?.invokeMethod("onRing", ring)
            pendingRing = null
        }
    }

    private fun readRingIntent(intent: Intent?) {
        if (intent == null || intent.action != AlarmNotifier.ACTION_RING) return
        pendingRing = mapOf(
            "id" to intent.getIntExtra("ring_id", 0),
            "kind" to (intent.getStringExtra("ring_kind") ?: "alarm"),
            "time" to (intent.getStringExtra("ring_time") ?: ""),
            "label" to (intent.getStringExtra("ring_label") ?: "")
        )
        intent.action = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CLOCK_EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                val filter = IntentFilter().apply {
                    addAction(Intent.ACTION_TIME_TICK)
                    addAction(Intent.ACTION_TIME_CHANGED)
                }
                registerReceiver(timeChangerReceiver, filter)
            }

            override fun onCancel(arguments: Any?) {
                try {
                    unregisterReceiver(timeChangerReceiver)
                } catch (e: Exception) {
                }
                eventSink = null
            }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXACT_ALARM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openExactAlarmSettings" -> {
                        openExactAlarmSettings()
                        result.success(null)
                    }
                    "canScheduleExactAlarms" -> {
                        result.success(canScheduleExactAlarms())
                    }
                    else -> result.notImplemented()
                }
            }

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_ALARM_CHANNEL)
        alarmChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "schedule" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val time = (call.argument<Number>("time") ?: 0L).toLong()
                    val kind = call.argument<String>("kind") ?: "alarm"
                    val label = call.argument<String>("label") ?: ""
                    val repeat = call.argument<Boolean>("repeat") ?: false
                    AlarmScheduler.schedule(applicationContext, id, time, kind, label, repeat)
                    result.success(null)
                }
                "cancel" -> {
                    AlarmScheduler.cancel(applicationContext, call.argument<Int>("id") ?: 0)
                    result.success(null)
                }
                "getLaunchRing" -> {
                    val ring = pendingRing
                    pendingRing = null
                    result.success(ring)
                }
                "stopRing" -> {
                    AlarmNotifier.stop(
                        applicationContext,
                        call.argument<Int>("id") ?: 0,
                        call.argument<String>("kind") ?: "alarm"
                    )
                    result.success(null)
                }
                "snoozeRing" -> {
                    AlarmNotifier.snooze(
                        applicationContext,
                        call.argument<Int>("id") ?: 0,
                        call.argument<String>("kind") ?: "alarm",
                        call.argument<String>("label") ?: ""
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        } else {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        }
    }

    private fun canScheduleExactAlarms(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
    }
}
