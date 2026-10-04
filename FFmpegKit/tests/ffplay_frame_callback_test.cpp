#include "ffmpegkit_wrapper.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <mutex>
#include <string>
#include <vector>

#include <gtest/gtest.h>

namespace {

void record_frame_callback(void *userdata, const uint8_t *, int, int, int,
                           const char *) {
  auto *calls = static_cast<std::atomic<int> *>(userdata);
  calls->fetch_add(1, std::memory_order_relaxed);
}

}  // namespace

TEST(FFplayFrameCallbackTest, WasmRegistrationDoesNotInstallFunctionPointer) {
#if defined(__EMSCRIPTEN__)
  std::atomic<int> calls{0};

  ffplay_kit_register_frame_callback(record_frame_callback, &calls);
  ffplay_kit_unregister_frame_callback();

  EXPECT_EQ(calls.load(std::memory_order_relaxed), 0);
  EXPECT_EQ(ffplay_kit_get_frame_buffer_size(), 0U);
#else
  GTEST_SKIP() << "This contract is specific to WebAssembly.";
#endif
}


#if !defined(__EMSCRIPTEN__) && !defined(__ANDROID__)
namespace {

struct NativeFrameCapture {
  std::mutex mutex;
  int callback_count = 0;
  int width = 0;
  int height = 0;
  int linesize = 0;
  std::string format;
  std::vector<uint8_t> pixels;
};

void copy_native_frame(void *userdata, const uint8_t *pixels, int width,
                       int height, int linesize, const char *format) {
  auto *capture = static_cast<NativeFrameCapture *>(userdata);
  if (!capture) return;

  std::lock_guard<std::mutex> lock(capture->mutex);
  ++capture->callback_count;
  capture->width = width;
  capture->height = height;
  capture->linesize = linesize;
  capture->format = format ? format : "";
  capture->pixels.clear();
  if (pixels && width > 0 && height > 0 && linesize >= width * 4) {
    capture->pixels.assign(
        pixels, pixels + static_cast<size_t>(height) *
                          static_cast<size_t>(linesize));
  }
}

class ScopedHandle {
 public:
  explicit ScopedHandle(void *handle) : handle_(handle) {}
  ~ScopedHandle() {
    if (handle_) ffmpeg_kit_handle_release(handle_);
  }

  ScopedHandle(const ScopedHandle &) = delete;
  ScopedHandle &operator=(const ScopedHandle &) = delete;

  void *get() const { return handle_; }

 private:
  void *handle_;
};

class ScopedFrameCallback {
 public:
  ~ScopedFrameCallback() { ffplay_kit_unregister_frame_callback(); }
};

class ScopedMediaFile {
 public:
  explicit ScopedMediaFile(std::filesystem::path path) : path_(path) {}
  ~ScopedMediaFile() {
    std::error_code error;
    std::filesystem::remove(path_, error);
  }

 private:
  std::filesystem::path path_;
};

void configure_headless_video() {
#ifdef _WIN32
  _putenv("SDL_VIDEODRIVER=dummy");
  _putenv("SDL_AUDIODRIVER=dummy");
#else
  setenv("SDL_VIDEODRIVER", "dummy", 1);
  setenv("SDL_AUDIODRIVER", "dummy", 1);
#endif
}

std::array<uint8_t, 4> pixel_at(const NativeFrameCapture &capture, int x,
                                int y) {
  const auto offset = static_cast<size_t>(y) *
                          static_cast<size_t>(capture.linesize) +
                      static_cast<size_t>(x) * 4U;
  return {capture.pixels[offset], capture.pixels[offset + 1],
          capture.pixels[offset + 2], capture.pixels[offset + 3]};
}

}  // namespace

TEST(FFplayFrameCallbackTest, NativeCallbackContainsComposedColorPattern) {
  const std::filesystem::path video_path =
      "ffplay_frame_callback_color_pattern.mp4";
  ScopedMediaFile media_file(video_path);

  const std::string generation_command =
      "-hide_banner -loglevel error -f lavfi -i "
      "color=c=black:size=64x48:rate=2:duration=1,"
      "drawbox=x=0:y=0:w=32:h=24:color=red:t=fill,"
      "drawbox=x=32:y=0:w=32:h=24:color=green:t=fill,"
      "drawbox=x=0:y=24:w=32:h=24:color=blue:t=fill,"
      "drawbox=x=32:y=24:w=32:h=24:color=white:t=fill "
      "-an -frames:v 2 -c:v mpeg4 -pix_fmt yuv420p -y " +
      video_path.string();
  ScopedHandle generation(ffmpeg_kit_execute(generation_command.c_str()));
  ASSERT_NE(generation.get(), nullptr);
  EXPECT_EQ(ffmpeg_kit_session_get_state(generation.get()),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  EXPECT_EQ(ffmpeg_kit_session_get_return_code(generation.get()), 0);
  ASSERT_TRUE(std::filesystem::exists(video_path));

  configure_headless_video();
  NativeFrameCapture capture;
  ScopedFrameCallback callback_scope;
  ffplay_kit_register_frame_callback(copy_native_frame, &capture);

  const std::string playback_command =
      "-hide_banner -loglevel error -autoexit -an -t 1 " +
      video_path.string();
  ScopedHandle playback(ffplay_kit_execute(playback_command.c_str(), 5000));
  ASSERT_NE(playback.get(), nullptr);
  EXPECT_EQ(ffmpeg_kit_session_get_state(playback.get()),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  EXPECT_EQ(ffmpeg_kit_session_get_return_code(playback.get()), 0);
  ffplay_kit_unregister_frame_callback();

  std::lock_guard<std::mutex> lock(capture.mutex);
  ASSERT_GE(capture.callback_count, 1);
  ASSERT_GT(capture.width, 0);
  ASSERT_GT(capture.height, 0);
  EXPECT_EQ(capture.linesize, capture.width * 4);
  EXPECT_EQ(capture.format, "rgba");
  ASSERT_EQ(capture.pixels.size(),
            static_cast<size_t>(capture.height) *
                static_cast<size_t>(capture.linesize));

  uint8_t min_alpha = 255;
  uint8_t max_alpha = 0;
  bool has_non_black_rgb = false;
  for (size_t offset = 0; offset + 3 < capture.pixels.size(); offset += 4) {
    min_alpha = std::min(min_alpha, capture.pixels[offset + 3]);
    max_alpha = std::max(max_alpha, capture.pixels[offset + 3]);
    has_non_black_rgb |= capture.pixels[offset] != 0 ||
                         capture.pixels[offset + 1] != 0 ||
                         capture.pixels[offset + 2] != 0;
  }
  EXPECT_GE(min_alpha, 200);
  EXPECT_LE(max_alpha, 255);
  ASSERT_TRUE(has_non_black_rgb);

  const auto red = pixel_at(capture, capture.width / 4, capture.height / 4);
  const auto green =
      pixel_at(capture, (capture.width * 3) / 4, capture.height / 4);
  const auto blue =
      pixel_at(capture, capture.width / 4, (capture.height * 3) / 4);
  const auto white = pixel_at(capture, (capture.width * 3) / 4,
                              (capture.height * 3) / 4);

  EXPECT_GT(red[0], 100);
  EXPECT_GT(red[0], red[1] + 35);
  EXPECT_GT(red[0], red[2] + 35);
  EXPECT_GT(green[1], 80);
  EXPECT_GT(green[1], green[0] + 20);
  EXPECT_GT(green[1], green[2] + 20);
  EXPECT_GT(blue[2], 100);
  EXPECT_GT(blue[2], blue[0] + 35);
  EXPECT_GT(blue[2], blue[1] + 35);
  EXPECT_GT(white[0], 150);
  EXPECT_GT(white[1], 150);
  EXPECT_GT(white[2], 150);
}
#endif
