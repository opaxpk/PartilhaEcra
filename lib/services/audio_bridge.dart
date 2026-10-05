import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Som do PC → recetores.
///  - Windows (Host): captura o som do sistema (código nativo, WASAPI loopback).
///  - Android (Recetor): reproduz o PCM recebido (código nativo, AudioTrack).
class AudioBridge {
  static const _events = EventChannel('partilhaecra/audio_stream');
  static const _native = MethodChannel('partilhaecra/native');

  /// Windows: 1.º evento = {'rate', 'channels'}; seguintes = blocos PCM 16-bit.
  static Stream<dynamic> loopback() => _events.receiveBroadcastStream();

  static Future<void> startPlayback({required int rate, required int channels, required int delayMs}) async {
    if (!Platform.isAndroid) return;
    try {
      await _native.invokeMethod('audioStart', {'rate': rate, 'channels': channels, 'delayMs': delayMs});
    } catch (_) {}
  }

  static void write(Uint8List pcm) {
    if (!Platform.isAndroid) return;
    _native.invokeMethod('audioWrite', pcm).catchError((Object _) => null);
  }

  static Future<void> stopPlayback() async {
    if (!Platform.isAndroid) return;
    try {
      await _native.invokeMethod('audioStop');
    } catch (_) {}
  }
}
