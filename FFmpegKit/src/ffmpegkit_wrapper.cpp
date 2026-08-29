/*
 * Copyright (c) 2025 Akash Patel
 *
 * This file is part of FFmpegKit.
 *
 * FFmpegKit is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * FFmpegKit is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with FFmpegKit.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifdef __MINGW32__
#include "pthread_compat.h"
#endif

extern "C" {
#include "libavutil/log.h"
#include "libavformat/avformat.h"
}

#include <sys/time.h>

#include "ffmpegkit_wrapper.h"
#include "ffplay_lib.h"
#include "AbstractSession.hpp"
#include "Chapter.hpp"
#include "FFmpegKit.hpp"
#include "FFmpegKitConfig.hpp"
#include "FFmpegKitObject.hpp"
#include "FFplayKit.hpp"
#include "FFprobeKit.hpp"
#include "MediaInformation.hpp"
#include "MediaInformationSession.hpp"
#include "Packages.hpp"
#include "Statistics.hpp"
#include "StreamInformation.hpp"
#include <cstring>
#include <cstdio>
#include <iostream>
#include <map>
#include <mutex>
#include <thread>
#include <vector>
#include <chrono>
#include <ctime>

static std::string getCurrentTimeStamp() {
  time_t now = time(0);
  struct tm *timeinfo = localtime(&now);
  char buffer[80];
  strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", timeinfo);
  struct timeval tv;
  gettimeofday(&tv, NULL);
  char milliseconds[4];
  snprintf(milliseconds, sizeof(milliseconds), "%03d",
           (int)(tv.tv_usec / 1000));
  return std::string(buffer) + "." + std::string(milliseconds);
}

#ifdef _WIN32
#include <windows.h>
#include <dbghelp.h>
BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    switch (fdwReason) {
        case DLL_PROCESS_ATTACH:
            // Disable per-thread callbacks to reduce loader lock pressure
            DisableThreadLibraryCalls(hinstDLL);
            break;
        case DLL_PROCESS_DETACH:
            break;
    }
    return TRUE;
}
// Note: Link with -ldbghelp
#elif defined(__ANDROID__)
#include <android/log.h>
#include <dlfcn.h>
#include <unwind.h>
#include <iomanip>
#include <sstream>

#define LOG_TAG "ffmpeg-kit"

struct AndroidUnwindState {
  int count;
};

static _Unwind_Reason_Code
android_unwind_callback(struct _Unwind_Context *context, void *arg) {
  AndroidUnwindState *state = (AndroidUnwindState *)arg;
  uintptr_t pc = _Unwind_GetIP(context);

  if (pc) {
    Dl_info info;
    std::stringstream ss;
    ss << "#" << std::setw(2) << std::setfill('0') << state->count << " pc "
       << std::hex << std::setw(16) << pc;

    // Use dli_saddr to calculate the offset within the specific function
    if (dladdr((void *)pc, &info) && info.dli_sname) {
      ss << " " << info.dli_fname << " (" << info.dli_sname << "+0x"
         << (pc - (uintptr_t)info.dli_saddr) << ")";
    } else {
      ss << " <unknown>";
    }

    std::string line = ss.str();
    std::cerr << line << std::endl;
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "%s", line.c_str());
  }

  state->count++;
  return (state->count >= 30) ? _URC_END_OF_STACK : _URC_NO_REASON;
}
#else
#include <execinfo.h>
#include <unistd.h>
#endif

// Macro to wrap the call with a header
#define PRINT_STACK_TRACE()                                                    \
  do {                                                                         \
    std::cerr << "--- STACK TRACE TRIGGERED[" << __FILE__ << ":" << __LINE__  \
              << "] ---" << std::endl;                                         \
    internal_print_stack_trace();                                              \
  } while (0)

void internal_print_stack_trace() {
#ifdef _WIN32
  static std::once_flag sym_init_flag;
  HANDLE process = GetCurrentProcess();
  std::call_once(sym_init_flag, [process]() {
    SymInitialize(process, NULL, TRUE);
  });
  
  void *stack[100];
  WORD frames = CaptureStackBackTrace(0, 100, stack, NULL);

  SYMBOL_INFO *symbol =
      (SYMBOL_INFO *)calloc(1, sizeof(SYMBOL_INFO) + 256 * sizeof(char));
  symbol->MaxNameLen = 255;
  symbol->SizeOfStruct = sizeof(SYMBOL_INFO);

  for (WORD i = 0; i < frames; i++) {
    SymFromAddr(process, (DWORD64)(stack[i]), 0, symbol);
    std::cerr << i << ": " << symbol->Name << " - 0x" << symbol->Address
              << std::endl;
  }
  free(symbol);
#elif defined(__ANDROID__)
  __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "--- Native Stack Trace ---");
  AndroidUnwindState state = {0};
  _Unwind_Backtrace(android_unwind_callback, &state);
#else
  void *array[20];
  size_t size = backtrace(array, 20);
  backtrace_symbols_fd(array, size, STDERR_FILENO);
#endif
}

using namespace ffmpegkit;

// Session registry to keep shared_ptrs alive for the duration of the session
static std::map<void*, std::shared_ptr<ffmpegkit::FFmpegKitObject>> &get_session_registry() {
    static std::map<void*, std::shared_ptr<ffmpegkit::FFmpegKitObject>> *registry = new std::map<void*, std::shared_ptr<ffmpegkit::FFmpegKitObject>>();
    return *registry;
}

#include "win32_mutex.hpp"
using RegistryMutex = KitMutex;

static RegistryMutex &get_registry_mutex() {
    static RegistryMutex *m = new RegistryMutex();
    return *m;
}

// DLL alignment attribute for GCC
#if defined(__GNUC__) && defined(_WIN32)
#define DLL_ALIGN __attribute__((force_align_arg_pointer))
#else
#define DLL_ALIGN
#endif

// ---- Helpers ----

static char *strdup_cpp(const std::string &str) {
  char *res = (char *)malloc(str.length() + 1);
  if (res) {
    strcpy(res, str.c_str());
  }
  return res;
}

static char *strdup_safe_ptr(std::shared_ptr<std::string> strPtr) {
  if (!strPtr)
    return nullptr;
  return strdup_cpp(*strPtr);
}

/**
 * Note on Thread Safety and Lock Scope:
 * We deliberately do NOT hold the registry mutex across the caller's operation to prevent 
 * deadlocking the application if a callback invokes further wrapper operations. 
 * By returning a copy of the std::shared_ptr, we bump the ref-count atomically, which 
 * guarantees memory safety (the object won't be destroyed mid-use).
 * However, this means a concurrent thread COULD call handle_release(), which issues a 
 * cancel() command while the caller is still using this pointer. Dart-level synchronization 
 * is required if you want to avoid acting on explicitly cancelled sessions.
 */
template <typename T> static std::shared_ptr<T> get_ptr_internal(void *handle) {
  if (!handle)
    return nullptr;

  // 1. Check the unified registry
  {
    std::lock_guard<RegistryMutex> lock(get_registry_mutex());
    auto it = get_session_registry().find(handle);
    if (it != get_session_registry().end()) {
      return std::dynamic_pointer_cast<T>(it->second);
    }
  }

  // 2. Support "fake" handles (Session IDs passed as pointers from log/stats callbacks)
  // WARNING: This heuristic relies on the assumption that real heap pointers (handles) 
  // will be > 1,000,000. It is a necessary bridging hack to pass raw numeric Session IDs 
  // through the opaque void* fields of C-callbacks without complex allocation tracking.
  uintptr_t value = (uintptr_t)handle;
  if (value > 0 && value < 1000000) {
    auto session = FFmpegKitConfig::getSession((long)value);
    if (session) {
      return std::dynamic_pointer_cast<T>(session);
    }
  }

  return nullptr;
}

template <typename T> static std::shared_ptr<T> get_ptr(void *handle) {
  return get_ptr_internal<T>(handle);
}

template <typename T> static void *create_handle(std::shared_ptr<T> ptr) {
  if (!ptr) return nullptr;
  
  void *handle = static_cast<void*>(ptr.get());
  
  std::lock_guard<RegistryMutex> registry_lock(get_registry_mutex());
  get_session_registry()[handle] = std::static_pointer_cast<FFmpegKitObject>(ptr);
  
  return handle;
}

template <typename T>
static void **
list_to_handle_array(std::shared_ptr<std::list<std::shared_ptr<T>>> list) {
  try {
    if (!list)
      return nullptr;
    size_t size = list->size();
    void **array = (void **)malloc((size + 1) * sizeof(void *));
    if (!array)
      return nullptr;

    size_t i = 0;
    for (auto &item : *list) {
      array[i++] = create_handle(item);
    }
    array[i] = nullptr;
    return array;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in list_to_handle_array: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

extern "C" {

void DLL_ALIGN ffmpeg_kit_initialize() {
    // 1. Core FFmpeg Logging
    av_log_set_level(AV_LOG_INFO);

    // 2. Initialize Network
    avformat_network_init();
}

const char * DLL_ALIGN ffmpeg_kit_get_build_stamp(void) {
    static const char kStamp[] = __DATE__ " " __TIME__;
    return kStamp;
}

void DLL_ALIGN ffmpeg_kit_handle_release(void *handle) {
  if (!handle) return;
  
  std::shared_ptr<Session> session;
  
  {
    std::lock_guard<RegistryMutex> registry_lock(get_registry_mutex());
    auto it = get_session_registry().find(handle);
    if (it != get_session_registry().end()) {
      session = std::dynamic_pointer_cast<Session>(it->second);
      get_session_registry().erase(it);
    }
  }

  if (session) {
    const SessionState state = session->getState();
    const bool should_cancel = state == SessionStateRunning;

    if (should_cancel) {
      session->cancel();
    }
    /**
     * Block destruction until the native background thread has gracefully exited.
     * We bound this with a 10-second timeout to prevent deadlocking the calling
     * thread (e.g., the Flutter UI isolate) if a session hangs indefinitely.
     */
    bool timed_out = false;
    if (should_cancel) {
      auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
      while (session->getState() == SessionStateRunning) {
        if (std::chrono::steady_clock::now() > deadline) {
          std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Warning] ffmpeg_kit_handle_release: timed out waiting for session to stop\n";
          timed_out = true;
          break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
      }
    }

    // For FFplay sessions, synchronise with the async execution thread so its
    // TLS destructors complete while the runtime is still fully initialized.
    // If the session timed out (thread still running), detach instead of
    // joining to avoid blocking the caller (e.g., Flutter UI isolate)
    // indefinitely.  The detached thread will run its TLS destructors when it
    // eventually exits on its own.
    if (session->isFFplay()) {
      if (session != nullptr) {
        static_cast<ffmpegkit::FFplaySession*>(session.get())->close();
      }
      if (timed_out) {
        std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Warning] ffmpeg_kit_handle_release: detaching stuck FFplay thread\n";
        ffmpegkit::FFmpegKitConfig::detachAsyncFFplayThread();
      } else {
        ffmpegkit::FFmpegKitConfig::joinAsyncFFplayThread();
      }
    }
  }
}

void DLL_ALIGN ffmpeg_kit_config_clear_sessions() {
  try {
    // First, clear our wrapper registry and collect any lingering sessions
    std::vector<std::shared_ptr<Session>> sessions_to_cancel;
    {
      std::lock_guard<RegistryMutex> registry_lock(get_registry_mutex());
      for (auto& pair : get_session_registry()) {
        auto session = std::dynamic_pointer_cast<Session>(pair.second);
        if (session) {
          sessions_to_cancel.push_back(session);
        }
      }
      get_session_registry().clear();
    }

    // Cancel and safely drain any running sessions locally
    for (auto& session : sessions_to_cancel) {
      session->cancel();
      auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
      while (session->getState() == SessionStateRunning) {
        if (std::chrono::steady_clock::now() > deadline) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
      }
    }

    // Finally, clear the backend history
    FFmpegKitConfig::clearSessions();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_clear_sessions: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

/* FFmpegKit */

FFmpegSessionHandle DLL_ALIGN ffmpeg_kit_execute(const char *command) {
  try {
    if (!command)
      return nullptr;
    auto session = FFmpegKit::execute(std::string(command));
    return create_handle(session);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_execute: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFmpegSessionHandle DLL_ALIGN
ffmpeg_kit_execute_async(const char *command,
                         FFmpegKitCompleteCallback complete_cb,
                         void *user_data) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = FFmpegSession::create(arguments);
    FFmpegSessionHandle handle = create_handle(session);
    auto lambda =[complete_cb, user_data, handle](std::shared_ptr<Session> s) {
      if (complete_cb) {
        complete_cb(handle, user_data);
      }
    };
    session->setCompleteCallback(lambda);
    FFmpegKitConfig::asyncFFmpegExecute(session);
    return handle;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_execute_async: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFmpegSessionHandle DLL_ALIGN ffmpeg_kit_execute_async_full(
    const char *command, FFmpegKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, FFmpegKitStatisticsCallback stats_cb,
    void *user_data, int64_t waitTimeout) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = FFmpegSession::create(arguments);
    FFmpegSessionHandle handle = create_handle(session);

    auto complete = [complete_cb, user_data,
                     handle](std::shared_ptr<Session> s) {
      if (complete_cb) {
        complete_cb(handle, user_data);
      }
    };
    auto log =[log_cb, user_data, handle](std::shared_ptr<Log> l) {
      if (log_cb && l) {
        std::string message = l->getMessage();
        log_cb(handle, message.c_str(), user_data);
      }
    };
    auto stats = [stats_cb, user_data, handle](std::shared_ptr<Statistics> s) {
      if (stats_cb && s) {
        stats_cb(handle, (int64_t)(s->getTimeElapsed() * 1000), (int64_t)(s->getTime() * 1000), s->getSize(), s->getBitrate(),
                 s->getSpeed(), s->getVideoFrameNumber(), s->getVideoFps(),
                 s->getVideoQuality(), s->getDupFrames(),
                 s->getDropFrames(), user_data);
      }
    };

    session->setCompleteCallback(complete);
    session->setLogCallback(log);
    session->setStatisticsCallback(stats);
    FFmpegKitConfig::asyncFFmpegExecute(session);
    return handle;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_execute_async_full: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFmpegSessionHandle DLL_ALIGN ffmpeg_kit_create_session(const char *command) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = FFmpegSession::create(arguments);
    if (!session) return nullptr;
    
    return create_handle(session);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_create_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFmpegSessionHandle DLL_ALIGN ffmpeg_kit_create_session_with_callbacks(
    const char *command, FFmpegKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, FFmpegKitStatisticsCallback stats_cb,
    void *user_data) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = FFmpegSession::create(arguments);
    if (!session) return nullptr;
    
    void* handle = create_handle(session);

    auto complete =[complete_cb, user_data, handle](std::shared_ptr<Session> s) {
      if (complete_cb) {
        complete_cb(handle, user_data);
      }
    };
    auto log =[log_cb, user_data, handle](std::shared_ptr<Log> l) {
      if (log_cb && l) {
        std::string message = l->getMessage();
        log_cb(handle, message.c_str(), user_data);
      }
    };
    auto stats =[stats_cb, user_data, handle](std::shared_ptr<Statistics> s) {
      if (stats_cb && s) {
        stats_cb(handle, (int64_t)(s->getTimeElapsed() * 1000), (int64_t)(s->getTime() * 1000), s->getSize(), s->getBitrate(),
                 s->getSpeed(), s->getVideoFrameNumber(), s->getVideoFps(),
                 s->getVideoQuality(), s->getDupFrames(),
                 s->getDropFrames(), user_data);
      }
    };
    session->setCompleteCallback(complete);
    session->setLogCallback(log);
    session->setStatisticsCallback(stats);
    return handle;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_create_session_with_callbacks: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFmpegSessionHandle DLL_ALIGN ffmpeg_kit_create_session_from_argv(int argc, const char** argv) {
    try {
        if (!argv || argc <= 0)
            return nullptr;
        
        std::list<std::string> arguments;
        for (int i = 0; i < argc; i++) {
            if (argv[i]) arguments.push_back(std::string(argv[i]));
        }

        auto session = ffmpegkit::FFmpegSession::create(arguments);
        if (!session) return nullptr;

        return create_handle(session);
    } catch (const std::exception &e) {
        std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] create_session_from_argv: " << e.what() << std::endl;
        PRINT_STACK_TRACE();
        return nullptr;
    }
}

FFmpegSessionHandle DLL_ALIGN ffmpeg_kit_create_session_from_argv_with_callbacks(
    int argc, const char** argv,
    FFmpegKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb,
    FFmpegKitStatisticsCallback stats_cb,
    void *user_data) {
    try {
        if (!argv || argc <= 0)
            return nullptr;
        
        std::list<std::string> arguments;
        for (int i = 0; i < argc; i++) {
            if (argv[i]) arguments.push_back(std::string(argv[i]));
        }

        auto session = ffmpegkit::FFmpegSession::create(arguments);
        if (!session) return nullptr;

        void* handle = create_handle(session);

        auto complete = [complete_cb, user_data, handle](std::shared_ptr<Session> s) {
            if (complete_cb) {
                complete_cb(handle, user_data);
            }
        };
        auto log = [log_cb, user_data, handle](std::shared_ptr<Log> l) {
            if (log_cb && l) {
                std::string message = l->getMessage();
                log_cb(handle, message.c_str(), user_data);
            }
        };
        auto stats = [stats_cb, user_data, handle](std::shared_ptr<Statistics> s) {
            if (stats_cb && s) {
                stats_cb(handle, (int64_t)(s->getTimeElapsed() * 1000), (int64_t)(s->getTime() * 1000), s->getSize(), s->getBitrate(),
                         s->getSpeed(), s->getVideoFrameNumber(), s->getVideoFps(),
                         s->getVideoQuality(), s->getDupFrames(),
                         s->getDropFrames(), user_data);
            }
        };

        session->setCompleteCallback(complete);
        session->setLogCallback(log);
        session->setStatisticsCallback(stats);

        return handle;
    } catch (const std::exception &e) {
        std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] create_session_from_argv_with_callbacks: " << e.what() << std::endl;
        PRINT_STACK_TRACE();
        return nullptr;
    }
}

void DLL_ALIGN ffmpeg_kit_close_session(FFmpegSessionHandle handle) {
    try {
        auto ptr = get_ptr<FFmpegSession>(handle);
        if (ptr) {
            ptr->cancel();
        }
    } catch (const std::exception &e) {
        std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_close_session: " << e.what() << std::endl;
        PRINT_STACK_TRACE();
    }
}

void DLL_ALIGN ffmpeg_kit_debug_print_stack() {
    void* p = nullptr;
    uintptr_t stack_ptr = (uintptr_t)&p;
    printf("[%s] [ffmpeg-kit] [DEBUG] Entry Stack Pointer: 0x%llx\n", getCurrentTimeStamp().c_str(), (unsigned long long)stack_ptr);
    printf("[%s] [ffmpeg-kit] [DEBUG] Alignment: %d\n", getCurrentTimeStamp().c_str(), (int)(stack_ptr % 16));
}

void DLL_ALIGN ffmpeg_kit_test_emit_unattributed_log(const char *message) {
    try {
        av_log(nullptr, AV_LOG_INFO, "%s\n", message ? message : "");
    } catch (const std::exception &e) {
        std::cerr << "[" << getCurrentTimeStamp()
                  << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_test_emit_unattributed_log: "
                  << e.what() << std::endl;
        PRINT_STACK_TRACE();
    }
}

void DLL_ALIGN ffmpeg_kit_set_log_callback(FFmpegSessionHandle session,
                                 FFmpegKitLogCallback log_cb, void *user_data) {
  try {
    auto ptr = get_ptr<FFmpegSession>(session);
    if (ptr) {
      auto log = [log_cb, user_data, session](std::shared_ptr<Log> l) {
        if (log_cb && l) {
          std::string message = l->getMessage();
          log_cb(session, message.c_str(), user_data);
        }
      };
      ptr->setLogCallback(log);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_set_log_callback: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_set_statistics_callback(FFmpegSessionHandle session,
                                        FFmpegKitStatisticsCallback stats_cb,
                                        void *user_data) {
  try {
    auto ptr = get_ptr<FFmpegSession>(session);
    if (ptr) {
      auto stats = [stats_cb, user_data,
                    session](std::shared_ptr<Statistics> s) {
        if (stats_cb && s) {
          stats_cb(session, (int64_t)(s->getTimeElapsed() * 1000), (int64_t)(s->getTime() * 1000), s->getSize(), s->getBitrate(),
                   s->getSpeed(), s->getVideoFrameNumber(), s->getVideoFps(),
                   s->getVideoQuality(), s->getDupFrames(),
                   s->getDropFrames(), user_data);
        }
      };
      ptr->setStatisticsCallback(stats);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_set_statistics_callback: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_set_complete_callback(FFmpegSessionHandle session,
                                      FFmpegKitCompleteCallback complete_cb,
                                      void *user_data) {
  try {
    auto ptr = get_ptr<FFmpegSession>(session);
    if (ptr) {
      auto complete = [complete_cb, user_data,
                       session](std::shared_ptr<Session> s) {
        if (complete_cb && s) {
          complete_cb(session, user_data);
        }
      };
      ptr->setCompleteCallback(complete);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_set_complete_callback: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_set_callbacks(FFmpegSessionHandle session,
                              FFmpegKitCompleteCallback complete_cb,
                              FFmpegKitLogCallback log_cb,
                              FFmpegKitStatisticsCallback stats_cb,
                              void *user_data) {
  try {
    auto ptr = get_ptr<FFmpegSession>(session);
    if (ptr) {
      auto complete =[complete_cb, user_data,
                       session](std::shared_ptr<Session> s) {
        if (complete_cb && s) {
          complete_cb(session, user_data);
        }
      };
      auto log =[log_cb, user_data, session](std::shared_ptr<Log> l) {
        if (log_cb && l) {
          std::string message = l->getMessage();
          log_cb(session, message.c_str(), user_data);
        }
      };
      auto stats = [stats_cb, user_data,
                    session](std::shared_ptr<Statistics> s) {
        if (stats_cb && s) {
          stats_cb(session, (int64_t)(s->getTimeElapsed() * 1000), (int64_t)(s->getTime() * 1000), s->getSize(), s->getBitrate(),
                   s->getSpeed(), s->getVideoFrameNumber(), s->getVideoFps(),
                   s->getVideoQuality(), s->getDupFrames(),
                   s->getDropFrames(), user_data);
        }
      };
      ptr->setCompleteCallback(complete);
      ptr->setLogCallback(log);
      ptr->setStatisticsCallback(stats);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_set_callbacks: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_session_execute(FFmpegSessionHandle session) {
  try {
    auto ptr = get_ptr<FFmpegSession>(session);
    if (ptr) {
      FFmpegKitConfig::ffmpegExecute(ptr);
    } else {
      std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Error] in ffmpeg_kit_session_execute: session not found" << std::endl;
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_execute: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_session_execute_async(FFmpegSessionHandle session) {
  try {
    auto ptr = get_ptr<FFmpegSession>(session);
    if (ptr) {
      FFmpegKitConfig::asyncFFmpegExecute(ptr);
    } else {
      std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Error] in ffmpeg_kit_session_execute_async: session not found" << std::endl;
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_execute_async: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_session_cancel(FFmpegSessionHandle session) {
  try {
    auto ptr = get_ptr<FFmpegSession>(session);
    if (ptr) {
      ptr->cancel();
    } else {
      std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Error] in ffmpeg_kit_session_cancel: session not found" << std::endl;
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_cancel: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_cancel(void) {
  try {
    FFmpegKit::cancel();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_cancel: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_cancel_session(int64_t session_id) {
  try {
    FFmpegKit::cancel(session_id);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_cancel_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

/* FFprobeKit */

FFprobeSessionHandle DLL_ALIGN ffprobe_kit_execute(const char *command) {
  try {
    if (!command)
      return nullptr;
    auto session = FFprobeKit::execute(std::string(command));
    return create_handle(session);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_execute: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFprobeSessionHandle DLL_ALIGN ffprobe_kit_execute_async(const char *command,
                          FFprobeKitCompleteCallback complete_cb,
                          void *user_data) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = FFprobeSession::create(arguments);
    FFprobeSessionHandle handle = create_handle(session);
    auto lambda = [complete_cb, user_data, handle](std::shared_ptr<Session> s) {
      if (complete_cb) {
        complete_cb(handle, user_data);
      }
    };
    session->setCompleteCallback(lambda);
    FFmpegKitConfig::asyncFFprobeExecute(session);
    return handle;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_execute_async: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

void DLL_ALIGN ffprobe_kit_cancel(void) {
  try {
    for (auto& session : *FFmpegKitConfig::getSessions()) {
      if (session->isFFprobe()) {
        session->cancel();
      }
    } 
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_cancel: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffprobe_kit_cancel_session(int64_t session_id) {
  try {
    auto session = FFmpegKitConfig::getSession(session_id);
    if (session && session->isFFprobe()) {
      session->cancel();
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_cancel_session: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

FFprobeSessionHandle DLL_ALIGN ffprobe_kit_create_session(const char *command) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = FFprobeSession::create(arguments);
    return create_handle(session);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_create_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFprobeSessionHandle DLL_ALIGN ffprobe_kit_create_session_with_callbacks(
    const char *command, FFprobeKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = FFprobeSession::create(arguments);
    FFprobeSessionHandle handle = create_handle(session);

    auto complete =[complete_cb, user_data,
                     handle](std::shared_ptr<Session> s) {
      if (complete_cb) {
        complete_cb(handle, user_data);
      }
    };
    auto log =[log_cb, user_data, handle](std::shared_ptr<Log> l) {
      if (log_cb && l) {
        std::string message = l->getMessage();
        log_cb(handle, message.c_str(), user_data);
      }
    };
    session->setCompleteCallback(complete);
    session->setLogCallback(log);
    return handle;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_create_session_with_callbacks: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFprobeSessionHandle DLL_ALIGN ffprobe_kit_create_session_from_argv(int argc, const char** argv) {
    try {
        if (!argv || argc <= 0)
            return nullptr;
        
        std::list<std::string> arguments;
        for (int i = 0; i < argc; i++) {
            if (argv[i]) arguments.push_back(std::string(argv[i]));
        }

        auto session = ffmpegkit::FFprobeSession::create(arguments);
        if (!session) return nullptr;

        return create_handle(session);
    } catch (const std::exception &e) {
        std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] ffprobe_create_session_from_argv: " << e.what() << std::endl;
        PRINT_STACK_TRACE();
        return nullptr;
    }
}

FFprobeSessionHandle DLL_ALIGN ffprobe_kit_create_session_from_argv_with_callbacks(
    int argc, const char** argv, FFprobeKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data) {
    try {
        if (!argv || argc <= 0)
            return nullptr;
        
        std::list<std::string> arguments;
        for (int i = 0; i < argc; i++) {
            if (argv[i]) arguments.push_back(std::string(argv[i]));
        }

        auto session = ffmpegkit::FFprobeSession::create(arguments);
        if (!session) return nullptr;

        void* handle = create_handle(session);

        auto complete =[complete_cb, user_data, handle](std::shared_ptr<Session> s) {
            if (complete_cb) {
                complete_cb(handle, user_data);
            }
        };
        auto log =[log_cb, user_data, handle](std::shared_ptr<Log> l) {
            if (log_cb && l) {
                std::string message = l->getMessage();
                log_cb(handle, message.c_str(), user_data);
            }
        };

        session->setCompleteCallback(complete);
        session->setLogCallback(log);

        return handle;
    } catch (const std::exception &e) {
        std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] ffprobe_create_session_from_argv_with_callbacks: " << e.what() << std::endl;
        PRINT_STACK_TRACE();
        return nullptr;
    }
}

void DLL_ALIGN ffprobe_kit_close_session(FFprobeSessionHandle handle) {
  try {
    auto ptr = get_ptr<FFprobeSession>(handle);
    if (ptr) {
      ptr->cancel();
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_close_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffprobe_kit_set_log_callback(FFprobeSessionHandle session,
                                  FFmpegKitLogCallback log_cb,
                                  void *user_data) {
  try {
    auto ptr = get_ptr<FFprobeSession>(session);
    if (ptr) {
      auto log =[log_cb, user_data, session](std::shared_ptr<Log> l) {
        if (log_cb && l) {
          std::string message = l->getMessage();
          log_cb(session, message.c_str(), user_data);
        }
      };
      ptr->setLogCallback(log);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_set_log_callback: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffprobe_kit_set_complete_callback(FFprobeSessionHandle session,
                                       FFprobeKitCompleteCallback complete_cb,
                                       void *user_data) {
  try {
    auto ptr = get_ptr<FFprobeSession>(session);
    if (ptr) {
      auto complete = [complete_cb, user_data,
                       session](std::shared_ptr<Session> s) {
        if (complete_cb && s) {
          complete_cb(session, user_data);
        }
      };
      ptr->setCompleteCallback(complete);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_set_complete_callback: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffprobe_kit_set_callbacks(FFprobeSessionHandle session,
                               FFprobeKitCompleteCallback complete_cb,
                               FFmpegKitLogCallback log_cb, void *user_data) {
  try {
    auto ptr = get_ptr<FFprobeSession>(session);
    if (ptr) {
      auto complete =[complete_cb, user_data,
                       session](std::shared_ptr<Session> s) {
        if (complete_cb && s) {
          complete_cb(session, user_data);
        }
      };
      auto log =[log_cb, user_data, session](std::shared_ptr<Log> l) {
        if (log_cb && l) {
          std::string message = l->getMessage();
          log_cb(session, message.c_str(), user_data);
        }
      };
      ptr->setCompleteCallback(complete);
      ptr->setLogCallback(log);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_set_callbacks: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffprobe_kit_session_execute(FFprobeSessionHandle session) {
  try {
    auto ptr = get_ptr<FFprobeSession>(session);
    if (ptr) {
      FFmpegKitConfig::ffprobeExecute(ptr);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_session_execute: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffprobe_kit_session_execute_async(FFprobeSessionHandle session) {
  try {
    auto ptr = get_ptr<FFprobeSession>(session);
    if (ptr) {
      FFmpegKitConfig::asyncFFprobeExecute(ptr);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_session_execute_async: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

MediaInformationSessionHandle DLL_ALIGN ffprobe_kit_get_media_information(const char *path) {
  try {
    if (!path)
      return nullptr;
    auto session = FFprobeKit::getMediaInformation(std::string(path));
    return create_handle(session);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_get_media_information: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

MediaInformationSessionHandle DLL_ALIGN ffprobe_kit_get_media_information_async(
    const char *path, ::MediaInformationSessionCompleteCallback complete_cb,
    void *user_data) {
  try {
    if (!path)
      return nullptr;
    auto session =
        FFprobeKit::getMediaInformationAsync(std::string(path), nullptr);
    MediaInformationSessionHandle handle = create_handle(session);
    if (complete_cb) {
      auto lambda = [complete_cb, user_data,
                     handle](std::shared_ptr<MediaInformationSession> s) {
        complete_cb(handle, user_data);
      };
      session->setCompleteCallback(lambda);
    }
    return handle;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_get_media_information_async: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

/* FFplayKit */

FFplaySessionHandle DLL_ALIGN ffplay_kit_execute(const char *command, int64_t timeout) {
  try {
    if (!command)
      return nullptr;
    auto session = FFplayKit::execute(std::string(command), timeout);
    return create_handle(session);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_execute: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFplaySessionHandle DLL_ALIGN ffplay_kit_execute_async(const char *command,
                         FFplayKitCompleteCallback complete_cb, void *user_data,
                         int64_t waitTimeout) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = FFplaySession::create(arguments);
    FFplaySessionHandle handle = create_handle(session);
    auto lambda = [complete_cb, user_data, handle](std::shared_ptr<Session> s) {
      if (complete_cb) {
        complete_cb(handle, user_data);
      }
    };
    session->setCompleteCallback(lambda);
    FFmpegKitConfig::asyncFFplayExecute(session, waitTimeout);
    return handle;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_execute_async: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFplaySessionHandle DLL_ALIGN ffplay_kit_create_session(const char *command) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = FFplaySession::create(arguments);
    return create_handle(session);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_create_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFplaySessionHandle DLL_ALIGN ffplay_kit_create_session_with_callbacks(
    const char *command, FFplayKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = FFplaySession::create(arguments);
    FFplaySessionHandle handle = create_handle(session);

    auto complete =[complete_cb, user_data,
                     handle](std::shared_ptr<Session> s) {
      if (complete_cb) {
        complete_cb(handle, user_data);
      }
    };
    auto log =[log_cb, user_data, handle](std::shared_ptr<Log> l) {
      if (log_cb && l) {
        std::string message = l->getMessage();
        log_cb(handle, message.c_str(), user_data);
      }
    };
    session->setCompleteCallback(complete);
    session->setLogCallback(log);
    return handle;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_create_session_with_callbacks: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFplaySessionHandle DLL_ALIGN ffplay_kit_create_session_from_argv(int argc, const char** argv) {
    try {
        if (!argv || argc <= 0)
            return nullptr;
        
        std::list<std::string> arguments;
        for (int i = 0; i < argc; i++) {
            if (argv[i]) arguments.push_back(std::string(argv[i]));
        }

        auto session = ffmpegkit::FFplaySession::create(arguments);
        if (!session) return nullptr;

        return create_handle(session);
    } catch (const std::exception &e) {
        std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] ffplay_create_session_from_argv: " << e.what() << std::endl;
        PRINT_STACK_TRACE();
        return nullptr;
    }
}

FFplaySessionHandle DLL_ALIGN ffplay_kit_create_session_from_argv_with_callbacks(
    int argc, const char** argv,
    FFplayKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb,
    void *user_data) {
    try {
        if (!argv || argc <= 0)
            return nullptr;
        
        std::list<std::string> arguments;
        for (int i = 0; i < argc; i++) {
            if (argv[i]) arguments.push_back(std::string(argv[i]));
        }

        auto session = ffmpegkit::FFplaySession::create(arguments);
        if (!session) return nullptr;

        void* handle = create_handle(session);

        auto complete = [complete_cb, user_data, handle](std::shared_ptr<Session> s) {
            if (complete_cb) {
                complete_cb(handle, user_data);
            }
        };
        auto log =[log_cb, user_data, handle](std::shared_ptr<Log> l) {
            if (log_cb && l) {
                std::string message = l->getMessage();
                log_cb(handle, message.c_str(), user_data);
            }
        };

        session->setCompleteCallback(complete);
        session->setLogCallback(log);

        return handle;
    } catch (const std::exception &e) {
        std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] ffplay_create_session_from_argv_with_callbacks: " << e.what() << std::endl;
        PRINT_STACK_TRACE();
        return nullptr;
    }
}

void DLL_ALIGN ffplay_kit_close_session(FFplaySessionHandle handle) { 
    ffmpeg_kit_handle_release(handle); 
}

void DLL_ALIGN ffplay_kit_set_log_callback(FFplaySessionHandle session,
                                 FFmpegKitLogCallback log_cb, void *user_data) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      auto log =[log_cb, user_data, session](std::shared_ptr<Log> l) {
        if (log_cb && l) {
          std::string message = l->getMessage();
          log_cb(session, message.c_str(), user_data);
        }
      };
      ptr->setLogCallback(log);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_set_log_callback: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_set_complete_callback(FFplaySessionHandle session,
                                      FFplayKitCompleteCallback complete_cb,
                                      void *user_data) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      auto complete =[complete_cb, user_data,
                       session](std::shared_ptr<Session> s) {
        if (complete_cb && s) {
          complete_cb(session, user_data);
        }
      };
      ptr->setCompleteCallback(complete);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_set_complete_callback: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_set_callbacks(FFplaySessionHandle session,
                              FFplayKitCompleteCallback complete_cb,
                              FFmpegKitLogCallback log_cb, void *user_data) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      auto complete =[complete_cb, user_data,
                       session](std::shared_ptr<Session> s) {
        if (complete_cb && s) {
          complete_cb(session, user_data);
        }
      };
      auto log =[log_cb, user_data, session](std::shared_ptr<Log> l) {
        if (log_cb && l) {
          std::string message = l->getMessage();
          log_cb(session, message.c_str(), user_data);
        }
      };
      ptr->setCompleteCallback(complete);
      ptr->setLogCallback(log);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_set_callbacks: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_session_execute(FFplaySessionHandle session, int64_t timeout) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      FFmpegKitConfig::ffplayExecute(ptr, timeout);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_execute: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

FFplaySessionHandle DLL_ALIGN ffplay_kit_get_current_session(void) {
  try {
    auto session = FFmpegKitConfig::getActiveFFplaySession();
    return create_handle(std::dynamic_pointer_cast<FFplaySession>(session));
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_get_current_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

void DLL_ALIGN ffplay_kit_session_execute_async(FFplaySessionHandle session,
                                      int64_t timeout) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      FFmpegKitConfig::asyncFFplayExecute(ptr, timeout);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_execute_async: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_session_seek(FFplaySessionHandle session, double seconds) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      ptr->seek(seconds);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_seek: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_session_pause(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      ptr->pause();
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_pause: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_session_start(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      ptr->start();
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_start: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_session_resume(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      ptr->resume();
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_resume: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_session_stop(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      ptr->stop();
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_stop: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_session_close(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      ptr->close();
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_close: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

double DLL_ALIGN ffplay_kit_session_get_position(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      return ptr->getPosition();
    }
    return 0.0;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_get_position: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1.0;
  }
}

void DLL_ALIGN ffplay_kit_session_set_position(FFplaySessionHandle session,
                                     double seconds) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      ptr->setPosition(seconds);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_set_position: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

int DLL_ALIGN ffplay_kit_session_get_video_width(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) return ptr->getVideoWidth();
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_get_video_width: " << e.what() << std::endl;
    return 0;
  }
}

int DLL_ALIGN ffplay_kit_session_get_video_height(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) return ptr->getVideoHeight();
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_get_video_height: " << e.what() << std::endl;
    return 0;
  }
}

int DLL_ALIGN ffplay_kit_has_video_stream(const char *path) {
  if (!path) return -1;
  try {
    AVFormatContext *fmt_ctx = nullptr;
    int ret = avformat_open_input(&fmt_ctx, path, nullptr, nullptr);
    if (ret < 0) return -1;
    ret = avformat_find_stream_info(fmt_ctx, nullptr);
    int has_video = 0;
    if (ret >= 0) {
      for (unsigned int i = 0; i < fmt_ctx->nb_streams; i++) {
        if (fmt_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
          has_video = 1;
          break;
        }
      }
    }
    avformat_close_input(&fmt_ctx);
    return (ret < 0) ? -1 : has_video;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_has_video_stream: " << e.what() << std::endl;
    return -1;
  }
}

double DLL_ALIGN ffplay_kit_session_get_duration(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      return ptr->getDuration();
    }
    return 0.0;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_get_duration: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1.0;
  }
}

bool DLL_ALIGN ffplay_kit_session_is_playing(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      return ptr->isPlaying();
    }
    return false;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_is_playing: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

bool DLL_ALIGN ffplay_kit_session_is_paused(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      return ptr->isPaused();
    }
    return false;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_is_paused: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

void DLL_ALIGN ffplay_kit_session_set_volume(FFplaySessionHandle session, double volume) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      ptr->setVolume(volume);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_set_volume: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

double DLL_ALIGN ffplay_kit_session_get_volume(FFplaySessionHandle session) {
  try {
    auto ptr = get_ptr<FFplaySession>(session);
    if (ptr) {
      return ptr->getVolume();  // -1.0 when context not ready; see header docs
    }
    return -1.0;  // invalid handle — same sentinel as context-not-ready
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_session_get_volume: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1.0;
  }
}

void DLL_ALIGN ffplay_kit_seek(double seconds) {
  try {
    FFplayKit::seek(seconds);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_seek: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_start(void) {
  try {
    FFplayKit::start();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_start: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_pause(void) {
  try {
    FFplayKit::pause();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_pause: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_resume(void) {
  try {
    FFplayKit::resume();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_resume: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_stop(void) {
  try {
    FFplayKit::stop();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_stop: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffplay_kit_close(void) {
  try {
    FFplayKit::close();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_close: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

double DLL_ALIGN ffplay_kit_get_position(void) {
  try {
    return FFplayKit::getPosition();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_get_position: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1.0;
  }
}

void DLL_ALIGN ffplay_kit_set_position(double seconds) {
  try {
    FFplayKit::setPosition(seconds);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_set_position: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

double DLL_ALIGN ffplay_kit_get_duration(void) {
  try {
    return FFplayKit::getDuration();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_get_duration: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1.0;
  }
}

bool DLL_ALIGN ffplay_kit_is_playing(void) {
  try {
    return FFplayKit::isPlaying();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_is_playing: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

bool DLL_ALIGN ffplay_kit_is_paused(void) {
  try {
    return FFplayKit::isPaused();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_is_paused: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

void DLL_ALIGN ffplay_kit_set_volume(double volume) {
  try {
    FFplayKit::setVolume(volume);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_set_volume: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

double DLL_ALIGN ffplay_kit_get_volume(void) {
  try {
    return FFplayKit::getVolume();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffplay_kit_get_volume: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1.0;
  }
}

#ifdef __ANDROID__
#include <android/native_window.h>
extern "C" void ffplay_set_android_window(ANativeWindow *nw);

/// Sets the Android ANativeWindow for FFplay video output.
///
/// ffplay_set_android_window() owns the single retained ANativeWindow
/// reference (acquire/release inside), so the Dart caller may release its own
/// reference (via releaseNativeWindowPtr) immediately after this call returns.
/// Pass 0 to clear the window (equivalent to ffplay_kit_clear_android_surface).
void DLL_ALIGN ffplay_kit_set_android_surface_ptr(int64_t native_window_ptr) {
  ANativeWindow *nw = reinterpret_cast<ANativeWindow *>(
      static_cast<uintptr_t>(native_window_ptr));
  ffplay_set_android_window(nw);
}

/// Clears the Android ANativeWindow, releasing the retained reference and
/// stopping video output.  Call when the Surface is destroyed.
void DLL_ALIGN ffplay_kit_clear_android_surface(void) {
  ffplay_kit_set_android_surface_ptr(0);
}
#else
void DLL_ALIGN ffplay_kit_set_android_surface_ptr(int64_t /*native_window_ptr*/) {}
void DLL_ALIGN ffplay_kit_clear_android_surface(void) {}
#endif /* __ANDROID__ */

void DLL_ALIGN ffplay_kit_register_frame_callback(
    FFplayKitFrameCallback callback, void *userdata) {
  ffplay_set_frame_callback(
      reinterpret_cast<void (*)(void *, const uint8_t *, int, int, int,
                                const char *)>(callback),
      userdata);
}

void DLL_ALIGN ffplay_kit_unregister_frame_callback(void) {
  ffplay_set_frame_callback(nullptr, nullptr);
}

/* Config */

void DLL_ALIGN ffmpeg_kit_config_enable_redirection(void) {
  try {
    FFmpegKitConfig::enableRedirection();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_enable_redirection: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_config_disable_redirection(void) {
  try {
    FFmpegKitConfig::disableRedirection();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_disable_redirection: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_config_set_log_level(FFmpegKitLogLevel level) {
  try {
    FFmpegKitConfig::setLogLevel((Level)level);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_set_log_level: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

FFmpegKitLogLevel DLL_ALIGN ffmpeg_kit_config_get_log_level(void) {
  try {
    return (FFmpegKitLogLevel)FFmpegKitConfig::getLogLevel();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_get_log_level: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return FFmpegKitLogLevel::FFMPEG_KIT_LOG_LEVEL_INFO;
  }
}

char * DLL_ALIGN ffmpeg_kit_config_log_level_to_string(FFmpegKitLogLevel level) {
  try {
    return strdup_cpp(FFmpegKitConfig::logLevelToString((Level)level));
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_log_level_to_string: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return strdup_cpp(FFmpegKitConfig::logLevelToString(Level::LevelAVLogInfo));
  }
}

void DLL_ALIGN ffmpeg_kit_config_set_font_directory(const char *path,
                                          const char *name_mappings_json) {
  try {
    // Mapping JSON parsing omitted for brevity/simplicity as it requires a JSON
    // parser. Passing empty map for now if null.
    std::map<std::string, std::string> map;
    FFmpegKitConfig::setFontDirectory(path ? std::string(path) : "", map);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_set_font_directory: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

int64_t DLL_ALIGN ffmpeg_kit_config_set_environment_variable(const char *name,
                                                   const char *value) {
  try {
    if (!name || !value)
      return -1;
    return FFmpegKitConfig::setEnvironmentVariable(std::string(name),
                                                   std::string(value));
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_set_environment_variable: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

void DLL_ALIGN ffmpeg_kit_config_ignore_signal(FFmpegKitSignal signal) {
  try {
    FFmpegKitConfig::ignoreSignal((Signal)signal);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_ignore_signal: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

char * DLL_ALIGN ffmpeg_kit_config_get_ffmpeg_version(void) {
  try {
    return strdup_cpp(FFmpegKitConfig::getFFmpegVersion());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_get_ffmpeg_version: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_config_get_ffmpeg_architecture(void) {
  try {
    return strdup_cpp(FFmpegKitConfig::getFFmpegArchitecture());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_get_ffmpeg_architecture: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_config_get_version(void) {
  try {
    return strdup_cpp(FFmpegKitConfig::getVersion());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_get_version: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

void DLL_ALIGN ffmpeg_kit_config_set_audio_output_device(const char *device_name) {
  try {
    FFmpegKitConfig::setAudioOutputDevice(device_name ? std::string(device_name)
                                                      : "");
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_set_audio_output_device: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

char * DLL_ALIGN ffmpeg_kit_config_list_audio_output_devices(void) {
  try {
    return strdup_cpp(FFmpegKitConfig::listAudioOutputDevices());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_list_audio_output_devices: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

/* Packages */

char * DLL_ALIGN ffmpeg_kit_packages_get_package_name(void) {
  try {
    return strdup_cpp(Packages::getPackageName());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_package_name: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_bundled_libraries(void) {
  try {
    auto libs = Packages::getExternalLibraries();
    std::string result = "";
    for (const auto &lib : *libs) {
      if (!result.empty())
        result += ", ";
      result += lib;
    }
    return strdup_cpp(result);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_bundled_libraries: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_external_libraries(void) {
  try {
    auto libs = Packages::getExternalLibraries();
    std::string result = "";
    for (const auto &lib : *libs) {
      if (!result.empty())
        result += ", ";
      result += lib;
    }
    return strdup_cpp(result);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_external_libraries: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_bundle_type(void) {
  try {
    return strdup_cpp(Packages::getBundleType());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_bundle_type: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

bool DLL_ALIGN ffmpeg_kit_packages_get_is_gpl(void) {
  try {
    return Packages::getIsGpl();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_is_gpl: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

bool DLL_ALIGN ffmpeg_kit_packages_get_is_nonfree(void) {
  try {
    return Packages::getIsNonFree();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_is_nonfree: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_registered_codecs(void) {
  try {
    auto codecs = Packages::getRegisteredCodecs();
    std::string result = "";
    for (const auto &codec : *codecs) {
      if (!result.empty())
        result += ", ";
      result += codec;
    }
    return strdup_cpp(result);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_registered_codecs: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_registered_encoders(void) {
  try {
    auto encoders = Packages::getRegisteredEncoders();
    std::string result = "";
    for (const auto &encoder : *encoders) {
      if (!result.empty())
        result += ", ";
      result += encoder;
    }
    return strdup_cpp(result);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_registered_encoders: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_registered_decoders(void) {
  try {
    auto decoders = Packages::getRegisteredDecoders();
    std::string result = "";
    for (const auto &decoder : *decoders) {
      if (!result.empty())
        result += ", ";
      result += decoder;
    }
    return strdup_cpp(result);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_registered_decoders: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_registered_muxers(void) {
  try {
    auto muxers = Packages::getRegisteredMuxers();
    std::string result = "";
    for (const auto &muxer : *muxers) {
      if (!result.empty())
        result += ", ";
      result += muxer;
    }
    return strdup_cpp(result);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_registered_muxers: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_registered_demuxers(void) {
  try {
    auto demuxers = Packages::getRegisteredDemuxers();
    std::string result = "";
    for (const auto &demuxer : *demuxers) {
      if (!result.empty())
        result += ", ";
      result += demuxer;
    }
    return strdup_cpp(result);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_registered_demuxers: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_registered_filters(void) {
  try {
    auto filters = Packages::getRegisteredFilters();
    std::string result = "";
    for (const auto &filter : *filters) {
      if (!result.empty())
        result += ", ";
      result += filter;
    }
    return strdup_cpp(result);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_registered_filters: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_registered_protocols(void) {
  try {
    auto protocols = Packages::getRegisteredProtocols();
    std::string result = "";
    for (const auto &protocol : *protocols) {
      if (!result.empty())
        result += ", ";
      result += protocol;
    }
    return strdup_cpp(result);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_registered_protocols: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_registered_bitstream_filters(void) {
  try {
    auto bsfs = Packages::getRegisteredBitStreamFilters();
    std::string result = "";
    for (const auto &bsf : *bsfs) {
      if (!result.empty())
        result += ", ";
      result += bsf;
    }
    return strdup_cpp(result);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_registered_bitstream_filters: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_packages_get_build_configuration(void) {
  try {
    return strdup_cpp(Packages::getBuildConfiguration());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_packages_get_build_configuration: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

/* Session Management */

int64_t DLL_ALIGN ffmpeg_kit_session_get_session_id(void *session_handle) {
  try {
    if (!session_handle)
      return -1;
    auto ptr = get_ptr<Session>(session_handle);
    return ptr ? ptr->getSessionId() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_session_id: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

FFmpegKitSessionState DLL_ALIGN ffmpeg_kit_session_get_state(void *session_handle) {
  try {
    if (!session_handle)
      return FFMPEG_KIT_SESSION_STATE_CREATED;
    auto ptr = get_ptr<Session>(session_handle);
    return ptr ? (FFmpegKitSessionState)ptr->getState()
               : FFMPEG_KIT_SESSION_STATE_CREATED;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_state: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return FFMPEG_KIT_SESSION_STATE_FAILED;
  }
}

int64_t DLL_ALIGN ffmpeg_kit_session_get_return_code(void *session_handle) {
  try {
    if (!session_handle)
      return -1;
    auto ptr = get_ptr<Session>(session_handle);
    auto obj = ptr ? ptr->getReturnCode() : nullptr;
    return obj ? obj->getValue() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_return_code: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

char * DLL_ALIGN ffmpeg_kit_session_get_output(void *session_handle) {
  try {
    if (!session_handle)
      return nullptr;
    auto ptr = get_ptr<Session>(session_handle);
    return ptr ? strdup_cpp(ptr->getOutput()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_output: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_session_get_logs_as_string(void *session_handle) {
  try {
    if (!session_handle)
      return nullptr;
    auto ptr = get_ptr<Session>(session_handle);
    return ptr ? strdup_cpp(ptr->getLogsAsString()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_logs_as_string: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_session_get_fail_stack_trace(void *session_handle) {
  try {
    if (!session_handle)
      return nullptr;
    auto ptr = get_ptr<Session>(session_handle);
    return ptr ? strdup_cpp(ptr->getFailStackTrace()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_fail_stack_trace: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

/* Media Information Session Specific */

MediaInformationSessionHandle DLL_ALIGN
media_information_create_session(const char *command) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = MediaInformationSession::create(arguments);
    return create_handle(session);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_create_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

MediaInformationSessionHandle DLL_ALIGN
media_information_create_session_from_argv(int argc, const char **argv) {
  try {
    if (!argv || argc <= 0)
      return nullptr;

    std::list<std::string> arguments;
    for (int i = 0; i < argc; i++) {
      if (!argv[i])
        return nullptr;
      arguments.emplace_back(argv[i]);
    }

    auto session = MediaInformationSession::create(arguments);
    return create_handle(session);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [Exception] in "
                 "media_information_create_session_from_argv: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

MediaInformationSessionHandle DLL_ALIGN media_information_create_session_with_callbacks(
    const char *command, ::MediaInformationSessionCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data) {
  try {
    if (!command)
      return nullptr;
    auto arguments = FFmpegKitConfig::parseArguments(command);
    auto session = MediaInformationSession::create(arguments);
    MediaInformationSessionHandle handle = create_handle(session);

    auto complete =[complete_cb, user_data,
                     handle](std::shared_ptr<Session> s) {
      if (complete_cb) {
        complete_cb(handle, user_data);
      }
    };
    auto log =[log_cb, user_data, handle](std::shared_ptr<Log> l) {
      if (log_cb && l) {
        std::string message = l->getMessage();
        log_cb(handle, message.c_str(), user_data);
      }
    };
    session->setCompleteCallback(complete);
    session->setLogCallback(log);
    return handle;
  } catch (const std::exception &e) {
    std::cerr
        << "[Exception] in media_information_create_session_with_callbacks: "
        << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

void DLL_ALIGN media_information_kit_set_log_callback(
    MediaInformationSessionHandle session, FFmpegKitLogCallback log_cb,
    void *user_data) {
  try {
    auto ptr = get_ptr<MediaInformationSession>(session);
    if (ptr) {
      auto log = [log_cb, user_data, session](std::shared_ptr<Log> l) {
        if (log_cb && l) {
          std::string message = l->getMessage();
          log_cb(session, message.c_str(), user_data);
        }
      };
      ptr->setLogCallback(log);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_kit_set_log_callback: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN media_information_kit_set_complete_callback(
    MediaInformationSessionHandle session,
    ::MediaInformationSessionCompleteCallback complete_cb, void *user_data) {
  try {
    auto ptr = get_ptr<MediaInformationSession>(session);
    if (ptr) {
      auto complete =[complete_cb, user_data,
                       session](std::shared_ptr<Session> s) {
        if (complete_cb && s) {
          complete_cb(session, user_data);
        }
      };
      ptr->setCompleteCallback(complete);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_kit_set_complete_callback: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN media_information_kit_set_callbacks(
    MediaInformationSessionHandle session,
    ::MediaInformationSessionCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data) {
  try {
    auto ptr = get_ptr<MediaInformationSession>(session);
    if (ptr) {
      auto complete = [complete_cb, user_data,
                       session](std::shared_ptr<Session> s) {
        if (complete_cb && s) {
          complete_cb(session, user_data);
        }
      };
      auto log =[log_cb, user_data, session](std::shared_ptr<Log> l) {
        if (log_cb && l) {
          std::string message = l->getMessage();
          log_cb(session, message.c_str(), user_data);
        }
      };
      ptr->setCompleteCallback(complete);
      ptr->setLogCallback(log);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_kit_set_callbacks: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN media_information_session_execute(MediaInformationSessionHandle session,
                                       int64_t timeout) {
  try {
    auto ptr = get_ptr<MediaInformationSession>(session);
    if (ptr) {
      FFmpegKitConfig::getMediaInformationExecute(ptr, timeout);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_session_execute: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN media_information_session_execute_async(
    MediaInformationSessionHandle session, int64_t timeout) {
  try {
    auto ptr = get_ptr<MediaInformationSession>(session);
    if (ptr) {
      FFmpegKitConfig::asyncGetMediaInformationExecute(ptr, timeout);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_session_execute_async: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

MediaInformationHandle DLL_ALIGN media_information_session_get_media_information(
    MediaInformationSessionHandle session) {
  try {
    if (!session)
      return nullptr;
    auto ptr = get_ptr<MediaInformationSession>(session);
    auto info = ptr ? ptr->getMediaInformation() : nullptr;
    return create_handle(info);
  } catch (const std::exception &e) {
    std::cerr
        << "[Exception] in media_information_session_get_media_information: "
        << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

/* Media Information */

char * DLL_ALIGN media_information_get_filename(MediaInformationHandle handle) {
  try {
    auto ptr = get_ptr<MediaInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getFilename()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_filename: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN media_information_get_format(MediaInformationHandle handle) {
  try {
    auto ptr = get_ptr<MediaInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getFormat()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_format: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN media_information_get_long_format(MediaInformationHandle handle) {
  try {
    auto ptr = get_ptr<MediaInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getLongFormat()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_long_format: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN media_information_get_duration(MediaInformationHandle handle) {
  try {
    auto ptr = get_ptr<MediaInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getDuration()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_duration: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN media_information_get_bitrate(MediaInformationHandle handle) {
  try {
    auto ptr = get_ptr<MediaInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getBitrate()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_bitrate: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN media_information_get_size(MediaInformationHandle handle) {
  try {
    auto ptr = get_ptr<MediaInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getSize()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_size: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN media_information_get_tags_json(MediaInformationHandle handle) {
  try {
    auto ptr = get_ptr<MediaInformation>(handle);
    if (!ptr)
      return nullptr;
    auto tags = ptr->getTags();
    return tags ? strdup_cpp(tags->toStyledString()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_tags_json: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

int64_t DLL_ALIGN media_information_get_streams_count(MediaInformationHandle handle) {
  try {
    if (!handle)
      return 0;
    auto ptr = get_ptr<MediaInformation>(handle);
    auto streams = ptr ? ptr->getStreams() : nullptr;
    return streams ? streams->size() : 0;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_streams_count: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

StreamInformationHandle DLL_ALIGN
media_information_get_stream_at(MediaInformationHandle handle, int64_t index) {
  try {
    if (!handle)
      return nullptr;
    auto ptr = get_ptr<MediaInformation>(handle);
    auto streams = ptr ? ptr->getStreams() : nullptr;
    if (streams && index >= 0 && index < streams->size()) {
      return create_handle(streams->at(index));
    }
    return nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_stream_at: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

int64_t DLL_ALIGN media_information_get_chapters_count(MediaInformationHandle handle) {
  try {
    if (!handle)
      return 0;
    auto ptr = get_ptr<MediaInformation>(handle);
    auto chapters = ptr ? ptr->getChapters() : nullptr;
    return chapters ? chapters->size() : 0;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_chapters_count: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

ChapterHandle DLL_ALIGN media_information_get_chapter_at(MediaInformationHandle handle,
                                               int64_t index) {
  try {
    if (!handle)
      return nullptr;
    auto ptr = get_ptr<MediaInformation>(handle);
    auto chapters = ptr ? ptr->getChapters() : nullptr;
    if (chapters && index >= 0 && index < chapters->size()) {
      return create_handle(chapters->at(index));
    }
    return nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_chapter_at: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

/* Stream Information */

#define STREAM_GETTER(Func, Type)                                              \
  Type * DLL_ALIGN stream_information_get_##Func(StreamInformationHandle handle) { \
    auto ptr = get_ptr<StreamInformation>(handle);                             \
    return ptr ? strdup_safe_ptr(ptr->get##Func()) : nullptr;                  \
  }

char * DLL_ALIGN stream_information_get_type(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getType()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_type: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN stream_information_get_codec(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getCodec()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_codec: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN stream_information_get_codec_long(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getCodecLong()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_codec_long: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN stream_information_get_format(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getFormat()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_format: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN stream_information_get_bitrate(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getBitrate()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_bitrate: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN stream_information_get_sample_rate(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getSampleRate()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_sample_rate: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN stream_information_get_sample_format(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getSampleFormat()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_sample_format: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN
stream_information_get_display_aspect_ratio(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getDisplayAspectRatio()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_display_aspect_ratio: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN
stream_information_get_average_frame_rate(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getAverageFrameRate()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_average_frame_rate: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN stream_information_get_real_frame_rate(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getRealFrameRate()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_real_frame_rate: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN stream_information_get_time_base(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getTimeBase()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_time_base: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

int64_t DLL_ALIGN stream_information_get_width(StreamInformationHandle handle) {
  try {
    if (!handle)
      return 0;
    auto ptr = get_ptr<StreamInformation>(handle);
    auto val = ptr ? ptr->getWidth() : nullptr;
    return val ? *val : 0;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_width: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
int64_t DLL_ALIGN stream_information_get_height(StreamInformationHandle handle) {
  try {
    if (!handle)
      return 0;
    auto ptr = get_ptr<StreamInformation>(handle);
    auto val = ptr ? ptr->getHeight() : nullptr;
    return val ? *val : 0;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_height: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
int64_t DLL_ALIGN stream_information_get_index(StreamInformationHandle handle) {
  try {
    if (!handle)
      return -1;
    auto ptr = get_ptr<StreamInformation>(handle);
    auto val = ptr ? ptr->getIndex() : nullptr;
    return val ? *val : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_index: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
char * DLL_ALIGN stream_information_get_tags_json(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    auto tags = ptr ? ptr->getTags() : nullptr;
    return tags ? strdup_cpp(tags->toStyledString()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_tags_json: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

/* Chapter */
int64_t DLL_ALIGN chapter_get_id(ChapterHandle handle) {
  try {
    if (!handle)
      return -1;
    auto ptr = get_ptr<Chapter>(handle);
    auto val = ptr ? ptr->getId() : nullptr;
    return val ? *val : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in chapter_get_id: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
char * DLL_ALIGN chapter_get_time_base(ChapterHandle handle) {
  try {
    auto ptr = get_ptr<Chapter>(handle);
    return ptr ? strdup_safe_ptr(ptr->getTimeBase()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in chapter_get_time_base: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
int64_t DLL_ALIGN chapter_get_start(ChapterHandle handle) {
  try {
    if (!handle)
      return -1;
    auto ptr = get_ptr<Chapter>(handle);
    auto val = ptr ? ptr->getStart() : nullptr;
    return val ? *val : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in chapter_get_start: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
char * DLL_ALIGN chapter_get_start_time(ChapterHandle handle) {
  try {
    auto ptr = get_ptr<Chapter>(handle);
    return ptr ? strdup_safe_ptr(ptr->getStartTime()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in chapter_get_start_time: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
int64_t DLL_ALIGN chapter_get_end(ChapterHandle handle) {
  try {
    if (!handle)
      return -1;
    auto ptr = get_ptr<Chapter>(handle);
    auto val = ptr ? ptr->getEnd() : nullptr;
    return val ? *val : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in chapter_get_end: " << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
char * DLL_ALIGN chapter_get_end_time(ChapterHandle handle) {
  try {
    auto ptr = get_ptr<Chapter>(handle);
    return ptr ? strdup_safe_ptr(ptr->getEndTime()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in chapter_get_end_time: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
char * DLL_ALIGN chapter_get_tags_json(ChapterHandle handle) {
  try {
    auto ptr = get_ptr<Chapter>(handle);
    auto tags = ptr ? ptr->getTags() : nullptr;
    return tags ? strdup_cpp(tags->toStyledString()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in chapter_get_tags_json: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

/* Session History */
FFmpegSessionHandle * DLL_ALIGN ffmpeg_kit_get_sessions(void) {
  try {
    return (FFmpegSessionHandle *)list_to_handle_array(
        FFmpegKitConfig::getSessions());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_sessions: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
FFmpegSessionHandle * DLL_ALIGN ffmpeg_kit_list_sessions(void) {
  try {
    return ffmpeg_kit_get_sessions();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_list_sessions: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFmpegSessionHandle * DLL_ALIGN ffmpeg_kit_get_ffmpeg_sessions(void) {
  try {
    return (FFmpegSessionHandle *)list_to_handle_array(
        FFmpegKitConfig::getFFmpegSessions());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_ffmpeg_sessions: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFprobeSessionHandle * DLL_ALIGN ffmpeg_kit_get_ffprobe_sessions(void) {
  try {
    return (FFprobeSessionHandle *)list_to_handle_array(
        FFmpegKitConfig::getFFprobeSessions());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_ffprobe_sessions: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
FFprobeSessionHandle * DLL_ALIGN ffprobe_kit_list_sessions(void) {
  try {
    return ffmpeg_kit_get_ffprobe_sessions();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_list_sessions: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFplaySessionHandle * DLL_ALIGN ffmpeg_kit_get_ffplay_sessions(void) {
  try {
    return (FFplaySessionHandle *)list_to_handle_array(
        FFmpegKitConfig::getFFplaySessions());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_ffplay_sessions: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

MediaInformationSessionHandle * DLL_ALIGN ffmpeg_kit_get_media_information_sessions(void) {
  try {
    return (MediaInformationSessionHandle *)list_to_handle_array(
        FFmpegKitConfig::getMediaInformationSessions());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_media_information_sessions: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
MediaInformationSessionHandle * DLL_ALIGN media_information_kit_list_sessions(void) {
  try {
    return ffmpeg_kit_get_media_information_sessions();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_kit_list_sessions: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFmpegSessionHandle DLL_ALIGN ffmpeg_kit_get_session(int64_t session_id) {
  try {
    return create_handle(FFmpegKitConfig::getSession(session_id));
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFmpegSessionHandle DLL_ALIGN ffmpeg_kit_get_last_session(void) {
  try {
    return create_handle(FFmpegKitConfig::getLastSession());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_last_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFmpegSessionHandle DLL_ALIGN ffmpeg_kit_get_last_ffmpeg_session(void) {
  try {
    return create_handle(FFmpegKitConfig::getLastFFmpegSession());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_last_ffmpeg_session: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFprobeSessionHandle DLL_ALIGN ffmpeg_kit_get_last_ffprobe_session(void) {
  try {
    return create_handle(FFmpegKitConfig::getLastFFprobeSession());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_last_ffprobe_session: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
FFprobeSessionHandle DLL_ALIGN ffprobe_kit_get_last_session(void) {
  try {
    return ffmpeg_kit_get_last_ffprobe_session();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_get_last_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}
FFprobeSessionHandle DLL_ALIGN ffprobe_kit_get_last_completed_session(void) {
  try {
    auto session = FFmpegKitConfig::getLastCompletedSession();
    if (session && session->isFFprobe()) {
      return create_handle(session);
    }
    return nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffprobe_kit_get_last_completed_session: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFplaySessionHandle DLL_ALIGN ffmpeg_kit_get_last_ffplay_session(void) {
  try {
    return create_handle(FFmpegKitConfig::getLastFFplaySession());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_last_ffplay_session: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

MediaInformationSessionHandle DLL_ALIGN
ffmpeg_kit_get_last_media_information_session(void) {
  try {
    return create_handle(FFmpegKitConfig::getLastMediaInformationSession());
  } catch (const std::exception &e) {
    std::cerr
        << "[Exception] in ffmpeg_kit_get_last_media_information_session: "
        << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

FFmpegSessionHandle DLL_ALIGN ffmpeg_kit_get_last_completed_session(void) {
  try {
    return create_handle(FFmpegKitConfig::getLastCompletedSession());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_last_completed_session: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

int64_t DLL_ALIGN ffmpeg_kit_get_session_history_size(void) {
  try {
    return FFmpegKitConfig::getSessionHistorySize();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_get_session_history_size: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

void DLL_ALIGN ffmpeg_kit_set_session_history_size(int64_t size) {
  try {
    FFmpegKitConfig::setSessionHistorySize(size);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_set_session_history_size: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_clear_sessions(void) {
  try {
    FFmpegKitConfig::clearSessions();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_clear_sessions: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

} /* End extern "C" */

/* Global Callbacks */
// Static storage for callbacks
static FFmpegKitLogCallback g_log_callback = nullptr;
static void *g_log_user_data = nullptr;

static FFmpegKitStatisticsCallback g_stats_callback = nullptr;
static void *g_stats_user_data = nullptr;

static FFmpegKitCompleteCallback g_ffmpeg_complete_callback = nullptr;
static void *g_ffmpeg_complete_user_data = nullptr;

static FFprobeKitCompleteCallback g_ffprobe_complete_callback = nullptr;
static void *g_ffprobe_complete_user_data = nullptr;

static FFplayKitCompleteCallback g_ffplay_complete_callback = nullptr;
static void *g_ffplay_complete_user_data = nullptr;

static ::MediaInformationSessionCompleteCallback g_media_complete_callback =
    nullptr;
static void *g_media_complete_user_data = nullptr;

extern "C" {
void DLL_ALIGN ffmpeg_kit_config_enable_log_callback(FFmpegKitLogCallback log_cb,
                                           void *user_data) {
  try {
    g_log_callback = log_cb;
    g_log_user_data = user_data;
    if (log_cb) {
      FFmpegKitConfig::enableLogCallback([](std::shared_ptr<Log> log) {
        if (g_log_callback && log) {
          const std::string &message = log->getMessage();

          // Pass ID as pointer (Hack to avoid allocation/threading issues)
          void *session_handle = (void *)(uintptr_t)log->getSessionId();

          g_log_callback(session_handle, message.c_str(), g_log_user_data);
        }
      });
    } else {
      FFmpegKitConfig::enableLogCallback(nullptr);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_enable_log_callback: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_config_enable_statistics_callback(
    FFmpegKitStatisticsCallback stats_cb, void *user_data) {
  try {
    g_stats_callback = stats_cb;
    g_stats_user_data = user_data;
    if (stats_cb) {
      FFmpegKitConfig::enableStatisticsCallback([](std::shared_ptr<Statistics> s) {
            if (g_stats_callback && s) {
              // Pass ID as pointer (Hack to avoid allocation/threading issues)
              void *session_handle = (void *)(uintptr_t)s->getSessionId();

              g_stats_callback(session_handle, (int64_t)(s->getTimeElapsed() * 1000), (int64_t)(s->getTime() * 1000), s->getSize(),
                               s->getBitrate(), s->getSpeed(),
                               s->getVideoFrameNumber(), s->getVideoFps(),
                               s->getVideoQuality(), s->getDupFrames(),
                               s->getDropFrames(), g_stats_user_data);
            }
          });
    } else {
      FFmpegKitConfig::enableStatisticsCallback(nullptr);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_enable_statistics_callback: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(
    FFmpegKitCompleteCallback complete_cb, void *user_data) {
  try {
    g_ffmpeg_complete_callback = complete_cb;
    g_ffmpeg_complete_user_data = user_data;
    if (complete_cb) {
      FFmpegKitConfig::enableFFmpegSessionCompleteCallback([](std::shared_ptr<FFmpegSession> title) {
            if (g_ffmpeg_complete_callback) {
              auto handle = create_handle(title);
              g_ffmpeg_complete_callback(handle, g_ffmpeg_complete_user_data);
              // Handle ownership transferred to Dart callback
            }
          });
    } else {
      FFmpegKitConfig::enableFFmpegSessionCompleteCallback(nullptr);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in "
                 "ffmpeg_kit_config_enable_ffmpeg_session_complete_callback: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_config_enable_ffprobe_session_complete_callback(
    FFprobeKitCompleteCallback complete_cb, void *user_data) {
  try {
    g_ffprobe_complete_callback = complete_cb;
    g_ffprobe_complete_user_data = user_data;
    if (complete_cb) {
      FFmpegKitConfig::enableFFprobeSessionCompleteCallback([](std::shared_ptr<FFprobeSession> title) {
            if (g_ffprobe_complete_callback) {
              auto handle = create_handle(title);
              g_ffprobe_complete_callback(handle, g_ffprobe_complete_user_data);
              // Handle ownership transferred to Dart callback
            }
          });
    } else {
      FFmpegKitConfig::enableFFprobeSessionCompleteCallback(nullptr);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in "
                 "ffmpeg_kit_config_enable_ffprobe_session_complete_callback: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_config_enable_ffplay_session_complete_callback(
    FFplayKitCompleteCallback complete_cb, void *user_data) {
  try {
    g_ffplay_complete_callback = complete_cb;
    g_ffplay_complete_user_data = user_data;
    if (complete_cb) {
      FFmpegKitConfig::enableFFplaySessionCompleteCallback([](std::shared_ptr<FFplaySession> title) {
            if (g_ffplay_complete_callback) {
              auto handle = create_handle(title);
              g_ffplay_complete_callback(handle, g_ffplay_complete_user_data);
              // Handle ownership transferred to Dart callback
            }
          });
    } else {
      FFmpegKitConfig::enableFFplaySessionCompleteCallback(nullptr);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in "
                 "ffmpeg_kit_config_enable_ffplay_session_complete_callback: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_config_enable_media_information_session_complete_callback(
    ::MediaInformationSessionCompleteCallback complete_cb, void *user_data) {
  try {
    g_media_complete_callback = complete_cb;
    g_media_complete_user_data = user_data;
    if (complete_cb) {
      FFmpegKitConfig::enableMediaInformationSessionCompleteCallback([](std::shared_ptr<MediaInformationSession> title) {
            if (g_media_complete_callback) {
              auto handle = create_handle(title);
              g_media_complete_callback(handle, g_media_complete_user_data);
              // Handle ownership transferred to Dart callback
            }
          });
    } else {
      FFmpegKitConfig::enableMediaInformationSessionCompleteCallback(nullptr);
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in "
                 "ffmpeg_kit_config_enable_media_information_session_complete_"
                 "callback: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

/* Utils */
char * DLL_ALIGN ffmpeg_kit_config_register_new_ffmpeg_pipe(void) {
  try {
    return strdup_safe_ptr(FFmpegKitConfig::registerNewFFmpegPipe());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_register_new_ffmpeg_pipe: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

void DLL_ALIGN ffmpeg_kit_config_close_ffmpeg_pipe(const char *pipe_path) {
  try {
    if (pipe_path) {
      FFmpegKitConfig::closeFFmpegPipe(std::string(pipe_path));
    }
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_close_ffmpeg_pipe: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_config_set_font_directory_list(const char **font_directory_list,
                                               int64_t list_size,
                                               const char *name_mappings_json) {
  try {
    std::list<std::string> fonts;
    if (font_directory_list) {
      for (int64_t i = 0; i < list_size; i++) {
        if (font_directory_list[i]) {
          fonts.push_back(std::string(font_directory_list[i]));
        }
      }
    }
    std::map<std::string, std::string> map;
    FFmpegKitConfig::setFontDirectoryList(fonts, map);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_set_font_directory_list: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

char * DLL_ALIGN ffmpeg_kit_config_get_build_date(void) {
  try {
    return strdup_cpp(FFmpegKitConfig::getBuildDate());
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_get_build_date: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_config_session_state_to_string(FFmpegKitSessionState state) {
  try {
    return strdup_cpp(
        FFmpegKitConfig::sessionStateToString((SessionState)state));
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_session_state_to_string: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char ** DLL_ALIGN ffmpeg_kit_config_parse_arguments(const char *command,
                                         int64_t *arg_count) {
  try {
    if (!command)
      return nullptr;
    auto list = FFmpegKitConfig::parseArguments(std::string(command));
    if (arg_count)
      *arg_count = list.size();

    char **array = (char **)malloc((list.size() + 1) * sizeof(char *));
    if (!array)
      return nullptr;

    size_t i = 0;
    for (const auto &arg : list) {
      array[i++] = strdup_cpp(arg);
    }
    array[i] = nullptr;
    return array;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_parse_arguments: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN ffmpeg_kit_config_arguments_to_string(char **arguments,
                                            int64_t arg_count) {
  try {
    if (!arguments)
      return nullptr;
    auto list = std::make_shared<std::list<std::string>>();
    for (int64_t i = 0; i < arg_count; i++) {
      if (arguments[i]) {
        list->push_back(std::string(arguments[i]));
      }
    }
    return strdup_cpp(FFmpegKitConfig::argumentsToString(list));
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_arguments_to_string: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

int64_t DLL_ALIGN ffmpeg_kit_config_messages_in_transmit(int64_t session_id) {
  try {
    return FFmpegKitConfig::messagesInTransmit(session_id);
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_messages_in_transmit: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

/* Session Management Extended */
int64_t DLL_ALIGN ffmpeg_kit_session_get_create_time(void *session_handle) {
  try {
    if (!session_handle)
      return 0;
    auto ptr = get_ptr<Session>(session_handle);
    if (!ptr)
      return -1;
    auto tp = ptr->getCreateTime();
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               tp.time_since_epoch())
        .count();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_create_time: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

int64_t DLL_ALIGN ffmpeg_kit_session_get_start_time(void *session_handle) {
  try {
    if (!session_handle)
      return 0;
    auto ptr = get_ptr<Session>(session_handle);
    if (!ptr)
      return -1;
    auto tp = ptr->getStartTime();
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               tp.time_since_epoch())
        .count();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_start_time: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

int64_t DLL_ALIGN ffmpeg_kit_session_get_end_time(void *session_handle) {
  try {
    if (!session_handle)
      return 0;
    auto ptr = get_ptr<Session>(session_handle);
    if (!ptr)
      return -1;
    auto tp = ptr->getEndTime();
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               tp.time_since_epoch())
        .count();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_end_time: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

int64_t DLL_ALIGN ffmpeg_kit_session_get_duration(void *session_handle) {
  try {
    if (!session_handle)
      return 0;
    auto ptr = get_ptr<Session>(session_handle);
    return ptr ? ptr->getDuration() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_duration: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

char * DLL_ALIGN ffmpeg_kit_session_get_command(void *session_handle) {
  try {
    if (!session_handle)
      return nullptr;
    auto ptr = get_ptr<Session>(session_handle);
    return ptr ? strdup_cpp(ptr->getCommand()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_command: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

int64_t DLL_ALIGN ffmpeg_kit_session_get_logs_count(void *session_handle) {
  try {
    if (!session_handle)
      return 0;
    auto ptr = get_ptr<Session>(session_handle);
    return ptr ? ptr->getLogsCount() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_logs_count: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

char * DLL_ALIGN ffmpeg_kit_session_get_log_at(void *session_handle, int64_t index) {
  try {
    if (!session_handle)
      return nullptr;
    auto ptr = get_ptr<Session>(session_handle);
    auto log = ptr ? ptr->getLogAt(index) : nullptr;
    if (log) {
      const std::string &message = log->getMessage();
      return strdup_cpp(message);
    }
    return nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_log_at: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

int64_t DLL_ALIGN ffmpeg_kit_session_get_log_level_at(void *session_handle,
                                            int64_t index) {
  try {
    if (!session_handle)
      return 0;
    auto ptr = get_ptr<Session>(session_handle);
    auto log = ptr ? ptr->getLogAt(index) : nullptr;
    if (log) {
      return (int64_t)log->getLevel();
    }
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_log_level_at: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

int64_t DLL_ALIGN ffmpeg_kit_session_get_statistics_count(void *session_handle) {
  try {
    if (!session_handle)
      return 0;
    auto ptr = get_ptr<FFmpegSession>(session_handle);
    return ptr ? ptr->getStatisticsCount() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_statistics_count: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

StatisticsHandle DLL_ALIGN ffmpeg_kit_session_get_statistics_at(void *session_handle,
                                                      int64_t index) {
  try {
    if (!session_handle)
      return nullptr;
    auto ptr = get_ptr<FFmpegSession>(session_handle);
    auto stats = ptr ? ptr->getStatisticsAt(index) : nullptr;
    if (stats) {
      return create_handle(stats);
    }
    return nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_session_get_statistics_at: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

/* Statistics Getters */
int64_t DLL_ALIGN ffmpeg_kit_statistics_get_video_frame_number(StatisticsHandle handle) {
  try {
    auto ptr = get_ptr<Statistics>(handle);
    return ptr ? ptr->getVideoFrameNumber() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_statistics_get_video_frame_number: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
double DLL_ALIGN ffmpeg_kit_statistics_get_video_fps(StatisticsHandle handle) {
  try {
    auto ptr = get_ptr<Statistics>(handle);
    return ptr ? ptr->getVideoFps() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_statistics_get_video_fps: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
double DLL_ALIGN ffmpeg_kit_statistics_get_video_quality(StatisticsHandle handle) {
  try {
    auto ptr = get_ptr<Statistics>(handle);
    return ptr ? ptr->getVideoQuality() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_statistics_get_video_quality: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
int64_t DLL_ALIGN ffmpeg_kit_statistics_get_size(StatisticsHandle handle) {
  try {
    auto ptr = get_ptr<Statistics>(handle);
    return ptr ? (int64_t)ptr->getSize() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_statistics_get_size: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
double DLL_ALIGN ffmpeg_kit_statistics_get_time(StatisticsHandle handle) {
  try {
    auto ptr = get_ptr<Statistics>(handle);
    return ptr ? ptr->getTime() * 1000.0 : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_statistics_get_time: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
double DLL_ALIGN ffmpeg_kit_statistics_get_time_elapsed(StatisticsHandle handle) {
  try {
    auto ptr = get_ptr<Statistics>(handle);
    return ptr ? ptr->getTimeElapsed() * 1000.0 : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_statistics_get_time_elapsed: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
double DLL_ALIGN ffmpeg_kit_statistics_get_bitrate(StatisticsHandle handle) {
  try {
    auto ptr = get_ptr<Statistics>(handle);
    return ptr ? ptr->getBitrate() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_statistics_get_bitrate: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}
double DLL_ALIGN ffmpeg_kit_statistics_get_speed(StatisticsHandle handle) {
  try {
    auto ptr = get_ptr<Statistics>(handle);
    return ptr ? ptr->getSpeed() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_statistics_get_speed: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

int64_t DLL_ALIGN ffmpeg_kit_statistics_get_dup_frames(
    StatisticsHandle handle) {
  try {
    auto ptr = get_ptr<Statistics>(handle);
    return ptr ? ptr->getDupFrames() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_statistics_get_dup_frames: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

int64_t DLL_ALIGN ffmpeg_kit_statistics_get_drop_frames(
    StatisticsHandle handle) {
  try {
    auto ptr = get_ptr<Statistics>(handle);
    return ptr ? ptr->getDropFrames() : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_statistics_get_drop_frames: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

/* Entity Properties Extended */

char * DLL_ALIGN media_information_get_start_time(MediaInformationHandle handle) {
  try {
    auto ptr = get_ptr<MediaInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getStartTime()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_start_time: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN media_information_get_string_property(MediaInformationHandle handle,
                                            const char *key) {
  try {
    auto ptr = get_ptr<MediaInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getStringProperty(key)) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_string_property: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

int64_t DLL_ALIGN media_information_get_number_property(MediaInformationHandle handle,
                                              const char *key) {
  try {
    auto ptr = get_ptr<MediaInformation>(handle);
    auto val = ptr ? ptr->getNumberProperty(key) : nullptr;
    return val ? *val : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_number_property: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

char * DLL_ALIGN media_information_get_all_properties_json(MediaInformationHandle handle) {
  try {
    auto ptr = get_ptr<MediaInformation>(handle);
    auto props = ptr ? ptr->getAllProperties() : nullptr;
    return props ? strdup_cpp(props->toStyledString()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in media_information_get_all_properties_json: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

// StreamInformation
char * DLL_ALIGN stream_information_get_channel_layout(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getChannelLayout()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_channel_layout: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN
stream_information_get_sample_aspect_ratio(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getSampleAspectRatio()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_sample_aspect_ratio: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN stream_information_get_codec_time_base(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getCodecTimeBase()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_codec_time_base: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

char * DLL_ALIGN stream_information_get_string_property(StreamInformationHandle handle,
                                             const char *key) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    return ptr ? strdup_safe_ptr(ptr->getStringProperty(key)) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_string_property: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

int64_t DLL_ALIGN stream_information_get_number_property(StreamInformationHandle handle,
                                               const char *key) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    auto val = ptr ? ptr->getNumberProperty(key) : nullptr;
    return val ? *val : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_number_property: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

char * DLL_ALIGN
stream_information_get_all_properties_json(StreamInformationHandle handle) {
  try {
    auto ptr = get_ptr<StreamInformation>(handle);
    auto props = ptr ? ptr->getAllProperties() : nullptr;
    return props ? strdup_cpp(props->toStyledString()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in stream_information_get_all_properties_json: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

// Chapter
char * DLL_ALIGN chapter_get_string_property(ChapterHandle handle, const char *key) {
  try {
    auto ptr = get_ptr<Chapter>(handle);
    return ptr ? strdup_safe_ptr(ptr->getStringProperty(key)) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in chapter_get_string_property: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

int64_t DLL_ALIGN chapter_get_number_property(ChapterHandle handle, const char *key) {
  try {
    auto ptr = get_ptr<Chapter>(handle);
    auto val = ptr ? ptr->getNumberProperty(key) : nullptr;
    return val ? *val : -1;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in chapter_get_number_property: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return -1;
  }
}

char * DLL_ALIGN chapter_get_all_properties_json(ChapterHandle handle) {
  try {
    auto ptr = get_ptr<Chapter>(handle);
    auto props = ptr ? ptr->getAllProperties() : nullptr;
    return props ? strdup_cpp(props->toStyledString()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in chapter_get_all_properties_json: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

bool DLL_ALIGN session_is_ffmpeg_session(void *session) {
  try {
    if (!session)
      return false;
    auto ptr = get_ptr<AbstractSession>(session);
    return ptr ? ptr->isFFmpeg() : false;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in session_is_ffmpeg_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

bool DLL_ALIGN session_is_ffprobe_session(void *session) {
  try {
    if (!session)
      return false;
    auto ptr = get_ptr<AbstractSession>(session);
    return ptr ? ptr->isFFprobe() : false;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in session_is_ffprobe_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

bool DLL_ALIGN session_is_ffplay_session(void *session) {
  try {
    if (!session)
      return false;
    auto ptr = get_ptr<AbstractSession>(session);
    return ptr ? ptr->isFFplay() : false;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in session_is_ffplay_session: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

bool DLL_ALIGN session_is_media_information_session(void *session) {
  try {
    if (!session)
      return false;
    auto ptr = get_ptr<AbstractSession>(session);
    return ptr ? ptr->isMediaInformation() : false;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in session_is_media_information_session: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

void DLL_ALIGN ffmpeg_kit_free(void *ptr) {
  if (ptr) {
    free(ptr);
  }
}

void DLL_ALIGN session_enable_debug_log(void *session) {
  try {
    if (!session)
      return;
    auto ptr = get_ptr<AbstractSession>(session);
    if (ptr)
      ptr->enableDebugLog();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in session_enable_debug_log: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN session_disable_debug_log(void *session) {
  try {
    if (!session)
      return;
    auto ptr = get_ptr<AbstractSession>(session);
    if (ptr)
      ptr->disableDebugLog();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in session_disable_debug_log: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

bool DLL_ALIGN session_is_debug_log_enabled(void *session) {
  try {
    if (!session)
      return false;
    auto ptr = get_ptr<AbstractSession>(session);
    return ptr ? ptr->isDebugLogEnabled() : false;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in session_is_debug_log_enabled: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

char * DLL_ALIGN session_get_debug_log(void *session) {
  try {
    if (!session)
      return nullptr;
    auto ptr = get_ptr<AbstractSession>(session);
    return ptr ? strdup_cpp(ptr->getDebugLog()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in session_get_debug_log: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

void DLL_ALIGN session_clear_debug_log(void *session) {
  try {
    if (!session)
      return;
    auto ptr = get_ptr<AbstractSession>(session);
    if (ptr)
      ptr->clearDebugLog();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in session_clear_debug_log: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_config_enable_debug_log(void *session) {
  try {
    if (!session)
      return;
    auto ptr = get_ptr<AbstractSession>(session);
    if (ptr)
      ptr->enableDebugLog();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_enable_debug_log: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

void DLL_ALIGN ffmpeg_kit_config_disable_debug_log(void *session) {
  try {
    if (!session)
      return;
    auto ptr = get_ptr<AbstractSession>(session);
    if (ptr)
      ptr->disableDebugLog();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_disable_debug_log: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}

bool DLL_ALIGN ffmpeg_kit_config_is_debug_log_enabled(void *session) {
  try {
    if (!session)
      return false;
    auto ptr = get_ptr<AbstractSession>(session);
    return ptr ? ptr->isDebugLogEnabled() : false;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_is_debug_log_enabled: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
    return false;
  }
}

char * DLL_ALIGN ffmpeg_kit_config_get_debug_log(void *session) {
  try {
    if (!session)
      return nullptr;
    auto ptr = get_ptr<AbstractSession>(session);
    return ptr ? strdup_cpp(ptr->getDebugLog()) : nullptr;
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_get_debug_log: " << e.what()
              << std::endl;
    PRINT_STACK_TRACE();
    return nullptr;
  }
}

void DLL_ALIGN ffmpeg_kit_config_clear_debug_log(void *session) {
  try {
    if (!session)
      return;
    auto ptr = get_ptr<AbstractSession>(session);
    if (ptr)
      ptr->clearDebugLog();
  } catch (const std::exception &e) {
    std::cerr << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [Exception] in ffmpeg_kit_config_clear_debug_log: "
              << e.what() << std::endl;
    PRINT_STACK_TRACE();
  }
}
}
