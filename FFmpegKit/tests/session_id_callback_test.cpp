#include <gtest/gtest.h>

#include "ffmpegkit_wrapper.h"

#include <cstdint>
#include <limits>
#include <mutex>
#include <vector>

namespace {

struct CallbackIds {
    std::mutex mutex;
    std::vector<int64_t> log_ids;
};

void log_callback(int64_t session_id, const char *, void *user_data) {
    auto *ids = static_cast<CallbackIds *>(user_data);
    std::lock_guard<std::mutex> lock(ids->mutex);
    ids->log_ids.push_back(session_id);
}

}  // namespace

TEST(GlobalCallbackSessionIdTest, StableSessionIdsDoNotUseOpaquePointerTransport) {
    ffmpeg_kit_initialize();
    ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
    ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
    ffmpeg_kit_config_enable_statistics_callback(nullptr, nullptr);
    ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(nullptr, nullptr);
    ffmpeg_kit_config_enable_ffprobe_session_complete_callback(nullptr, nullptr);
    ffmpeg_kit_config_enable_ffplay_session_complete_callback(nullptr, nullptr);
    ffmpeg_kit_config_enable_media_information_session_complete_callback(nullptr, nullptr);

    CallbackIds ids;
    ffmpeg_kit_config_enable_log_callback(log_callback, &ids);

    const std::vector<int64_t> expected_ids = {
        1,
        999999,
        1000000,
        1000001,
        static_cast<int64_t>(std::numeric_limits<int32_t>::max()),
        static_cast<int64_t>(std::numeric_limits<int32_t>::max()) + 1,
    };
    for (const int64_t session_id : expected_ids) {
        ffmpeg_kit_test_emit_log_with_session_id(session_id,
                                                    "stable session id");
    }

    ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);

    std::lock_guard<std::mutex> lock(ids.mutex);
    EXPECT_EQ(ids.log_ids, expected_ids);
}
