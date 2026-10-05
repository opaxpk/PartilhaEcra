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
    required this.validFor,
  });

  final String id;
  String name;
  String platform;
  String ip;
  int port;
  String link;
  bool sharing;
  DateTime lastSeen;

  /// Tempo durante o qual o dispositivo continua na lista sem novo sinal.
  Duration validFor;
}

/// Mensagem de anúncio do Host (usada no broadcast, multicast e em /info).
Map<String, dynamic> buildAnnouncement(LinkType link) => {
      'app': kProtocolId,
      'id': AppSettings.deviceId,
      'name': AppSettings.deviceName,
      'platform': AppSettings.platformName,
      'port': kSignalPort,
      'link': link.label,
      'sharing': true,
    };

/// Anuncia este dispositivo (quando é Host) por broadcast e multicast UDP a cada segundo.
class DiscoveryBroadcaster {
  RawDatagramSocket? _socket;
  Timer? _timer;
  LinkType link = LinkType.unknown;

  Future<void> start() async {
    await stop();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;
    _socket!.multicastHops = 4;
    link = (await getPrimaryNetwork())?.type ?? LinkType.unknown;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _send());
    _send();
  }

  Future<void> _send() async {
    final socket = _socket;
    if (socket == null) return;
    final payload = utf8.encode(jsonEncode(buildAnnouncement(link)));
    final targets = [...await broadcastTargets(), InternetAddress(kMulticastGroup)];
    for (final target in targets) {
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

/// Encontra Hosts na rede. Partilhado por todos os ecrãs (contagem de referências).
///
/// Usa três métodos, porque algumas extensões/repetidores Wi-Fi bloqueiam o broadcast:
///  1. broadcast UDP, 2. multicast UDP, 3. procura direta em todos os IPs da sub-rede.
class DiscoveryListener {
  DiscoveryListener._();
  static final DiscoveryListener instance = DiscoveryListener._();

  final _devices = <String, DiscoveredDevice>{};
  final _controller = StreamController<List<DiscoveredDevice>>.broadcast();
  RawDatagramSocket? _socket;
  Timer? _pruneTimer;
  Timer? _scanTimer;
  int _refs = 0;
  bool scanning = false;
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
      try {
        _socket!.joinMulticast(InternetAddress(kMulticastGroup));
      } catch (_) {}
      _socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _socket?.receive();
        if (dg == null) return;
        try {
          final data = jsonDecode(utf8.decode(dg.data));
          if (data is Map) _upsert(data, dg.address.address, const Duration(seconds: 4));
        } catch (_) {}
      });
    } catch (e) {
      error = 'Não foi possível escutar a rede: $e';
    }
    _pruneTimer = Timer.periodic(const Duration(seconds: 1), (_) => _prune());
    _scanTimer = Timer.periodic(const Duration(seconds: 12), (_) => scanSubnet());
    _emit();
    // Primeira procura direta logo ao abrir.
    unawaited(scanSubnet());
  }

  void _upsert(Map<dynamic, dynamic> data, String ip, Duration validFor) {
    if (data['app'] != kProtocolId) return;
    final id = data['id'] as String?;
    if (id == null || id == AppSettings.deviceId) return;
    final device = _devices[id];
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
        validFor: validFor,
      );
    } else {
      device
        ..name = (data['name'] ?? device.name).toString()
        ..ip = ip
        ..port = (data['port'] as num?)?.toInt() ?? device.port
        ..link = (data['link'] ?? device.link).toString()
        ..sharing = data['sharing'] == true
        ..lastSeen = DateTime.now()
        ..validFor = validFor > device.validFor ? validFor : device.validFor;
    }
    _emit();
  }

  /// Pergunta diretamente a cada IP da sub-rede (/24) se é um Host da PartilhaEcra.
  Future<void> scanSubnet() async {
    if (scanning || _refs == 0) return;
    scanning = true;
    _emit();
    try {
      final nets = await listLocalNetworks();
      final own = nets.map((n) => n.ip).toSet();
      final prefixes = <String>{
        ...nets.map((n) => n.ip.substring(0, n.ip.lastIndexOf('.'))),
        // Extensões Wi-Fi em modo "router" criam outra sub-rede; procura também nas
        // gamas mais usadas pelos routers e nas dos Hosts a que já te ligaste.
        if (nets.any((n) => n.ip.startsWith('192.168.'))) ...['192.168.0', '192.168.1'],
        ...AppSettings.recentHosts.map((ip) => ip.substring(0, ip.lastIndexOf('.'))),
      };
      final targets = <String>[
        // Hosts conhecidos primeiro: aparecem logo.
        ...AppSettings.recentHosts.where((ip) => !own.contains(ip)),
        for (final p in prefixes)
          for (var i = 1; i < 255; i++)
            if (!own.contains('$p.$i') && !AppSettings.recentHosts.contains('$p.$i')) '$p.$i',
      ];
      const batch = 64;
      for (var i = 0; i < targets.length && _refs > 0; i += batch) {
        final slice = targets.sublist(i, (i + batch).clamp(0, targets.length));
        await Future.wait(slice.map(_probe));
      }
    } catch (_) {
    } finally {
      scanning = false;
      _emit();
    }
  }

  Future<void> _probe(String ip) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 700);
    try {
      final req = await client.get(ip, kSignalPort, '/info').timeout(const Duration(milliseconds: 900));
      final res = await req.close().timeout(const Duration(milliseconds: 900));
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 1));
      final data = jsonDecode(body);
      if (data is Map) _upsert(data, ip, const Duration(seconds: 30));
    } catch (_) {
      // Ninguém nesse IP.
    } finally {
      client.close(force: true);
    }
  }

  void _prune() {
    final now = DateTime.now();
    final before = _devices.length;
    _devices.removeWhere((_, d) => now.difference(d.lastSeen) > d.validFor);
    if (_devices.length != before) _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(devices);
  }

  Future<void> _stop() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _socket?.close();
    _socket = null;
    _devices.clear();
    await NativeBridge.releaseMulticastLock();
  }
}
