#include <gtest/gtest.h>

#if !defined(__EMSCRIPTEN__)
#error "The Wasm callback authority test must compile with Emscripten."
#endif

#include <emscripten/proxying.h>
#include <emscripten/threading.h>
#include <pthread.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace {

struct CallbackEvent {
    std::string payload;
    bool on_main_runtime_thread;
    bool on_worker_thread;
};

struct CallbackDiagnostics {
    pthread_t main_runtime_thread{};
    pthread_t worker_thread{};
    em_proxying_queue *proxy_queue = nullptr;

    std::atomic<bool> worker_started{false};
    std::atomic<bool> worker_done{false};
    std::atomic<bool> worker_is_distinct{false};
    std::atomic<bool> proxy_enqueued{false};
    std::atomic<int> invocation_count{0};

    std::mutex events_mutex;
    std::vector<CallbackEvent> events;
};

using Callback = void (*)(void *user_data, const char *payload);

struct CallbackRegistration {
    Callback callback = nullptr;
    void *user_data = nullptr;

    void register_callback(Callback next_callback, void *next_user_data) {
        callback = next_callback;
        user_data = next_user_data;
    }

    void invoke(const char *payload) const {
        ASSERT_NE(callback, nullptr);
        callback(user_data, payload);
    }
};

void record_callback(void *user_data, const char *payload) {
    auto *diagnostics = static_cast<CallbackDiagnostics *>(user_data);
    const bool on_main = emscripten_is_main_runtime_thread() != 0;
    const bool on_worker = pthread_equal(pthread_self(), diagnostics->worker_thread) != 0;

    {
        std::lock_guard<std::mutex> lock(diagnostics->events_mutex);
        diagnostics->events.push_back({payload, on_main, on_worker});
    }
    diagnostics->invocation_count.fetch_add(1, std::memory_order_release);
}

void invoke_registered_callback(void *user_data) {
    auto *registration = static_cast<CallbackRegistration *>(user_data);
    registration->invoke("main-runtime-proxied");
}

struct WorkerArguments {
    CallbackDiagnostics *diagnostics;
    CallbackRegistration *registration;
};

void *worker_entry(void *raw_arguments) {
    auto *arguments = static_cast<WorkerArguments *>(raw_arguments);
    auto *diagnostics = arguments->diagnostics;

    diagnostics->worker_thread = pthread_self();
    diagnostics->worker_started.store(true, std::memory_order_release);
    diagnostics->worker_is_distinct.store(
        pthread_equal(diagnostics->worker_thread, diagnostics->main_runtime_thread) == 0,
        std::memory_order_release);

    // This is the baseline: a registered callback invoked directly by the
    // producer pthread runs on that worker before any proxying is applied.
    arguments->registration->invoke("worker-direct");

    const int enqueued = emscripten_proxy_async(
        diagnostics->proxy_queue,
        diagnostics->main_runtime_thread,
        invoke_registered_callback,
        arguments->registration);
    diagnostics->proxy_enqueued.store(enqueued != 0, std::memory_order_release);
    diagnostics->worker_done.store(true, std::memory_order_release);
    return nullptr;
}

}  // namespace

TEST(WasmCallbackAuthorityTest, WorkerAndMainRuntimeCallbackIdentity) {
    ASSERT_TRUE(emscripten_is_main_runtime_thread());

    CallbackDiagnostics diagnostics;
    diagnostics.main_runtime_thread = emscripten_main_runtime_thread_id();
    ASSERT_TRUE(pthread_equal(diagnostics.main_runtime_thread, pthread_self()));

    CallbackRegistration registration;
    registration.register_callback(record_callback, &diagnostics);
    diagnostics.proxy_queue = em_proxying_queue_create();
    ASSERT_NE(diagnostics.proxy_queue, nullptr);

    WorkerArguments arguments{&diagnostics, &registration};
    pthread_t worker{};
    ASSERT_EQ(pthread_create(&worker, nullptr, worker_entry, &arguments), 0);

    // The main runtime must explicitly drain the proxy queue while the
    // worker remains independent. This also gives the test an explicit,
    // bounded wait instead of relying on a sleep or an infinite join.
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (std::chrono::steady_clock::now() < deadline &&
           (!diagnostics.worker_done.load(std::memory_order_acquire) ||
            diagnostics.invocation_count.load(std::memory_order_acquire) < 2)) {
        emscripten_proxy_execute_queue(diagnostics.proxy_queue);
    }

    ASSERT_TRUE(diagnostics.worker_done.load(std::memory_order_acquire));
    ASSERT_TRUE(diagnostics.proxy_enqueued.load(std::memory_order_acquire));
    ASSERT_EQ(pthread_join(worker, nullptr), 0);

    // The first event is the unproxied worker callback. The second event is
    // the same registered callback delivered through the main-runtime queue.
    std::vector<CallbackEvent> events;
    {
        std::lock_guard<std::mutex> lock(diagnostics.events_mutex);
        events = diagnostics.events;
    }
    ASSERT_EQ(events.size(), 2U);
    EXPECT_EQ(events[0].payload, "worker-direct");
    EXPECT_FALSE(events[0].on_main_runtime_thread);
    EXPECT_TRUE(events[0].on_worker_thread);
    EXPECT_EQ(events[1].payload, "main-runtime-proxied");
    EXPECT_TRUE(events[1].on_main_runtime_thread);
    EXPECT_FALSE(events[1].on_worker_thread);
    EXPECT_TRUE(diagnostics.worker_is_distinct.load(std::memory_order_acquire));
    EXPECT_EQ(diagnostics.invocation_count.load(std::memory_order_acquire), 2);

    em_proxying_queue_destroy(diagnostics.proxy_queue);
}
