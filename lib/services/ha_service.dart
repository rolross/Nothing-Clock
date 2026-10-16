import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nothing_clock/services/nextcloud_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HaEntity {
  final String id;
  final String name;
  const HaEntity(this.id, this.name);
}

class HaService {
  static const List<String> events = ['bedtime', 'wake', 'awake'];
  static const List<String> _domains = ['script.', 'scene.', 'automation.'];

  static Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p;
  }

  static Future<String> url() async =>
      ((await _prefs()).getString('ha_url') ?? '')
          .trim()
          .replaceAll(RegExp(r'/+$'), '');

  static Future<String> _token() async =>
      ((await _prefs()).getString('ha_token') ?? '').trim();

  static Future<bool> isConfigured() async =>
      (await url()).isNotEmpty && (await _token()).isNotEmpty;

  /// Lee .ecosystem/config.json de Nextcloud: {"haUrl": "...", "haToken": "..."}
  static Future<void> refreshConfig([NextcloudCredentials? creds]) async {
    try {
      creds ??= await NextcloudClient.loadCredentials();
      if (creds == null) return;
      final text =
          await NextcloudClient.downloadPath(creds, '.ecosystem/config.json');
      if (text == null) return;
      final json = jsonDecode(text);
      final u = ((json['haUrl'] as String?) ?? '').trim();
      final t = ((json['haToken'] as String?) ?? '').trim();
      final p = await SharedPreferences.getInstance();
      if (u.isEmpty || t.isEmpty) {
        await p.remove('ha_url');
        await p.remove('ha_token');
      } else {
        await p.setString('ha_url', u);
        await p.setString('ha_token', t);
      }
    } catch (e) {
      debugPrint('HA config refresh failed: $e');
    }
  }

  static Future<List<HaEntity>> listEntities() async {
    final base = await url();
    final token = await _token();
    final res = await http.get(
      Uri.parse('$base/api/states'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) {
      throw Exception('Token rejected by Home Assistant');
    }
    if (res.statusCode != 200) {
      throw Exception('Home Assistant ${res.statusCode}');
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    final out = <HaEntity>[];
    for (final e in list) {
      final id = e['entity_id'] as String;
      if (!_domains.any(id.startsWith)) continue;
      final name = (e['attributes']?['friendly_name'] as String?) ?? id;
      out.add(HaEntity(id, name));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Lanza el evento y la entidad elegida. Devuelve null si todo fue bien.
  static Future<String?> test(String event) async {
    try {
      final base = await url();
      final token = await _token();
      final p = await _prefs();

      Future<http.Response> post(String path, Map<String, dynamic> body) =>
          http
              .post(
                Uri.parse('$base$path'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(body),
              )
              .timeout(const Duration(seconds: 10));

      var res = await post(
          '/api/events/nothingclock_$event', {'event': event, 'test': true});
      if (res.statusCode >= 300) return 'HTTP ${res.statusCode}';

      final entity = p.getString('ha_entity_$event') ?? '';
      if (entity.isNotEmpty) {
        final domain = entity.split('.').first;
        final svcDomain =
            ['script', 'scene', 'automation'].contains(domain) ? domain : 'homeassistant';
        final service = domain == 'automation' ? 'trigger' : 'turn_on';
        res = await post('/api/services/$svcDomain/$service', {'entity_id': entity});
        if (res.statusCode >= 300) return 'HTTP ${res.statusCode}';
      }
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }
}
