import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/app_settings.dart';

class SyncPeer {
  final String deviceId;
  final String deviceName;
  final String host;
  final int port;
  final String role;

  const SyncPeer({
    required this.deviceId,
    required this.deviceName,
    required this.host,
    required this.port,
    required this.role,
  });

  bool get isMaster => role == 'master';
}

/// Local-network discovery for Dabirkhane.
///
/// This does not replace the HTTP sync protocol. It only removes the need
/// to manually type the peer IP address. The existing pairing key remains
/// the authentication mechanism for the HTTP connection.
class SyncDiscoveryService {
  SyncDiscoveryService._();

  static final SyncDiscoveryService instance = SyncDiscoveryService._();

  static const int discoveryPort = 39422;
  static const String _type = 'DABIRKHANE_DISCOVERY_V1';

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _announceTimer;
  bool _starting = false;

  final StreamController<SyncPeer> _peersController =
      StreamController<SyncPeer>.broadcast();
  Stream<SyncPeer> get peers => _peersController.stream;

  Future<void> start() async {
    if (_socket != null || _starting) return;
    _starting = true;
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: false,
      );
      _socket!.broadcastEnabled = true;
      _subscription = _socket!.listen(_handleSocketEvent, onError: (_) {});

      final role = await AppSettings.getSyncRole();
      if (role == 'master') {
        _announceTimer?.cancel();
        _announceTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => announce(),
        );
        await announce();
      }
    } catch (_) {
      await stop();
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> announce() async {
    final socket = _socket;
    if (socket == null) return;

    final role = await AppSettings.getSyncRole();
    final deviceId = await AppSettings.getDeviceId();
    final deviceName = await AppSettings.getSyncDeviceName();
    final port = await AppSettings.getSyncPort();

    final packet = utf8.encode(jsonEncode({
      'type': _type,
      'action': 'announce',
      'device_id': deviceId,
      'device_name': deviceName,
      'role': role,
      'port': port,
    }));

    try {
      socket.send(packet, InternetAddress('255.255.255.255'), discoveryPort);
      for (final address in await _directedBroadcastAddresses()) {
        socket.send(packet, address, discoveryPort);
      }
    } catch (_) {}
  }

  Future<List<InternetAddress>> _directedBroadcastAddresses() async {
    final result = <InternetAddress>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length != 4) continue;
          // Most office/home LANs use /24. The global broadcast above is
          // still sent first, so this is only a compatibility fallback.
          result.add(
            InternetAddress(
              '${parts[0]}.${parts[1]}.${parts[2]}.255',
            ),
          );
        }
      }
    } catch (_) {}
    return result;
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;

    Datagram? datagram;
    while ((datagram = socket.receive()) != null) {
      final d = datagram!;
      try {
        final map = jsonDecode(utf8.decode(d.data));
        if (map is! Map) continue;
        if (map['type'] != _type) continue;

        final action = map['action']?.toString();
        if (action == 'discover') {
          _respondToDiscovery(d.address);
          continue;
        }

        if (action == 'announce') {
          final peer = SyncPeer(
            deviceId: map['device_id']?.toString() ?? '',
            deviceName: map['device_name']?.toString() ?? 'دبیرخانه',
            host: d.address.address,
            port: (map['port'] as num?)?.toInt() ?? 39421,
            role: map['role']?.toString() ?? 'client',
          );
          if (peer.deviceId.isEmpty) continue;
          _peersController.add(peer);
        }
      } catch (_) {}
    }
  }

  Future<void> _respondToDiscovery(InternetAddress target) async {
    final socket = _socket;
    if (socket == null) return;

    final role = await AppSettings.getSyncRole();
    final packet = utf8.encode(jsonEncode({
      'type': _type,
      'action': 'announce',
      'device_id': await AppSettings.getDeviceId(),
      'device_name': await AppSettings.getSyncDeviceName(),
      'role': role,
      'port': await AppSettings.getSyncPort(),
    }));

    try {
      socket.send(packet, target, discoveryPort);
    } catch (_) {}
  }

  Future<List<SyncPeer>> discover({
    Duration timeout = const Duration(seconds: 3),
    bool mastersOnly = true,
  }) async {
    await start();
    final socket = _socket;
    if (socket == null) return [];

    final found = <String, SyncPeer>{};
    final sub = peers.listen((peer) {
      if (mastersOnly && !peer.isMaster) return;
      found[peer.deviceId] = peer;
    });

    final request = utf8.encode(jsonEncode({
      'type': _type,
      'action': 'discover',
      'device_id': await AppSettings.getDeviceId(),
    }));

    try {
      socket.send(
        request,
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
      for (final address in await _directedBroadcastAddresses()) {
        socket.send(request, address, discoveryPort);
      }
    } catch (_) {}

    await Future<void>.delayed(timeout);
    await sub.cancel();
    return found.values.toList();
  }

  void dispose() {
    _peersController.close();
    unawaited(stop());
  }
}
