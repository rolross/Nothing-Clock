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
  static const String folder = '.ecosystem/nothingclock';
  static const List<String> legacyFolders = ['.NothingClock', 'NothingClock'];
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

  static Future<void> _mkcol(NextcloudCredentials c, String url) async {
    final req = http.Request('MKCOL', Uri.parse(url))..headers.addAll(_headers(c));
    final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 20)));
    if (res.statusCode == 401) throw NextcloudAuthException();
    // 201 creada, 405 ya existe
    if (res.statusCode != 201 && res.statusCode != 405) {
      throw Exception('MKCOL ${res.statusCode}');
    }
  }

  static String _base(NextcloudCredentials c) =>
      '${c.server}/remote.php/dav/files/${Uri.encodeComponent(c.userId)}';

  /// Crea .ecosystem y nothingclock solo si faltan (no modifica lo existente).
  static Future<void> _ensureFolder(NextcloudCredentials c) async {
    var current = _base(c);
    for (final segment in folder.split('/')) {
      current = '$current/$segment';
      await _mkcol(c, current);
    }
  }

  /// Mueve la carpeta antigua (oculta o visible) a .ecosystem/nothingclock.
  static Future<void> migrateLegacyFolder(NextcloudCredentials c) async {
    final base = _base(c);
    await _mkcol(c, '$base/${folder.split('/').first}');
    for (final legacy in legacyFolders) {
      final req = http.Request('MOVE', Uri.parse('$base/$legacy'))
        ..headers.addAll(
            _headers(c, {'Destination': '$base/$folder', 'Overwrite': 'F'}));
      final res = await http.Response.fromStream(
          await req.send().timeout(const Duration(seconds: 20)));
      if (res.statusCode == 401) throw NextcloudAuthException();
      if (res.statusCode == 201 || res.statusCode == 204) break;
      // 404 no existía, 412 el destino ya existe: se ignora
    }
  }

  /// Descarga cualquier fichero por ruta relativa (null si no existe).
  static Future<String?> downloadPath(
      NextcloudCredentials c, String relativePath) async {
    final res = await http
        .get(
          Uri.parse(
              '${c.server}/remote.php/dav/files/${Uri.encodeComponent(c.userId)}/$relativePath'),
          headers: _headers(c),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return null;
    if (res.statusCode == 401) throw NextcloudAuthException();
    if (res.statusCode != 200) throw Exception('GET ${res.statusCode}');
    return utf8.decode(res.bodyBytes);
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

  static String _errorDetail(http.Response res) {
    final m = RegExp(r'<s:message>(.*?)</s:message>', dotAll: true)
        .firstMatch(res.body);
    final detail =
        (m?.group(1) ?? res.body).replaceAll(RegExp(r'\s+'), ' ').trim();
    return detail.length > 160 ? detail.substring(0, 160) : detail;
  }

  static Future<void> upload(NextcloudCredentials c, String content) async {
    await _ensureFolder(c);
    http.Response? last;
    for (final type in const [
      'application/octet-stream',
      'text/plain',
      'application/json'
    ]) {
      final res = await http
          .put(
            _fileUri(c),
            headers: _headers(c, {'Content-Type': type}),
            body: utf8.encode(content),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 401) throw NextcloudAuthException();
      if (res.statusCode == 200 ||
          res.statusCode == 201 ||
          res.statusCode == 204) {
        return;
      }
      last = res;
      if (res.statusCode != 415) break;
    }
    throw Exception('PUT ${last?.statusCode}: ${_errorDetail(last!)}');
  }
}
