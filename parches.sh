/bin/bash

cat > lib/services/nextcloud_client.dart << 'EOF'
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class NextcloudAuthException implements Exception {
  @override
  String toString() => 'Authorization revoked';
}

class NextcloudCredentials {
  final String server;
  final String loginName;
  final String userId;
  final String appPassword;

  const NextcloudCredentials({
    required this.server,
    required this.loginName,
    required this.userId,
    required this.appPassword,
  });

  String get host => Uri.parse(server).host;
}

class NextcloudClient {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const String _ua = 'NothingClock/1.0 (Android)';
  static const String folder = 'NothingClock';
  static const String fileName = 'backup.json';

  static String normalizeServer(String input) {
    var s = input.trim();
    if (s.isEmpty) throw Exception('Empty server address');
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    s = s.replaceAll(RegExp(r'/+$'), '');
    s = s.replaceAll(RegExp(r'/index\.php.*$'), '');
    return s;
  }

  static Future<NextcloudCredentials?> loadCredentials() async {
    try {
      final server = await _storage.read(key: 'nc_server');
      final login = await _storage.read(key: 'nc_login');
      final user = await _storage.read(key: 'nc_user');
      final pass = await _storage.read(key: 'nc_password');
      if (server == null || login == null || pass == null) return null;
      return NextcloudCredentials(
        server: server,
        loginName: login,
        userId: user ?? login,
        appPassword: pass,
      );
    } catch (e) {
      debugPrint('loadCredentials failed: $e');
      return null;
    }
  }

  static Future<void> saveCredentials(NextcloudCredentials c) async {
    await _storage.write(key: 'nc_server', value: c.server);
    await _storage.write(key: 'nc_login', value: c.loginName);
    await _storage.write(key: 'nc_user', value: c.userId);
    await _storage.write(key: 'nc_password', value: c.appPassword);
  }

  static Future<void> clearCredentials() async {
    for (final k in ['nc_server', 'nc_login', 'nc_user', 'nc_password']) {
      await _storage.delete(key: k);
    }
  }

  static Map<String, String> _headers(NextcloudCredentials c,
      [Map<String, String>? extra]) {
    final basic = base64Encode(utf8.encode('${c.loginName}:${c.appPassword}'));
    return {
      'Authorization': 'Basic $basic',
      'User-Agent': _ua,
      if (extra != null) ...extra,
    };
  }

  static Future<String?> _fetchUserId(
      String server, String loginName, String appPassword) async {
    try {
      final basic = base64Encode(utf8.encode('$loginName:$appPassword'));
      final res = await http.get(
        Uri.parse('$server/ocs/v1.php/cloud/user?format=json'),
        headers: {
          'Authorization': 'Basic $basic',
          'OCS-APIRequest': 'true',
          'Accept': 'application/json',
          'User-Agent': _ua,
        },
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      return json['ocs']['data']['id'] as String?;
    } catch (e) {
      debugPrint('fetchUserId failed: $e');
      return null;
    }
  }

  /// Login Flow v2: abre el navegador, espera la autorización y guarda una
  /// contraseña de aplicación.
  static Future<NextcloudCredentials> login(
    String serverInput, {
    bool Function()? isCancelled,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final server = normalizeServer(serverInput);

    final start = await http
        .post(Uri.parse('$server/index.php/login/v2'),
            headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 15));
    if (start.statusCode != 200) {
      throw Exception('Invalid Nextcloud server (${start.statusCode})');
    }
    final data = jsonDecode(start.body);
    final String pollToken = data['poll']['token'];
    final String pollEndpoint = data['poll']['endpoint'];
    final String loginUrl = data['login'];

    await launchUrl(Uri.parse(loginUrl), mode: LaunchMode.externalApplication);

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 2));
      if (isCancelled?.call() ?? false) {
        throw Exception('Cancelled');
      }
      try {
        final res = await http.post(
          Uri.parse(pollEndpoint),
          headers: {'User-Agent': _ua},
          body: {'token': pollToken},
        ).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final j = jsonDecode(res.body);
          final serverUrl =
              (j['server'] as String).replaceAll(RegExp(r'/+$'), '');
          final loginName = j['loginName'] as String;
          final appPassword = j['appPassword'] as String;
          final userId =
              await _fetchUserId(serverUrl, loginName, appPassword) ?? loginName;
          final creds = NextcloudCredentials(
            server: serverUrl,
            loginName: loginName,
            userId: userId,
            appPassword: appPassword,
          );
          await saveCredentials(creds);
          return creds;
        }
      } catch (e) {
        debugPrint('poll failed: $e');
      }
    }
    throw TimeoutException('Authorization timed out');
  }

  static Uri _folderUri(NextcloudCredentials c) => Uri.parse(
      '${c.server}/remote.php/dav/files/${Uri.encodeComponent(c.userId)}/$folder');

  static Uri _fileUri(NextcloudCredentials c) =>
      Uri.parse('${_folderUri(c)}/$fileName');

  static Future<void> _ensureFolder(NextcloudCredentials c) async {
    final req = http.Request('MKCOL', _folderUri(c))..headers.addAll(_headers(c));
    final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 20)));
    if (res.statusCode == 401) throw NextcloudAuthException();
    // 201 creada, 405 ya existe
    if (res.statusCode != 201 && res.statusCode != 405) {
      throw Exception('MKCOL ${res.statusCode}');
    }
  }

  /// Devuelve el contenido del backup o null si no existe.
  static Future<String?> download(NextcloudCredentials c) async {
    final res = await http
        .get(_fileUri(c), headers: _headers(c))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return null;
    if (res.statusCode == 401) throw NextcloudAuthException();
    if (res.statusCode != 200) throw Exception('GET ${res.statusCode}');
    return utf8.decode(res.bodyBytes);
  }

  static Future<void> upload(NextcloudCredentials c, String content) async {
    await _ensureFolder(c);
    final res = await http
        .put(
          _fileUri(c),
          headers: _headers(c, {'Content-Type': 'application/json'}),
          body: utf8.encode(content),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 401) throw NextcloudAuthException();
    if (res.statusCode != 200 && res.statusCode != 201 && res.statusCode != 204) {
      throw Exception('PUT ${res.statusCode}');
    }
  }
}
EOF

cat > lib/services/sync_service.dart << 'EOF'
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:nothing_clock/models/alarm.dart';
import 'package:nothing_clock/services/alarms_service.dart';
import 'package:nothing_clock/services/nextcloud_client.dart';
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
    }
  }

  Future<void> connect(String server, {bool Function()? isCancelled}) async {
    final creds = await NextcloudClient.login(server, isCancelled: isCancelled);
    _creds = creds;
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
    if (state == AppLifecycleState.resumed && connected) {
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
EOF

cat > lib/widgets/nextcloud_settings_tile.dart << 'EOF'
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/services/sync_service.dart';

class NextcloudSettingsTile extends StatelessWidget {
  const NextcloudSettingsTile({super.key});

  String _two(int v) => v.toString().padLeft(2, '0');

  String _subtitle(SyncService s) {
    if (!s.connected) {
      return s.lastError != null
          ? '${tr("Sync error")}: ${s.lastError}'
          : tr("Not connected");
    }
    final parts = <String>[s.accountLabel ?? ''];
    if (s.lastError != null) {
      parts.add(tr("Sync error"));
    } else if (s.lastSync != null) {
      final t = s.lastSync!;
      parts.add('${tr("Synced")} ${_two(t.hour)}:${_two(t.minute)}');
    }
    return parts.join(' · ');
  }

  Future<void> _connect(BuildContext context) async {
    final controller = TextEditingController(text: 'https://');
    final server = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr("Nextcloud server")),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://cloud.example.com'),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr("CANCEL"))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(tr("Connect"))),
        ],
      ),
    );
    if (server == null || server.length < 9) return;
    if (!context.mounted) return;

    var cancelled = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 16),
            Expanded(child: Text(tr("Authorize NothingClock in the browser..."))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(ctx);
            },
            child: Text(tr("CANCEL")),
          ),
        ],
      ),
    );

    String? error;
    try {
      await SyncService.instance.connect(server, isCancelled: () => cancelled);
    } catch (e) {
      if (!cancelled) error = e.toString();
    }
    if (!cancelled && context.mounted) Navigator.of(context).pop();
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr("Sync error")}: $error')),
      );
    }
  }

  Future<void> _manage(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(SyncService.instance.accountLabel ?? 'Nextcloud'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'sync'),
              child: Text(tr("Sync now"))),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'disconnect'),
              child: Text(tr("Disconnect"))),
        ],
      ),
    );
    if (choice == 'sync') {
      await SyncService.instance.sync();
    } else if (choice == 'disconnect') {
      await SyncService.instance.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return AnimatedBuilder(
      animation: sync,
      builder: (context, _) {
        final theme = Theme.of(context);
        return ListTile(
          onTap: () => sync.connected ? _manage(context) : _connect(context),
          title: Row(
            children: [
              Text(tr("Nextcloud sync").toUpperCase()),
              const SizedBox(width: 15),
              const Icon(FontAwesomeIcons.cloud, size: 15),
            ],
          ),
          subtitle: Text(
            _subtitle(sync),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurface),
          ),
          trailing: Padding(
            padding: const EdgeInsets.only(left: 15.0),
            child: sync.syncing
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.arrow_forward_ios, size: 15),
          ),
        );
      },
    );
  }
}
EOF

cat > fix14.py << 'EOF'
import re, sys
from pathlib import Path

failed = []
SYNC_IMPORT = "import 'package:nothing_clock/services/sync_service.dart';"

def edit(path, *steps):
    try:
        p = Path(path)
        s = p.read_text(encoding="utf-8")
        for kind, a, b in steps:
            if kind == "s":
                assert a in s, f"no encontrado: {a[:70]!r}"
                s = s.replace(a, b, 1)
            else:
                s, n = re.subn(a, lambda m: b, s, count=1, flags=re.S)
                assert n == 1, f"regex no encontrado: {a[:70]!r}"
        p.write_text(s, encoding="utf-8")
        print("OK", path)
    except AssertionError as e:
        failed.append(path)
        print("FALLO", path, "->", e)

edit("lib/services/alarms_service.dart",
 ("s", "List<Alarm>? _cachedAlarms;", "static List<Alarm>? _cachedAlarms;"),
 ("s", "Future<void> deleteAlarm(Alarm alarm) async {",
       '''Future<void> replaceAll(List<Alarm> alarms) async {
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

  Future<void> deleteAlarm(Alarm alarm) async {'''),
)

edit("lib/view_models/alarms_view_model.dart",
 ("s", "import 'package:nothing_clock/services/alarms_service.dart';",
       "import 'package:nothing_clock/services/alarms_service.dart';\n" + SYNC_IMPORT),
 ("s", "Future<void> addAlarm(Alarm newAlarm) async {",
       "Future<void> addAlarm(Alarm newAlarm) async {\n    SyncService.markDirty();"),
 ("s", "void toggleAlarmState(Alarm alarm) {",
       "void toggleAlarmState(Alarm alarm) {\n    SyncService.markDirty();"),
 ("s", "Future<void> updateAlarm(Alarm alarm, DateTime time, Map<String, bool> days, String label) async {",
       "Future<void> updateAlarm(Alarm alarm, DateTime time, Map<String, bool> days, String label) async {\n    SyncService.markDirty();"),
 ("s", "Future<void> deleteAlarm(Alarm alarm) async {",
       "Future<void> deleteAlarm(Alarm alarm) async {\n    SyncService.markDirty();"),
)

edit("lib/screens/alarms_screen.dart",
 ("s", "import 'package:nothing_clock/models/alarm.dart';",
       "import 'package:nothing_clock/models/alarm.dart';\n" + SYNC_IMPORT),
 ("s", "WidgetsBinding.instance.addObserver(this);",
       "WidgetsBinding.instance.addObserver(this);\n    SyncService.remoteApplied.addListener(_loadAlarms);"),
 ("s", "WidgetsBinding.instance.removeObserver(this);",
       "WidgetsBinding.instance.removeObserver(this);\n    SyncService.remoteApplied.removeListener(_loadAlarms);"),
)

edit("lib/providers/timer_provider.dart",
 ("s", "import 'package:nothing_clock/services/timer_service.dart';",
       "import 'package:nothing_clock/services/timer_service.dart';\n" + SYNC_IMPORT),
 ("s", "TimerService.changes.addListener(_syncFromPrefs);",
       "TimerService.changes.addListener(_syncFromPrefs);\n    SyncService.remoteApplied.addListener(_onRemoteApplied);"),
 ("s", "TimerService.changes.removeListener(_syncFromPrefs);",
       "TimerService.changes.removeListener(_syncFromPrefs);\n    SyncService.remoteApplied.removeListener(_onRemoteApplied);"),
 ("s", "'saved_timers', _timers.map((t) => jsonEncode(t.toJson())).toList());",
       "'saved_timers', _timers.map((t) => jsonEncode(t.toJson())).toList());\n    SyncService.markDirty();"),
 ("s", "Future<void> _syncFromPrefs() async {",
       '''Future<void> _onRemoteApplied() async {
    await _loadSaved();
    notifyListeners();
  }

  Future<void> _syncFromPrefs() async {'''),
)

edit("lib/providers/worldclocks_provider.dart",
 ("s", "import 'package:shared_preferences/shared_preferences.dart';",
       "import 'package:shared_preferences/shared_preferences.dart';\n" + SYNC_IMPORT),
 ("s", "_subscribeToTimeTick(context);",
       "_subscribeToTimeTick(context);\n    SyncService.remoteApplied.addListener(_onRemoteApplied);"),
 ("s", "_timeTickSubscription?.cancel();",
       "_timeTickSubscription?.cancel();\n    SyncService.remoteApplied.removeListener(_onRemoteApplied);"),
 ("s", "await prefs.setStringList('world_clocks', worldClockStrings);",
       "await prefs.setStringList('world_clocks', worldClockStrings);\n      SyncService.markDirty();"),
 ("s", "await prefs.setBool('show_seconds', value);",
       "await prefs.setBool('show_seconds', value);\n    SyncService.markDirty();"),
 ("s", "/// Updates all world clocks by recalculating their time offsets.",
       '''Future<void> _onRemoteApplied() async {
    final prefs = await SharedPreferences.getInstance();
    _showSeconds = prefs.getBool('show_seconds') ?? false;
    WorldClockData.showSeconds = _showSeconds;
    _updateSecondsTimer();
    await _loadWorldClocks();
    await _fetchInitialTimeData();
    notifyListeners();
  }

  /// Updates all world clocks by recalculating their time offsets.'''),
)

edit("lib/screens/settings_screen.dart",
 ("s", "import 'package:nothing_clock/l10n/app_locale.dart';",
       "import 'package:nothing_clock/l10n/app_locale.dart';\nimport 'package:nothing_clock/widgets/nextcloud_settings_tile.dart';"),
 ("s", '_buildListTile(context, tr("Theme"),',
       'const NextcloudSettingsTile(),\n                _buildListTile(context, tr("Theme"),'),
)

edit("lib/main.dart",
 ("s", "import 'package:nothing_clock/services/native_alarms.dart';",
       "import 'package:nothing_clock/services/native_alarms.dart';\n" + SYNC_IMPORT),
 ("s", "unawaited(Permission.notification.request());",
       "unawaited(SyncService.instance.init());\n  unawaited(Permission.notification.request());"),
)

edit("lib/l10n/app_locale.dart",
 ("s", '"Language": "Idioma",',
       '''"Language": "Idioma",
    "Nextcloud sync": "Sincronización con Nextcloud",
    "Nextcloud server": "Servidor de Nextcloud",
    "Not connected": "Sin conectar",
    "Connect": "CONECTAR",
    "Authorize NothingClock in the browser...": "Autoriza NothingClock en el navegador…",
    "Sync now": "Sincronizar ahora",
    "Disconnect": "Desconectar",
    "Synced": "Sincronizado",
    "Sync error": "Error de sincronización",'''),
)

sys.exit(1 if failed else 0)
EOF

python3 fix14.py && rm fix14.py
flutter run
