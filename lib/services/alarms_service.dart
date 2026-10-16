import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:nothing_clock/models/alarm.dart';
import 'package:nothing_clock/services/native_alarms.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AlarmsService {
  static List<Alarm>? _cachedAlarms;

  static const MethodChannel _channel = MethodChannel('exactAlarmChannel');

  static const Map<String, int> dayStringToWeekday = {
    "SUN": DateTime.sunday,
    "MON": DateTime.monday,
    "TUE": DateTime.tuesday,
    "WED": DateTime.wednesday,
    "THU": DateTime.thursday,
    "FRI": DateTime.friday,
    "SAT": DateTime.saturday,
  };

  // Stubs para alarmas antiguas programadas con el plugin anterior.
  @pragma('vm:entry-point')
  static Future<void> alarmCallback(int id) async {}

  @pragma('vm:entry-point')
  static Future<void> snoozeCallback(int id) async {}

  Future<bool> canScheduleExactAlarms() async {
    try {
      final bool? result = await _channel.invokeMethod("canScheduleExactAlarms");
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("Error checking if exact alarms can be scheduled: $e");
      return false;
    }
  }

  static Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod("openExactAlarmSettings");
    } on PlatformException catch (e) {
      debugPrint("Error opening exact alarm settings: $e");
    }
  }

  Future<void> saveAlarmData(Alarm alarm) async {
    final box = await Hive.openBox<Alarm>('alarms');
    await box.add(alarm);

    _cachedAlarms?.add(alarm);
    loadAlarms();
  }

  int getNumberOfAlarms() {
    return _cachedAlarms?.length ?? 0;
  }

  Future<List<Alarm>> loadAlarms() async {
    if (_cachedAlarms != null) {
      return _cachedAlarms!;
    }

    final box = await Hive.openBox<Alarm>('alarms');
    _cachedAlarms = box.values.toList();
    return _cachedAlarms!;
  }

  static int _alarmId(Alarm alarm, int weekday) {
    final int truncated = alarm.id & ((1 << 28) - 1);
    return ((truncated << 3) | (weekday & 0x7)) & 0x7FFFFFFF;
  }

  List<String> _activeDays(Alarm alarm) {
    return alarm.days.entries.where((e) => e.value).map((e) => e.key).toList();
  }

  static bool hasDays(Alarm a) => a.days.values.any((v) => v);

  static Future<bool> consumeOnceFired(Alarm alarm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final key = 'once_fired_${_alarmId(alarm, 0)}';
    final fired = prefs.getBool(key) ?? false;
    if (fired) await prefs.remove(key);
    return fired;
  }

  /// Reprograma las alarmas activas con el sistema nativo (una sola vez).
  static Future<void> migrateToNative() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('native_alarms_v1') ?? false) return;
    final service = AlarmsService();
    final alarms = await service.loadAlarms();
    for (final a in alarms) {
      if (a.isEnabled) await service.scheduleAlarmAt(a);
    }
    await prefs.setBool('native_alarms_v1', true);
  }

  Future<void> scheduleAlarmAt(Alarm alarm, {bool skipNext = false}) async {
    final days = _activeDays(alarm);

    if (days.isEmpty) {
      final now = DateTime.now();
      var when = DateTime(now.year, now.month, now.day, alarm.time.hour, alarm.time.minute);
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      final onceId = _alarmId(alarm, 0);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await prefs.remove('once_fired_$onceId');
      await NativeAlarms.schedule(
        id: onceId,
        time: when,
        kind: alarm.isSleep ? 'sleep' : 'alarm',
        label: alarm.label,
        repeat: false,
      );
      return;
    }

    final entries = <MapEntry<int, DateTime>>[];
    for (final dayKey in days) {
      final weekday = dayStringToWeekday[dayKey];
      if (weekday == null) continue;
      entries.add(MapEntry(weekday, _getNextOccurrence(alarm.time, weekday)));
    }
    entries.sort((a, b) => a.value.compareTo(b.value));
    for (var i = 0; i < entries.length; i++) {
      var when = entries[i].value;
      if (skipNext && i == 0) when = when.add(const Duration(days: 7));
      await NativeAlarms.schedule(
        id: _alarmId(alarm, entries[i].key),
        time: when,
        kind: alarm.isSleep ? 'sleep' : 'alarm',
        label: alarm.label,
        repeat: true,
      );
    }
    if (alarm.isSleep) await rescheduleBedtime();
  }

  DateTime? nextTrigger(Alarm alarm) {
    final now = DateTime.now();
    final days = _activeDays(alarm);
    if (days.isEmpty) {
      var when = DateTime(now.year, now.month, now.day, alarm.time.hour, alarm.time.minute);
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      return when;
    }
    DateTime? best;
    for (final d in days) {
      final w = dayStringToWeekday[d];
      if (w == null) continue;
      final t = _getNextOccurrence(alarm.time, w);
      if (best == null || t.isBefore(best)) best = t;
    }
    return best;
  }

  Future<void> cancelBedtime() async {
    for (var w = 1; w <= 7; w++) {
      await NativeAlarms.cancel(-1000 - w);
      await NativeAlarms.cancel(-1100 - w);
    }
  }

  /// Programa la hora de dormir (y su recordatorio) según la alarma Sleep Time.
  Future<void> rescheduleBedtime() async {
    await cancelBedtime();
    final alarms = await loadAlarms();
    final sleep = alarms.where((a) => a.isSleep).firstOrNull;
    if (sleep == null || !sleep.isEnabled) return;
    final days = _activeDays(sleep);
    if (days.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final bedMin = prefs.getInt('sleep_bedtime') ?? 23 * 60;
    final reminder = prefs.getInt('sleep_reminder') ?? 0;
    final wakeMin = sleep.time.hour * 60 + sleep.time.minute;
    final crossesMidnight = bedMin > wakeMin;
    final bedTime = DateTime(2000, 1, 1, bedMin ~/ 60, bedMin % 60);
    final now = DateTime.now();

    for (final d in days) {
      final wakeDay = dayStringToWeekday[d];
      if (wakeDay == null) continue;
      final bedDay = crossesMidnight
          ? (wakeDay == DateTime.monday ? DateTime.sunday : wakeDay - 1)
          : wakeDay;
      final when = _getNextOccurrence(bedTime, bedDay);
      await NativeAlarms.schedule(
        id: -1000 - wakeDay,
        time: when,
        kind: 'bedtime',
        label: '',
        repeat: true,
      );
      if (reminder > 0) {
        var r = when.subtract(Duration(minutes: reminder));
        while (!r.isAfter(now)) {
          r = r.add(const Duration(days: 7));
        }
        await NativeAlarms.schedule(
          id: -1100 - wakeDay,
          time: r,
          kind: 'bedtime_reminder',
          label: '$reminder',
          repeat: true,
        );
      }
    }
  }

  Future<void> cancelAlarm(Alarm alarm) async {
    for (final weekday in [0, ...dayStringToWeekday.values]) {
      final id = _alarmId(alarm, weekday);
      await NativeAlarms.cancel(id);
      await NativeAlarms.cancel(-id - 1);
    }
    if (alarm.isSleep) await rescheduleBedtime();
  }

  Future<void> replaceAll(List<Alarm> alarms) async {
    final box = await Hive.openBox<Alarm>('alarms');
    for (final a in box.values.toList()) {
      await cancelAlarm(a);
    }
    await box.clear();
    _cachedAlarms = null;
    for (final a in alarms) {
      await box.add(a);
    }
    _cachedAlarms = box.values.toList();
    for (final a in _cachedAlarms!) {
      if (a.isEnabled) await scheduleAlarmAt(a);
    }
  }

  Future<void> deleteAlarm(Alarm alarm) async {
    await cancelAlarm(alarm);
    _cachedAlarms?.remove(alarm);
    await alarm.delete();
  }

  DateTime _getNextOccurrence(DateTime alarmTime, int targetDay) {
    final now = DateTime.now();

    DateTime scheduled =
        DateTime(now.year, now.month, now.day, alarmTime.hour, alarmTime.minute);
    int daysToAdd = (targetDay - scheduled.weekday) % 7;

    if (daysToAdd == 0 && scheduled.isBefore(now)) {
      daysToAdd = 7;
    } else if (daysToAdd < 0) {
      daysToAdd += 7;
    }

    return scheduled.add(Duration(days: daysToAdd));
  }
}
