#include <gtest/gtest.h>
#include "FFmpegKitConfig.hpp"
#include "ffmpegkit_wrapper.h"
#include <atomic>
#include <thread>

namespace {

struct CallbackContext {
    const int generation;
    std::atomic<int> calls{0};
    std::atomic<int> mismatches{0};
};

template <int Generation>
void recordCall(void *userData) {
    auto *context = static_cast<CallbackContext *>(userData);
    if (context->generation != Generation) ++context->mismatches;
    ++context->calls;
}

template <int Generation>
void logCallback(void *, const char *, void *userData) {
    recordCall<Generation>(userData);
}

template <int Generation>
void completeCallback(void *, void *userData) {
    recordCall<Generation>(userData);
}

class GlobalCallbackRegistrationTest : public ::testing::Test {
protected:
    void TearDown() override {
        ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
        ffmpeg_kit_config_enable_statistics_callback(nullptr, nullptr);
        ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(nullptr, nullptr);
        ffmpeg_kit_config_enable_ffprobe_session_complete_callback(nullptr, nullptr);
        ffmpeg_kit_config_enable_ffplay_session_complete_callback(nullptr, nullptr);
        ffmpeg_kit_config_enable_media_information_session_complete_callback(nullptr, nullptr);
    }
};

TEST_F(GlobalCallbackRegistrationTest, LogSnapshotRetainsCallbackAndUserData) {
    CallbackContext first{1};
    CallbackContext second{2};
    auto entry = std::make_shared<ffmpegkit::Log>(1, ffmpegkit::LevelAVLogInfo, "entry");
    ffmpeg_kit_config_enable_log_callback(logCallback<1>, &first);
    auto original = ffmpegkit::FFmpegKitConfig::getLogCallback();
    ASSERT_TRUE(original);
    ffmpeg_kit_config_enable_log_callback(logCallback<2>, &second);
    auto replacement = ffmpegkit::FFmpegKitConfig::getLogCallback();
    ASSERT_TRUE(replacement);
    original(entry);
    replacement(entry);
    ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
    EXPECT_FALSE(ffmpegkit::FFmpegKitConfig::getLogCallback());
    EXPECT_EQ(first.calls.load(), 1);
    EXPECT_EQ(second.calls.load(), 1);
    EXPECT_EQ(first.mismatches.load() + second.mismatches.load(), 0);
}

template <typename Setter, typename Getter>
void checkCompleteSnapshot(Setter set, Getter get) {
    CallbackContext first{1};
    CallbackContext second{2};
    set(completeCallback<1>, &first);
    auto original = get();
    ASSERT_TRUE(original);
    set(completeCallback<2>, &second);
    auto replacement = get();
    ASSERT_TRUE(replacement);
    // No native session is needed to check the callback/context pair.
    original(nullptr);
    replacement(nullptr);
    set(nullptr, nullptr);
    EXPECT_FALSE(get());
    EXPECT_EQ(first.calls.load(), 1);
    EXPECT_EQ(second.calls.load(), 1);
    EXPECT_EQ(first.mismatches.load() + second.mismatches.load(), 0);
}

TEST_F(GlobalCallbackRegistrationTest, FFmpegSnapshotRetainsCallbackAndUserData) {
    checkCompleteSnapshot(ffmpeg_kit_config_enable_ffmpeg_session_complete_callback,
                          ffmpegkit::FFmpegKitConfig::getFFmpegSessionCompleteCallback);
}

TEST_F(GlobalCallbackRegistrationTest, FFprobeSnapshotRetainsCallbackAndUserData) {
    checkCompleteSnapshot(ffmpeg_kit_config_enable_ffprobe_session_complete_callback,
                          ffmpegkit::FFmpegKitConfig::getFFprobeSessionCompleteCallback);
}

TEST_F(GlobalCallbackRegistrationTest, FFplaySnapshotRetainsCallbackAndUserData) {
    checkCompleteSnapshot(ffmpeg_kit_config_enable_ffplay_session_complete_callback,
                          ffmpegkit::FFmpegKitConfig::getFFplaySessionCompleteCallback);
}

TEST_F(GlobalCallbackRegistrationTest, MediaInformationSnapshotRetainsCallbackAndUserData) {
    checkCompleteSnapshot(ffmpeg_kit_config_enable_media_information_session_complete_callback,
                          ffmpegkit::FFmpegKitConfig::getMediaInformationSessionCompleteCallback);
}

TEST_F(GlobalCallbackRegistrationTest, ConcurrentLogReplacementKeepsCallbackAndUserDataPaired) {
    CallbackContext first{1};
    CallbackContext second{2};
    auto entry = std::make_shared<ffmpegkit::Log>(1, ffmpegkit::LevelAVLogInfo, "entry");
    ffmpeg_kit_config_enable_log_callback(logCallback<1>, &first);
    std::atomic<bool> start{false};
    std::thread replacing([&] {
        while (!start.load()) std::this_thread::yield();
        for (int i = 0; i < 10000; ++i) {
            ffmpeg_kit_config_enable_log_callback(logCallback<1>, &first);
            ffmpeg_kit_config_enable_log_callback(logCallback<2>, &second);
            ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
        }
    });
    start = true;
    for (int i = 0; i < 10000; ++i) {
        auto callback = ffmpegkit::FFmpegKitConfig::getLogCallback();
        if (callback) callback(entry);
    }
    replacing.join();
    ffmpeg_kit_config_enable_log_callback(logCallback<1>, &first);
    ffmpegkit::FFmpegKitConfig::getLogCallback()(entry);
    ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
    EXPECT_GT(first.calls.load() + second.calls.load(), 0);
    EXPECT_EQ(first.mismatches.load() + second.mismatches.load(), 0);
}

} // namespace
