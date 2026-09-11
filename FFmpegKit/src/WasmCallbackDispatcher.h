/*
 * Copyright (c) 2025 Akash Patel
 *
 * This file is part of FFmpegKit.
 */

#ifndef FFMPEG_KIT_WASM_CALLBACK_DISPATCHER_H
#define FFMPEG_KIT_WASM_CALLBACK_DISPATCHER_H

#include <cstdint>
#include <functional>
#include <string>

#if defined(__EMSCRIPTEN__)
#include <pthread.h>
#endif


/**
 * Delivers owned callback payloads on the runtime thread used by Wasm.
 *
 * Native builds invoke callbacks directly. Emscripten worker callers enqueue
 * an owned event on a proxying queue targeting the main runtime thread.
 * Callers must keep the dispatcher alive until every accepted event has run.
 */
class WasmCallbackDispatcher final {
 public:
  using Callback = std::function<void(std::string payload)>;
  using Task = std::function<void()>;
  using SessionCallback = void (*)(int64_t session_id, void *user_data);

  WasmCallbackDispatcher();
  ~WasmCallbackDispatcher();

  WasmCallbackDispatcher(const WasmCallbackDispatcher &) = delete;
  WasmCallbackDispatcher &operator=(const WasmCallbackDispatcher &) = delete;

  /**
   * Delivers a copied payload exactly once if this returns true.
   *
   * The callback receives the payload by value, making ownership across a
   * producer-thread return explicit. A false result means the callback was
   * not accepted and will not run.
   */
  bool dispatch(std::string payload, Callback callback);

  /**
   * Delivers a stable session-ID callback exactly once if this returns true.
   * Only the scalar ID, callback pointer, and user data are retained by an
   * accepted event, so no C++ session object crosses the runtime boundary.
   */
  bool dispatch_session_callback(int64_t session_id,
                                 SessionCallback callback, void *user_data);

  /**
   * Delivers an owned callback task exactly once if this returns true.
   *
   * The task owns any copied string or scalar captures that it needs until
   * the callback runs on the target runtime thread.
   */
  bool dispatch_task(Task callback);

  /** Returns whether the caller is the platform's main runtime thread. */
  bool is_main_runtime_thread() const;

  /**
   * Executes pending events for the current thread.
   *
   * This is a no-op on native builds. On Emscripten it is useful for hosts
   * and tests that explicitly drive the main runtime queue.
   */
  void process_pending();

 private:
  struct OwnedEvent {
    std::string payload;
    Callback callback;
  };

  struct OwnedSessionEvent {
    int64_t session_id;
    SessionCallback callback;
    void *user_data;
  };

  struct OwnedTaskEvent {
    Task callback;
  };

  static void invoke_owned_event(void *raw_event);
  static void invoke_owned_session_event(void *raw_event);
  static void invoke_owned_task_event(void *raw_event);

#if defined(__EMSCRIPTEN__)
  struct em_proxying_queue *queue_;
  pthread_t main_runtime_thread_;
#endif
};

#endif  // FFMPEG_KIT_WASM_CALLBACK_DISPATCHER_H
