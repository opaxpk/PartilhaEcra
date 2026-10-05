import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'device_profile.dart';
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

  // --- Adaptação automática ao desempenho deste aparelho ---
  /// Degraus de resolução (lado mais curto) usados quando o aparelho não aguenta.
  static const _levels = [1440, 1080, 900, 720, 540, 480];
  late int _initialMaxHeight;
  late int maxHeight;
  late int maxFps;
  int? _lastDecoded;
  int? _lastDropped;
  double? _lastDecodeTime;
  int _badWindows = 0;

  /// Resolução que já se provou demasiado pesada: não volta a subir até lá.
  int? _ceiling;
  int _goodWindows = 0;
  DateTime _lastAdjust = DateTime.fromMillisecondsSinceEpoch(0);

  /// Escala que o Host está a aplicar ao vídeo deste recetor (1.0 = original).
  double _hostScale = 1.0;
  DateTime _hostScaleChangedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Lado curto do ecrã original do Host, deduzido a partir do que chega.
  int? _sourceShort;

  /// Tempo médio de descodificação por imagem (ms) — para mostrar e para adaptar.
  double? decodeMs;

  /// true quando a resolução foi baixada automaticamente para este aparelho.
  bool get adapted => maxHeight < _initialMaxHeight;

  /// Limites que este aparelho pede ao Host.
  void _computeLimits() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize;
    final screenShort = size.isEmpty ? 1080 : size.shortestSide.round();
    if (DeviceProfile.videoCompat) {
      // Projetores/TV boxes: VP8 por software — até 1080p a 30 fps.
      _initialMaxHeight = screenShort.clamp(480, 1080);
      maxFps = 30;
      // Começa em 720p (o que estes aparelhos aguentam por software); sobe se houver folga.
      maxHeight = _initialMaxHeight < 720 ? _initialMaxHeight : 720;
    } else {
      _initialMaxHeight = screenShort.clamp(720, 2160);
      maxFps = 60;
      maxHeight = _initialMaxHeight;
    }
  }

  Future<void> connect() async {
    _computeLimits();
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
      // Codec que este aparelho descodifica melhor (VP8 em projetores/TV boxes).
      'codec': DeviceProfile.videoCompat ? 'VP8' : 'H264',
      // O que este aparelho consegue mostrar: o Host não envia mais do que isto.
      'maxHeight': maxHeight,
      'maxFps': maxFps,
      if (DeviceProfile.videoCompat) 'maxBitrate': 6000000,
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
      case 'sourceChanged':
        // O Host trocou de ecrã/janela: volta a medir o tamanho original.
        _sourceShort = null;
        _hostScale = 1.0;
        _hostScaleChangedAt = DateTime.now();
        break;
      case 'encoding':
        _hostScale = (msg['scale'] as num?)?.toDouble() ?? _hostScale;
        _hostScaleChangedAt = DateTime.now();
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
    // Modo de compatibilidade: retira o H.264 da proposta para forçar VP8 por software
    // (funciona mesmo com Hosts em versões antigas).
    final offerSdp = DeviceProfile.videoCompat ? removeVideoCodecs(sdp ?? '', {'H264'}) : sdp;
    await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
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
          _adapt(
            decoded: _num(v['framesDecoded'])?.toInt(),
            dropped: _num(v['framesDropped'])?.toInt(),
            decodeTime: _num(v['totalDecodeTime']),
          );
          width = _num(v['frameWidth'])?.toInt() ?? width;
          height = _num(v['frameHeight'])?.toInt() ?? height;
          _trackSourceSize();
          final bytes = _num(v['bytesReceived'])?.toInt();
          final ts = r.timestamp;
          if (bytes != null) {
            if (_lastBytes != null && _lastTs != null && ts > _lastTs!) {
              // timestamp em milissegundos (formato standard do WebRTC)
              // O timestamp pode vir em microssegundos (Android/Windows) ou milissegundos.
              final delta = ts - _lastTs!;
              final seconds = delta > 100000 ? delta / 1e6 : delta / 1000.0;
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

  /// Mede o desempenho da descodificação (janela de 1 s) e pede ao Host para
  /// baixar/subir a resolução. Só olha para o tempo de descodificação e imagens
  /// perdidas — um ecrã parado envia poucas imagens e isso não é um problema.
  void _adapt({int? decoded, int? dropped, double? decodeTime}) {
    if (decoded == null) return;
    final dDecoded = _lastDecoded == null ? 0 : decoded - _lastDecoded!;
    final dDropped = (dropped != null && _lastDropped != null) ? dropped - _lastDropped! : 0;
    final dTime = (decodeTime != null && _lastDecodeTime != null) ? decodeTime - _lastDecodeTime! : null;
    _lastDecoded = decoded;
    _lastDropped = dropped;
    _lastDecodeTime = decodeTime;
    if (dDecoded < 5) return; // pouco movimento: nada a medir

    final budgetMs = 1000 / maxFps;
    if (dTime != null) decodeMs = dTime * 1000 / dDecoded;
    final dropRatio = dDropped / (dDecoded + dDropped);
    final struggling = (decodeMs != null && decodeMs! > budgetMs * 0.85) || dropRatio > 0.08;
    final relaxed = (decodeMs == null || decodeMs! < budgetMs * 0.45) && dropRatio < 0.01;

    if (struggling) {
      _badWindows++;
      _goodWindows = 0;
    } else if (relaxed) {
      _goodWindows++;
      _badWindows = 0;
    } else {
      _badWindows = 0;
      _goodWindows = 0;
    }

    final cooledDown = DateTime.now().difference(_lastAdjust) > const Duration(seconds: 6);
    if (_badWindows >= 3 && cooledDown) {
      final lower = _levels.where((l) => l < maxHeight).firstOrNull;
      if (lower != null) {
        _ceiling = maxHeight;
        _requestLimits(lower);
      }
      _badWindows = 0;
    } else if (_goodWindows >= 30 && cooledDown && maxHeight < _initialMaxHeight) {
      final higher = _levels.reversed
          .where((l) => l > maxHeight && l <= _initialMaxHeight && (_ceiling == null || l < _ceiling!))
          .firstOrNull;
      if (higher != null) _requestLimits(higher);
      _goodWindows = 0;
    }
  }

  /// Deduz o tamanho original do ecrã do Host: imagem recebida × escala aplicada.
  void _trackSourceSize() {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return;
    // Depois de uma mudança de escala, espera que as imagens já venham no novo tamanho.
    if (DateTime.now().difference(_hostScaleChangedAt) < const Duration(seconds: 3)) return;
    final estimate = ((w < h ? w : h) * _hostScale).round();
    if (estimate > (_sourceShort ?? 0) + 8) {
      _sourceShort = estimate;
      // Primeira vez (ou ecrã maior): ajusta logo ao limite atual.
      if (estimate / _hostScale > maxHeight * 1.05) _requestLimits(maxHeight);
    }
  }

  void _requestLimits(int height) {
    maxHeight = height;
    _lastAdjust = DateTime.now();
    final src = _sourceShort;
    final scale = (src == null || src <= height) ? 1.0 : src / height;
    _send({'type': 'adjust', 'maxHeight': maxHeight, 'maxFps': maxFps, 'scale': scale});
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

/// Remove codecs de vídeo (e os respetivos RTX) de um SDP. Mantém o SDP intacto
/// se isso deixasse o vídeo sem nenhum codec.
String removeVideoCodecs(String sdp, Set<String> codecNames) {
  if (sdp.isEmpty) return sdp;
  final nl = sdp.contains('\r\n') ? '\r\n' : '\n';
  final lines = sdp.split(nl);
  final names = codecNames.map((e) => e.toUpperCase()).toSet();

  final remove = <String>{};
  var inVideo = false;
  for (final l in lines) {
    if (l.startsWith('m=')) inVideo = l.startsWith('m=video');
    if (!inVideo) continue;
    final m = RegExp(r'^a=rtpmap:(\d+) ([^/]+)/').firstMatch(l);
    if (m != null && names.contains(m.group(2)!.toUpperCase())) remove.add(m.group(1)!);
  }
  if (remove.isEmpty) return sdp;
  // RTX associado (a=fmtp:97 apt=96).
  inVideo = false;
  for (final l in lines) {
    if (l.startsWith('m=')) inVideo = l.startsWith('m=video');
    if (!inVideo) continue;
    final m = RegExp(r'^a=fmtp:(\d+) apt=(\d+)').firstMatch(l);
    if (m != null && remove.contains(m.group(2))) remove.add(m.group(1)!);
  }

  final out = <String>[];
  inVideo = false;
  for (final l in lines) {
    if (l.startsWith('m=')) {
      inVideo = l.startsWith('m=video');
      if (inVideo) {
        final parts = l.split(' ');
        final kept = [...parts.take(3), ...parts.skip(3).where((pt) => !remove.contains(pt))];
        if (kept.length <= 3) return sdp; // não sobraria nenhum codec
        out.add(kept.join(' '));
        continue;
      }
    }
    if (inVideo) {
      final m = RegExp(r'^a=(rtpmap|fmtp|rtcp-fb):(\d+)').firstMatch(l);
      if (m != null && remove.contains(m.group(2))) continue;
    }
    out.add(l);
  }
  return out.join(nl);
}

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
