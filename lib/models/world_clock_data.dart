import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

class WorldClockData with ChangeNotifier {
  static bool showSeconds = false;

  final double longitude;
  final double latitude;
  final String displayName;

  int utcTime;
  String currentFormattedTime;
  int currentHour = 12;
  String? timezoneId;

  set utc(int value) {
    if (value < -12) {
      utcTime = -12;
      notifyListeners();
      return;
    } else if (value > 14) {
      utcTime = 14;
      notifyListeners();
      return;
    }

    utcTime = value;
    notifyListeners();
  }

  int get utc => utcTime;

  void calculateTimeOffset() {
    int hour;
    int minute;
    int second;

    bool done = false;
    hour = 0;
    minute = 0;
    second = 0;

    if (timezoneId != null) {
      try {
        final now = tz.TZDateTime.now(tz.getLocation(timezoneId!));
        hour = now.hour;
        minute = now.minute;
        second = now.second;
        done = true;
      } catch (_) {
        done = false;
      }
    }

    if (!done) {
      final DateTime utcNow = DateTime.now().toUtc();
      hour = ((utcNow.hour + utcTime) % 24 + 24) % 24;
      minute = utcNow.minute;
      second = utcNow.second;
    }

    currentHour = hour;
    final hh = hour.toString().padLeft(2, "0");
    final mm = minute.toString().padLeft(2, "0");
    final ss = second.toString().padLeft(2, "0");

    currentFormattedTime = "$hh:$mm";
  }

  Duration _remoteOffset() {
    if (timezoneId != null) {
      try {
        return tz.TZDateTime.now(tz.getLocation(timezoneId!)).timeZoneOffset;
      } catch (_) {}
    }
    return Duration(hours: utcTime);
  }

  /// Diferencia con la hora del móvil, p. ej. "+1 H" o "-6 H" ("" si es igual).
  String get diffLabel {
    final minutes = (_remoteOffset() - DateTime.now().timeZoneOffset).inMinutes;
    if (minutes == 0) return '';
    final sign = minutes > 0 ? '+' : '-';
    final abs = minutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    return m == 0 ? '$sign$h H' : '$sign$h:${m.toString().padLeft(2, '0')} H';
  }

  bool get isDay => currentHour >= 7 && currentHour < 20;

  WorldClockData({
    required this.currentFormattedTime,
    required this.utcTime,
    required this.longitude,
    required this.latitude,
    required this.displayName,
    this.timezoneId,
  });
}
