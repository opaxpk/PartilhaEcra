import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config.dart';
import 'native_bridge.dart';
import 'network_info.dart';
import 'settings.dart';

class DiscoveredDevice {
  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.ip,
    required this.port,
    required this.link,
    required this.sharing,
    required this.lastSeen,
  });

  final String id;
  String name;
  String platform;
  String ip;
  int port;
  String link;
  bool sharing;
  DateTime lastSeen;
}

/// Anuncia este dispositivo (quando é Host) por broadcast UDP a cada segundo.
class DiscoveryBroadcaster {
  RawDatagramSocket? _socket;
  Timer? _timer;
  LinkType _link = LinkType.unknown;

  Future<void> start() async {
    await stop();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;
    _link = (await getPrimaryNetwork())?.type ?? LinkType.unknown;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _send());
    _send();
  }

  Future<void> _send() async {
    final socket = _socket;
    if (socket == null) return;
    final payload = utf8.encode(jsonEncode({
      'app': kProtocolId,
      'id': AppSettings.deviceId,
      'name': AppSettings.deviceName,
      'platform': AppSettings.platformName,
      'port': kSignalPort,
      'link': _link.label,
      'sharing': true,
    }));
    for (final target in await broadcastTargets()) {
      try {
        socket.send(payload, target, kDiscoveryPort);
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// Escuta anúncios de Hosts na rede. Partilhado por todos os ecrãs (contagem de referências).
class DiscoveryListener {
  DiscoveryListener._();
  static final DiscoveryListener instance = DiscoveryListener._();

  final _devices = <String, DiscoveredDevice>{};
  final _controller = StreamController<List<DiscoveredDevice>>.broadcast();
  RawDatagramSocket? _socket;
  Timer? _pruneTimer;
  int _refs = 0;
  String? error;

  Stream<List<DiscoveredDevice>> get stream => _controller.stream;
  List<DiscoveredDevice> get devices {
    final list = _devices.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<void> acquire() async {
    _refs++;
    if (_refs == 1) await _start();
  }

  Future<void> release() async {
    _refs = (_refs - 1).clamp(0, 1 << 30);
    if (_refs == 0) await _stop();
  }

  Future<void> _start() async {
    error = null;
    await NativeBridge.acquireMulticastLock();
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kDiscoveryPort,
        reuseAddress: true,
      );
      _socket!.broadcastEnabled = true;
      _socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _socket?.receive();
        if (dg != null) _handle(dg);
      });
    } catch (e) {
      error = 'Não foi possível escutar a rede: $e';
    }
    _pruneTimer = Timer.periodic(const Duration(seconds: 1), (_) => _prune());
    _emit();
  }

  void _handle(Datagram dg) {
    try {
      final data = jsonDecode(utf8.decode(dg.data));
      if (data is! Map || data['app'] != kProtocolId) return;
      final id = data['id'] as String?;
      if (id == null || id == AppSettings.deviceId) return;
      final device = _devices[id];
      final ip = dg.address.address;
      if (device == null) {
        _devices[id] = DiscoveredDevice(
          id: id,
          name: (data['name'] ?? 'Dispositivo').toString(),
          platform: (data['platform'] ?? '').toString(),
          ip: ip,
          port: (data['port'] as num?)?.toInt() ?? kSignalPort,
          link: (data['link'] ?? '').toString(),
          sharing: data['sharing'] == true,
          lastSeen: DateTime.now(),
        );
      } else {
        device
          ..name = (data['name'] ?? device.name).toString()
          ..ip = ip
          ..port = (data['port'] as num?)?.toInt() ?? device.port
          ..link = (data['link'] ?? device.link).toString()
          ..sharing = data['sharing'] == true
          ..lastSeen = DateTime.now();
      }
      _emit();
    } catch (_) {}
  }

  void _prune() {
    final now = DateTime.now();
    final before = _devices.length;
    _devices.removeWhere((_, d) => now.difference(d.lastSeen) > const Duration(seconds: 4));
    if (_devices.length != before) _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(devices);
  }

  Future<void> _stop() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _devices.clear();
    await NativeBridge.releaseMulticastLock();
  }
}
