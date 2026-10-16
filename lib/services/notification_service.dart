import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/screens/alarm_ring_screen.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static bool _ringShowing = false;

  static Future<void> initialize() async {
    const AndroidInitializationSettings settings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: settings));
  }

  /// Muestra la pantalla de alarma/timer a partir de los datos nativos.
  static void handleRing(Map<String, dynamic> ring) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), () => _openRing(ring));
    });
  }

  static void _openRing(Map<String, dynamic> ring) {
    final nav = navigatorKey.currentState;
    if (nav == null || _ringShowing) return;
    _ringShowing = true;
    nav
        .push(MaterialPageRoute(
          builder: (_) => AlarmRingScreen(
            notificationId: (ring['id'] as num?)?.toInt() ?? 0,
            time: (ring['time'] as String?) ?? '',
            label: (ring['label'] as String?) ?? '',
            isTimer: ring['kind'] == 'timer',
          ),
        ))
        .then((_) {
      _ringShowing = false;
    });
  }

  static Future<void> cancelId(int id) async {
    await initialize();
    await _plugin.cancel(id);
  }

  static Future<void> cancelTimerRunning() => cancelId(4243);

  static Future<void> showTimerRunning({required String name, required DateTime end}) async {
    await initialize();
    await AppLocale.init();
    final details = AndroidNotificationDetails(
      'timer_running',
      'Timer',
      channelDescription: 'Running timer',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      showWhen: true,
      when: end.millisecondsSinceEpoch,
      usesChronometer: true,
      chronometerCountDown: true,
    );
    await _plugin.show(
      4243,
      name.isEmpty ? tr('Timer') : name,
      tr('Time remaining'),
      NotificationDetails(android: details),
      payload: 'timer_running',
    );
  }
}
