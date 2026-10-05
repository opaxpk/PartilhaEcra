import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'settings.dart';

/// Informação sobre o aparelho e a forma de descodificar o vídeo.
///
/// Alguns projetores e TV boxes (Rockchip, Amlogic, Allwinner...) crasham o WebRTC
/// quando o descodificador por hardware entrega as imagens por "textura"
/// ("Rendered texture metadata was null"). Três modos:
///  - hardware normal (telemóveis/PCs): textura, o mais eficiente;
///  - hardware "em memória" (projetores, automático): continua a ser o chip a
///    descodificar — imagem nítida e leve — mas sem o caminho que crasha;
///  - software (VP8): último recurso, mais pesado para o aparelho.
class DeviceProfile {
  static const _channel = MethodChannel('partilhaecra/native');

  static bool isTv = false;
  static String manufacturer = '';
  static String hardware = '';

  /// Descodificação por software (VP8). Último recurso.
  static bool videoCompat = false;

  /// Descodificação por hardware a entregar imagens em memória (projetores/TV boxes).
  static bool hwByteBuffer = false;

  static const _problemChips = ['rockchip', 'rk3', 'amlogic', 'meson', 'allwinner', 'sun50i', 'realtek'];

  static bool get chipsetNeedsCare {
    final id = '$manufacturer $hardware'.toLowerCase();
    return _problemChips.any(id.contains);
  }

  /// Aparelho fraco (projetor/TV box): limita fps e débito.
  static bool get lowPower => videoCompat || hwByteBuffer;

  /// Chamado no arranque, antes de qualquer uso do WebRTC.
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await _channel.invokeMethod<Map<dynamic, dynamic>>('deviceInfo');
      if (info != null) {
        isTv = info['isTv'] == true;
        manufacturer = (info['manufacturer'] ?? '').toString();
        hardware = '${info['hardware'] ?? ''} ${info['board'] ?? ''}';
      }
    } catch (_) {}

    final mode = AppSettings.decoderMode;
    // Projetores/TV boxes: em "Automático" usa Software — o descodificador por hardware
    // destes chips (ex.: Rockchip) entrega imagens num formato que o WebRTC lê mal
    // (imagem verde/riscada) ou crasha. Hardware fica como opção manual.
    final weakDevice = isTv || chipsetNeedsCare;
    videoCompat = mode == 'sw' || (mode == 'auto' && weakDevice);
    hwByteBuffer = mode == 'hw' && weakDevice;

    try {
      await _channel.invokeMethod('setHwByteBuffer', hwByteBuffer);
    } catch (_) {}

    try {
      await WebRTC.initialize(options: <String, dynamic>{
        // Software: VP8 sem o descodificador do chip.
        if (videoCompat) 'forceSWCodecList': <String>['VP8'],
      });
    } catch (_) {}
  }

  static String get modeLabel => videoCompat
      ? 'Software (VP8)'
      : hwByteBuffer
          ? 'Hardware (experimental)'
          : 'Hardware';
}
