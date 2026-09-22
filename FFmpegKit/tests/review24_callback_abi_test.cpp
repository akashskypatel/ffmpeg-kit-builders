#include <gtest/gtest.h>

#include "FFmpegSession.hpp"
#include "FFmpegKitConfig.hpp"
#include "Level.hpp"
#include "ffmpegkit_wrapper.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <list>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>

namespace {

using StructuredCallback = void (*)(int64_t, int64_t, int32_t, char *, void *);
static_assert(std::is_same_v<FFmpegKitGlobalLogCallback, StructuredCallback>);

struct LogEvent {
  int64_t session_id;
  int64_t sequence;
  int32_t level;
  std::string message;
  bool was_null;
};

struct LogObservation {
  std::mutex mutex;
  std::vector<LogEvent> events;
};

void log_callback(int64_t session_id, int64_t sequence, int32_t level,
                  char *owned_message, void *user_data) {
  auto *observation = static_cast<LogObservation *>(user_data);
  LogEvent event{session_id, sequence, level,
                 owned_message != nullptr ? owned_message : "",
                 owned_message == nullptr};
  {
    std::lock_guard<std::mutex> lock(observation->mutex);
    observation->events.push_back(std::move(event));
  }
  ffmpeg_kit_free(owned_message);
}
std::size_t event_count(LogObservation &observation) {
  std::lock_guard<std::mutex> lock(observation.mutex);
  return observation.events.size();
}

bool wait_for_event_count(LogObservation &observation, std::size_t expected,
                          std::chrono::seconds timeout = std::chrono::seconds(5)) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (std::chrono::steady_clock::now() < deadline) {
    ffmpeg_kit_test_process_wasm_callback_queue();
    if (event_count(observation) >= expected) return true;
    std::this_thread::yield();
  }
  ffmpeg_kit_test_process_wasm_callback_queue();
  return event_count(observation) >= expected;
}

struct CompletionOrderObservation {
  std::mutex mutex;
  std::vector<int> order;
  std::atomic<int> completion_count{0};
};

void ordered_log_callback(int64_t, int64_t, int32_t, char *owned_message,
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

}  // namespace

TEST(Review24NativeCallbackAbiTest,
     CallbackCarriesStableIdentitySequenceLevelAndOwnedMessage) {
  ffmpeg_kit_initialize();
  ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);

  LogObservation observation;
  const int64_t baseline = ffmpeg_kit_test_get_log_payload_outstanding();
  ffmpeg_kit_config_enable_log_callback(log_callback, &observation);
  ffmpeg_kit_test_emit_log_event_with_session_id(
      7000000001LL, 19, FFMPEG_KIT_LOG_LEVEL_WARNING, "owned-message");
  ffmpeg_kit_test_emit_log_event_with_session_id(
      7000000001LL, 20, FFMPEG_KIT_LOG_LEVEL_ERROR, nullptr);

  ASSERT_TRUE(wait_for_event_count(observation, 2));
  ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);

  std::lock_guard<std::mutex> lock(observation.mutex);
  ASSERT_EQ(observation.events.size(), 2u);
  EXPECT_EQ(observation.events[0].session_id, 7000000001LL);
  EXPECT_EQ(observation.events[0].sequence, 19);
  EXPECT_EQ(observation.events[0].level, FFMPEG_KIT_LOG_LEVEL_WARNING);
  EXPECT_EQ(observation.events[0].message, "owned-message");
  EXPECT_FALSE(observation.events[0].was_null);
  EXPECT_EQ(observation.events[1].session_id, 7000000001LL);
  EXPECT_EQ(observation.events[1].sequence, 20);
  EXPECT_EQ(observation.events[1].level, FFMPEG_KIT_LOG_LEVEL_ERROR);
  EXPECT_TRUE(observation.events[1].was_null);
  EXPECT_EQ(ffmpeg_kit_test_get_log_payload_outstanding(), baseline);
}

TEST(Review24NativeCallbackAbiTest, ReportsPinnedVersionAndCallbackAbiIdentity) {
  char *version = ffmpeg_kit_config_get_version();
  char *callback_abi = ffmpeg_kit_config_get_callback_abi_version();
  ASSERT_NE(version, nullptr);
  ASSERT_NE(callback_abi, nullptr);

  EXPECT_STREQ(version, "0.11.2");
  EXPECT_STREQ(callback_abi, "review24-global-log-v1");
  ffmpeg_kit_free(version);
  ffmpeg_kit_free(callback_abi);
}

TEST(Review24NativeCallbackAbiTest, MultiSessionSequencesRemainIndependent) {
  ffmpeg_kit_initialize();
  ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);

  LogObservation observation;
  ffmpeg_kit_config_enable_log_callback(log_callback, &observation);
  ffmpeg_kit_test_emit_log_event_with_session_id(
      701, 0, FFMPEG_KIT_LOG_LEVEL_INFO, "session-a-0");
  ffmpeg_kit_test_emit_log_event_with_session_id(
      702, 0, FFMPEG_KIT_LOG_LEVEL_INFO, "session-b-0");
  ffmpeg_kit_test_emit_log_event_with_session_id(
      701, 1, FFMPEG_KIT_LOG_LEVEL_ERROR, "session-a-1");

  ASSERT_TRUE(wait_for_event_count(observation, 3));
  ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);

  std::lock_guard<std::mutex> lock(observation.mutex);
  ASSERT_EQ(observation.events.size(), 3u);
  EXPECT_EQ(observation.events[0].session_id, 701);
  EXPECT_EQ(observation.events[0].sequence, 0);
  EXPECT_EQ(observation.events[1].session_id, 702);
  EXPECT_EQ(observation.events[1].sequence, 0);
  EXPECT_EQ(observation.events[2].session_id, 701);
  EXPECT_EQ(observation.events[2].sequence, 1);
  EXPECT_EQ(ffmpeg_kit_test_get_log_payload_outstanding(), 0);
}

TEST(Review24NativeCallbackAbiTest,
     AcceptedLogIsDeliveredBeforeSameSessionCompletion) {
  constexpr int64_t kSessionId = 7000000002LL;
  ffmpeg_kit_initialize();
  ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
  ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(nullptr, nullptr);

  CompletionOrderObservation observation;
  ffmpeg_kit_config_enable_log_callback(ordered_log_callback, &observation);
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
  ASSERT_EQ(observation.completion_count.load(std::memory_order_acquire), 1);
  worker.join();
  ffmpeg_kit_test_process_wasm_callback_queue();

  {
    std::lock_guard<std::mutex> lock(observation.mutex);
    ASSERT_EQ(observation.order.size(), 2u);
    EXPECT_EQ(observation.order[0], 1);
    EXPECT_EQ(observation.order[1], 2);
  }
  ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
  ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(nullptr, nullptr);
}

#if defined(__EMSCRIPTEN__)
TEST(Review24NativeCallbackAbiTest,
     RejectedWasmLogReleasesPayloadWithoutInvokingCallback) {
  constexpr int64_t kSessionId = 7000000003LL;
  ffmpeg_kit_initialize();
  ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);

  LogObservation observation;
  const int64_t baseline = ffmpeg_kit_test_get_log_payload_outstanding();
  ffmpeg_kit_config_enable_log_callback(log_callback, &observation);
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

  EXPECT_EQ(event_count(observation), 0u);
  EXPECT_EQ(ffmpeg_kit_test_get_log_payload_outstanding(), baseline);
  ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
}
#endif

TEST(Review24NativeCallbackAbiTest,
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

TEST(Review24NativeCallbackAbiTest,
     GlobalLogCallbackRegistrationDoesNotEnableRedirection) {
  const bool redirection_was_enabled =
      ffmpegkit::FFmpegKitConfig::isRedirectionEnabledForTesting();
  ffmpegkit::FFmpegKitConfig::disableRedirection();
  ASSERT_FALSE(ffmpegkit::FFmpegKitConfig::isRedirectionEnabledForTesting());

  LogObservation observation;
  ffmpeg_kit_config_enable_log_callback(log_callback, &observation);
  EXPECT_FALSE(ffmpegkit::FFmpegKitConfig::isRedirectionEnabledForTesting());
  ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);

  if (redirection_was_enabled) {
    ffmpegkit::FFmpegKitConfig::enableRedirection();
  }
}
