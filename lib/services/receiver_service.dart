import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'settings.dart';

enum ReceiverStatus { connecting, waitingVideo, playing, ended, error }

/// Lado do Recetor: liga-se ao Host, envia o código e recebe o vídeo.
class ReceiverService extends ChangeNotifier {
  ReceiverService({required this.ip, required this.port, required this.pin});

  final String ip;
  final int port;
  final String pin;

  final RTCVideoRenderer renderer = RTCVideoRenderer();
  WebSocket? _ws;
  RTCPeerConnection? _pc;
  Timer? _statsTimer;
  Future<void> _queue = Future.value();
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteSet = false;
  bool _disposed = false;

  ReceiverStatus status = ReceiverStatus.connecting;
  String? message;
  String hostName = '';
  String hostPlatform = '';

  // Estatísticas
  double? latencyMs;
  double? fps;
  int? width;
  int? height;
  double? mbps;
  int? _lastBytes;
  double? _lastTs;

  Future<void> connect() async {
    await renderer.initialize();
    try {
      _ws = await WebSocket.connect('ws://$ip:$port').timeout(const Duration(seconds: 6));
    } catch (e) {
      _fail('Não foi possível ligar a $ip. Confirma que o Host está a partilhar e que estão na mesma rede.');
      return;
    }
    _ws!.listen(
      (data) {
        _queue = _queue.then((_) => _onMessage(data)).catchError((Object e) {
          debugPrint('Erro a processar mensagem: $e');
        });
      },
      onDone: () {
        if (status != ReceiverStatus.error && status != ReceiverStatus.ended) {
          _end('A ligação ao Host terminou.');
        }
      },
      onError: (_) => _fail('Erro na ligação ao Host.'),
      cancelOnError: true,
    );
    _send({
      'type': 'hello',
      'pin': pin,
      'name': AppSettings.deviceName,
      'platform': AppSettings.platformName,
    });
  }

  Future<void> _onMessage(dynamic data) async {
    if (data is! String) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'accepted':
        hostName = (msg['hostName'] ?? '').toString();
        hostPlatform = (msg['platform'] ?? '').toString();
        await AppSettings.addRecentHost(ip);
        status = ReceiverStatus.waitingVideo;
        _notify();
        break;
      case 'rejected':
        _fail((msg['reason'] ?? 'Ligação recusada.').toString());
        break;
      case 'offer':
        await _handleOffer(msg['sdp'] as String?);
        break;
      case 'candidate':
        final c = RTCIceCandidate(
          msg['candidate'] as String?,
          msg['sdpMid'] as String?,
          (msg['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_remoteSet && _pc != null) {
          await _pc!.addCandidate(c);
        } else {
          _pendingCandidates.add(c);
        }
        break;
      case 'kicked':
        _end('O Host desligou-te da partilha.');
        break;
      case 'bye':
        _end('O Host parou a partilha.');
        break;
    }
  }

  Future<void> _handleOffer(String? sdp) async {
    final pc = await createPeerConnection(<String, dynamic>{
      'iceServers': <dynamic>[],
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _send({
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    pc.onTrack = (event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
        status = ReceiverStatus.playing;
        _notify();
      }
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _fail('A ligação de vídeo falhou. Verifica a firewall do Windows (porta UDP).');
      }
    };
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    _remoteSet = true;
    for (final c in _pendingCandidates) {
      await pc.addCandidate(c);
    }
    _pendingCandidates.clear();
    final answer = await pc.createAnswer(<String, dynamic>{});
    await pc.setLocalDescription(answer);
    _send({'type': 'answer', 'sdp': answer.sdp});
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _collectStats());
  }

  Future<void> _collectStats() async {
    final pc = _pc;
    if (pc == null) return;
    try {
      final reports = await pc.getStats();
      for (final r in reports) {
        final v = r.values;
        if (r.type == 'inbound-rtp' && (v['kind'] == 'video' || v['mediaType'] == 'video')) {
          fps = _num(v['framesPerSecond']) ?? fps;
          width = _num(v['frameWidth'])?.toInt() ?? width;
          height = _num(v['frameHeight'])?.toInt() ?? height;
          final bytes = _num(v['bytesReceived'])?.toInt();
          final ts = r.timestamp;
          if (bytes != null) {
            if (_lastBytes != null && _lastTs != null && ts > _lastTs!) {
              // timestamp em milissegundos (formato standard do WebRTC)
              final seconds = (ts - _lastTs!) / 1000.0;
              if (seconds > 0) mbps = (bytes - _lastBytes!) * 8 / seconds / 1e6;
            }
            _lastBytes = bytes;
            _lastTs = ts;
          }
        } else if (r.type == 'candidate-pair' &&
            (v['state'] == 'succeeded' || v['nominated'] == true)) {
          final rtt = _num(v['currentRoundTripTime']);
          if (rtt != null) latencyMs = rtt * 1000 / 2; // tempo de ida na rede
        }
      }
      _notify();
    } catch (_) {}
  }

  /// Captura a imagem atual do ecrã recebido (PNG).
  Future<ByteBuffer?> captureFrame() async {
    final stream = renderer.srcObject;
    if (stream == null) return null;
    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) return null;
    return tracks.first.captureFrame();
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _ws?.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _fail(String text) {
    status = ReceiverStatus.error;
    message = text;
    _teardown();
    _notify();
  }

  void _end(String text) {
    status = ReceiverStatus.ended;
    message = text;
    _teardown();
    _notify();
  }

  void _teardown() {
    _statsTimer?.cancel();
    _statsTimer = null;
    final pc = _pc;
    _pc = null;
    pc?.close();
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    renderer.srcObject = null;
  }

  Future<void> disconnect() async {
    _send({'type': 'bye'});
    _teardown();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    renderer.dispose();
    super.dispose();
  }
}

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
