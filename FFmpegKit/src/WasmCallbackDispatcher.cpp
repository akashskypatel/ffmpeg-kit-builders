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
  }
#endif
}

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

  if (queue_ == nullptr ||
      !emscripten_proxy_async(queue_, main_runtime_thread_,
                              &WasmCallbackDispatcher::invoke_owned_event,
                              event.get())) {
    return false;
  }
  event.release();
  return true;
#else
  invoke_owned_event(event.release());
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

  if (queue_ == nullptr ||
      !emscripten_proxy_async(
          queue_, main_runtime_thread_,
          &WasmCallbackDispatcher::invoke_owned_session_event, event.get())) {
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
