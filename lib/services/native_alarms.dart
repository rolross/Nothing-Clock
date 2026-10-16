import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeAlarms {
  static const MethodChannel _channel = MethodChannel('nativeAlarmChannel');

  static Future<void> init(void Function(Map<String, dynamic>) onRing) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onRing' && call.arguments is Map) {
        onRing(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
    try {
      final launch = await _channel.invokeMethod<Map>('getLaunchRing');
      if (launch != null) onRing(Map<String, dynamic>.from(launch));
    } catch (e) {
      debugPrint('getLaunchRing failed: $e');
    }
  }

  static Future<void> schedule({
    required int id,
    required DateTime time,
    required String kind,
    required String label,
    required bool repeat,
  }) async {
    try {
      await _channel.invokeMethod('schedule', {
        'id': id,
        'time': time.millisecondsSinceEpoch,
        'kind': kind,
        'label': label,
        'repeat': repeat,
      });
    } catch (e) {
      debugPrint('schedule failed: $e');
    }
  }

  static Future<void> cancel(int id) async {
    try {
      await _channel.invokeMethod('cancel', {'id': id});
    } catch (e) {
      debugPrint('cancel failed: $e');
    }
  }

  static Future<void> stopRing(int id, String kind) async {
    try {
      await _channel.invokeMethod('stopRing', {'id': id, 'kind': kind});
    } catch (e) {
      debugPrint('stopRing failed: $e');
    }
  }

  static Future<void> snoozeRing(int id, String kind, String label) async {
    try {
      await _channel
          .invokeMethod('snoozeRing', {'id': id, 'kind': kind, 'label': label});
    } catch (e) {
      debugPrint('snoozeRing failed: $e');
    }
  }
}
