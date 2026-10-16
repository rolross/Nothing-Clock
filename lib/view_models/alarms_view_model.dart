import 'package:flutter/foundation.dart';
import 'package:nothing_clock/models/alarm.dart';
import 'package:nothing_clock/services/alarms_service.dart';
import 'package:nothing_clock/services/sync_service.dart';

class AlarmsViewModel with ChangeNotifier {
  final AlarmsService _alarmsService = AlarmsService();

  List<Alarm> _alarms = [];
  Alarm? _sleepAlarm;

  List<Alarm> get alarms => _alarms;
  Alarm? get sleepAlarm => _sleepAlarm;

  Future<void> loadAlarms() async {
    final all = await _alarmsService.loadAlarms();
    for (final a in all) {
      if (a.isEnabled && !AlarmsService.hasDays(a) && await AlarmsService.consumeOnceFired(a)) {
        a.isEnabled = false;
        a.uiRev++;
        await a.save();
      }
    }
    _alarms = all.where((a) => !a.isSleep).toList();

    var sleep = all.where((a) => a.isSleep).firstOrNull;
    if (sleep == null) {
      sleep = Alarm(
        time: DateTime(2000, 1, 1, 8, 15),
        days: {
          "MON": true,
          "TUE": true,
          "WED": true,
          "THU": false,
          "FRI": false,
          "SAT": false,
          "SUN": false
        },
        label: 'SLEEP TIME',
        isSleep: true,
      );
      await _alarmsService.saveAlarmData(sleep);
    }
    _sleepAlarm = sleep;
    notifyListeners();
  }

  Future<void> addAlarm(Alarm newAlarm) async {
    SyncService.markDirty();
    newAlarm.isEnabled = true;
    await _alarmsService.saveAlarmData(newAlarm);
    await _alarmsService.scheduleAlarmAt(newAlarm);
    await loadAlarms();
  }

  void toggleAlarmState(Alarm alarm) {
    SyncService.markDirty();
    alarm.isEnabled = !alarm.isEnabled;
    if (alarm.isEnabled) {
      _alarmsService.scheduleAlarmAt(alarm);
    } else {
      _alarmsService.cancelAlarm(alarm);
    }
    alarm.save();
    alarm.uiRev++;
    notifyListeners();
  }

  Future<void> updateAlarm(Alarm alarm, DateTime time, Map<String, bool> days, String label) async {
    SyncService.markDirty();
    await _alarmsService.cancelAlarm(alarm);
    alarm.time = time;
    alarm.days = Map<String, bool>.from(days);
    alarm.label = label;
    await alarm.save();
    if (alarm.isEnabled) {
      await _alarmsService.scheduleAlarmAt(alarm);
    }
    alarm.uiRev++;
    notifyListeners();
  }

  Future<void> skipNextOccurrence(Alarm alarm) async {
    await _alarmsService.cancelAlarm(alarm);
    await _alarmsService.scheduleAlarmAt(alarm, skipNext: true);
    alarm.uiRev++;
    notifyListeners();
  }

  void refreshAlarm(Alarm alarm) {
    alarm.uiRev++;
    notifyListeners();
  }

  Future<void> deleteAlarm(Alarm alarm) async {
    SyncService.markDirty();
    await _alarmsService.deleteAlarm(alarm);
    await loadAlarms();
  }
}
