import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'native_bridge.dart';

class CaptureCancelled implements Exception {
  @override
  String toString() => 'A partilha foi cancelada.';
}

class CaptureHelper {
  /// Lista ecrãs e janelas disponíveis (só Windows).
  static Future<List<DesktopCapturerSource>> desktopSources() {
    return desktopCapturer.getSources(
      types: [SourceType.Screen, SourceType.Window],
      thumbnailSize: ThumbnailSize(320, 180),
    );
  }

  /// Captura o ecrã. No Windows pode receber uma fonte específica (ecrã ou janela).
  static Future<MediaStream> captureScreen({
    DesktopCapturerSource? source,
    int fps = 60,
  }) async {
    if (Platform.isAndroid) {
      final granted = await Helper.requestCapturePermission();
      if (!granted) throw CaptureCancelled();
      // O Android 14+ exige um serviço em primeiro plano ativo antes de capturar.
      await NativeBridge.startCaptureService();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      try {
        return await navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
          'video': true,
          'audio': false,
        });
      } catch (e) {
        await NativeBridge.stopCaptureService();
        rethrow;
      }
    }

    if (Platform.isWindows) {
      var chosen = source;
      if (chosen == null) {
        final sources = await desktopSources();
        final screens = sources.where((s) => s.type == SourceType.Screen).toList();
        if (screens.isEmpty) throw Exception('Nenhum ecrã encontrado.');
        chosen = screens.first;
      }
      return navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
        'video': {
          'deviceId': {'exact': chosen.id},
          'mandatory': {'frameRate': fps.toDouble()},
        },
        'audio': false,
      });
    }

    throw UnsupportedError('Plataforma não suportada.');
  }
}
