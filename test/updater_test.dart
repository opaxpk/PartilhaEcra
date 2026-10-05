import 'package:flutter_test/flutter_test.dart';
import 'package:partilha_ecra/services/network_info.dart';
import 'package:partilha_ecra/services/updater.dart';

void main() {
  group('Updater.isNewer', () {
    test('deteta versões mais recentes', () {
      expect(Updater.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(Updater.isNewer('1.1.0', '1.0.9'), isTrue);
      expect(Updater.isNewer('2.0.0', '1.9.9'), isTrue);
    });

    test('ignora versões iguais ou antigas', () {
      expect(Updater.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(Updater.isNewer('1.0.0', '1.0.1'), isFalse);
      expect(Updater.isNewer('1.0', '1.0.0'), isFalse);
    });
  });

  group('network_info', () {
    test('IPs privados', () {
      expect(isPrivateIPv4('192.168.1.10'), isTrue);
      expect(isPrivateIPv4('10.0.0.5'), isTrue);
      expect(isPrivateIPv4('172.20.1.1'), isTrue);
      expect(isPrivateIPv4('8.8.8.8'), isFalse);
    });

    test('tipo de ligação', () {
      expect(classifyInterface('wlan0'), LinkType.wifi);
      expect(classifyInterface('Wi-Fi'), LinkType.wifi);
      expect(classifyInterface('Ethernet'), LinkType.cable);
      expect(classifyInterface('eth0'), LinkType.cable);
    });
  });
}
