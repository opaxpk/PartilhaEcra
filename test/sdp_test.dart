import 'package:flutter_test/flutter_test.dart';
import 'package:partilha_ecra/services/host_service.dart';

void main() {
  const sdp = 'v=0\r\n'
      'm=video 9 UDP/TLS/RTP/SAVPF 96 102\r\n'
      'c=IN IP4 0.0.0.0\r\n'
      'a=rtpmap:96 VP8/90000\r\n'
      'a=rtpmap:102 H264/90000\r\n'
      'a=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1\r\n';

  test('acrescenta limites de débito ao vídeo', () {
    final out = withBitrateHints(sdp, 20000);
    expect(out, contains('a=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1;x-google-start-bitrate=12000'));
    expect(out, contains('a=fmtp:96 x-google-start-bitrate=12000;x-google-min-bitrate=4000;x-google-max-bitrate=20000'));
    expect(out, contains('b=AS:20000'));
    expect(out.split('\r\n').where((l) => l.startsWith('a=fmtp:96')).length, 1);
  });

  test('SDP vazio fica igual', () {
    expect(withBitrateHints('', 8000), '');
  });
}
