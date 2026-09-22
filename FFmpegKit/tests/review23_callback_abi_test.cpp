#include <gtest/gtest.h>

#include "FFmpegSession.hpp"
#include "Level.hpp"
#include "ffmpegkit_wrapper.h"

#include <cstdint>
#include <list>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace {

struct V2Event {
  int64_t session_id;
  int64_t sequence;
  int32_t level;
  std::string message;
  bool was_null;
};

struct V2Observation {
  std::mutex mutex;
  std::vector<V2Event> events;
};

void v2_log_callback(int64_t session_id, int64_t sequence, int32_t level,
                     char *owned_message, void *user_data) {
  auto *observation = static_cast<V2Observation *>(user_data);
  V2Event event{session_id, sequence, level,
                owned_message != nullptr ? owned_message : "",
                owned_message == nullptr};
  {
    std::lock_guard<std::mutex> lock(observation->mutex);
    observation->events.push_back(std::move(event));
  }
  ffmpeg_kit_free(owned_message);
}

}  // namespace

TEST(Review23NativeRegressionTest,
     V2CallbackCarriesStableIdentitySequenceLevelAndOwnedMessage) {
  ffmpeg_kit_initialize();
  ffmpeg_kit_config_enable_log_callback_v2(nullptr, nullptr);

  V2Observation observation;
  ffmpeg_kit_config_enable_log_callback_v2(v2_log_callback, &observation);
  ffmpeg_kit_test_emit_log_event_with_session_id(
      7000000001LL, 19, FFMPEG_KIT_LOG_LEVEL_WARNING, "owned-message");
  ffmpeg_kit_test_emit_log_event_with_session_id(
      7000000001LL, 20, FFMPEG_KIT_LOG_LEVEL_ERROR, nullptr);
  ffmpeg_kit_config_enable_log_callback_v2(nullptr, nullptr);

  std::lock_guard<std::mutex> lock(observation.mutex);
  ASSERT_EQ(observation.events.size(), 2u);
  EXPECT_EQ(observation.events[0].session_id, 7000000001LL);
  EXPECT_EQ(observation.events[0].sequence, 19);
  EXPECT_EQ(observation.events[0].level, FFMPEG_KIT_LOG_LEVEL_WARNING);
  EXPECT_EQ(observation.events[0].message, "owned-message");
  EXPECT_FALSE(observation.events[0].was_null);
  EXPECT_EQ(observation.events[1].sequence, 20);
  EXPECT_EQ(observation.events[1].level, FFMPEG_KIT_LOG_LEVEL_ERROR);
  EXPECT_TRUE(observation.events[1].was_null);
}

TEST(Review23NativeRegressionTest,
     IndexedHistoryPreservesOrderAndCarriesPerSessionSequences) {
  auto session = ffmpegkit::FFmpegSession::create(
      std::list<std::string>{"-version"});
  ASSERT_NE(session, nullptr);

  constexpr int kLogCount = 256;
  for (int index = 0; index < kLogCount; ++index) {
    const auto level = index % 2 == 0 ? ffmpegkit::LevelAVLogInfo
                                      : ffmpegkit::LevelAVLogError;
    const std::string message = "history-" + std::to_string(index);
    session->addLog(std::make_shared<ffmpegkit::Log>(
        session->getSessionId(), level, message.c_str()));
  }

  ASSERT_EQ(session->getLogsCount(), kLogCount);
  for (int index = 0; index < kLogCount; ++index) {
    const auto log = session->getLogAt(index);
    ASSERT_NE(log, nullptr);
    EXPECT_EQ(log->getSequence(), index);
    EXPECT_EQ(log->getMessage(), "history-" + std::to_string(index));
  }
  EXPECT_EQ(session->getLogAt(-1), nullptr);
  EXPECT_EQ(session->getLogAt(kLogCount), nullptr);
}
