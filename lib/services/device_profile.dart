import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'settings.dart';

/// Informação sobre o aparelho e modo de compatibilidade de vídeo.
///
/// Alguns projetores e TV boxes (Rockchip, Amlogic, Allwinner...) têm
/// descodificadores de vídeo por hardware que crasham o WebRTC
/// ("Rendered texture metadata was null"). Nesses aparelhos a app pede ao
/// Host para usar VP8 e descodifica-o por software.
class DeviceProfile {
  static const _channel = MethodChannel('partilhaecra/native');

  static bool isTv = false;
  static String manufacturer = '';
  static String hardware = '';

  /// true = este aparelho deve receber VP8 descodificado por software.
  static bool videoCompat = false;

  static const _problemChips = ['rockchip', 'rk3', 'amlogic', 'meson', 'allwinner', 'sun50i', 'realtek'];

  static bool get chipsetNeedsCompat {
    final id = '$manufacturer $hardware'.toLowerCase();
    return _problemChips.any(id.contains);
  }

  /// Chamado no arranque, antes de qualquer uso do WebRTC.
  static Future<void> init() async {
    if (Platform.isAndroid) {
      try {
        final info = await _channel.invokeMethod<Map<dynamic, dynamic>>('deviceInfo');
        if (info != null) {
          isTv = info['isTv'] == true;
          manufacturer = (info['manufacturer'] ?? '').toString();
          hardware = '${info['hardware'] ?? ''} ${info['board'] ?? ''}';
        }
      } catch (_) {}
    }
    videoCompat = Platform.isAndroid && (AppSettings.videoCompat ?? (isTv || chipsetNeedsCompat));

    if (videoCompat) {
      try {
        // VP8 por software: evita o descodificador por hardware problemático.
        await WebRTC.initialize(options: <String, dynamic>{
          'forceSWCodecList': <String>['VP8'],
        });
      } catch (_) {}
    }
  }
}
