#include "ffmpegkit_wrapper.h"

#include <atomic>
#include <cstdint>

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
