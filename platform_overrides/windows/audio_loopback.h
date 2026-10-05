#ifndef RUNNER_AUDIO_LOOPBACK_H_
#define RUNNER_AUDIO_LOOPBACK_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <thread>

// Captura o som que o PC está a reproduzir (WASAPI loopback) e envia-o para o
// Dart pelo EventChannel "partilhaecra/audio_stream":
//   1.º evento: mapa {"rate": int, "channels": int}
//   seguintes:  blocos PCM 16-bit intercalados (Uint8List), ~10 ms cada.
class AudioLoopback {
 public:
  // Mensagem de janela usada para entregar os blocos na thread da plataforma.
  static constexpr UINT kFlushMessage = WM_APP + 0x51;

  AudioLoopback(flutter::BinaryMessenger* messenger, HWND window);
  ~AudioLoopback();

  // Chamado na thread da plataforma (janela) quando chega kFlushMessage.
  void Flush();

 private:
  void Start();
  void Stop();
  void CaptureLoop();
  void Enqueue(flutter::EncodableValue value);

  HWND window_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  std::thread thread_;
  std::atomic<bool> running_{false};
  std::mutex mutex_;
  std::deque<flutter::EncodableValue> queue_;
};

#endif  // RUNNER_AUDIO_LOOPBACK_H_
