#include <gtest/gtest.h>

#include "ffmpegkit_wrapper.h"
#include "FFmpegKitConfig.hpp"

#include <atomic>
#include <chrono>
#include <thread>

namespace {

struct CallbackUserData {
    int marker;
    std::atomic<int> *mismatches;
    std::atomic<int> *calls;
};

void callback_a(FFmpegSessionHandle, const char *, void *user_data) {
    auto *data = static_cast<CallbackUserData *>(user_data);
    if (data == nullptr || data->marker != 1) {
        if (data != nullptr) {
            data->mismatches->fetch_add(1, std::memory_order_relaxed);
        }
        return;
    }
    data->calls->fetch_add(1, std::memory_order_relaxed);
}

void callback_b(FFmpegSessionHandle, const char *, void *user_data) {
    auto *data = static_cast<CallbackUserData *>(user_data);
    if (data == nullptr || data->marker != 2) {
        if (data != nullptr) {
            data->mismatches->fetch_add(1, std::memory_order_relaxed);
        }
        return;
    }
    data->calls->fetch_add(1, std::memory_order_relaxed);
}

}  // namespace

TEST(WrapperCallbackStateTest,
     ConcurrentRegistrationPreservesCallbackUserDataPairs) {
    ffmpeg_kit_initialize();
    const bool redirection_was_enabled =
        ffmpegkit::FFmpegKitConfig::isRedirectionEnabledForTesting();
    if (!redirection_was_enabled) {
        ffmpegkit::FFmpegKitConfig::enableRedirection();
    }

    const auto previous_level = ffmpeg_kit_config_get_log_level();
    ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
    ffmpeg_kit_config_set_log_level(FFMPEG_KIT_LOG_LEVEL_INFO);

    std::atomic<int> mismatches{0};
    std::atomic<int> calls{0};
    CallbackUserData data_a{1, &mismatches, &calls};
    CallbackUserData data_b{2, &mismatches, &calls};

#ifdef __EMSCRIPTEN__
    constexpr int kEmissionCount = 1000;
#else
    constexpr int kEmissionCount = 6000;
#endif
    constexpr int kRegistrationCount = 3000;

    ffmpeg_kit_config_enable_log_callback(callback_a, &data_a);

    std::thread registrar([&] {
        for (int i = 0; i < kRegistrationCount; ++i) {
            if (i % 3 == 0) {
                ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
            } else if (i % 2 == 0) {
                ffmpeg_kit_config_enable_log_callback(callback_a, &data_a);
            } else {
                ffmpeg_kit_config_enable_log_callback(callback_b, &data_b);
            }
            if (i % 32 == 0) {
                std::this_thread::yield();
            }
        }
    });

    std::thread emitter([&] {
        for (int i = 0; i < kEmissionCount; ++i) {
            ffmpeg_kit_test_emit_unattributed_log("callback-state-stress");
            if (i % 32 == 0) {
                std::this_thread::yield();
            }
        }
    });

    registrar.join();
    emitter.join();

    // Leave a callback installed while the final emissions drain so the test
    // also proves that the stress path actually delivered callback traffic.
    ffmpeg_kit_config_enable_log_callback(callback_a, &data_a);
    constexpr int kFinalEmissionCount = 128;
    for (int i = 0; i < kFinalEmissionCount; ++i) {
        ffmpeg_kit_test_emit_unattributed_log("callback-state-final");
    }

    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(5);
    while (calls.load(std::memory_order_acquire) < kFinalEmissionCount &&
           std::chrono::steady_clock::now() < deadline) {
        std::this_thread::yield();
    }

    ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
    ffmpeg_kit_config_set_log_level(previous_level);
    if (!redirection_was_enabled) {
        ffmpegkit::FFmpegKitConfig::disableRedirection();
    }


    EXPECT_EQ(mismatches.load(std::memory_order_relaxed), 0);
    EXPECT_GE(calls.load(std::memory_order_relaxed), kFinalEmissionCount);
}
