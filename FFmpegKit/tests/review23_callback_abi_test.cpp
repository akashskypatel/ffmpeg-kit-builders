#include <gtest/gtest.h>

#include "FFmpegSession.hpp"
#include "FFmpegKitConfig.hpp"
#include "Level.hpp"
#include "ffmpegkit_wrapper.h"

#include <cstdint>
#include <atomic>
#include <chrono>
#include <list>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
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

struct CompletionOrderObservation {
  std::mutex mutex;
  std::vector<int> order;
  std::atomic<int> completion_count{0};
};

void ordered_v2_log_callback(int64_t, int64_t, int32_t, char *owned_message,
                             void *user_data) {
  auto *observation = static_cast<CompletionOrderObservation *>(user_data);
  {
    std::lock_guard<std::mutex> lock(observation->mutex);
    observation->order.push_back(1);
  }
  ffmpeg_kit_free(owned_message);
}

void ordered_completion_callback(int64_t, void *user_data) {
  auto *observation = static_cast<CompletionOrderObservation *>(user_data);
  {
    std::lock_guard<std::mutex> lock(observation->mutex);
    observation->order.push_back(2);
  }
  observation->completion_count.fetch_add(1, std::memory_order_release);
}

TEST(Review23NativeRegressionTest,
     AcceptedV2LogIsDeliveredBeforeSameSessionCompletion) {
  constexpr int64_t kSessionId = 7000000002LL;
  ffmpeg_kit_initialize();
  ffmpeg_kit_config_enable_log_callback_v2(nullptr, nullptr);
  ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(nullptr, nullptr);

  CompletionOrderObservation observation;
  const int64_t baseline =
      ffmpeg_kit_test_get_v2_log_payload_outstanding();
  ffmpeg_kit_config_enable_log_callback_v2(ordered_v2_log_callback,
                                            &observation);
  ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(
      ordered_completion_callback, &observation);

  std::thread worker([kSessionId] {
    ffmpeg_kit_test_emit_log_event_with_session_id(
        kSessionId, 7, FFMPEG_KIT_LOG_LEVEL_INFO, "before-completion");
    ffmpeg_kit_test_emit_ffmpeg_completion_with_session_id(kSessionId);
  });

  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::seconds(15);
  while (std::chrono::steady_clock::now() < deadline &&
         observation.completion_count.load(std::memory_order_acquire) != 1) {
    ffmpeg_kit_test_process_wasm_callback_queue();
    std::this_thread::yield();
  }
  ASSERT_TRUE(observation.completion_count.load(std::memory_order_acquire) ==
              1);
  worker.join();
  ffmpeg_kit_test_process_wasm_callback_queue();

  {
    std::lock_guard<std::mutex> lock(observation.mutex);
    ASSERT_EQ(observation.order.size(), 2u);
    EXPECT_EQ(observation.order[0], 1);
    EXPECT_EQ(observation.order[1], 2);
  }
  EXPECT_EQ(ffmpeg_kit_test_get_v2_log_payload_outstanding(), baseline);
  ffmpeg_kit_config_enable_log_callback_v2(nullptr, nullptr);
  ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(nullptr, nullptr);
}

#if defined(__EMSCRIPTEN__)
TEST(Review23NativeRegressionTest,
     RejectedWasmV2LogReleasesPayloadWithoutInvokingCallback) {
  constexpr int64_t kSessionId = 7000000003LL;
  ffmpeg_kit_initialize();
  ffmpeg_kit_config_enable_log_callback_v2(nullptr, nullptr);

  V2Observation observation;
  const int64_t baseline =
      ffmpeg_kit_test_get_v2_log_payload_outstanding();
  ffmpeg_kit_config_enable_log_callback_v2(v2_log_callback, &observation);
  std::atomic<bool> worker_done{false};
  std::thread worker([&] {
    ffmpeg_kit_test_set_wasm_callback_enqueue_failures(2);
    ffmpeg_kit_test_emit_log_event_with_session_id(
        kSessionId, 8, FFMPEG_KIT_LOG_LEVEL_ERROR, "rejected-message");
    worker_done.store(true, std::memory_order_release);
  });

  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::seconds(5);
  while (!worker_done.load(std::memory_order_acquire) &&
         std::chrono::steady_clock::now() < deadline) {
    ffmpeg_kit_test_process_wasm_callback_queue();
    std::this_thread::yield();
  }
  worker.join();
  ffmpeg_kit_test_set_wasm_callback_enqueue_failures(0);
  ffmpeg_kit_test_process_wasm_callback_queue();

  {
    std::lock_guard<std::mutex> lock(observation.mutex);
    EXPECT_TRUE(observation.events.empty());
  }
  EXPECT_EQ(ffmpeg_kit_test_get_v2_log_payload_outstanding(), baseline);
  ffmpeg_kit_config_enable_log_callback_v2(nullptr, nullptr);
}
#endif
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

TEST(Review23NativeRegressionTest,
     GlobalLogCallbackRegistrationDoesNotEnableRedirection) {
  const bool redirection_was_enabled =
      ffmpegkit::FFmpegKitConfig::isRedirectionEnabledForTesting();
  ffmpegkit::FFmpegKitConfig::disableRedirection();
  ASSERT_FALSE(ffmpegkit::FFmpegKitConfig::isRedirectionEnabledForTesting());

  V2Observation observation;
  ffmpeg_kit_config_enable_log_callback_v2(v2_log_callback, &observation);
  EXPECT_FALSE(ffmpegkit::FFmpegKitConfig::isRedirectionEnabledForTesting());
  ffmpeg_kit_config_enable_log_callback_v2(nullptr, nullptr);

  if (redirection_was_enabled) {
    ffmpegkit::FFmpegKitConfig::enableRedirection();
  }
}
