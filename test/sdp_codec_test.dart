import 'package:flutter_test/flutter_test.dart';
import 'package:partilha_ecra/services/receiver_service.dart';

void main() {
  const offer = 'v=0\r\n'
      'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
      'a=rtpmap:111 opus/48000/2\r\n'
      'm=video 9 UDP/TLS/RTP/SAVPF 102 103 96 97\r\n'
      'a=rtpmap:102 H264/90000\r\n'
      'a=rtcp-fb:102 nack\r\n'
      'a=fmtp:102 packetization-mode=1\r\n'
      'a=rtpmap:103 rtx/90000\r\n'
      'a=fmtp:103 apt=102\r\n'
      'a=rtpmap:96 VP8/90000\r\n'
      'a=rtpmap:97 rtx/90000\r\n'
      'a=fmtp:97 apt=96\r\n';

  test('remove H264 e o RTX associado', () {
    final out = removeVideoCodecs(offer, {'H264'});
    expect(out, contains('m=video 9 UDP/TLS/RTP/SAVPF 96 97'));
    expect(out, isNot(contains('H264')));
    expect(out, isNot(contains('apt=102')));
    expect(out, contains('a=rtpmap:96 VP8/90000'));
    expect(out, contains('a=rtpmap:111 opus/48000/2'));
  });

  test('não remove se ficar sem codecs', () {
    const only = 'm=video 9 UDP/TLS/RTP/SAVPF 102\r\na=rtpmap:102 H264/90000\r\n';
    expect(removeVideoCodecs(only, {'H264'}), only);
  });
}
