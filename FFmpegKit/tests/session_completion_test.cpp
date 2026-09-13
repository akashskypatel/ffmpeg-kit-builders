#include <gtest/gtest.h>

#include "FFmpegKitConfig.hpp"
#include "Session.hpp"
#include "SessionState.hpp"
#include "ffmpegkit_wrapper.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

#if defined(__EMSCRIPTEN__)
#include <emscripten/threading.h>
#endif

namespace {

struct CompletionRecord {
  int64_t session_id;
  ffmpegkit::SessionState state;
  bool on_main_runtime_thread;
};

struct CompletionObservation {
  int64_t expected_session_id = 0;
  std::atomic<int> callback_count{0};
  std::mutex mutex;
  std::vector<CompletionRecord> records;
};

void record_completion(int64_t session_id, void *user_data) {
  auto *observation = static_cast<CompletionObservation *>(user_data);
  auto session = ffmpegkit::FFmpegKitConfig::getSession(session_id);
  const auto state = session ? session->getState()
                             : ffmpegkit::SessionStateCreated;
  bool on_main_runtime_thread = true;
#if defined(__EMSCRIPTEN__)
  on_main_runtime_thread = emscripten_is_main_runtime_thread() != 0;
#endif
  {
    std::lock_guard<std::mutex> lock(observation->mutex);
    observation->records.push_back(
        {session_id, state, on_main_runtime_thread});
  }
  observation->callback_count.fetch_add(1, std::memory_order_release);
}

struct BatchHandles {
  FFmpegSessionHandle ffmpeg = nullptr;
  FFprobeSessionHandle ffprobe = nullptr;
  FFplaySessionHandle ffplay = nullptr;
  MediaInformationSessionHandle media = nullptr;
};

bool populate_batch(BatchHandles &handles, CompletionObservation *observations) {
  handles.ffmpeg = ffmpeg_kit_create_session("-version");
  handles.ffprobe = ffprobe_kit_create_session("-version");
  handles.ffplay = ffplay_kit_create_session("-version");
  handles.media = media_information_create_session(
      "-i /definitely/missing/callback-test-input");
  if (!handles.ffmpeg || !handles.ffprobe || !handles.ffplay ||
      !handles.media) {
    return false;
  }

  if (observations != nullptr) {
    observations[0].expected_session_id =
        ffmpeg_kit_session_get_session_id(handles.ffmpeg);
    observations[1].expected_session_id =
        ffmpeg_kit_session_get_session_id(handles.ffprobe);
    observations[2].expected_session_id =
        ffmpeg_kit_session_get_session_id(handles.ffplay);
    observations[3].expected_session_id =
        ffmpeg_kit_session_get_session_id(handles.media);
  }

  ffmpeg_kit_session_execute_async(handles.ffmpeg);
  ffprobe_kit_session_execute_async(handles.ffprobe);
  ffplay_kit_session_execute_async(handles.ffplay, 100);
  media_information_session_execute_async(handles.media, 100);
  return true;
}

void release_batch(BatchHandles &handles) {
  ffmpeg_kit_handle_release(handles.ffmpeg);
  ffmpeg_kit_handle_release(handles.ffprobe);
  ffmpeg_kit_handle_release(handles.ffplay);
  ffmpeg_kit_handle_release(handles.media);
  handles = {};
}

void settle_async_callbacks() {
  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::seconds(1);
  while (std::chrono::steady_clock::now() < deadline) {
    ffmpeg_kit_test_process_wasm_callback_queue();
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
}

bool wait_for_callbacks(CompletionObservation *observations, size_t count) {
  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::seconds(15);
  while (std::chrono::steady_clock::now() < deadline) {
    ffmpeg_kit_test_process_wasm_callback_queue();
    bool complete = true;
    for (size_t index = 0; index < count; ++index) {
      complete = complete &&
                 observations[index].callback_count.load(
                     std::memory_order_acquire) == 1;
    }
    if (complete) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  ffmpeg_kit_test_process_wasm_callback_queue();
  return false;
}

bool wait_for_terminal(void *handle) {
  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::seconds(15);
  while (std::chrono::steady_clock::now() < deadline) {
    ffmpeg_kit_test_process_wasm_callback_queue();
    const auto state = ffmpeg_kit_session_get_state(handle);
    if (state == FFMPEG_KIT_SESSION_STATE_COMPLETED ||
        state == FFMPEG_KIT_SESSION_STATE_FAILED) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return false;
}

bool wait_for_batch_terminal(const BatchHandles &handles) {
  return wait_for_terminal(handles.ffmpeg) &&
         wait_for_terminal(handles.ffprobe) &&
         wait_for_terminal(handles.ffplay) &&
         wait_for_terminal(handles.media);
}

void enable_all(CompletionObservation *observations) {
  ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(
      record_completion, &observations[0]);
  ffmpeg_kit_config_enable_ffprobe_session_complete_callback(
      record_completion, &observations[1]);
  ffmpeg_kit_config_enable_ffplay_session_complete_callback(
      record_completion, &observations[2]);
  ffmpeg_kit_config_enable_media_information_session_complete_callback(
      record_completion, &observations[3]);
}

void disable_all() {
  ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(nullptr,
                                                                nullptr);
  ffmpeg_kit_config_enable_ffprobe_session_complete_callback(nullptr,
                                                                 nullptr);
  ffmpeg_kit_config_enable_ffplay_session_complete_callback(nullptr,
                                                                nullptr);
  ffmpeg_kit_config_enable_media_information_session_complete_callback(
      nullptr, nullptr);
}

void expect_batch(CompletionObservation *observations) {
  for (size_t index = 0; index < 4; ++index) {
    ASSERT_EQ(
        observations[index].callback_count.load(std::memory_order_acquire), 1);
    std::lock_guard<std::mutex> lock(observations[index].mutex);
    ASSERT_EQ(observations[index].records.size(), 1u);
    EXPECT_EQ(observations[index].records[0].session_id,
              observations[index].expected_session_id);
    EXPECT_TRUE(observations[index].records[0].state ==
                    ffmpegkit::SessionStateCompleted ||
                observations[index].records[0].state ==
                    ffmpegkit::SessionStateFailed);
#if defined(__EMSCRIPTEN__)
    EXPECT_TRUE(observations[index].records[0].on_main_runtime_thread);
#endif
  }
}

}  // namespace

TEST(SessionCompletionTest,
     AsyncCompletionUsesStableIdsFinalStateAndRuntimeThread) {
  ffmpeg_kit_initialize();
  const bool redirection_was_enabled =
      ffmpegkit::FFmpegKitConfig::isRedirectionEnabledForTesting();
  if (!redirection_was_enabled) {
    ffmpegkit::FFmpegKitConfig::enableRedirection();
  }
  disable_all();

  // A null callback disables delivery before asynchronous work starts.
  BatchHandles disabled_handles;
  ASSERT_TRUE(populate_batch(disabled_handles, nullptr));
  ASSERT_TRUE(wait_for_batch_terminal(disabled_handles));
  ffmpeg_kit_test_process_wasm_callback_queue();
  release_batch(disabled_handles);
  settle_async_callbacks();

  CompletionObservation first[4];
  enable_all(first);
  BatchHandles first_handles;
  ASSERT_TRUE(populate_batch(first_handles, first));
  ASSERT_TRUE(wait_for_callbacks(first, 4));
  expect_batch(first);
  release_batch(first_handles);

  // Reconfiguration must route subsequent completions to the new user data.
  CompletionObservation reconfigured[4];
  enable_all(reconfigured);
  BatchHandles reconfigured_handles;
  ASSERT_TRUE(populate_batch(reconfigured_handles, reconfigured));
  ASSERT_TRUE(wait_for_callbacks(reconfigured, 4));
  expect_batch(reconfigured);
  for (const auto &observation : first) {
    EXPECT_EQ(observation.callback_count.load(std::memory_order_acquire), 1);
  }
  release_batch(reconfigured_handles);

  // Unregistering the callbacks suppresses later asynchronous completions.
  disable_all();
  CompletionObservation unregistered[4];
  BatchHandles unregistered_handles;
  ASSERT_TRUE(populate_batch(unregistered_handles, unregistered));
  ASSERT_TRUE(wait_for_batch_terminal(unregistered_handles));
  ffmpeg_kit_test_process_wasm_callback_queue();
  for (const auto &observation : unregistered) {
    EXPECT_EQ(observation.callback_count.load(std::memory_order_acquire), 0);
  }
  release_batch(unregistered_handles);
  disable_all();
  if (!redirection_was_enabled) {
    ffmpegkit::FFmpegKitConfig::disableRedirection();
  }
}
