import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Qualidade da transmissão (controla o débito e a escala de resolução).
enum StreamQuality { auto, economy, max }

extension StreamQualityInfo on StreamQuality {
  String get label => switch (this) {
        StreamQuality.auto => 'Auto',
        StreamQuality.economy => 'Poupança',
        StreamQuality.max => 'Máxima',
      };

  /// Débito máximo em bits por segundo.
  int get maxBitrate => switch (this) {
        StreamQuality.auto => 8000000,
        StreamQuality.economy => 3000000,
        StreamQuality.max => 20000000,
      };

  /// Débito mínimo em bits por segundo (evita que a imagem caia para baixa resolução).
  int get minBitrate => switch (this) {
        StreamQuality.auto => 1500000,
        StreamQuality.economy => 500000,
        StreamQuality.max => 4000000,
      };

  /// Fator de redução da resolução (1.0 = resolução nativa).
  double get scaleDown => switch (this) {
        StreamQuality.auto => 1.0,
        StreamQuality.economy => 1.5,
        StreamQuality.max => 1.0,
      };
}

class AppSettings {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    if (_p.getString('deviceId') == null) {
      await _p.setString('deviceId', _randomHex(12));
    }
    if ((_p.getString('deviceName') ?? '').trim().isEmpty) {
      await _p.setString('deviceName', _defaultName());
    }
  }

  static String get deviceId => _p.getString('deviceId')!;

  static String get deviceName => _p.getString('deviceName')!;
  static Future<void> setDeviceName(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    await _p.setString('deviceName', clean.length > 40 ? clean.substring(0, 40) : clean);
  }

  static StreamQuality get quality =>
      StreamQuality.values[(_p.getInt('quality') ?? 0).clamp(0, StreamQuality.values.length - 1)];
  static Future<void> setQuality(StreamQuality q) => _p.setInt('quality', q.index);

  /// true = otimizar para vídeos (fluidez primeiro); false = texto/documentos (nitidez primeiro).
  static bool get optimizeForVideo => _p.getBool('optimizeForVideo') ?? true;
  static Future<void> setOptimizeForVideo(bool v) => _p.setBool('optimizeForVideo', v);

  static int get fps => _p.getInt('fps') ?? 60;
  static Future<void> setFps(int v) => _p.setInt('fps', v);

  /// IPs de Hosts a que este dispositivo já se ligou (para os voltar a encontrar
  /// mesmo quando estão noutra sub-rede, ex.: atrás de uma extensão Wi-Fi).
  static List<String> get recentHosts => _p.getStringList('recentHosts') ?? const [];
  static Future<void> addRecentHost(String ip) async {
    final list = [ip, ...recentHosts.where((e) => e != ip)].take(6).toList();
    await _p.setStringList('recentHosts', list);
  }

  /// Descodificação de vídeo neste aparelho: 'auto', 'hw' (hardware) ou 'sw' (software).
  static String get decoderMode {
    final v = _p.getString('decoderMode');
    return (v == 'hw' || v == 'sw') ? v! : 'auto';
  }

  static Future<void> setDecoderMode(String v) => _p.setString('decoderMode', v);

  /// (Antigo) Modo de compatibilidade de vídeo — já não é usado.
  static bool? get videoCompat => _p.getBool('videoCompat');
  static Future<void> setVideoCompat(bool? v) async {
    if (v == null) {
      await _p.remove('videoCompat');
    } else {
      await _p.setBool('videoCompat', v);
    }
  }

  static bool get autoCheckUpdates => _p.getBool('autoCheckUpdates') ?? true;
  static Future<void> setAutoCheckUpdates(bool v) => _p.setBool('autoCheckUpdates', v);

  /// Versão que o utilizador escolheu ignorar no aviso de atualização.
  static String? get skippedVersion => _p.getString('skippedVersion');
  static Future<void> setSkippedVersion(String v) => _p.setString('skippedVersion', v);

  static String get platformName => Platform.isAndroid
      ? 'Android'
      : Platform.isWindows
          ? 'Windows'
          : Platform.operatingSystem;

  static String _defaultName() {
    if (Platform.isWindows) {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return host;
    }
    return '$platformName-${_randomHex(4).toUpperCase()}';
  }

  static String _randomHex(int length) {
    final r = Random.secure();
    const chars = '0123456789abcdef';
    return List.generate(length, (_) => chars[r.nextInt(16)]).join();
  }
}
