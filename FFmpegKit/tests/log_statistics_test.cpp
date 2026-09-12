#include <gtest/gtest.h>

#include "ffmpegkit_wrapper.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <pthread.h>
#include <string>
#include <thread>
#include <vector>

#if defined(__EMSCRIPTEN__)
#include <emscripten/threading.h>
#endif

namespace {

constexpr int kEventCount = 2048;
constexpr int64_t kSessionId = 7000000001LL;

enum class EventKind {
  Log,
  Statistics,
  Completion,
};

struct Event {
  EventKind kind;
  int64_t session_id;
  std::string message;
  int64_t time_elapsed = 0;
  int64_t time = 0;
  int64_t size = 0;
  double bitrate = 0;
  double speed = 0;
  int64_t video_frame_number = 0;
  double video_fps = 0;
  double video_quality = 0;
  int64_t dup_frames = 0;
  int64_t drop_frames = 0;
  bool on_main_runtime_thread = false;
};

struct Observation {
  pthread_t main_runtime_thread{};
  std::mutex mutex;
  std::vector<Event> events;
  std::atomic<int> completion_count{0};
  std::atomic<bool> worker_done{false};
};

bool is_main_runtime_thread(const Observation &observation) {
#if defined(__EMSCRIPTEN__)
  return emscripten_is_main_runtime_thread() != 0 &&
         pthread_equal(pthread_self(), observation.main_runtime_thread) != 0;
#else
  return pthread_equal(pthread_self(), observation.main_runtime_thread) != 0;
#endif
}

void log_callback(int64_t session_id, const char *message, void *user_data) {
  auto *observation = static_cast<Observation *>(user_data);
  std::lock_guard<std::mutex> lock(observation->mutex);
  observation->events.push_back(
      {EventKind::Log, session_id, message != nullptr ? message : "",
       0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
       is_main_runtime_thread(*observation)});
}

void statistics_callback(int64_t session_id, int64_t time_elapsed, int64_t time,
                         int64_t size, double bitrate, double speed,
                         int64_t video_frame_number, double video_fps,
                         double video_quality, int64_t dup_frames,
                         int64_t drop_frames, void *user_data) {
  auto *observation = static_cast<Observation *>(user_data);
  std::lock_guard<std::mutex> lock(observation->mutex);
  Event event{EventKind::Statistics, session_id};
  event.time_elapsed = time_elapsed;
  event.time = time;
  event.size = size;
  event.bitrate = bitrate;
  event.speed = speed;
  event.video_frame_number = video_frame_number;
  event.video_fps = video_fps;
  event.video_quality = video_quality;
  event.dup_frames = dup_frames;
  event.drop_frames = drop_frames;
  event.on_main_runtime_thread = is_main_runtime_thread(*observation);
  observation->events.push_back(std::move(event));
}

void completion_callback(int64_t session_id, void *user_data) {
  auto *observation = static_cast<Observation *>(user_data);
  {
    std::lock_guard<std::mutex> lock(observation->mutex);
    observation->events.push_back(
        {EventKind::Completion, session_id, "", 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, is_main_runtime_thread(*observation)});
  }
  observation->completion_count.fetch_add(1, std::memory_order_release);
}

struct WorkerArguments {
  Observation *observation;
};

void *emit_worker(void *raw_arguments) {
  auto *arguments = static_cast<WorkerArguments *>(raw_arguments);
  for (int index = 0; index < kEventCount; ++index) {
    std::string message = "callback-log-" + std::to_string(index);
    ffmpeg_kit_test_emit_v2_log_with_session_id(kSessionId, message.c_str());
    message = "producer-buffer-overwritten";

    ffmpeg_kit_test_emit_v2_statistics_with_session_id(
        kSessionId, 1000 + index, 2000 + index, 3000 + index,
        4.5 + index, 5.5 + index, 6000 + index, 7.5 + index,
        8.5 + index, 9 + index, 10 + index);
  }

  ffmpeg_kit_test_emit_v2_ffmpeg_completion_with_session_id(kSessionId);
  arguments->observation->worker_done.store(true, std::memory_order_release);
  return nullptr;
}

void disable_callbacks() {
  ffmpeg_kit_config_enable_log_callback_v2(nullptr, nullptr);
  ffmpeg_kit_config_enable_statistics_callback_v2(nullptr, nullptr);
  ffmpeg_kit_config_enable_ffmpeg_session_complete_callback_v2(nullptr,
                                                                nullptr);
}


}  // namespace

TEST(LogStatisticsTest,
     WorkerEventsAreOwnedOrderedAndDeliveredBeforeCompletion) {
  ffmpeg_kit_initialize();
  disable_callbacks();

  Observation observation;
  observation.main_runtime_thread = pthread_self();
  ffmpeg_kit_config_enable_log_callback_v2(log_callback, &observation);
  ffmpeg_kit_config_enable_statistics_callback_v2(statistics_callback,
                                                  &observation);
  ffmpeg_kit_config_enable_ffmpeg_session_complete_callback_v2(
      completion_callback, &observation);

  WorkerArguments arguments{&observation};
  pthread_t worker{};
  ASSERT_EQ(pthread_create(&worker, nullptr, emit_worker, &arguments), 0);

  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::seconds(15);
  while (std::chrono::steady_clock::now() < deadline &&
         (!observation.worker_done.load(std::memory_order_acquire) ||
          observation.completion_count.load(std::memory_order_acquire) != 1)) {
    ffmpeg_kit_test_process_wasm_callback_queue();
    std::this_thread::yield();
  }

  ASSERT_TRUE(observation.worker_done.load(std::memory_order_acquire));
  ASSERT_EQ(pthread_join(worker, nullptr), 0);
  ffmpeg_kit_test_process_wasm_callback_queue();

  std::vector<Event> events;
  {
    std::lock_guard<std::mutex> lock(observation.mutex);
    events = observation.events;
  }

  ASSERT_EQ(events.size(), static_cast<size_t>(kEventCount * 2 + 1));
  ASSERT_EQ(observation.completion_count.load(std::memory_order_acquire), 1);

  for (int index = 0; index < kEventCount; ++index) {
    const Event &log = events[static_cast<size_t>(index * 2)];
    const Event &statistics = events[static_cast<size_t>(index * 2 + 1)];
    EXPECT_EQ(log.kind, EventKind::Log);
    EXPECT_EQ(log.session_id, kSessionId);
    EXPECT_EQ(log.message, "callback-log-" + std::to_string(index));
    EXPECT_EQ(statistics.kind, EventKind::Statistics);
    EXPECT_EQ(statistics.session_id, kSessionId);
    EXPECT_EQ(statistics.time_elapsed, 1000 + index);
    EXPECT_EQ(statistics.time, 2000 + index);
    EXPECT_EQ(statistics.size, 3000 + index);
    EXPECT_DOUBLE_EQ(statistics.bitrate, 4.5 + index);
    EXPECT_DOUBLE_EQ(statistics.speed, 5.5 + index);
    EXPECT_EQ(statistics.video_frame_number, 6000 + index);
    EXPECT_DOUBLE_EQ(statistics.video_fps, 7.5 + index);
    EXPECT_DOUBLE_EQ(statistics.video_quality, 8.5 + index);
    EXPECT_EQ(statistics.dup_frames, 9 + index);
    EXPECT_EQ(statistics.drop_frames, 10 + index);
#if defined(__EMSCRIPTEN__)
    EXPECT_TRUE(log.on_main_runtime_thread);
    EXPECT_TRUE(statistics.on_main_runtime_thread);
#endif
  }

  const Event &completion = events.back();
  EXPECT_EQ(completion.kind, EventKind::Completion);
  EXPECT_EQ(completion.session_id, kSessionId);
#if defined(__EMSCRIPTEN__)
  EXPECT_TRUE(completion.on_main_runtime_thread);
#endif

  disable_callbacks();
}
