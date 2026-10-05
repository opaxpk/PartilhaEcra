import 'dart:io';

enum LinkType { cable, wifi, unknown }

extension LinkTypeLabel on LinkType {
  String get label => switch (this) {
        LinkType.cable => 'Cabo',
        LinkType.wifi => 'Wi-Fi',
        LinkType.unknown => 'Rede',
      };
}

class LocalNetwork {
  LocalNetwork(this.ip, this.interfaceName, this.type);
  final String ip;
  final String interfaceName;
  final LinkType type;
}

const _ignoredInterfaces = [
  'vethernet',
  'virtualbox',
  'vmware',
  'docker',
  'hyper-v',
  'loopback',
  'rmnet', // dados móveis no Android
  'tun',
  'tap',
  'wsl',
  'zerotier',
  'tailscale',
];

bool isPrivateIPv4(String ip) {
  final p = ip.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.any((e) => e == null)) return false;
  final a = p[0]!, b = p[1]!;
  return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
}

LinkType classifyInterface(String name) {
  final n = name.toLowerCase();
  if (n.contains('wlan') || n.contains('wi-fi') || n.contains('wifi') || n.contains('wireless')) {
    return LinkType.wifi;
  }
  if (n.contains('eth') || n.contains('ethernet') || n.startsWith('en') || n.contains('usb')) {
    return LinkType.cable;
  }
  return LinkType.unknown;
}

Future<List<LocalNetwork>> listLocalNetworks() async {
  final result = <LocalNetwork>[];
  try {
    final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in ifaces) {
      final lower = iface.name.toLowerCase();
      if (_ignoredInterfaces.any(lower.contains)) continue;
      for (final addr in iface.addresses) {
        if (!isPrivateIPv4(addr.address)) continue;
        result.add(LocalNetwork(addr.address, iface.name, classifyInterface(iface.name)));
      }
    }
  } catch (_) {}
  // Cabo primeiro, depois Wi-Fi.
  result.sort((a, b) => a.type.index.compareTo(b.type.index));
  return result;
}

Future<LocalNetwork?> getPrimaryNetwork() async {
  final list = await listLocalNetworks();
  return list.isEmpty ? null : list.first;
}

/// Endereços para onde enviar o anúncio de descoberta.
Future<List<InternetAddress>> broadcastTargets() async {
  final targets = <String>{'255.255.255.255'};
  for (final net in await listLocalNetworks()) {
    final p = net.ip.split('.');
    // Assume /24 (o caso de quase todas as redes domésticas).
    targets.add('${p[0]}.${p[1]}.${p[2]}.255');
  }
  return targets.map(InternetAddress.new).toList();
}
