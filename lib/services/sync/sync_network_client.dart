import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import '../../utils/app_settings.dart';
import 'sync_discovery_service.dart';

class SyncNetworkClient {
  SyncNetworkClient._();

  static Future<int?> requestNextLetterNumber() async {
    final role = await AppSettings.getSyncRole();
    final enabled = await AppSettings.getSyncEnabled();
    if (!enabled || role != 'client') return null;

    var host = await AppSettings.getSyncPeerHost();
    final key = await AppSettings.getSyncKey();
    if (host == null || host.isEmpty) {
      final peers = await SyncDiscoveryService.instance.discover();
      if (peers.isNotEmpty) {
        host = peers.first.host;
        await AppSettings.setSyncPeerHost(host);
        await AppSettings.setSyncPeerPort(peers.first.port);
      }
    }
    if (host == null || host.isEmpty || key.isEmpty) return null;

    final port = await AppSettings.getSyncPeerPort();
    final client = HttpClient();
    try {
      final route = '/sync/next-number';
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final signature = Hmac(sha256, utf8.encode(key)).convert(utf8.encode('$timestamp|POST|$route|')).toString();
      final request = await client.post(host, port, route);
      request.headers.set('x-sync-timestamp', timestamp);
      request.headers.set('x-sync-signature', signature);
      request.headers.contentType = ContentType.json;
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return null;
      final data = jsonDecode(text) as Map;
      return (data['number'] as num?)?.toInt();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
