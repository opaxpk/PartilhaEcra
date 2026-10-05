#include "audio_loopback.h"

#include <audioclient.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <mmdeviceapi.h>
#include <mmreg.h>

#include <algorithm>
#include <utility>
#include <vector>

namespace {

template <typename T>
void SafeRelease(T** ptr) {
  if (*ptr) {
    (*ptr)->Release();
    *ptr = nullptr;
  }
}

int16_t FloatToPcm16(float v) {
  if (v > 1.0f) v = 1.0f;
  if (v < -1.0f) v = -1.0f;
  return static_cast<int16_t>(v * 32767.0f);
}

}  // namespace

AudioLoopback::AudioLoopback(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      messenger, "partilhaecra/audio_stream",
      &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* arguments,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                 events)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        sink_ = std::move(events);
        Start();
        return nullptr;
      },
      [this](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        Stop();
        sink_.reset();
        return nullptr;
      });
  channel_->SetStreamHandler(std::move(handler));
}

AudioLoopback::~AudioLoopback() { Stop(); }

void AudioLoopback::Start() {
  Stop();
  running_ = true;
  thread_ = std::thread([this]() { CaptureLoop(); });
}

void AudioLoopback::Stop() {
  running_ = false;
  if (thread_.joinable()) {
    thread_.join();
  }
  std::lock_guard<std::mutex> lock(mutex_);
  queue_.clear();
}

void AudioLoopback::Enqueue(flutter::EncodableValue value) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    queue_.push_back(std::move(value));
    // Se a interface estiver ocupada, não acumula mais de ~1 s de som.
    while (queue_.size() > 100) {
      queue_.pop_front();
    }
  }
  PostMessage(window_, kFlushMessage, 0, 0);
}

void AudioLoopback::Flush() {
  std::deque<flutter::EncodableValue> items;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    items.swap(queue_);
  }
  if (!sink_) return;
  for (auto& item : items) {
    sink_->Success(item);
  }
}

void AudioLoopback::CaptureLoop() {
  const HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool com_ready = SUCCEEDED(init);

  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  IAudioClient* client = nullptr;
  IAudioCaptureClient* capture = nullptr;
  WAVEFORMATEX* mix = nullptr;

  do {
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                reinterpret_cast<void**>(&enumerator)))) {
      break;
    }
    if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole,
                                                   &device))) {
      break;
    }
    if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                reinterpret_cast<void**>(&client)))) {
      break;
    }
    if (FAILED(client->GetMixFormat(&mix))) {
      break;
    }
    // 100 ms de buffer interno (unidades de 100 ns).
    const REFERENCE_TIME buffer_duration = 1000000;
    if (FAILED(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                  AUDCLNT_STREAMFLAGS_LOOPBACK,
                                  buffer_duration, 0, mix, nullptr))) {
      break;
    }
    if (FAILED(client->GetService(__uuidof(IAudioCaptureClient),
                                  reinterpret_cast<void**>(&capture)))) {
      break;
    }

    bool is_float = mix->wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
    if (mix->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
      const auto* ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(mix);
      // KSDATAFORMAT_SUBTYPE_IEEE_FLOAT = {00000003-0000-0010-8000-00aa00389b71}
      is_float = ext->SubFormat.Data1 == 3;
    }
    const int bits = static_cast<int>(mix->wBitsPerSample);
    const int in_channels = static_cast<int>(mix->nChannels);
    const int out_channels = in_channels >= 2 ? 2 : 1;
    const int rate = static_cast<int>(mix->nSamplesPerSec);

    flutter::EncodableMap format;
    format[flutter::EncodableValue("rate")] = flutter::EncodableValue(rate);
    format[flutter::EncodableValue("channels")] =
        flutter::EncodableValue(out_channels);
    Enqueue(flutter::EncodableValue(format));

    if (FAILED(client->Start())) {
      break;
    }

    while (running_) {
      Sleep(10);
      UINT32 packet_frames = 0;
      while (running_ &&
             SUCCEEDED(capture->GetNextPacketSize(&packet_frames)) &&
             packet_frames > 0) {
        BYTE* data = nullptr;
        UINT32 frames = 0;
        DWORD flags = 0;
        if (FAILED(capture->GetBuffer(&data, &frames, &flags, nullptr,
                                      nullptr))) {
          break;
        }
        std::vector<uint8_t> out(static_cast<size_t>(frames) *
                                 static_cast<size_t>(out_channels) * 2u);
        auto* dst = reinterpret_cast<int16_t*>(out.data());
        if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) == 0 && data != nullptr) {
          for (UINT32 f = 0; f < frames; ++f) {
            for (int c = 0; c < out_channels; ++c) {
              const size_t i = static_cast<size_t>(f) *
                                   static_cast<size_t>(in_channels) +
                               static_cast<size_t>(c);
              int16_t sample = 0;
              if (is_float && bits == 32) {
                sample = FloatToPcm16(reinterpret_cast<const float*>(data)[i]);
              } else if (bits == 16) {
                sample = reinterpret_cast<const int16_t*>(data)[i];
              } else if (bits == 32) {
                sample = static_cast<int16_t>(
                    reinterpret_cast<const int32_t*>(data)[i] >> 16);
              } else if (bits == 24) {
                const BYTE* p = data + i * 3u;
                const int32_t v = static_cast<int32_t>(
                    (static_cast<uint32_t>(p[0]) << 8) |
                    (static_cast<uint32_t>(p[1]) << 16) |
                    (static_cast<uint32_t>(p[2]) << 24));
                sample = static_cast<int16_t>(v >> 16);
              }
              dst[static_cast<size_t>(f) * static_cast<size_t>(out_channels) +
                  static_cast<size_t>(c)] = sample;
            }
          }
        }
        capture->ReleaseBuffer(frames);
        if (!out.empty()) {
          Enqueue(flutter::EncodableValue(std::move(out)));
        }
      }
    }
    client->Stop();
  } while (false);

  SafeRelease(&capture);
  SafeRelease(&client);
  SafeRelease(&device);
  SafeRelease(&enumerator);
  if (mix) {
    CoTaskMemFree(mix);
  }
  if (com_ready) {
    CoUninitialize();
  }
}
