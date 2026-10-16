import 'package:flutter/foundation.dart';
import 'package:nothing_clock/services/native_alarms.dart';
import 'package:nothing_clock/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimerState {
  final String? activeId;
  final String name;
  final String state; // idle | running | paused | completed
  final int total;
  final DateTime? end;
  final int pausedRemaining;

  const TimerState({
    required this.activeId,
    required this.name,
    required this.state,
    required this.total,
    required this.end,
    required this.pausedRemaining,
  });
}

class TimerService {
  static const int alarmId = 4242;
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  // Stub para alarmas antiguas programadas con el plugin anterior.
  @pragma('vm:entry-point')
  static Future<void> timerCallback(int id) async {}

  static Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  static Future<TimerState> loadState() async {
    final prefs = await _prefs();
    final endMs = prefs.getInt('t_end_ms');
    return TimerState(
      activeId: prefs.getString('t_active_id'),
      name: prefs.getString('t_active_name') ?? '',
      state: prefs.getString('t_state') ?? 'idle',
      total: prefs.getInt('t_total') ?? 0,
      end: endMs == null ? null : DateTime.fromMillisecondsSinceEpoch(endMs),
      pausedRemaining: prefs.getInt('t_paused_remaining') ?? 0,
    );
  }

  static Future<void> start({
    required String id,
    required String name,
    required int total,
    required int remaining,
  }) async {
    final prefs = await _prefs();
    final end = DateTime.now().add(Duration(seconds: remaining));
    await prefs.setString('t_active_id', id);
    await prefs.setString('t_active_name', name);
    await prefs.setString('t_state', 'running');
    await prefs.setInt('t_total', total);
    await prefs.setInt('t_end_ms', end.millisecondsSinceEpoch);
    await prefs.remove('t_paused_remaining');

    await NotificationService.cancelId(alarmId);
    await NativeAlarms.schedule(
      id: alarmId,
      time: end,
      kind: 'timer',
      label: name,
      repeat: false,
    );
    await NotificationService.showTimerRunning(name: name, end: end);
    changes.value++;
  }

  static Future<void> pause({required int remaining, int? total}) async {
    final prefs = await _prefs();
    await prefs.setString('t_state', 'paused');
    await prefs.setInt('t_paused_remaining', remaining);
    if (total != null) await prefs.setInt('t_total', total);
    await prefs.remove('t_end_ms');
    await NativeAlarms.cancel(alarmId);
    await NotificationService.cancelTimerRunning();
    changes.value++;
  }

  static Future<void> stop() async {
    final prefs = await _prefs();
    await prefs.setString('t_state', 'idle');
    await prefs.remove('t_end_ms');
    await prefs.remove('t_paused_remaining');
    await prefs.remove('t_active_id');
    await NativeAlarms.cancel(alarmId);
    await NotificationService.cancelTimerRunning();
    await NativeAlarms.stopRing(alarmId, 'timer');
    await NotificationService.cancelId(alarmId);
    changes.value++;
  }

  static Future<void> snooze(int minutes) async {
    final prefs = await _prefs();
    final id = prefs.getString('t_active_id');
    if (id == null) return;
    final name = prefs.getString('t_active_name') ?? '';
    await NativeAlarms.stopRing(alarmId, 'timer');
    await start(
      id: id,
      name: name,
      total: minutes * 60,
      remaining: minutes * 60,
    );
  }

  static Future<void> updateName(String name) async {
    final prefs = await _prefs();
    if (prefs.getString('t_active_id') != null) {
      await prefs.setString('t_active_name', name);
    }
  }
}
