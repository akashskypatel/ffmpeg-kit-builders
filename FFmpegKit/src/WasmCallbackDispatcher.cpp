#include "WasmCallbackDispatcher.h"

#include <memory>
#include <utility>

#if defined(__EMSCRIPTEN__)
#include <emscripten/proxying.h>
#include <emscripten/threading.h>
#endif

WasmCallbackDispatcher::WasmCallbackDispatcher()
#if defined(__EMSCRIPTEN__)
    : queue_(em_proxying_queue_create()),
      main_runtime_thread_(emscripten_main_runtime_thread_id())
#endif
{
}

WasmCallbackDispatcher::~WasmCallbackDispatcher() {
#if defined(__EMSCRIPTEN__)
  if (queue_ != nullptr) {
    em_proxying_queue_destroy(queue_);
    queue_ = nullptr;
  }
#endif
}

#if defined(__EMSCRIPTEN__)
bool WasmCallbackDispatcher::enqueue(void (*callback)(void *), void *event) {
  // A mailbox can report a transient failure while the target runtime is
  // returning to its event loop. Retry once before reporting a rejected
  // callback, while still preserving the bool failure contract.
  for (int attempt = 0; attempt < 2; ++attempt) {
#if defined(FFMPEG_KIT_TEST_HOOKS)
    int failures = enqueue_failures_.load(std::memory_order_acquire);
    while (failures > 0 &&
           !enqueue_failures_.compare_exchange_weak(
               failures, failures - 1, std::memory_order_acq_rel,
               std::memory_order_acquire)) {
    }
    if (failures > 0) {
      continue;
    }
#endif
    if (queue_ != nullptr &&
        emscripten_proxy_async(queue_, main_runtime_thread_, callback, event)) {
      return true;
    }
  }
  return false;
}
#endif

bool WasmCallbackDispatcher::dispatch(std::string payload,
                                      Callback callback) {
  if (!callback) {
    return false;
  }

  auto event = std::make_unique<OwnedEvent>(
      OwnedEvent{std::move(payload), std::move(callback)});

#if defined(__EMSCRIPTEN__)
  if (emscripten_is_main_runtime_thread()) {
    invoke_owned_event(event.release());
    return true;
  }

  if (!enqueue(&WasmCallbackDispatcher::invoke_owned_event, event.get())) {
    return false;
  }
  event.release();
  return true;
#else
  invoke_owned_event(event.release());
  return true;
#endif
}
bool WasmCallbackDispatcher::dispatch_task(Task callback) {
  if (!callback) {
    return false;
  }

  auto event =
      std::make_unique<OwnedTaskEvent>(OwnedTaskEvent{std::move(callback)});

#if defined(__EMSCRIPTEN__)
  if (emscripten_is_main_runtime_thread()) {
    invoke_owned_task_event(event.release());
    return true;
  }

  if (!enqueue(&WasmCallbackDispatcher::invoke_owned_task_event,
               event.get())) {
    return false;
  }
  event.release();
  return true;
#else
  invoke_owned_task_event(event.release());
  return true;
#endif
}

bool WasmCallbackDispatcher::is_main_runtime_thread() const {
#if defined(__EMSCRIPTEN__)
  return emscripten_is_main_runtime_thread() != 0;
#else
  return true;
#endif
}

void WasmCallbackDispatcher::process_pending() {
#if defined(__EMSCRIPTEN__)
  if (emscripten_is_main_runtime_thread() && queue_ != nullptr) {
    emscripten_proxy_execute_queue(queue_);
  }
#endif
}

void WasmCallbackDispatcher::invoke_owned_event(void *raw_event) {
  std::unique_ptr<OwnedEvent> event(static_cast<OwnedEvent *>(raw_event));
  event->callback(std::move(event->payload));
}

bool WasmCallbackDispatcher::dispatch_session_callback(
    int64_t session_id, SessionCallback callback, void *user_data) {
  if (!callback) {
    return false;
  }

  auto event = std::make_unique<OwnedSessionEvent>(
      OwnedSessionEvent{session_id, callback, user_data});

#if defined(__EMSCRIPTEN__)
  if (emscripten_is_main_runtime_thread()) {
    invoke_owned_session_event(event.release());
    return true;
  }

  if (!enqueue(&WasmCallbackDispatcher::invoke_owned_session_event,
               event.get())) {
    return false;
  }
  event.release();
  return true;
#else
  invoke_owned_session_event(event.release());
  return true;
#endif
}

void WasmCallbackDispatcher::invoke_owned_session_event(void *raw_event) {
  std::unique_ptr<OwnedSessionEvent> event(
      static_cast<OwnedSessionEvent *>(raw_event));
  event->callback(event->session_id, event->user_data);
}

void WasmCallbackDispatcher::invoke_owned_task_event(void *raw_event) {
  std::unique_ptr<OwnedTaskEvent> event(
      static_cast<OwnedTaskEvent *>(raw_event));
  event->callback();
}

void WasmCallbackDispatcher::invoke_borrowed_task_event(void *raw_event) {
  static_cast<OwnedTaskEvent *>(raw_event)->callback();
}

bool WasmCallbackDispatcher::dispatch_task_sync(Task callback) {
  if (!callback) {
    return false;
  }

#if defined(__EMSCRIPTEN__)
  if (emscripten_is_main_runtime_thread()) {
    callback();
    return true;
  }

  OwnedTaskEvent event{std::move(callback)};
  return queue_ != nullptr &&
         emscripten_proxy_sync(
             queue_, main_runtime_thread_,
             &WasmCallbackDispatcher::invoke_borrowed_task_event, &event);
#else
  callback();
  return true;
#endif
}

#if defined(FFMPEG_KIT_TEST_HOOKS)
void WasmCallbackDispatcher::set_enqueue_failures_for_testing(int count) {
  enqueue_failures_.store(count > 0 ? count : 0, std::memory_order_release);
}
#endif
