import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../../db/database_helper.dart';
import '../../utils/app_settings.dart';
import '../sync_models.dart';

class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();
  static final ValueNotifier<SyncStatus> _statusNotifier =
      ValueNotifier<SyncStatus>(SyncStatus.disconnected);
  static ValueNotifier<SyncStatus> get statusNotifier => _statusNotifier;

  HttpServer? _server;
  Timer? _timer;
  bool _running = false;
  bool _syncing = false;
  String? _lastError;
  DateTime? _lastPeerActivity;

  SyncStatus get status => _statusNotifier.value;
  String? get lastError => _lastError;

  Future<void> initialize() async {
    if (_running) return;
    _running = true;

    await DatabaseHelper.database;
    await DatabaseHelper.ensureSyncIdentity();

    final enabled = await AppSettings.getSyncEnabled();
    if (enabled) {
      await start();
    }
  }

  Future<void> start() async {
    if (!_running) _running = true;
    if (_server == null) {
      final port = await AppSettings.getSyncPort();
      try {
        _server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          port,
          shared: true,
        );
        _server!.listen(
          _handleRequest,
          onError: (_) {
            _setStatus(SyncStatus.error, 'خطا در سرور هماهنگ‌سازی');
          },
        );
      } catch (e) {
        _lastError = 'امکان باز کردن پورت هماهنگ‌سازی وجود ندارد: $e';
        _setStatus(SyncStatus.error, _lastError);
        return;
      }
    }

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final role = await AppSettings.getSyncRole();
      if (role == 'master') {
        final last = _lastPeerActivity;
        if (last == null ||
            DateTime.now().difference(last) > const Duration(seconds: 35)) {
          _setStatus(SyncStatus.disconnected);
        }
      } else {
        await syncNow();
      }
    });
    await syncNow();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _server?.close(force: true);
    _server = null;
    _setStatus(SyncStatus.disconnected);
  }

  Future<void> syncNow() async {
    if (_syncing) return;
    final enabled = await AppSettings.getSyncEnabled();
    if (!enabled) {
      _setStatus(SyncStatus.disconnected);
      return;
    }

    final host = await AppSettings.getSyncPeerHost();
    final role = await AppSettings.getSyncRole();
    final key = await AppSettings.getSyncKey();
    if ((host == null || host.isEmpty) && role == 'master') {
      return;
    }
    if (host == null || host.isEmpty || key.isEmpty) {
      _setStatus(SyncStatus.disconnected);
      return;
    }

    _syncing = true;
    _setStatus(SyncStatus.connecting);
    try {
      final port = await AppSettings.getSyncPeerPort();
      await _requestJson('GET', '/sync/info', host: host, port: port, key: key);
      _setStatus(SyncStatus.syncing);

      await _pullRemote(host, port, key);
      await _pushLocal(host, port, key);
      await _syncFiles(host, port, key);

      await AppSettings.setSyncLastSuccess(DateTime.now());
      _setStatus(SyncStatus.connected);
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      _setStatus(SyncStatus.error, _lastError);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _pullRemote(String host, int port, String key) async {
    final cursor = await AppSettings.getSyncPeerPullCursor();
    final response = await _requestJson(
      'GET',
      '/sync/pull?after=$cursor',
      host: host,
      port: port,
      key: key,
    );

    final changes = (response['changes'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => SyncChange.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    for (final change in changes) {
      if (change.deviceId == await AppSettings.getDeviceId()) continue;
      await DatabaseHelper.applySyncChange(change);
    }

    final remoteCursor = (response['last_id'] as num?)?.toInt();
    if (remoteCursor != null && remoteCursor >= cursor) {
      await AppSettings.setSyncPeerPullCursor(remoteCursor);
    }
  }

  Future<void> _pushLocal(String host, int port, String key) async {
    final cursor = await AppSettings.getSyncPeerPushCursor();
    final changes = await DatabaseHelper.getSyncChangesAfter(
      cursor,
      limit: 100,
    );
    if (changes.isEmpty) return;

    final response = await _requestJson(
      'POST',
      '/sync/push',
      host: host,
      port: port,
      key: key,
      body: {'changes': changes.map((e) => e.toMap()).toList()},
    );

    if (response['ok'] == true) {
      final last = changes.last.id;
      await AppSettings.setSyncPeerPushCursor(last);
    }
  }

  Future<void> _syncFiles(String host, int port, String key) async {
    final localManifest = await _buildFileManifest();
    final remote = await _requestJson(
      'POST',
      '/sync/files/manifest',
      host: host,
      port: port,
      key: key,
      body: {'files': localManifest},
    );

    final missing = (remote['need_upload'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e));

    for (final item in missing) {
      final rel = item['path']?.toString();
      if (rel == null || rel.isEmpty) continue;
      final root = await AppSettings.getLettersDirectory();
      final file = File(path.join(root.path, rel));
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final client = HttpClient();
      final req = await client.post(host, port, '/sync/file');
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      req.headers.set('x-sync-timestamp', timestamp);
      req.headers.set(
        'x-sync-signature',
        _sign(key, timestamp, 'POST', '/sync/file', base64Encode(bytes)),
      );
      req.headers.set('x-sync-path', Uri.encodeComponent(rel));
      req.headers.contentType = ContentType('application', 'octet-stream');
      req.add(bytes);
      final res = await req.close();
      await res.drain();
    }

    final remoteOnly = (remote['need_download'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e));

    for (final item in remoteOnly) {
      final rel = item['path']?.toString();
      if (rel == null || rel.isEmpty) continue;
      await _downloadFile(host, port, key, rel);
    }
  }

  Future<List<Map<String, dynamic>>> _buildFileManifest() async {
    final root = await AppSettings.getLettersDirectory();
    if (!await root.exists()) return [];
    final result = <Map<String, dynamic>>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = path
          .relative(entity.path, from: root.path)
          .replaceAll('\\', '/');
      final bytes = await entity.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      result.add({'path': rel, 'sha256': hash, 'size': bytes.length});
    }
    return result;
  }

  Future<void> _downloadFile(
    String host,
    int port,
    String key,
    String rel,
  ) async {
    final client = HttpClient();
    try {
      final route = '/sync/file?path=${Uri.encodeQueryComponent(rel)}';
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final req = await client.get(host, port, route);
      req.headers.set('x-sync-timestamp', timestamp);
      req.headers.set(
        'x-sync-signature',
        _sign(key, timestamp, 'GET', route, ''),
      );
      final res = await req.close();
      if (res.statusCode != 200) return;
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final root = await AppSettings.getLettersDirectory();
      final target = File(path.join(root.path, rel));
      await target.parent.create(recursive: true);
      if (await target.exists()) {
        final existingHash = sha256
            .convert(await target.readAsBytes())
            .toString();
        if (existingHash == sha256.convert(bytes).toString()) return;
      }
      await target.writeAsBytes(bytes, flush: true);
    } finally {
      client.close(force: true);
    }
  }

  String _sign(
    String key,
    String timestamp,
    String method,
    String route,
    String body,
  ) {
    final mac = Hmac(sha256, utf8.encode(key));
    return mac
        .convert(utf8.encode('$timestamp|$method|$route|$body'))
        .toString();
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String route, {
    required String host,
    required int port,
    required String key,
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    try {
      final req = method == 'GET'
          ? await client.get(host, port, route)
          : await client.post(host, port, route);
      final bodyText = body == null ? '' : jsonEncode(body);
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      req.headers.set('x-sync-timestamp', timestamp);
      req.headers.set(
        'x-sync-signature',
        _sign(key, timestamp, method, route, bodyText),
      );
      req.headers.contentType = ContentType.json;
      if (bodyText.isNotEmpty) req.write(bodyText);
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(text.isEmpty ? 'HTTP ${res.statusCode}' : text);
      }
      return text.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(text) as Map);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final key = await AppSettings.getSyncKey();
      final bodyBytes = request.method == 'POST'
          ? await request.fold<List<int>>(<int>[], (a, b) => a..addAll(b))
          : <int>[];
      final timestamp = request.headers.value('x-sync-timestamp') ?? '';
      final signature = request.headers.value('x-sync-signature') ?? '';
      final parsedTimestamp = int.tryParse(timestamp);
      final fresh =
          parsedTimestamp != null &&
          (DateTime.now().millisecondsSinceEpoch - parsedTimestamp).abs() <=
              120000;
      final bodyForSignature =
          request.method == 'POST' && request.uri.path == '/sync/file'
          ? base64Encode(bodyBytes)
          : utf8.decode(bodyBytes);
      final expected = _sign(
        key,
        timestamp,
        request.method,
        request.uri.toString(),
        bodyForSignature,
      );
      if (key.isEmpty || !fresh || signature != expected) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      _lastPeerActivity = DateTime.now();
      _setStatus(SyncStatus.connected);

      final uri = request.uri;
      if (uri.path == '/sync/info' && request.method == 'GET') {
        final role = await AppSettings.getSyncRole();

        await _writeJson(request, {
          'ok': true,
          'device_id': await AppSettings.getDeviceId(),
          'role': role,
          'port': await AppSettings.getSyncPort(),
        });

        return;
      }

      if (uri.path == '/sync/next-number' && request.method == 'POST') {
        final role = await AppSettings.getSyncRole();
        if (role != 'master') {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
          return;
        }
        final next = await DatabaseHelper.reserveMasterLetterNumber();
        await _writeJson(request, {'ok': true, 'number': next});
        return;
      }

      if (uri.path == '/sync/pull' && request.method == 'GET') {
        final after = int.tryParse(uri.queryParameters['after'] ?? '') ?? 0;
        final changes = await DatabaseHelper.getSyncChangesAfter(
          after,
          limit: 100,
        );
        final last = await DatabaseHelper.getLastSyncChangeId();
        await _writeJson(request, {
          'ok': true,
          'last_id': last,
          'changes': changes.map((e) => e.toMap()).toList(),
        });
        return;
      }

      if (uri.path == '/sync/push' && request.method == 'POST') {
        final body = _readJsonBytes(bodyBytes);
        final changes = (body['changes'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => SyncChange.fromMap(Map<String, dynamic>.from(e)));
        for (final change in changes) {
          await DatabaseHelper.applySyncChange(change);
        }
        await _writeJson(request, {'ok': true});
        return;
      }

      if (uri.path == '/sync/files/manifest' && request.method == 'POST') {
        final body = _readJsonBytes(bodyBytes);
        final incoming = (body['files'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final local = await _buildFileManifest();
        final localMap = {for (final e in local) e['path'].toString(): e};
        final incomingMap = {for (final e in incoming) e['path'].toString(): e};
        final missing = <Map<String, dynamic>>[];
        for (final e in local) {
          final remote = incomingMap[e['path'].toString()];
          if (remote == null || remote['sha256'] != e['sha256']) {
            missing.add(e);
          }
        }
        final remoteOnly = <Map<String, dynamic>>[];
        for (final e in incoming) {
          final localItem = localMap[e['path'].toString()];
          if (localItem == null || localItem['sha256'] != e['sha256']) {
            remoteOnly.add(e);
          }
        }
        await _writeJson(request, {
          'ok': true,
          'need_upload': remoteOnly,
          'need_download': missing,
        });
        return;
      }

      if (uri.path == '/sync/file' && request.method == 'POST') {
        final rel = Uri.decodeComponent(
          request.headers.value('x-sync-path') ?? '',
        );
        if (rel.isEmpty || path.isAbsolute(rel) || rel.contains('..')) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        final bytes = bodyBytes;
        final root = await AppSettings.getLettersDirectory();
        final target = File(path.join(root.path, rel));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes, flush: true);
        await request.response.close();
        return;
      }

      if (uri.path == '/sync/file' && request.method == 'GET') {
        final rel = uri.queryParameters['path'] ?? '';
        if (rel.isEmpty || path.isAbsolute(rel) || rel.contains('..')) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        final root = await AppSettings.getLettersDirectory();
        final file = File(path.join(root.path, rel));
        if (!await file.exists()) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.binary;
        await request.response.addStream(file.openRead());
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'ok': false, 'error': e.toString()}));
      await request.response.close();
    }
  }

  Map<String, dynamic> _readJsonBytes(List<int> bytes) {
    if (bytes.isEmpty) return {};
    final text = utf8.decode(bytes);
    if (text.trim().isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  }

  Future<void> _writeJson(
    HttpRequest request,
    Map<String, dynamic> data,
  ) async {
    final response = request.response;

    response.headers.contentType = ContentType.json;
    response.add(utf8.encode(jsonEncode(data)));

    await response.close();
  }

  void _setStatus(SyncStatus value, [String? error]) {
    _lastError = error ?? _lastError;
    _statusNotifier.value = value;
  }
}
