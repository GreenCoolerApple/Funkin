#define WIN32_LEAN_AND_MEAN // Excludes rarely-used APIs, reducing compile time and binary size.
#define NOMINMAX // Prevents Windows from defining min() and max() macros, which can conflict with standard C++ functions.

#include <windows.h>
#include <objbase.h>
#include <objidl.h>
#include <GL/gl.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <audioclientactivationparams.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "videorecorder.hpp"

#ifdef VIDEORECORDER_DEBUG
#include <cstdio>
#define VR_LOG(...) std::fprintf(stderr, __VA_ARGS__)
#else
#define VR_LOG(...)
#endif

#ifndef GL_BGRA
#define GL_BGRA 0x80E1
#endif

namespace
{
  /**
   * One captured frame, waiting to be encoded.
   */
  struct Frame
  {
    // 4 bytes per pixel (blue, green, red, unused), with the bottom row first.
    std::vector<uint8_t> pixels;
    int width = 0;
    int height = 0;
    // When the frame was captured, in 100 nanosecond units since recording started.
    LONGLONG timestamp = 0;
  };

  // If the encoder falls behind by more than this many frames, new frames are dropped.
  // This is about a quarter of a second at 30 frames per second, so it is raised for higher frame rates.
  const size_t MAX_QUEUED_FRAMES = 16;

  // The sound is recorded as 16-bit stereo, which is encoded to AAC.
  const int AUDIO_SAMPLE_RATE = 48000;
  const int AUDIO_CHANNELS = 2;
  const int AUDIO_BYTES_PER_FRAME = AUDIO_CHANNELS * 2;
  // The AAC encoder works on blocks of 1024 samples.
  const int AUDIO_CHUNK_FRAMES = 1024;
  // 192 kilobits per second, one of the rates the AAC encoder accepts.
  const UINT32 AUDIO_BYTES_PER_SECOND_AAC = 24000;
  // If no sound arrived for this many frames of time, the gap is filled with silence to keep the sound in sync with the video.
  const int64_t AUDIO_GAP_FRAMES = AUDIO_SAMPLE_RATE / 20;

  // Guards the queue, the pool and `gStopRequested`.
  std::mutex gMutex;
  std::condition_variable gCondition;
  std::deque<Frame> gQueue;
  // Pixel buffers that can be reused, so a new one does not have to be allocated for every frame.
  std::vector<std::vector<uint8_t>> gPool;
  bool gStopRequested = false;

  std::thread gThread;
  std::atomic<bool> gRecording(false);
  std::atomic<bool> gHasAudio(false);
  std::atomic<int> gFrameCount(0);
  std::atomic<int> gDroppedFrames(0);

  // Set by `VIDEORECORDER_Start`, before the encoder thread starts.
  std::wstring gPath;
  int gEncodedWidth = 0;
  int gEncodedHeight = 0;
  int gFps = 30;
  bool gAudioRequested = false;
  LARGE_INTEGER gFrequency;
  LARGE_INTEGER gStartCounter;

  // Only used by the thread that captures frames.
  LONGLONG gLastTimestamp = 0;
  bool gUseBgra = true;

  // Lets `VIDEORECORDER_Start` wait for the encoder thread to finish setting up,
  // and lets the encoder thread wait for the clock to be reset.
  std::mutex gInitMutex;
  std::condition_variable gInitCondition;
  bool gInitDone = false;
  bool gInitOk = false;
  bool gGo = false;

  // The writer is used by the encoder thread (video) and the audio thread (sound), so every call is locked.
  std::mutex gWriterMutex;
  IMFSinkWriter* gWriter = nullptr;
  DWORD gVideoStream = 0;
  DWORD gAudioStream = 0;

  template <class T>
  void SafeRelease(T** pointer)
  {
    if (*pointer != nullptr)
    {
      (*pointer)->Release();
      *pointer = nullptr;
    }
  }

  std::wstring ToWide(const char* text)
  {
    if (text == nullptr) return std::wstring();

    int length = MultiByteToWideChar(CP_UTF8, 0, text, -1, nullptr, 0);
    if (length <= 1) return std::wstring();

    std::wstring result(length, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text, -1, &result[0], length);
    result.resize(length - 1);
    return result;
  }

  ///// AUDIO /////

  /**
   * Receives the result of starting the per-process audio capture. It has to be agile, so Windows can call it from any thread.
   */
  class ActivateHandler : public IActivateAudioInterfaceCompletionHandler, public IAgileObject
  {
  public:
    ActivateHandler()
    {
      completed = CreateEvent(nullptr, FALSE, FALSE, nullptr);
    }

    ~ActivateHandler()
    {
      if (completed != nullptr) CloseHandle(completed);
    }

    HANDLE GetEvent() const
    {
      return completed;
    }

    STDMETHOD(QueryInterface)(REFIID riid, void** result) override
    {
      if (riid == __uuidof(IUnknown) || riid == __uuidof(IActivateAudioInterfaceCompletionHandler))
      {
        *result = static_cast<IActivateAudioInterfaceCompletionHandler*>(this);
      }
      else if (riid == __uuidof(IAgileObject))
      {
        *result = static_cast<IAgileObject*>(this);
      }
      else
      {
        *result = nullptr;
        return E_NOINTERFACE;
      }

      AddRef();
      return S_OK;
    }

    STDMETHOD_(ULONG, AddRef)() override
    {
      return (ULONG)InterlockedIncrement(&references);
    }

    STDMETHOD_(ULONG, Release)() override
    {
      ULONG count = (ULONG)InterlockedDecrement(&references);
      if (count == 0) delete this;
      return count;
    }

    STDMETHOD(ActivateCompleted)(IActivateAudioInterfaceAsyncOperation*) override
    {
      SetEvent(completed);
      return S_OK;
    }

  private:
    LONG references = 1;
    HANDLE completed = nullptr;
  };

  /**
   * Captures the sound played by this process, using the per-process loopback of Windows.
   */
  struct AudioCapture
  {
    IAudioClient* client = nullptr;
    IAudioCaptureClient* capture = nullptr;
    HANDLE event = nullptr;

    bool TryInitialize(IAudioClient* audioClient, DWORD extraFlags)
    {
      WAVEFORMATEX format = {};
      format.wFormatTag = WAVE_FORMAT_PCM;
      format.nChannels = AUDIO_CHANNELS;
      format.nSamplesPerSec = AUDIO_SAMPLE_RATE;
      format.wBitsPerSample = 16;
      format.nBlockAlign = AUDIO_BYTES_PER_FRAME;
      format.nAvgBytesPerSec = AUDIO_SAMPLE_RATE * AUDIO_BYTES_PER_FRAME;

      // The buffer holds 200 milliseconds of sound.
      const HRESULT hr = audioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK | extraFlags,
        2000000, 0, &format, nullptr);
      VR_LOG("audio: IAudioClient::Initialize (extra flags 0x%lx) returned 0x%08lx\n", (unsigned long)extraFlags, (unsigned long)hr);
      return SUCCEEDED(hr);
    }

    /**
     * Gets ready to capture, without starting yet.
     * @return `false` if this is not possible, for example on versions of Windows without per-process capture.
     */
    bool Initialize()
    {
      AUDIOCLIENT_ACTIVATION_PARAMS parameters = {};
      parameters.ActivationType = AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
      parameters.ProcessLoopbackParams.TargetProcessId = GetCurrentProcessId();
      parameters.ProcessLoopbackParams.ProcessLoopbackMode = PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE;

      PROPVARIANT activateParameters = {};
      activateParameters.vt = VT_BLOB;
      activateParameters.blob.cbSize = sizeof(parameters);
      activateParameters.blob.pBlobData = (BYTE*)&parameters;

      ActivateHandler* handler = new ActivateHandler();
      IActivateAudioInterfaceAsyncOperation* operation = nullptr;
      HRESULT hr = ActivateAudioInterfaceAsync(VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, __uuidof(IAudioClient), &activateParameters, handler, &operation);

      bool ok = false;
      VR_LOG("audio: ActivateAudioInterfaceAsync returned 0x%08lx\n", (unsigned long)hr);
      if (SUCCEEDED(hr))
      {
        if (WaitForSingleObject(handler->GetEvent(), 5000) == WAIT_OBJECT_0)
        {
          HRESULT activateResult = E_FAIL;
          IUnknown* unknown = nullptr;
          HRESULT resultHr = operation->GetActivateResult(&activateResult, &unknown);
          VR_LOG("audio: GetActivateResult returned 0x%08lx, activation result 0x%08lx\n", (unsigned long)resultHr, (unsigned long)activateResult);
          if (SUCCEEDED(resultHr) && SUCCEEDED(activateResult) && unknown != nullptr)
          {
            unknown->QueryInterface(__uuidof(IAudioClient), (void**)&client);
            SafeRelease(&unknown);
            ok = client != nullptr;
          }
        }
        else
        {
          VR_LOG("audio: activation timed out\n");
        }
      }

      SafeRelease(&operation);
      handler->Release();
      if (!ok) return false;

      // Some versions of Windows only accept the format when it is converted for us.
      if (!TryInitialize(client, 0) && !TryInitialize(client, AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY))
      {
        SafeRelease(&client);
        return false;
      }

      event = CreateEvent(nullptr, FALSE, FALSE, nullptr);
      if (event == nullptr || FAILED(client->SetEventHandle(event)) || FAILED(client->GetService(__uuidof(IAudioCaptureClient), (void**)&capture)))
      {
        Release();
        return false;
      }

      return true;
    }

    void Release()
    {
      SafeRelease(&capture);
      SafeRelease(&client);
      if (event != nullptr)
      {
        CloseHandle(event);
        event = nullptr;
      }
    }
  };

  AudioCapture gAudio;
  std::thread gAudioThread;
  std::atomic<bool> gAudioStop(false);

  bool WriteAudio(const uint8_t* pcm, int frames, int64_t firstFrame)
  {
    const DWORD size = (DWORD)frames * AUDIO_BYTES_PER_FRAME;

    IMFMediaBuffer* buffer = nullptr;
    IMFSample* sample = nullptr;
    BYTE* data = nullptr;

    HRESULT hr = MFCreateMemoryBuffer(size, &buffer);
    if (SUCCEEDED(hr)) hr = buffer->Lock(&data, nullptr, nullptr);
    if (SUCCEEDED(hr))
    {
      std::memcpy(data, pcm, size);
      buffer->Unlock();
      hr = buffer->SetCurrentLength(size);
    }
    if (SUCCEEDED(hr)) hr = MFCreateSample(&sample);
    if (SUCCEEDED(hr)) hr = sample->AddBuffer(buffer);
    if (SUCCEEDED(hr)) hr = sample->SetSampleTime(firstFrame * 10000000LL / AUDIO_SAMPLE_RATE);
    if (SUCCEEDED(hr)) hr = sample->SetSampleDuration((LONGLONG)frames * 10000000LL / AUDIO_SAMPLE_RATE);
    if (SUCCEEDED(hr))
    {
      std::lock_guard<std::mutex> lock(gWriterMutex);
      hr = gWriter->WriteSample(gAudioStream, sample);
    }

    SafeRelease(&sample);
    SafeRelease(&buffer);
    return SUCCEEDED(hr);
  }

  /**
   * Reads the sound as it is played, and writes it to the file in blocks.
   * The sound has to line up with the video, so the time that passed is used to fill in the gaps when nothing is playing.
   */
  void AudioThread()
  {
    const HRESULT comResult = CoInitializeEx(nullptr, COINIT_MULTITHREADED);

    std::vector<uint8_t> pending;
    // Frames of sound already given to the writer.
    int64_t writtenFrames = 0;
    // Frames of sound captured so far, including the silence that was added.
    int64_t receivedFrames = 0;

    for (;;)
    {
      const bool stopping = gAudioStop.load();
      WaitForSingleObject(gAudio.event, 10);

      // Take everything the game played since the last time.
      for (;;)
      {
        UINT32 packetFrames = 0;
        if (FAILED(gAudio.capture->GetNextPacketSize(&packetFrames)) || packetFrames == 0) break;

        BYTE* data = nullptr;
        UINT32 frames = 0;
        DWORD flags = 0;
        if (FAILED(gAudio.capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) break;

        const size_t bytes = (size_t)frames * AUDIO_BYTES_PER_FRAME;
        const size_t oldSize = pending.size();
        pending.resize(oldSize + bytes);
        if (data == nullptr || (flags & AUDCLNT_BUFFERFLAGS_SILENT)) std::memset(pending.data() + oldSize, 0, bytes);
        else
          std::memcpy(pending.data() + oldSize, data, bytes);

        gAudio.capture->ReleaseBuffer(frames);
        receivedFrames += frames;
      }

      // When nothing is playing, no sound arrives at all, so fill the gap with silence.
      LARGE_INTEGER now;
      QueryPerformanceCounter(&now);
      const int64_t expectedFrames = (now.QuadPart - gStartCounter.QuadPart) * AUDIO_SAMPLE_RATE / gFrequency.QuadPart;
      const int64_t missingFrames = expectedFrames - receivedFrames;
      if (missingFrames > AUDIO_GAP_FRAMES)
      {
        pending.resize(pending.size() + (size_t)missingFrames * AUDIO_BYTES_PER_FRAME, 0);
        receivedFrames += missingFrames;
      }

      // Write whole blocks, and the rest too once recording is stopping.
      size_t offset = 0;
      const size_t chunkBytes = (size_t)AUDIO_CHUNK_FRAMES * AUDIO_BYTES_PER_FRAME;
      while (pending.size() - offset >= chunkBytes)
      {
        WriteAudio(pending.data() + offset, AUDIO_CHUNK_FRAMES, writtenFrames);
        writtenFrames += AUDIO_CHUNK_FRAMES;
        offset += chunkBytes;
      }
      if (stopping && pending.size() > offset)
      {
        const int rest = (int)((pending.size() - offset) / AUDIO_BYTES_PER_FRAME);
        if (rest > 0) WriteAudio(pending.data() + offset, rest, writtenFrames);
        offset = pending.size();
      }
      if (offset > 0) pending.erase(pending.begin(), pending.begin() + offset);

      if (stopping) break;
    }

    VR_LOG("audio: thread ended, %lld frames written, %lld captured\n", (long long)writtenFrames, (long long)receivedFrames);
    if (SUCCEEDED(comResult)) CoUninitialize();
  }

  ///// VIDEO /////

  /**
   * Creates the media type for the video, for the given subtype.
   */
  HRESULT CreateVideoType(const GUID& subtype, UINT32 bitrate, IMFMediaType** outType)
  {
    IMFMediaType* type = nullptr;
    HRESULT hr = MFCreateMediaType(&type);

    if (SUCCEEDED(hr)) hr = type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    if (SUCCEEDED(hr)) hr = type->SetGUID(MF_MT_SUBTYPE, subtype);
    if (SUCCEEDED(hr) && bitrate > 0) hr = type->SetUINT32(MF_MT_AVG_BITRATE, bitrate);
    if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    if (SUCCEEDED(hr)) hr = MFSetAttributeSize(type, MF_MT_FRAME_SIZE, (UINT32)gEncodedWidth, (UINT32)gEncodedHeight);
    if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(type, MF_MT_FRAME_RATE, (UINT32)gFps, 1);
    if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(type, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);

    if (FAILED(hr))
    {
      SafeRelease(&type);
      return hr;
    }

    *outType = type;
    return S_OK;
  }

  /**
   * Creates the media type for the sound, which is either AAC or the raw sound that is given to the encoder.
   */
  HRESULT CreateAudioType(bool aac, IMFMediaType** outType)
  {
    IMFMediaType* type = nullptr;
    HRESULT hr = MFCreateMediaType(&type);

    if (SUCCEEDED(hr)) hr = type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    if (SUCCEEDED(hr)) hr = type->SetGUID(MF_MT_SUBTYPE, aac ? MFAudioFormat_AAC : MFAudioFormat_PCM);
    if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, AUDIO_SAMPLE_RATE);
    if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, AUDIO_CHANNELS);
    if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, aac ? AUDIO_BYTES_PER_SECOND_AAC : AUDIO_SAMPLE_RATE * AUDIO_BYTES_PER_FRAME);
    if (SUCCEEDED(hr)) hr = type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, aac ? 1 : AUDIO_BYTES_PER_FRAME);
    if (SUCCEEDED(hr) && aac) hr = type->SetUINT32(MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION, 0x29);

    if (FAILED(hr))
    {
      SafeRelease(&type);
      return hr;
    }

    *outType = type;
    return S_OK;
  }

  /**
   * Creates the writer that encodes the video to H.264 and the sound to AAC, and writes them to the MP4 file.
   */
  bool CreateWriter(bool withAudio)
  {
    IMFAttributes* attributes = nullptr;
    if (FAILED(MFCreateAttributes(&attributes, 2))) return false;

    // Let the graphics card encode when it can, and do not slow down the writer if it is busy.
    attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
    attributes->SetUINT32(MF_SINK_WRITER_DISABLE_THROTTLING, TRUE);

    IMFSinkWriter* writer = nullptr;
    HRESULT hr = MFCreateSinkWriterFromURL(gPath.c_str(), nullptr, attributes, &writer);
    SafeRelease(&attributes);
    if (FAILED(hr)) return false;

    // About 0.2 bits per pixel, which looks good for game footage, within sensible limits.
    uint64_t bitrate = (uint64_t)gEncodedWidth * (uint64_t)gEncodedHeight * (uint64_t)gFps / 5;
    bitrate = std::min<uint64_t>(std::max<uint64_t>(bitrate, 3000000ULL), 40000000ULL);

    IMFMediaType* outputType = nullptr;
    IMFMediaType* inputType = nullptr;
    DWORD videoStream = 0;
    DWORD audioStream = 0;

    hr = CreateVideoType(MFVideoFormat_H264, (UINT32)bitrate, &outputType);
    if (SUCCEEDED(hr)) hr = writer->AddStream(outputType, &videoStream);
    SafeRelease(&outputType);
    if (SUCCEEDED(hr)) hr = CreateVideoType(MFVideoFormat_RGB32, 0, &inputType);
    if (SUCCEEDED(hr)) hr = writer->SetInputMediaType(videoStream, inputType, nullptr);
    SafeRelease(&inputType);

    if (SUCCEEDED(hr) && withAudio)
    {
      hr = CreateAudioType(true, &outputType);
      if (SUCCEEDED(hr)) hr = writer->AddStream(outputType, &audioStream);
      SafeRelease(&outputType);
      if (SUCCEEDED(hr)) hr = CreateAudioType(false, &inputType);
      if (SUCCEEDED(hr)) hr = writer->SetInputMediaType(audioStream, inputType, nullptr);
      SafeRelease(&inputType);
    }

    if (SUCCEEDED(hr)) hr = writer->BeginWriting();

    if (FAILED(hr))
    {
      SafeRelease(&writer);
      return false;
    }

    gWriter = writer;
    gVideoStream = videoStream;
    gAudioStream = audioStream;
    return true;
  }

  /**
   * Copies a captured frame into the buffer of the encoder, which has the size of the video.
   * Both have the bottom row first. If the frame is not the size of the video, it is stretched to fit.
   */
  void CopyFrame(const Frame& frame, uint8_t* destination)
  {
    const size_t destinationStride = (size_t)gEncodedWidth * 4;
    const size_t sourceStride = (size_t)frame.width * 4;

    // The video size is the window size rounded down to an even number, so a frame is usually
    // the same size, or one pixel larger, which is just cropped.
    if (frame.width >= gEncodedWidth && frame.height >= gEncodedHeight && frame.width - gEncodedWidth <= 1 && frame.height - gEncodedHeight <= 1)
    {
      for (int row = 0; row < gEncodedHeight; row++)
      {
        std::memcpy(destination + row * destinationStride, frame.pixels.data() + row * sourceStride, destinationStride);
      }
      return;
    }

    // The window was resized while recording: stretch the frame, so the video keeps its size.
    for (int row = 0; row < gEncodedHeight; row++)
    {
      const int sourceRow = (int)((int64_t)row * frame.height / gEncodedHeight);
      const uint32_t* sourcePixels = (const uint32_t*)(frame.pixels.data() + (size_t)sourceRow * sourceStride);
      uint32_t* destinationPixels = (uint32_t*)(destination + row * destinationStride);

      for (int column = 0; column < gEncodedWidth; column++)
      {
        destinationPixels[column] = sourcePixels[(int)((int64_t)column * frame.width / gEncodedWidth)];
      }
    }
  }

  bool WriteSample(const Frame& frame)
  {
    const DWORD size = (DWORD)gEncodedWidth * (DWORD)gEncodedHeight * 4;

    IMFMediaBuffer* buffer = nullptr;
    IMFSample* sample = nullptr;
    BYTE* data = nullptr;

    HRESULT hr = MFCreateMemoryBuffer(size, &buffer);
    if (SUCCEEDED(hr)) hr = buffer->Lock(&data, nullptr, nullptr);
    if (SUCCEEDED(hr))
    {
      CopyFrame(frame, data);
      buffer->Unlock();
      hr = buffer->SetCurrentLength(size);
    }
    if (SUCCEEDED(hr)) hr = MFCreateSample(&sample);
    if (SUCCEEDED(hr)) hr = sample->AddBuffer(buffer);
    if (SUCCEEDED(hr)) hr = sample->SetSampleTime(frame.timestamp);
    if (SUCCEEDED(hr)) hr = sample->SetSampleDuration(10000000LL / gFps);
    if (SUCCEEDED(hr))
    {
      std::lock_guard<std::mutex> lock(gWriterMutex);
      hr = gWriter->WriteSample(gVideoStream, sample);
    }

    SafeRelease(&sample);
    SafeRelease(&buffer);
    return SUCCEEDED(hr);
  }

  /**
   * The encoder thread. It sets up Media Foundation, then encodes the queued frames until it is told to stop.
   */
  void EncoderThread()
  {
    const HRESULT comResult = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool mediaFoundationStarted = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));

    bool audioReady = mediaFoundationStarted && gAudioRequested && gAudio.Initialize();
    bool ok = mediaFoundationStarted && CreateWriter(audioReady);
    VR_LOG("audio: capture ready = %d, writer created = %d\n", (int)audioReady, (int)ok);

    // If the sound cannot be encoded, for example without the AAC encoder, record the video without it.
    if (!ok && audioReady)
    {
      audioReady = false;
      gAudio.Release();
      ok = CreateWriter(false);
    }

    gHasAudio = ok && audioReady;
    if (!gHasAudio) gAudio.Release();

    {
      std::lock_guard<std::mutex> lock(gInitMutex);
      gInitOk = ok;
      gInitDone = true;
    }
    gInitCondition.notify_all();

    if (ok)
    {
      // `VIDEORECORDER_Start` resets the clock once everything is ready, so the video and the sound start at the same time.
      {
        std::unique_lock<std::mutex> lock(gInitMutex);
        gInitCondition.wait(lock, [] { return gGo; });
      }

      if (gHasAudio)
      {
        gAudioStop = false;
        gAudio.client->Start();
        gAudioThread = std::thread(AudioThread);
      }

      for (;;)
      {
        Frame frame;

        {
          std::unique_lock<std::mutex> lock(gMutex);
          gCondition.wait(lock, [] { return !gQueue.empty() || gStopRequested; });

          // Stop only once every queued frame has been written.
          if (gQueue.empty()) break;

          frame = std::move(gQueue.front());
          gQueue.pop_front();
        }

        WriteSample(frame);

        {
          std::lock_guard<std::mutex> lock(gMutex);
          if (gPool.size() < MAX_QUEUED_FRAMES + 2) gPool.push_back(std::move(frame.pixels));
        }
      }

      if (gHasAudio)
      {
        // The sound thread writes the rest of the sound before it ends.
        gAudioStop = true;
        SetEvent(gAudio.event);
        gAudioThread.join();
        gAudio.client->Stop();
      }

      // Writes the end of the file. Without this, the video cannot be played.
      {
        std::lock_guard<std::mutex> lock(gWriterMutex);
        gWriter->Finalize();
      }
    }

    gAudio.Release();
    SafeRelease(&gWriter);
    if (mediaFoundationStarted) MFShutdown();
    if (SUCCEEDED(comResult)) CoUninitialize();
  }

  std::vector<uint8_t> TakeBuffer(size_t size)
  {
    std::vector<uint8_t> buffer;

    {
      std::lock_guard<std::mutex> lock(gMutex);
      if (!gPool.empty())
      {
        buffer = std::move(gPool.back());
        gPool.pop_back();
      }
    }

    buffer.resize(size);
    return buffer;
  }

  void RecycleBuffer(std::vector<uint8_t>&& buffer)
  {
    std::lock_guard<std::mutex> lock(gMutex);
    if (gPool.size() < MAX_QUEUED_FRAMES + 2) gPool.push_back(std::move(buffer));
  }

  bool Enqueue(Frame&& frame)
  {
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);

    LONGLONG timestamp = (now.QuadPart - gStartCounter.QuadPart) * 10000000LL / gFrequency.QuadPart;
    // The writer needs every frame to be later than the previous one.
    if (timestamp <= gLastTimestamp) timestamp = gLastTimestamp + 1;
    frame.timestamp = timestamp;

    {
      std::lock_guard<std::mutex> lock(gMutex);
      if (gQueue.size() < MAX_QUEUED_FRAMES)
      {
        gLastTimestamp = timestamp;
        gQueue.push_back(std::move(frame));
        gFrameCount++;
        gCondition.notify_one();
        return true;
      }
    }

    // The encoder is too far behind, so this frame is skipped.
    gDroppedFrames++;
    RecycleBuffer(std::move(frame.pixels));
    return false;
  }

  void ClearGlErrors()
  {
    // Errors from earlier OpenGL calls must not be mistaken for ours.
    for (int i = 0; i < 8 && glGetError() != GL_NO_ERROR; i++)
    {
    }
  }
}

bool VIDEORECORDER_Start(const char* path, int width, int height, int fps, bool audio)
{
  if (gRecording.load()) return false;
  if (gThread.joinable()) gThread.join();
  if (width < 16 || height < 16 || fps < 1 || fps > 120) return false;

  gPath = ToWide(path);
  if (gPath.empty()) return false;

  // H.264 needs the size to be an even number.
  gEncodedWidth = width & ~1;
  gEncodedHeight = height & ~1;
  gFps = fps;
  gAudioRequested = audio;

  QueryPerformanceFrequency(&gFrequency);
  QueryPerformanceCounter(&gStartCounter);
  gLastTimestamp = -1;
  gUseBgra = true;
  gFrameCount = 0;
  gDroppedFrames = 0;
  gHasAudio = false;

  {
    std::lock_guard<std::mutex> lock(gMutex);
    gQueue.clear();
    gStopRequested = false;
  }

  {
    std::lock_guard<std::mutex> lock(gInitMutex);
    gInitDone = false;
    gInitOk = false;
    gGo = false;
  }

  gThread = std::thread(EncoderThread);

  bool ok = false;
  {
    std::unique_lock<std::mutex> lock(gInitMutex);
    ok = gInitCondition.wait_for(lock, std::chrono::seconds(15), [] { return gInitDone; }) && gInitOk;
  }

  if (!ok)
  {
    {
      std::lock_guard<std::mutex> lock(gMutex);
      gStopRequested = true;
    }
    gCondition.notify_all();
    {
      // In case the thread is waiting for the clock.
      std::lock_guard<std::mutex> lock(gInitMutex);
      gGo = true;
    }
    gInitCondition.notify_all();
    gThread.join();
    return false;
  }

  // The first frame and the first sound start at zero.
  QueryPerformanceCounter(&gStartCounter);
  {
    std::lock_guard<std::mutex> lock(gInitMutex);
    gGo = true;
  }
  gInitCondition.notify_all();

  gRecording = true;
  return true;
}

bool VIDEORECORDER_WriteFrame(const unsigned char* bgra, int width, int height)
{
  if (!gRecording.load() || bgra == nullptr || width <= 0 || height <= 0) return false;

  Frame frame;
  frame.width = width;
  frame.height = height;
  frame.pixels = TakeBuffer((size_t)width * (size_t)height * 4);
  std::memcpy(frame.pixels.data(), bgra, frame.pixels.size());

  return Enqueue(std::move(frame));
}

bool VIDEORECORDER_Capture(int width, int height)
{
  if (!gRecording.load() || width <= 0 || height <= 0) return false;

  Frame frame;
  frame.width = width;
  frame.height = height;
  frame.pixels = TakeBuffer((size_t)width * (size_t)height * 4);

  glPixelStorei(GL_PACK_ALIGNMENT, 1);

  // OpenGL returns the bottom row first, which is the order the encoder wants, so no flipping is needed.
  ClearGlErrors();
  glReadPixels(0, 0, width, height, gUseBgra ? GL_BGRA : GL_RGBA, GL_UNSIGNED_BYTE, frame.pixels.data());

  if (glGetError() != GL_NO_ERROR)
  {
    if (!gUseBgra)
    {
      RecycleBuffer(std::move(frame.pixels));
      gDroppedFrames++;
      return false;
    }

    // This graphics card cannot read BGRA, so read RGBA and swap the red and blue channels from now on.
    gUseBgra = false;
    ClearGlErrors();
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, frame.pixels.data());

    if (glGetError() != GL_NO_ERROR)
    {
      RecycleBuffer(std::move(frame.pixels));
      gDroppedFrames++;
      return false;
    }
  }

  if (!gUseBgra)
  {
    uint8_t* pixels = frame.pixels.data();
    for (size_t i = 0; i + 3 < frame.pixels.size(); i += 4)
    {
      std::swap(pixels[i], pixels[i + 2]);
    }
  }

  return Enqueue(std::move(frame));
}

void VIDEORECORDER_Stop()
{
  gRecording = false;

  if (gThread.joinable())
  {
    {
      std::lock_guard<std::mutex> lock(gMutex);
      gStopRequested = true;
    }
    gCondition.notify_all();

    // The thread writes the frames that are still queued, then closes the file.
    gThread.join();
  }

  gHasAudio = false;

  std::lock_guard<std::mutex> lock(gMutex);
  gQueue.clear();
  gPool.clear();
}

bool VIDEORECORDER_IsRecording()
{
  return gRecording.load();
}

bool VIDEORECORDER_HasAudio()
{
  return gHasAudio.load();
}

int VIDEORECORDER_GetFrameCount()
{
  return gFrameCount.load();
}

int VIDEORECORDER_GetDroppedFrames()
{
  return gDroppedFrames.load();
}
