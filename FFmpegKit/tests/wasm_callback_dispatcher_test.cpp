#include <gtest/gtest.h>

#include "WasmCallbackDispatcher.h"

#include <atomic>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

#if defined(__EMSCRIPTEN__)
#include <emscripten/threading.h>
#include <pthread.h>
#endif

namespace {

#if defined(__EMSCRIPTEN__)
constexpr int kCallbackCount = 10000;

struct DispatchEvent {
  pthread_t producer{};
  pthread_t consumer{};
  std::string payload;
};

struct DispatchDiagnostics {
  pthread_t main_runtime_thread{};
  std::mutex events_mutex;
  std::vector<DispatchEvent> events;
  std::atomic<int> accepted{0};
  std::atomic<int> rejected{0};
  std::atomic<int> completed{0};
  std::atomic<bool> worker_done{false};
};

struct WorkerArguments {
  WasmCallbackDispatcher *dispatcher;
  DispatchDiagnostics *diagnostics;
};

void *dispatch_worker(void *raw_arguments) {
  auto *arguments = static_cast<WorkerArguments *>(raw_arguments);
  auto *diagnostics = arguments->diagnostics;
  const pthread_t producer = pthread_self();

  for (int index = 0; index < kCallbackCount; ++index) {
    const bool accepted = arguments->dispatcher->dispatch(
        "callback-payload-" + std::to_string(index),
        [diagnostics, producer](std::string payload) {
          {
            std::lock_guard<std::mutex> lock(diagnostics->events_mutex);
            diagnostics->events.push_back(
                {producer, pthread_self(), std::move(payload)});
          }
          diagnostics->completed.fetch_add(1, std::memory_order_release);
        });
    if (accepted) {
      diagnostics->accepted.fetch_add(1, std::memory_order_release);
    } else {
      diagnostics->rejected.fetch_add(1, std::memory_order_release);
    }
  }

  diagnostics->worker_done.store(true, std::memory_order_release);
  return nullptr;
}
#endif

}  // namespace

#if defined(__EMSCRIPTEN__)
TEST(WasmCallbackDispatcherTest, WorkerPayloadsRunOnMainExactlyOnce) {
  ASSERT_TRUE(emscripten_is_main_runtime_thread());

  WasmCallbackDispatcher dispatcher;
  DispatchDiagnostics diagnostics;
  diagnostics.main_runtime_thread = pthread_self();
  ASSERT_TRUE(dispatcher.is_main_runtime_thread());

  WorkerArguments arguments{&dispatcher, &diagnostics};
  pthread_t worker{};
  ASSERT_EQ(pthread_create(&worker, nullptr, dispatch_worker, &arguments), 0);

  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::seconds(10);
  while (std::chrono::steady_clock::now() < deadline &&
         (!diagnostics.worker_done.load(std::memory_order_acquire) ||
          diagnostics.completed.load(std::memory_order_acquire) <
              kCallbackCount)) {
    dispatcher.process_pending();
  }

  ASSERT_TRUE(diagnostics.worker_done.load(std::memory_order_acquire));
  ASSERT_EQ(pthread_join(worker, nullptr), 0);
  dispatcher.process_pending();

  EXPECT_EQ(diagnostics.accepted.load(std::memory_order_acquire),
            kCallbackCount);
  EXPECT_EQ(diagnostics.rejected.load(std::memory_order_acquire), 0);
  EXPECT_EQ(diagnostics.completed.load(std::memory_order_acquire),
            kCallbackCount);

  std::vector<DispatchEvent> events;
  {
    std::lock_guard<std::mutex> lock(diagnostics.events_mutex);
    events = diagnostics.events;
  }
  ASSERT_EQ(events.size(), static_cast<size_t>(kCallbackCount));

  std::vector<bool> seen(kCallbackCount, false);
  for (const DispatchEvent &event : events) {
    EXPECT_FALSE(pthread_equal(event.producer,
                               diagnostics.main_runtime_thread));
    EXPECT_TRUE(pthread_equal(event.consumer,
                              diagnostics.main_runtime_thread));
    ASSERT_TRUE(event.payload.rfind("callback-payload-", 0) == 0);
    const int index = std::stoi(event.payload.substr(11));
    ASSERT_GE(index, 0);
    ASSERT_LT(index, kCallbackCount);
    EXPECT_FALSE(seen[index]);
    seen[index] = true;
  }
  EXPECT_TRUE(std::all_of(seen.begin(), seen.end(),
                          [](bool value) { return value; }));
}
#else
TEST(WasmCallbackDispatcherTest, NativeDispatchRunsDirectly) {
  WasmCallbackDispatcher dispatcher;
  bool called = false;
  std::string received;

  EXPECT_TRUE(dispatcher.is_main_runtime_thread());
  EXPECT_TRUE(dispatcher.dispatch(
      "native-owned-payload", [&](std::string payload) {
        called = true;
        received = std::move(payload);
      }));
  EXPECT_TRUE(called);
  EXPECT_EQ(received, "native-owned-payload");
}
#endif
