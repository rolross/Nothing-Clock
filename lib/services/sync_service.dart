import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:nothing_clock/models/alarm.dart';
import 'package:nothing_clock/services/alarms_service.dart';
import 'package:nothing_clock/services/nextcloud_client.dart';
import 'package:nothing_clock/services/ha_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  static final SyncService instance = SyncService._();

  /// Se incrementa cada vez que se aplican datos remotos en local.
  static final ValueNotifier<int> remoteApplied = ValueNotifier<int>(0);

  static const List<String> _dayOrder = [
    'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'
  ];

  SyncService._() {
    WidgetsBinding.instance.addObserver(this);
  }

  NextcloudCredentials? _creds;
  bool _syncing = false;
  bool _pending = false;
  Timer? _debounce;
  Timer? _periodic;
  String? lastError;
  DateTime? lastSync;

  bool get connected => _creds != null;
  bool get syncing => _syncing;
  String? get accountLabel =>
      _creds == null ? null : '${_creds!.loginName} @ ${_creds!.host}';

  Future<void> init() async {
    _creds = await NextcloudClient.loadCredentials();
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('sync_last_at');
    if (ms != null) lastSync = DateTime.fromMillisecondsSinceEpoch(ms);
    notifyListeners();
    if (_creds != null) {
      Future.delayed(const Duration(seconds: 4), () => sync());
      _startPeriodic();
    }
  }

  void _startPeriodic() {
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(seconds: 60), (_) => sync());
  }

  void _stopPeriodic() {
    _periodic?.cancel();
    _periodic = null;
  }

  Future<void> connect(String server, {bool Function()? isCancelled}) async {
    final creds = await NextcloudClient.login(server, isCancelled: isCancelled);
    _creds = creds;
    _startPeriodic();
    lastError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sync_last_local');
    await prefs.remove('sync_last_remote');
    notifyListeners();
    unawaited(sync());
  }

  Future<void> disconnect() async {
    _debounce?.cancel();
    await NextcloudClient.clearCredentials();
    _creds = null;
    lastError = null;
    lastSync = null;
    _stopPeriodic();
    final prefs = await SharedPreferences.getInstance();
    for (final k in [
      'sync_last_local', 'sync_last_remote', 'sync_last_at', 'sync_dirty_at'
    ]) {
      await prefs.remove(k);
    }
    notifyListeners();
  }

  /// Llamar cuando cambian alarmas, timers o relojes. Sincroniza a los pocos segundos.
  static void markDirty() => instance._markDirty();

  Future<void> _markDirty() async {
    if (_creds == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_dirty_at', DateTime.now().millisecondsSinceEpoch);
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopPeriodic();
    }
    if (state == AppLifecycleState.resumed && connected) {
      _startPeriodic();
      final last = lastSync;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 20)) {
        sync();
      }
    }
  }

  Future<void> sync() async {
    final creds = _creds;
    if (creds == null) return;
    if (_syncing) {
      _pending = true;
      return;
    }
    _syncing = true;
    lastError = null;
    notifyListeners();
    try {
      await _doSync(creds);
      unawaited(HaService.refreshConfig(creds));
      lastSync = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('sync_last_at', lastSync!.millisecondsSinceEpoch);
    } on NextcloudAuthException {
      lastError = 'Authorization revoked';
      await NextcloudClient.clearCredentials();
      _creds = null;
    } catch (e) {
      lastError = e.toString();
      debugPrint('Sync failed: $e');
    } finally {
      _syncing = false;
      notifyListeners();
      if (_pending) {
        _pending = false;
        unawaited(sync());
      }
    }
  }

  // ---------- Instantánea de los datos locales ----------

  Future<Map<String, dynamic>> _buildData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final box = await Hive.openBox<Alarm>('alarms');
    final alarms = box.values
        .map((a) => <String, dynamic>{
              'id': a.id,
              'hour': a.time.hour,
              'minute': a.time.minute,
              'days': {for (final d in _dayOrder) d: a.days[d] ?? false},
              'enabled': a.isEnabled,
              'label': a.label,
              'sleep': a.isSleep,
            })
        .toList();
    alarms.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));

    final timers = (prefs.getStringList('saved_timers') ?? [])
        .map((s) => jsonDecode(s))
        .toList();

    final clocks = (prefs.getStringList('world_clocks') ?? []).map((s) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return <String, dynamic>{
        'displayName': m['displayName'],
        'latitude': m['latitude'],
        'longitude': m['longitude'],
        'timezoneId': m['timezoneId'],
      };
    }).toList();

    return {
      'alarms': alarms,
      'timers': timers,
      'worldClocks': clocks,
      'showSeconds': prefs.getBool('show_seconds') ?? false,
      'sleepPrefs': {
        'bedtime': prefs.getInt('sleep_bedtime') ?? 1380,
        'reminder': prefs.getInt('sleep_reminder') ?? 0,
      },
    };
  }

  Future<void> _applyData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList('saved_timers',
        (data['timers'] as List? ?? []).map((t) => jsonEncode(t)).toList());

    await prefs.setStringList(
      'world_clocks',
      (data['worldClocks'] as List? ?? []).map((c) {
        final m = Map<String, dynamic>.from(c as Map);
        return jsonEncode({
          'currentFormattedTime': '00:00',
          'utcTime': 0,
          'longitude': m['longitude'],
          'latitude': m['latitude'],
          'displayName': m['displayName'],
          'timezoneId': m['timezoneId'],
        });
      }).toList(),
    );

    await prefs.setBool('show_seconds', data['showSeconds'] == true);
    final sp = data['sleepPrefs'];
    if (sp is Map) {
      await prefs.setInt('sleep_bedtime', (sp['bedtime'] as num?)?.toInt() ?? 1380);
      await prefs.setInt('sleep_reminder', (sp['reminder'] as num?)?.toInt() ?? 0);
    }

    final alarms = (data['alarms'] as List? ?? []).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final days = Map<String, dynamic>.from(m['days'] as Map);
      return Alarm(
        id: (m['id'] as num).toInt(),
        time: DateTime(2000, 1, 1, (m['hour'] as num).toInt(),
            (m['minute'] as num).toInt()),
        days: {for (final d in _dayOrder) d: days[d] == true},
        isEnabled: m['enabled'] == true,
        label: (m['label'] as String?) ?? '',
        isSleep: m['sleep'] == true,
      );
    }).toList();
    await AlarmsService().replaceAll(alarms);
    await AlarmsService().rescheduleBedtime();

    remoteApplied.value++;
  }

  Map<String, dynamic> _merge(
      Map<String, dynamic> local, Map<String, dynamic> remote) {
    List<Map<String, dynamic>> list(dynamic v) => (v as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Alarmas: unión por id (gana la local) y una sola Sleep Time.
    final localAlarms = list(local['alarms']);
    final remoteAlarms = list(remote['alarms']);
    final byId = <int, Map<String, dynamic>>{};
    for (final a in remoteAlarms) {
      byId[(a['id'] as num).toInt()] = a;
    }
    for (final a in localAlarms) {
      byId[(a['id'] as num).toInt()] = a;
    }
    final localSleep = localAlarms.where((a) => a['sleep'] == true).toList();
    final keepSleepId =
        localSleep.isNotEmpty ? (localSleep.first['id'] as num).toInt() : null;
    final alarms = byId.values.where((a) {
      if (a['sleep'] != true) return true;
      if (keepSleepId == null) return true;
      return (a['id'] as num).toInt() == keepSleepId;
    }).toList();
    alarms.sort((a, b) => (a['id'] as num).compareTo(b['id'] as num));

    // Timers por id.
    final timers = <String, Map<String, dynamic>>{};
    for (final t in list(local['timers'])) {
      timers[t['id'].toString()] = t;
    }
    for (final t in list(remote['timers'])) {
      timers.putIfAbsent(t['id'].toString(), () => t);
    }

    // Relojes mundiales por nombre y coordenadas aproximadas.
    String clockKey(Map<String, dynamic> c) =>
        '${c['displayName']}|${(c['latitude'] as num?)?.toStringAsFixed(1)}|${(c['longitude'] as num?)?.toStringAsFixed(1)}';
    final clocks = <String, Map<String, dynamic>>{};
    for (final c in list(local['worldClocks'])) {
      clocks[clockKey(c)] = c;
    }
    for (final c in list(remote['worldClocks'])) {
      clocks.putIfAbsent(clockKey(c), () => c);
    }

    return {
      'alarms': alarms,
      'timers': timers.values.toList(),
      'worldClocks': clocks.values.toList(),
      'showSeconds': local['showSeconds'] == true,
      'sleepPrefs': local['sleepPrefs'] ?? remote['sleepPrefs'],
    };
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('sync_device_id');
    if (id == null) {
      id = Random().nextInt(1 << 30).toRadixString(36);
      await prefs.setString('sync_device_id', id);
    }
    return id;
  }

  Future<void> _upload(
      NextcloudCredentials creds, Map<String, dynamic> data) async {
    final body = jsonEncode({
      'app': 'com.rolros.nothingclock',
      'version': 1,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'device': await _deviceId(),
      'data': data,
    });
    await NextcloudClient.upload(creds, body);
  }

  Future<void> _remember(String local, String? remote) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_last_local', local);
    if (remote != null) await prefs.setString('sync_last_remote', remote);
  }

  Future<void> _doSync(NextcloudCredentials creds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    if (!(prefs.getBool('nc_folder_migrated_v3') ?? false)) {
      await NextcloudClient.migrateLegacyFolder(creds);
      await prefs.setBool('nc_folder_migrated_v3', true);
    }

    final localData = await _buildData();
    final localJson = jsonEncode(localData);
    final lastLocal = prefs.getString('sync_last_local');
    final lastRemote = prefs.getString('sync_last_remote');

    final remoteText = await NextcloudClient.download(creds);
    Map<String, dynamic>? remoteData;
    int remoteUpdated = 0;
    if (remoteText != null) {
      final remote = jsonDecode(remoteText) as Map<String, dynamic>;
      remoteData = (remote['data'] as Map).cast<String, dynamic>();
      remoteUpdated = (remote['updatedAt'] as num?)?.toInt() ?? 0;
    }
    final remoteJson = remoteData == null ? null : jsonEncode(remoteData);

    // Aplica los datos remotos en local y recuerda el estado resultante.
    Future<void> applyRemote(Map<String, dynamic> data, String remoteStr) async {
      await _applyData(data);
      final rebuilt = jsonEncode(await _buildData());
      await _remember(rebuilt, remoteStr);
    }

    // Sube el estado local y recuerda el resultado.
    Future<void> uploadLocal(Map<String, dynamic> data) async {
      await _upload(creds, data);
      final s = jsonEncode(data);
      await _remember(s, s);
    }

    if (remoteData == null) {
      await uploadLocal(localData);
      return;
    }

    if (remoteJson == localJson) {
      await _remember(localJson, remoteJson);
      return;
    }

    if (lastLocal == null) {
      // Primera sincronización con datos en ambos lados: fusionar sin perder nada.
      final merged = _merge(localData, remoteData);
      await _applyData(merged);
      final rebuilt = await _buildData();
      await uploadLocal(rebuilt);
      return;
    }

    final localChanged = localJson != lastLocal;
    final remoteChanged = remoteJson != lastRemote;

    if (!localChanged && !remoteChanged) return;
    if (!localChanged) {
      await applyRemote(remoteData, remoteJson!);
    } else if (!remoteChanged) {
      await uploadLocal(localData);
    } else {
      // Cambiaron los dos lados: gana el más reciente.
      final localAt = prefs.getInt('sync_dirty_at') ?? 0;
      if (remoteUpdated > localAt) {
        await applyRemote(remoteData, remoteJson!);
      } else {
        await uploadLocal(localData);
      }
    }
  }
}
