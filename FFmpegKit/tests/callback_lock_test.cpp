#include <gtest/gtest.h>

extern "C" {
#include "libavutil/log.h"
}

#include "ffmpegkit_wrapper.h"

#include <atomic>
#include <chrono>
#include <thread>

namespace {

struct ReentrantCallbackState {
    std::atomic<int> callback_count{0};
    std::atomic<bool> reentry_completed{false};
};

void reentrant_log_callback(FFmpegSessionHandle, const char *, void *user_data) {
    auto *state = static_cast<ReentrantCallbackState *>(user_data);
    state->callback_count.fetch_add(1, std::memory_order_relaxed);

    // This re-enters the same global callback registration path used by the
    // callback currently being dispatched. It must not wait on a lock held by
    // the dispatcher.
    ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
    state->reentry_completed.store(true, std::memory_order_release);
}

}  // namespace

TEST(GlobalCallbackLockTest, LogCallbackCanReenterRegistration) {
    ffmpeg_kit_initialize();

    const auto previous_level = ffmpeg_kit_config_get_log_level();
    ReentrantCallbackState state;
    ffmpeg_kit_config_enable_log_callback(reentrant_log_callback, &state);
    ffmpeg_kit_config_set_log_level(FFMPEG_KIT_LOG_LEVEL_INFO);

    av_log(nullptr, AV_LOG_INFO, "g1 callback lock re-entry\n");

    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(5);
    while (std::chrono::steady_clock::now() < deadline &&
           !state.reentry_completed.load(std::memory_order_acquire)) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    EXPECT_TRUE(state.reentry_completed.load(std::memory_order_acquire));
    EXPECT_EQ(state.callback_count.load(std::memory_order_relaxed), 1);

    // Keep the test isolated if it is run as part of the native test suite.
    ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
    ffmpeg_kit_config_set_log_level(previous_level);
}
