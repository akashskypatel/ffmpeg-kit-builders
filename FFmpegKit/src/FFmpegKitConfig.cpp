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

#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>

extern "C" {
#include "libavutil/bprint.h"
#include "libavutil/ffversion.h"
#include "libavutil/log.h"
#include "libavutil/mem.h"
}

#include "ffmpeg_lib.h"
#include "ffmpegkit_session_context.h"
#include "ffmpeg_tls.h"
#include "ffprobe_lib.h"

#include "ArchDetect.hpp"
#include "FFmpegKitConfig.hpp"
#include "FFmpegSession.hpp"
#include "FFplaySession.hpp"
#include "FFprobeSession.hpp"
#include "Level.hpp"
#include "LogRedirectionStrategy.hpp"
#include "MediaInformationJsonParser.hpp"
#include "MediaInformationSession.hpp" // Removed duplicate below
#include "Packages.hpp"
#include "SessionState.hpp"
#include "ffplay_lib.h"
#include "win32_mutex.hpp"

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cctype>
#include <cstdlib>
#include <ctime>
#include <functional>
#include <fstream>
#include <iostream>
#include <climits>
#include <mutex>
#include <signal.h>
#include <sstream>
#include <thread> // 2. Standard library headers at the end
#include <unordered_map>

#if (defined(__ANDROID__) && __ANDROID_API__ < 28) || defined(__APPLE__)
#include <cstdlib>
#include <errno.h>
#include <pthread.h>
#include <time.h>

extern "C" {

struct timedjoin_args {
  pthread_t td;
  void **res;
  pthread_mutex_t mtx;
  pthread_cond_t cond;
  int joined;
  int detached;
  int join_rc;
};

static void *waiter_routine(void *ap) {
  auto *args = static_cast<struct timedjoin_args *>(ap);
  void *result = nullptr;

  // Perform the actual join
  int rc = pthread_join(args->td, &result);

  pthread_mutex_lock(&args->mtx);
  args->join_rc = rc;
  if (rc == 0 && args->res) {
    *args->res = result;
  }
  args->joined = 1;
  pthread_cond_signal(&args->cond);
  int detached = args->detached;
  pthread_mutex_unlock(&args->mtx);

  if (detached) {
    pthread_mutex_destroy(&args->mtx);
    pthread_cond_destroy(&args->cond);
    free(args);
  }
  return nullptr;
}

/**
 * Fallback implementation of pthread_timedjoin_np.
 * WARNING: If this returns ETIMEDOUT, the target thread 'td' is effectively
 * no longer joinable by the caller because an internal waiter thread now
 * owns the join. Attempting to join 'td' again results in Undefined Behavior.
 */
int pthread_timedjoin_np(pthread_t td, void **res, const struct timespec *ts) {
  auto *args = static_cast<struct timedjoin_args *>(
      calloc(1, sizeof(struct timedjoin_args)));
  if (!args)
    return ENOMEM;

  args->td = td;
  args->res = res;

  int ret;
  if ((ret = pthread_mutex_init(&args->mtx, nullptr)) != 0)
    goto free_args;
  if ((ret = pthread_cond_init(&args->cond, nullptr)) != 0)
    goto destroy_mtx;

  pthread_t waiter_thread;
  if ((ret = pthread_create(&waiter_thread, nullptr, waiter_routine, args)) !=
      0) {
    goto destroy_cond;
  }

  pthread_mutex_lock(&args->mtx);
  while (!args->joined) {
    ret = pthread_cond_timedwait(&args->cond, &args->mtx, ts);

    if (ret == ETIMEDOUT)
      break;
    if (ret == 0 || ret == EINTR)
      continue; // Spurious wakeup or signal

    // Unexpected system error (EINVAL, etc.) - break to avoid infinite loop
    break;
  }

  int actual_join_rc; // FIX #2: Declare WITHOUT initialization to allow goto
                      // jumps
  if (!args->joined) {
    // TIMEOUT PATH: Hand off cleanup responsibility to the waiter thread
    args->detached = 1;
    pthread_mutex_unlock(&args->mtx);
    pthread_detach(waiter_thread);
    return ETIMEDOUT;
  }

  // SUCCESS PATH: Copy the result BEFORE unlocking for strict memory visibility
  actual_join_rc = args->join_rc; // Assign here, after the goto targets
  pthread_mutex_unlock(&args->mtx);

  // Join the waiter (it's guaranteed to be finishing now)
  pthread_join(waiter_thread, nullptr);

  pthread_cond_destroy(&args->cond);
  pthread_mutex_destroy(&args->mtx);
  free(args);

  return actual_join_rc;

destroy_cond:
  pthread_cond_destroy(&args->cond);
destroy_mtx:
  pthread_mutex_destroy(&args->mtx);
free_args:
  free(args);
  return ret;
}

} // extern "C"
#endif

extern "C" {
void set_report_callback(void (*callback)(int, float, float, int64_t, double,
                                          double, double, double, int64_t,
                                          int64_t));
void cancel_operation(long id);
void ffmpegkit_set_log_delegate_callback(
    void (*callback)(void *ptr, int level, const char *format, va_list vargs));
}

static std::string getCurrentTimeStamp() {
  time_t now = time(0);
  struct tm timeinfo;
#if defined(_WIN32) || defined(_WIN64)
  localtime_s(&timeinfo, &now);
#else
  localtime_r(&now, &timeinfo);
#endif
  char buffer[80];
  strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &timeinfo);
  struct timeval tv;
  gettimeofday(&tv, NULL);
  char milliseconds[4];
  snprintf(milliseconds, sizeof(milliseconds), "%03d",
           (int)(tv.tv_usec / 1000));
  return std::string(buffer) + "." + std::string(milliseconds);
}

/**
 * Generates ids for named ffmpeg kit pipes.
 */
static std::atomic<long> pipeIndexGenerator(1);

/* Session history variables */
static int sessionHistorySize;
static KitMutex &getSessionMutex() {
  static KitMutex *m = new KitMutex();
  return *m;
}
static std::map<long, std::shared_ptr<ffmpegkit::Session>> &
getSessionHistoryMap() {
  static auto *instance =
      new std::map<long, std::shared_ptr<ffmpegkit::Session>>();
  return *instance;
}
static std::list<std::shared_ptr<ffmpegkit::Session>> &getSessionHistoryList() {
  static auto *instance = new std::list<std::shared_ptr<ffmpegkit::Session>>();
  return *instance;
}
static std::atomic<long> activeFFplaySessionId(0);

/** Session control variables */
#define SESSION_MAP_SIZE 1000
static std::atomic<short> sessionMap[SESSION_MAP_SIZE];
static std::atomic<int> sessionInTransitMessageCountMap[SESSION_MAP_SIZE];
static std::atomic<int> unattributedMessagesInTransitCount{0};
static std::mutex &getSessionMessageDrainMutex() {
  static auto *mutex = new std::mutex();
  return *mutex;
}
static std::condition_variable &getSessionMessageDrainMonitor() {
  static auto *monitor = new std::condition_variable();
  return *monitor;
}
static void notifySessionMessageDrain() {
  getSessionMessageDrainMonitor().notify_all();
}

/** Holds callback defined to redirect logs */
static ffmpegkit::LogCallback logCallback;

/** Holds callback defined to redirect statistics */
static ffmpegkit::StatisticsCallback statisticsCallback;

/** Holds complete callbacks defined to redirect asynchronous execution results
 */
static ffmpegkit::FFmpegSessionCompleteCallback ffmpegSessionCompleteCallback;
static ffmpegkit::FFprobeSessionCompleteCallback ffprobeSessionCompleteCallback;
static ffmpegkit::FFplaySessionCompleteCallback ffplaySessionCompleteCallback;
static ffmpegkit::MediaInformationSessionCompleteCallback
    mediaInformationSessionCompleteCallback;

static ffmpegkit::LogRedirectionStrategy globalLogRedirectionStrategy;

/** Redirection control variables */
static std::atomic<int> redirectionEnabled{0};
static KitMutex &getCallbackDataMutex() {
  static KitMutex *m = new KitMutex();
  return *m;
}
static KitMutex &getGlobalCallbacksMutex() {
  static KitMutex *m = new KitMutex();
  return *m;
}
static std::mutex &getCallbackMutex() {
  static std::mutex *instance = new std::mutex();
  return *instance;
}
static std::condition_variable &getCallbackMonitor() {
  static std::condition_variable *instance = new std::condition_variable();
  return *instance;
}
class CallbackData;
static std::list<CallbackData *> &getCallbackDataList() {
  static auto *instance = new std::list<CallbackData *>();
  return *instance;
}
static KitMutex &getRootSessionIdRegistryMutex() {
  static KitMutex *m = new KitMutex();
  return *m;
}
static std::unordered_map<const void *, long> &getRootSessionIdRegistry() {
  static auto *instance = new std::unordered_map<const void *, long>();
  return *instance;
}

/** Fields that control the handling of SIGNALs */
volatile int handleSIGQUIT = 1;
volatile int handleSIGINT = 1;
volatile int handleSIGTERM = 1;
volatile int handleSIGXCPU = 1;
volatile int handleSIGPIPE = 1;

/** Holds the default log level */
int configuredLogLevel = ffmpegkit::LevelAVLogInfo;

extern "C" {
void ffmpegkit_log_callback_function(void *ptr, int level, const char *format,
                                     va_list vargs);
}

static void installSharedLogState() {
  av_log_set_level(configuredLogLevel);
  ffmpegkit_set_log_delegate_callback(ffmpegkit_log_callback_function);
  av_log_set_callback(ffmpegkit_log_callback_function);
}

static void restoreConfiguredLogState() {
  av_log_set_level(configuredLogLevel);
  ffmpegkit_set_log_delegate_callback(ffmpegkit_log_callback_function);
  av_log_set_callback(ffmpegkit_log_callback_function);
}

#ifdef __cplusplus
extern "C" {
#endif

/** Forward declaration for function defined in ffmpeg.c */
int ffmpeg_execute(int argc, char **argv);

/** Forward declaration for function defined in ffprobe.c */
int ffprobe_execute(int argc, char **argv);

void ffmpegkit_log_callback_function(void *ptr, int level, const char *format,
                                     va_list vargs);

#ifdef __cplusplus
}
#endif

static thread_local std::shared_ptr<ffmpegkit::Session> tlsSession = nullptr;
static thread_local long tlsSessionId = 0;
static std::atomic<long> globalFFplaySessionId(0);

static bool shouldLogAttributionDiagnostics() {
  static std::once_flag onceFlag;
  static bool enabled = false;

  std::call_once(onceFlag, []() {
    const char *value = std::getenv("FFMPEG_KIT_LOG_ATTRIBUTION_DEBUG");
    if (value == nullptr) {
      enabled = false;
      return;
    }

    std::string flag(value);
    std::transform(flag.begin(), flag.end(), flag.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    enabled = !(flag.empty() || flag == "0" || flag == "false" ||
                flag == "no" || flag == "off");
  });

  return enabled;
}

static std::string currentThreadIdString() {
  std::ostringstream stream;
  stream << static_cast<unsigned long long>(
      std::hash<std::thread::id>{}(std::this_thread::get_id()));
  return stream.str();
}

static const char *avClassNameFromLogPtr(void *ptr) {
  if (ptr == nullptr) {
    return "NULL";
  }

  const AVClass *const *avClassPtr = reinterpret_cast<const AVClass *const *>(ptr);
  if (avClassPtr == nullptr || *avClassPtr == nullptr) {
    return "unknown";
  }

  return (*avClassPtr)->class_name != nullptr ? (*avClassPtr)->class_name
                                              : "unknown";
}

static long lookupRegisteredRootSessionId(const void *root) {
  if (root == nullptr) {
    return 0;
  }

  std::unique_lock<KitMutex> lock(getRootSessionIdRegistryMutex(),
                                  std::defer_lock);
  lock.lock();
  auto &registry = getRootSessionIdRegistry();
  auto entry = registry.find(root);
  const long sessionId = (entry != registry.end()) ? entry->second : 0;
  lock.unlock();

  return sessionId;
}

static void *parentLogContext(void *ptr) {
  if (ptr == nullptr) {
    return nullptr;
  }

  const AVClass *const *avClassPtr =
      reinterpret_cast<const AVClass *const *>(ptr);
  if (avClassPtr == nullptr || *avClassPtr == nullptr) {
    return nullptr;
  }

  const AVClass *avc = *avClassPtr;
  if (avc->parent_log_context_offset <= 0) {
    return nullptr;
  }

  return *(void **)(((uint8_t *)ptr) + avc->parent_log_context_offset);
}

static long resolveSessionIdFromLogContext(void *ptr) {
  void *current = ptr;

  for (int depth = 0; current != nullptr && depth < 8; depth++) {
    const long sessionId = lookupRegisteredRootSessionId(current);
    if (sessionId != 0) {
      return sessionId;
    }

    void *parent = parentLogContext(current);
    if (parent == current) {
      break;
    }
    current = parent;
  }

  return 0;
}

static void logAttributionDiagnostics(const char *kind, long sessionId,
                                      void *ptr, int level,
                                      bool hadThreadSession,
                                      bool hadThreadSessionId) {
  if (!shouldLogAttributionDiagnostics() || sessionId != 0) {
    return;
  }

  std::ostringstream message;
  message << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [DEBUG] "
          << kind << " attributed to session 0"
          << " thread=" << currentThreadIdString();

  message << " level=" << level;
  if (ptr != nullptr) {
    message << " ptr=" << ptr << " class=" << avClassNameFromLogPtr(ptr);
  }

  message << " tlsSession=" << (hadThreadSession ? "set" : "null")
          << " tlsSessionId=" << (hadThreadSessionId ? "set" : "zero")
          << " ffplayFallback="
          << (globalFFplaySessionId.load() != 0 ? "set" : "zero");

  std::cerr << message.str() << std::endl;
}

static void logStatisticsDiagnostics(long sessionId, int frameNumber, float fps,
                                     float quality, int64_t size,
                                     double timeElapsed, double time,
                                     double bitrate, double speed,
                                     bool hadThreadSession,
                                     bool hadThreadSessionId) {
  if (!shouldLogAttributionDiagnostics() || sessionId != 0) {
    return;
  }

  std::ostringstream message;
  message << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [DEBUG] "
          << "statistics attributed to session 0"
          << " thread=" << currentThreadIdString()
          << " frame=" << frameNumber
          << " fps=" << fps
          << " quality=" << quality
          << " size=" << size
          << " timeElapsed=" << timeElapsed
          << " time=" << time
          << " bitrate=" << bitrate
          << " speed=" << speed
          << " tlsSession=" << (hadThreadSession ? "set" : "null")
          << " tlsSessionId=" << (hadThreadSessionId ? "set" : "zero")
          << " ffplayFallback="
          << (globalFFplaySessionId.load() != 0 ? "set" : "zero");

  std::cerr << message.str() << std::endl;
}

static void bindSessionToThread(
    const std::shared_ptr<ffmpegkit::Session> &session) {
  tlsSession = session;
  tlsSessionId = (session != nullptr) ? session->getSessionId() : 0;
}

static void bindSessionIdToThread(long sessionId) {
  tlsSessionId = sessionId;
}

static void clearSessionIdFromThread() {
  tlsSessionId = 0;
}

static void clearSessionFromThread() {
  tlsSession = nullptr;
  clearSessionIdFromThread();
}

extern "C" void ffmpegkit_bind_session_id(long session_id) {
  bindSessionIdToThread(session_id);
}

extern "C" void ffmpegkit_unbind_session_id(void) { clearSessionIdFromThread(); }

extern "C" void ffmpegkit_register_root_context(const void *root,
                                                long session_id) {
  if (root == nullptr || session_id == 0) {
    return;
  }

  std::unique_lock<KitMutex> lock(getRootSessionIdRegistryMutex(),
                                  std::defer_lock);
  lock.lock();
  getRootSessionIdRegistry()[root] = session_id;
  lock.unlock();
}

extern "C" void ffmpegkit_unregister_root_context(const void *root) {
  if (root == nullptr) {
    return;
  }

  std::unique_lock<KitMutex> lock(getRootSessionIdRegistryMutex(),
                                  std::defer_lock);
  lock.lock();
  getRootSessionIdRegistry().erase(root);
  lock.unlock();
}

static std::once_flag ffmpegKitInitializerFlag;
static pthread_t callbackThread = 0;
static pthread_t asyncFFplayThread = 0;

void *ffmpegKitInitialize();

const void *_ffmpegKitConfigInitializer{ffmpegKitInitialize()};

enum CallbackType { LogType, StatisticsType };

static bool fs_exists(const std::string &s, const bool isFile,
                      const bool isDirectory) {
  struct stat dir_info;

  if (stat(s.c_str(), &dir_info) == 0) {
    if (isFile && S_ISREG(dir_info.st_mode)) {
      return true;
    }
    if (isDirectory && S_ISDIR(dir_info.st_mode)) {
      return true;
    }
  }

  return false;
}

static bool fs_create_dir(const std::string &s) {
  if (!fs_exists(s, false, true)) {
    bool mkdirSuccess = false;
#ifdef _WIN32
    mkdirSuccess = (mkdir(s.c_str()) != 0);
#else
    mkdirSuccess = (mkdir(s.c_str(), S_IRWXU | S_IRWXG | S_IROTH) != 0);
#endif
    if (mkdirSuccess) {
      std::cout << "[" << getCurrentTimeStamp()
                << "] [ffmpeg-kit] [ERROR] Failed to create directory: " << s
                << ". Operation failed with " << errno << "." << std::endl;
      return false;
    }
  }
  return true;
}

/*
 * Delete expired sessions from the session history.
 * This function should only be called while holding the session mutex.
 * It is the caller's responsibility to acquire the session mutex before calling this function.
 */
void deleteExpiredSessions() {
  // This function should only be called while holding the session mutex
  // It is the caller's responsibility to acquire the session mutex before calling this function
  size_t deletedCount = 0;
  size_t initialHistorySize = getSessionHistoryList().size();
  
  // Fix the infinite loop issue by tracking iterations to prevent hanging
  size_t iterations = 0;
  const size_t maxIterations = initialHistorySize; // Prevent infinite loop by limiting iterations
  
  while (getSessionHistoryList().size() > sessionHistorySize && iterations < maxIterations) {
    // Check if list is empty to prevent accessing front() on empty list
    if (getSessionHistoryList().empty()) {
      break;
    }
    
    auto first = getSessionHistoryList().front();
    // Fix the infinite loop issue: if the front session is not deletable, break the loop
    if (first != nullptr && first->getState() != ffmpegkit::SessionStateCreated && first->getState() != ffmpegkit::SessionStateRunning) {
      getSessionHistoryList().pop_front();
      getSessionHistoryMap().erase(first->getSessionId());
      deletedCount++;
    } else {
      // If the front session is not deletable, we can't delete it, so break to prevent infinite loop
      break;
    }
    iterations++;
  }

  if (deletedCount > 0) {
    av_log(nullptr, AV_LOG_DEBUG, "[%s] [ffmpeg-kit] [DEBUG] Deleted %zu expired sessions.\n", getCurrentTimeStamp().c_str(), deletedCount);
  }
}

void addSessionToSessionHistory(
    const std::shared_ptr<ffmpegkit::Session> session) {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);

  const long sessionId = session->getSessionId();

  lock.lock();

  /*
   * ASYNC SESSIONS CALL THIS METHOD TWICE
   * THIS CHECK PREVENTS ADDING THE SAME SESSION AGAIN
   */
  if (getSessionHistoryMap().count(sessionId) == 0) {
    getSessionHistoryMap().insert({sessionId, session});
    getSessionHistoryList().push_back(session);
    // deleteExpiredSessions() is called while already holding the session mutex, which is fine by convention
    deleteExpiredSessions();
  }

  lock.unlock();
}

/**
 * Callback data class.
 */
class CallbackData {
public:
  CallbackData(const long sessionId, const int logLevel, const AVBPrint *data)
      : _type{LogType}, _sessionId{sessionId}, _logLevel{logLevel} {
    av_bprint_init(&_logData, 0, AV_BPRINT_SIZE_UNLIMITED);
    av_bprintf(&_logData, "%s", data->str);
  }

  CallbackData(const long sessionId, const int videoFrameNumber,
               const float videoFps, const float videoQuality,
               const int64_t size, const double timeElapsed, const double time,
               const double bitrate, const double speed,
               const int64_t dupFrames, const int64_t dropFrames)
      : _type{StatisticsType}, _sessionId{sessionId},
        _statisticsFrameNumber{videoFrameNumber}, _statisticsFps{videoFps},
        _statisticsQuality{videoQuality}, _statisticsSize{size},
        _statisticsTimeElapsed{timeElapsed}, _statisticsTime{time},
        _statisticsBitrate{bitrate}, _statisticsSpeed{speed},
        _statisticsDupFrames{dupFrames},
        _statisticsDropFrames{dropFrames} {}

  ~CallbackData() {
    if (_type == LogType) {
      av_bprint_finalize(&_logData, NULL);
    }
  }

  CallbackType getType() { return _type; }

  long getSessionId() { return _sessionId; }

  int getLogLevel() { return _logLevel; }

  AVBPrint *getLogData() { return &_logData; }

  int getStatisticsFrameNumber() { return _statisticsFrameNumber; }

  float getStatisticsFps() { return _statisticsFps; }

  float getStatisticsQuality() { return _statisticsQuality; }

  int64_t getStatisticsSize() { return _statisticsSize; }

  double getStatisticsTimeElapsed() { return _statisticsTimeElapsed; }

  double getStatisticsTime() { return _statisticsTime; }

  double getStatisticsBitrate() { return _statisticsBitrate; }

  double getStatisticsSpeed() { return _statisticsSpeed; }

  int64_t getStatisticsDupFrames() { return _statisticsDupFrames; }

  int64_t getStatisticsDropFrames() { return _statisticsDropFrames; }

private:
  CallbackType _type;
  long _sessionId; // session id

  int _logLevel;     // log level
  AVBPrint _logData; // log data

  int _statisticsFrameNumber;    // statistics frame number
  float _statisticsFps;          // statistics fps
  float _statisticsQuality;      // statistics quality
  int64_t _statisticsSize;       // statistics size
  double _statisticsTimeElapsed; // statistics time elapsed
  double _statisticsTime;        // statistics time
  double _statisticsBitrate;     // statistics bitrate
  double _statisticsSpeed;       // statistics speed
  int64_t _statisticsDupFrames;  // duplicated frame count
  int64_t _statisticsDropFrames; // dropped frame count
};

/**
 * Waits on the callback semaphore for the given time.
 *
 * @param milliSeconds wait time in milliseconds
 */
static void callbackWait(int milliSeconds) {
  std::unique_lock<std::mutex> callbackLock{getCallbackMutex()};
  getCallbackMonitor().wait_for(callbackLock,
                                std::chrono::milliseconds(milliSeconds));
}

/**
 * Notifies threads waiting on callback semaphore.
 */
static void callbackNotify() { getCallbackMonitor().notify_one(); }

static const char *avutil_log_get_level_str(int level) {
  switch (level) {
  case AV_LOG_QUIET:
    return "quiet";
  case AV_LOG_DEBUG:
    return "debug";
  case AV_LOG_VERBOSE:
    return "verbose";
  case AV_LOG_INFO:
    return "info";
  case AV_LOG_WARNING:
    return "warning";
  case AV_LOG_ERROR:
    return "error";
  case AV_LOG_FATAL:
    return "fatal";
  case AV_LOG_PANIC:
    return "panic";
  default:
    return "";
  }
}

static void avutil_log_format_line(void *avcl, int level, const char *fmt,
                                   va_list vl, AVBPrint part[4],
                                   int *print_prefix) {
  int flags = av_log_get_flags();
  AVClass *avc = avcl ? *(AVClass **)avcl : NULL;
  av_bprint_init(part + 0, 0, 1);
  av_bprint_init(part + 1, 0, 1);
  av_bprint_init(part + 2, 0, 1);
  av_bprint_init(part + 3, 0, 65536);

  if (*print_prefix && avc) {
    if (avc->parent_log_context_offset) {
      AVClass **parent =
          *(AVClass ***)(((uint8_t *)avcl) + avc->parent_log_context_offset);
      if (parent && *parent) {
        av_bprintf(part + 0, "[%s @ %p] ", (*parent)->item_name(parent),
                   parent);
      }
    }
    av_bprintf(part + 1, "[%s @ %p] ", avc->item_name(avcl), avcl);
  }

  if (*print_prefix && (level > AV_LOG_QUIET) && (flags & AV_LOG_PRINT_LEVEL))
    av_bprintf(part + 2, "[%s] ", avutil_log_get_level_str(level));

  av_vbprintf(part + 3, fmt, vl);

  if (*part[0].str || *part[1].str || *part[2].str || *part[3].str) {
    char lastc = part[3].len && part[3].len <= part[3].size
                     ? part[3].str[part[3].len - 1]
                     : 0;
    *print_prefix = lastc == '\n' || lastc == '\r';
  }
}

static void avutil_log_sanitize(char *line) {
  while (*line) {
    if (*line < 0x08 || (*line > 0x0D && *line < 0x20))
      *line = '?';
    line++;
  }
}

/**
 * Adds log data to the end of callback data list.
 *
 * @param level log level
 * @param data log data
 */
static void logCallbackDataAdd(int level, AVBPrint *data) {
  std::shared_ptr<ffmpegkit::Session> currentSession = tlsSession;
  long sessionId =
      (currentSession != nullptr) ? currentSession->getSessionId() : tlsSessionId;

  if (currentSession == nullptr && sessionId == 0) {
    long ffplaySessionId = globalFFplaySessionId.load();
    if (ffplaySessionId != 0) {
      currentSession = ffmpegkit::FFmpegKitConfig::getSession(ffplaySessionId);
      sessionId = ffplaySessionId;
    }
  }

  if (currentSession != nullptr) {
    currentSession->debugLog(
        "FFmpegKitConfig::logCallbackDataAdd sessionId: %ld level: %d msg: %s", sessionId, level,
        (data->str ? data->str : "NULL"));
  }

  std::unique_lock<KitMutex> lock(getCallbackDataMutex(), std::defer_lock);
  CallbackData *callbackData = new CallbackData(sessionId, level, data);

  if (sessionId == 0) {
    std::atomic_fetch_add(&unattributedMessagesInTransitCount, 1);
  } else {
    std::atomic_fetch_add(
        &sessionInTransitMessageCountMap[sessionId % SESSION_MAP_SIZE], 1);
  }

  lock.lock();
  getCallbackDataList().push_back(callbackData);
  lock.unlock();

  callbackNotify();
}

/**
 * Adds statistics data to the end of callback data list.
 */
static void statisticsCallbackDataAdd(int frameNumber, float fps, float quality,
                                      int64_t size, double timeElapsed,
                                      double time, double bitrate,
                                      double speed, int64_t dupFrames,
                                      int64_t dropFrames) {
  std::shared_ptr<ffmpegkit::Session> currentSession = tlsSession;
  long sessionId =
      (currentSession != nullptr) ? currentSession->getSessionId() : tlsSessionId;

  if (currentSession == nullptr && sessionId == 0) {
    long ffplaySessionId = globalFFplaySessionId.load();
    if (ffplaySessionId != 0) {
      currentSession = ffmpegkit::FFmpegKitConfig::getSession(ffplaySessionId);
      sessionId = ffplaySessionId;
    }
  }

  logStatisticsDiagnostics(sessionId, frameNumber, fps, quality, size,
                           timeElapsed, time, bitrate, speed,
                           currentSession != nullptr, tlsSessionId != 0);

  if (currentSession != nullptr) {
    currentSession->debugLog(
        "FFmpegKitConfig::statisticsCallbackDataAdd sessionId: %ld frameNumber: %d fps: %f quality: %f size: %lld timeElapsed: %f time: %f bitrate: %f speed: %f dupFrames: %lld dropFrames: %lld", 
        sessionId, frameNumber, fps, quality, size, timeElapsed, time, bitrate, speed, dupFrames, dropFrames);
  }
  
  std::unique_lock<KitMutex> lock(getCallbackDataMutex(), std::defer_lock);
  CallbackData *callbackData =
      new CallbackData(sessionId, frameNumber, fps, quality, size, timeElapsed,
                       time, bitrate, speed, dupFrames, dropFrames);

  if (sessionId == 0) {
    std::atomic_fetch_add(&unattributedMessagesInTransitCount, 1);
  } else {
    std::atomic_fetch_add(
        &sessionInTransitMessageCountMap[sessionId % SESSION_MAP_SIZE], 1);
  }

  lock.lock();
  getCallbackDataList().push_back(callbackData);
  lock.unlock();

  callbackNotify();
}

/**
 * Removes head of callback data list.
 */
static CallbackData *callbackDataRemove() {
  std::unique_lock<KitMutex> lock(getCallbackDataMutex(), std::defer_lock);
  CallbackData *newData = nullptr;

  lock.lock();
  if (getCallbackDataList().size() > 0) {
    newData = getCallbackDataList().front();
    getCallbackDataList().pop_front();
  }
  lock.unlock();

  return newData;
}

/**
 * Registers a session id to the session map.
 *
 * @param sessionId session id
 */
static void registerSessionId(long sessionId) {
  av_log(nullptr, AV_LOG_DEBUG, "registerSessionId session_id=%ld\n", sessionId);
  std::atomic_store(&sessionMap[sessionId % SESSION_MAP_SIZE], (short)1);
}

/**
 * Removes a session id from the session map.
 *
 * @param sessionId session id
 */
static void removeSession(long sessionId) {
  av_log(nullptr, AV_LOG_DEBUG, "removeSession session_id=%ld\n", sessionId);
  std::atomic_store(&sessionMap[sessionId % SESSION_MAP_SIZE], (short)0);
}

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Adds a cancel session request to the session map.
 *
 * @param sessionId session id
 */
void cancelSession(long sessionId) {
  av_log(nullptr, AV_LOG_DEBUG, "cancelSession session_id=%ld\n", sessionId);
  std::atomic_store(&sessionMap[sessionId % SESSION_MAP_SIZE], (short)2);  
}

/**
 * Checks whether a cancel request for the given session id exists in the
 * session map.
 *
 * @param sessionId session id
 * @return 1 if exists, false otherwise
 */
int cancelRequested(long sessionId) {
  if (std::atomic_load(&sessionMap[sessionId % SESSION_MAP_SIZE]) == 2) {
    av_log(nullptr, AV_LOG_DEBUG, "cancelRequested session_id=%ld\n", sessionId);
    return 1;
  } else {
    return 0;
  }
}

FFMPEG_THREAD_LOCAL void (*report_callback)(int, float, float, int64_t, double,
                                            double, double, double, int64_t,
                                            int64_t) = NULL;
extern void sigterm_handler(int sig);

void set_report_callback(void (*callback)(int, float, float, int64_t, double,
                                          double, double, double, int64_t,
                                          int64_t)) {
  report_callback = callback;
}

void cancel_operation(long id) {
  if (id == 0) {
    sigterm_handler(SIGINT);
  } else {
    cancelSession(id);
  }
}

#ifdef __cplusplus
}
#endif

/**
 * Resets the number of messages in transmit for this session.
 *
 * @param sessionId session id
 */
static void resetMessagesInTransmit(long sessionId) {
  if (sessionId == 0) {
    std::atomic_store(&unattributedMessagesInTransitCount, 0);
    notifySessionMessageDrain();
    return;
  }

  std::atomic_store(
      &sessionInTransitMessageCountMap[sessionId % SESSION_MAP_SIZE], 0);
  notifySessionMessageDrain();
}

/**
 * Callback function for FFmpeg/FFprobe logs.
 *
 * @param ptr pointer to AVClass struct
 * @param level log level
 * @param format format string
 * @param vargs arguments
 */
void ffmpegkit_log_callback_function(void *ptr, int level, const char *format,
                                     va_list vargs) {
  std::shared_ptr<ffmpegkit::Session> currentSession = tlsSession;
  long sessionId =
      (currentSession != nullptr) ? currentSession->getSessionId() : tlsSessionId;

  if (currentSession == nullptr && sessionId == 0) {
    sessionId = resolveSessionIdFromLogContext(ptr);
  }
  if (currentSession == nullptr && sessionId == 0) {
    long ffplaySessionId = globalFFplaySessionId.load();
    if (ffplaySessionId != 0) {
      currentSession = ffmpegkit::FFmpegKitConfig::getSession(ffplaySessionId);
      sessionId = ffplaySessionId;
    }
  }

  logAttributionDiagnostics("log", sessionId, ptr, level,
                            currentSession != nullptr, tlsSessionId != 0);

  AVBPrint fullLine;
  AVBPrint part[4];
  int print_prefix = 1;

  // DO NOT PROCESS UNWANTED LOGS
  if (level >= 0) {
    level &= 0xff;
  }
  int activeLogLevel = av_log_get_level();

  // LevelAVLogStdErr logs are always redirected
  if ((activeLogLevel == ffmpegkit::LevelAVLogQuiet &&
       level != ffmpegkit::LevelAVLogStdErr) ||
      (level > activeLogLevel)) {
    return;
  }

  av_bprint_init(&fullLine, 0, AV_BPRINT_SIZE_UNLIMITED);

  avutil_log_format_line(ptr, level, format, vargs, part, &print_prefix);
  avutil_log_sanitize(part[0].str);
  avutil_log_sanitize(part[1].str);
  avutil_log_sanitize(part[2].str);
  avutil_log_sanitize(part[3].str);

  // COMBINE ALL 4 LOG PARTS
  av_bprintf(&fullLine, "%s%s%s%s", part[0].str, part[1].str, part[2].str,
             part[3].str);

  if (fullLine.len > 0) {
    logCallbackDataAdd(level, &fullLine);
  }

  av_bprint_finalize(part, NULL);
  av_bprint_finalize(part + 1, NULL);
  av_bprint_finalize(part + 2, NULL);
  av_bprint_finalize(part + 3, NULL);
  av_bprint_finalize(&fullLine, NULL);
}

/**
 * Callback function for FFmpeg statistics.
 *
 * @param frameNumber last processed frame number
 * @param fps frames processed per second
 * @param quality quality of the output stream (video only)
 * @param size size in bytes
 * @param time processed output duration
 * @param bitrate output bit rate in kbits/s
 * @param speed processing speed = processed duration / operation duration
 */
void ffmpegkit_statistics_callback_function(int frameNumber, float fps,
                                            float quality, int64_t size,
                                            double timeElapsed, double time,
                                            double bitrate, double speed,
                                            int64_t dupFrames,
                                            int64_t dropFrames) {
  statisticsCallbackDataAdd(frameNumber, fps, quality, size, timeElapsed, time,
                            bitrate, speed, dupFrames, dropFrames);
}

static void process_log(long sessionId, int levelValueInt,
                        AVBPrint *logMessage) {
  int activeLogLevel = av_log_get_level();
  ffmpegkit::Level levelValue = static_cast<ffmpegkit::Level>(levelValueInt);
  std::shared_ptr<ffmpegkit::Log> log =
      std::make_shared<ffmpegkit::Log>(sessionId, levelValue, logMessage->str);
  bool globalCallbackDefined = false;
  bool sessionCallbackDefined = false;
  ffmpegkit::LogRedirectionStrategy activeLogRedirectionStrategy =
      globalLogRedirectionStrategy;

  // LevelAVLogStdErr logs are always redirected
  if ((activeLogLevel == ffmpegkit::LevelAVLogQuiet &&
       levelValue != ffmpegkit::LevelAVLogStdErr) ||
      (levelValue > activeLogLevel)) {
    // LOG NEITHER PRINTED NOR FORWARDED
    return;
  }

  auto session = ffmpegkit::FFmpegKitConfig::getSession(sessionId);
  if (session != nullptr) {
    activeLogRedirectionStrategy = session->getLogRedirectionStrategy();
    session->addLog(log);

    ffmpegkit::LogCallback sessionLogCallback = session->getLogCallback();
    if (sessionLogCallback != nullptr) {
      sessionCallbackDefined = true;

      try {
        // NOTIFY SESSION CALLBACK DEFINED
        sessionLogCallback(log);
      } catch (const std::exception &exception) {
        std::cout << "[" << getCurrentTimeStamp()
                  << "] [ffmpeg-kit] [ERROR] Exception thrown inside session "
                     "log callback. "
                  << exception.what() << std::endl;
      }
    }
  }

  {
    std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
    if (logCallback != nullptr) {
      globalCallbackDefined = true;

      try {
        // NOTIFY GLOBAL CALLBACK DEFINED
        logCallback(log);
      } catch (const std::exception &exception) {
        std::cout << "[" << getCurrentTimeStamp()
                  << "] [ffmpeg-kit] [ERROR] Exception thrown inside global "
                     "log callback. "
                  << exception.what() << std::endl;
      }
    }
  }

  // EXECUTE THE LOG STRATEGY
  switch (activeLogRedirectionStrategy) {
  case ffmpegkit::LogRedirectionStrategyNeverPrintLogs: {
    return;
  }
  case ffmpegkit::LogRedirectionStrategyPrintLogsWhenGlobalCallbackNotDefined: {
    if (globalCallbackDefined) {
      return;
    }
  } break;
  case ffmpegkit::
      LogRedirectionStrategyPrintLogsWhenSessionCallbackNotDefined: {
    if (sessionCallbackDefined) {
      return;
    }
  } break;
  case ffmpegkit::LogRedirectionStrategyPrintLogsWhenNoCallbacksDefined: {
    if (globalCallbackDefined || sessionCallbackDefined) {
      return;
    }
  } break;
  case ffmpegkit::LogRedirectionStrategyAlwaysPrintLogs: {
  } break;
  }

  // PRINT LOGS
  switch (levelValue) {
  case ffmpegkit::LevelAVLogQuiet:
    // PRINT NO OUTPUT
    break;
  default:
    // WRITE TO STDOUT
    std::cout << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] "
              << ffmpegkit::FFmpegKitConfig::logLevelToString(levelValue)
              << ": " << logMessage->str;
    break;
  }
}

void process_statistics(long sessionId, int videoFrameNumber, float videoFps,
                        float videoQuality, long size, double timeElapsed,
                        double time, double bitrate, double speed,
                        int64_t dupFrames, int64_t dropFrames) {
  std::shared_ptr<ffmpegkit::Statistics> statistics =
      std::make_shared<ffmpegkit::Statistics>(
          sessionId, videoFrameNumber, videoFps, videoQuality, size,
          timeElapsed, time, bitrate, speed, dupFrames, dropFrames);

  auto session = ffmpegkit::FFmpegKitConfig::getSession(sessionId);
  if (session != nullptr && session->isFFmpeg()) {
    std::shared_ptr<ffmpegkit::FFmpegSession> ffmpegSession =
        std::static_pointer_cast<ffmpegkit::FFmpegSession>(session);
    ffmpegSession->addStatistics(statistics);

    ffmpegkit::StatisticsCallback sessionStatisticsCallback =
        ffmpegSession->getStatisticsCallback();
    if (sessionStatisticsCallback != nullptr) {
      try {
        sessionStatisticsCallback(statistics);
      } catch (const std::exception &exception) {
        std::cout << "[" << getCurrentTimeStamp()
                  << "] [ffmpeg-kit] [ERROR] Exception thrown inside session "
                     "statistics callback. "
                  << exception.what() << std::endl;
      }
    }
  }

  {
    std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
    if (statisticsCallback != nullptr) {
      try {
        statisticsCallback(statistics);
      } catch (const std::exception &exception) {
        std::cout << "[" << getCurrentTimeStamp()
                  << "] [ffmpeg-kit] [ERROR] Exception thrown inside global "
                     "statistics callback. "
                  << exception.what() << std::endl;
      }
    }
  }
}

/**
 * Forwards asynchronous messages to Callbacks.
 */
void *callbackThreadFunction(void *pointer) {
  int activeLogLevel = av_log_get_level();
  if ((activeLogLevel != ffmpegkit::LevelAVLogQuiet) &&
      (ffmpegkit::LevelAVLogDebug <= activeLogLevel)) {
    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [INFO] Async callback block started."
              << std::endl;
  }

  while (redirectionEnabled.load(std::memory_order_acquire)) {
    try {
      CallbackData *callbackData = callbackDataRemove();

      if (callbackData != nullptr) {
        std::unique_ptr<CallbackData> callbackGuard(callbackData);
        const long sessionId = callbackGuard->getSessionId();
        struct CallbackDrainGuard {
          long sessionId;
          ~CallbackDrainGuard() {
            if (sessionId == 0) {
              std::atomic_fetch_sub(&unattributedMessagesInTransitCount, 1);
            } else {
              std::atomic_fetch_sub(
                  &sessionInTransitMessageCountMap[sessionId %
                                                   SESSION_MAP_SIZE],
                  1);
            }
            notifySessionMessageDrain();
          }
        } drainGuard{sessionId};

        if (callbackGuard->getType() == LogType) {
          process_log(sessionId, callbackGuard->getLogLevel(),
                      callbackGuard->getLogData());
        } else {

          process_statistics(sessionId, callbackGuard->getStatisticsFrameNumber(),
                             callbackGuard->getStatisticsFps(),
                             callbackGuard->getStatisticsQuality(),
                             callbackGuard->getStatisticsSize(),
                             callbackGuard->getStatisticsTimeElapsed(),
                             callbackGuard->getStatisticsTime(),
                             callbackGuard->getStatisticsBitrate(),
                             callbackGuard->getStatisticsSpeed(),
                             callbackGuard->getStatisticsDupFrames(),
                             callbackGuard->getStatisticsDropFrames());
        }
      } else {

        callbackWait(100);
      }

    } catch (const std::exception &exception) {
      activeLogLevel = av_log_get_level();
      if ((activeLogLevel != ffmpegkit::LevelAVLogQuiet) &&
          (ffmpegkit::LevelAVLogWarning <= activeLogLevel)) {
        std::cout
            << "[" << getCurrentTimeStamp()
            << "] [ffmpeg-kit] [INFO] Async callback block received error: "
            << exception.what() << std::endl;
      }
    }
  }

  activeLogLevel = av_log_get_level();
  if ((activeLogLevel != ffmpegkit::LevelAVLogQuiet) &&
      (ffmpegkit::LevelAVLogDebug <= activeLogLevel)) {
    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [INFO] Async callback block stopped."
              << std::endl;
  }

  return NULL;
}

/**
 * Helper to reconstruct command string from argument list for the new _lib
 * APIs.
 */
static std::string
buildCommandString(const char *toolName,
                   const std::shared_ptr<std::list<std::string>> &arguments) {
  std::string cmd = toolName;
  for (const auto &arg : *arguments) {
    cmd += " ";
    // Basic quote handling: if arg has space, wrap in quotes
    if (arg.find(' ') != std::string::npos) {
      cmd += "\"" + arg + "\"";
    } else {
      cmd += arg;
    }
  }
  return cmd;
}

static int
executeFFmpeg(const std::shared_ptr<ffmpegkit::FFmpegSession> &session,
              const std::shared_ptr<std::list<std::string>> arguments) {
  if (session == nullptr) {
    return -1;
  }
  const long sessionId = session->getSessionId();
  std::string sessionStr = std::to_string(sessionId);
  session->debugLog("FFmpegKitConfig::executeFFmpeg begin session_handle=%s session_id=%d", sessionStr.c_str(), sessionId);
  
  bindSessionToThread(session);

  registerSessionId(sessionId);
  resetMessagesInTransmit(sessionId);

  // 1. Construct command string for the library init
  std::string fullCommand = buildCommandString("ffmpeg", arguments);

  // 2. Initialize Wrapper Context
  FFmpegContext *ctx = ffmpeg_init(fullCommand.c_str());

  if (!ctx) {
    removeSession(sessionId);
    clearSessionFromThread();
    return -1; // ENOMEM or parse error
  }

  ffmpeg_set_session_id(ctx, sessionId);
  if (session && session->isFFmpeg()) {
    std::static_pointer_cast<ffmpegkit::FFmpegSession>(session)->setContext(ctx);
  }

  // 3. Set up logging and callbacks
  installSharedLogState();
  set_report_callback(ffmpegkit_statistics_callback_function);

  // 4. RUN
  // This blocks until transcoding is finished
  int returnCode = ffmpeg_run(ctx);

  // ALWAYS REMOVE THE ID FROM THE MAP
  removeSession(sessionId);

  // 5. CLEANUP
  if (session && session->isFFmpeg()) {
    std::static_pointer_cast<ffmpegkit::FFmpegSession>(session)->setContext(
        nullptr);
  }
  clearSessionFromThread();
  if (ffmpeg_shutdown_incomplete(ctx)) {
    session->debugLog("FFmpegKitConfig::executeFFmpeg preserving wrapper context after incomplete shutdown session_handle=%s session_id=%d", sessionStr.c_str(), sessionId);
  } else {
    ffmpeg_free(ctx);
  }
  restoreConfiguredLogState();

  session->debugLog("FFmpegKitConfig::executeFFmpeg end session_handle=%s session_id=%d", sessionStr.c_str(), sessionId);

  return returnCode;
}

int executeFFprobe(const std::shared_ptr<ffmpegkit::AbstractSession> &session,
                   const std::shared_ptr<std::list<std::string>> arguments,
                   std::string *capturedOutput = nullptr) {
  if (session == nullptr) {
    return -1;
  }
  const long sessionId = session->getSessionId();
  std::string sessionStr = std::to_string(sessionId);
  session->debugLog("FFmpegKitConfig::executeFFprobe begin session_handle=%s session_id=%d", sessionStr.c_str(), sessionId);
  bindSessionToThread(session);

  registerSessionId(sessionId);
  resetMessagesInTransmit(sessionId);

  // 1. Construct command string
  std::string fullCommand = buildCommandString("ffprobe", arguments);

  // 2. Initialize Wrapper Context
  FFprobeContext *ctx = ffprobe_init(fullCommand.c_str());

  if (!ctx) {
    removeSession(sessionId);
    clearSessionFromThread();
    return -1;
  }

  ffprobe_set_session_id(ctx, sessionId);
  if (session->isFFprobe()) {
    std::static_pointer_cast<ffmpegkit::FFprobeSession>(session)->setContext(ctx);
  }

  // 3. Set up logging and callbacks
  installSharedLogState();
  set_report_callback(ffmpegkit_statistics_callback_function);

  // 4. RUN
  // This blocks until probe is finished.
  // Output is captured into ctx->output (AVBPrint) inside the lib.
  int returnCode = ffprobe_run(ctx);

  // 5. BRIDGE OUTPUT
  // MediaInformationSession expects the JSON output to appear in the logs
  // (specifically as LevelAVLogStdErr or via the log system).
  // Since ffprobe_lib.c no longer writes to stdout/stderr, we must manually
  // inject the captured buffer into the log system.
  if (ctx) {
    char *output = ffprobe_get_output(ctx);
    if (output) {
      if (capturedOutput != nullptr) {
        capturedOutput->assign(output);
      }

      AVBPrint bprint;
      av_bprint_init(&bprint, 0, AV_BPRINT_SIZE_UNLIMITED);
      av_bprintf(&bprint, "%s", output);

      // Inject into the log system so MediaInformationJsonParser can find it
      // Use LevelAVLogStdErr as that is what MediaInformationSession listens
      // for
      logCallbackDataAdd(ffmpegkit::LevelAVLogStdErr, &bprint);

      av_bprint_finalize(&bprint, NULL);
      av_free(output);
    } else {
      session->debugLog("FFprobeExecute: sessionId: %ld output was NULL", sessionId);
    }
  }

  // ALWAYS REMOVE THE ID FROM THE MAP
  removeSession(sessionId);

  // 6. CLEANUP
  if (session->isFFprobe()) {
    std::static_pointer_cast<ffmpegkit::FFprobeSession>(session)->setContext(nullptr);
  }
  clearSessionFromThread();
  ffprobe_free(ctx);
  restoreConfiguredLogState();

  session->debugLog("FFmpegKitConfig::executeFFprobe end session_handle=%s session_id=%d", sessionStr.c_str(), sessionId);

  return returnCode;
}

int executeFFplay(const long sessionId,
                  const std::shared_ptr<std::list<std::string>> arguments) {
  auto session = ffmpegkit::FFmpegKitConfig::getSession(sessionId);
  std::string sessionStr = std::to_string(sessionId);
  session->debugLog("FFmpegKitConfig::executeFFplay begin session_handle=%s session_id=%d", sessionStr.c_str(), sessionId);
  bindSessionToThread(session);
  globalFFplaySessionId = sessionId;

  if (tlsSession != nullptr) {
    tlsSession->debugLog("FFmpegKitConfig::executeFFplay sessionId: %ld tls Bound", sessionId);
  }
  registerSessionId(sessionId);
  resetMessagesInTransmit(sessionId);

  // 1. Construct command string
  std::string fullCommand = buildCommandString("ffplay", arguments);

  // 2. Configure log level and callbacks
  installSharedLogState();
  set_report_callback(ffmpegkit_statistics_callback_function);

  bool helpRequested = false;
  for (const auto &arg : *arguments) {
    if (arg == "-h" || arg == "--help" || arg == "-help" || arg == "?") {
      helpRequested = true;
      tlsSession->debugLog(
          "FFmpegKitConfig::executeFFplay sessionId: %ld ffplay help requested", sessionId);
      break;
    }
  }

  // 3. Initialize Wrapper Context
  FFplayContext *ctx = ffplay_init(fullCommand.c_str(), nullptr);
  if (!ctx) {
    if (helpRequested) {
      // Help was displayed successfully - wait for logs and return success
      if (tlsSession != nullptr) {
        static_cast<ffmpegkit::FFplaySession *>(tlsSession.get())
            ->waitForAsynchronousMessagesInTransmit(
                ffmpegkit::AbstractSession::
                    DefaultTimeoutForAsynchronousMessagesInTransmit);
      }
      removeSession(sessionId);
      if (tlsSession != nullptr) {
        tlsSession->debugLog("FFmpegKitConfig::executeFFplay sessionId: %ld ffplay help "
                             "displayed, returning success",
                             sessionId);
      }
      clearSessionFromThread();
      globalFFplaySessionId = 0;
      return 0; // Success - help was displayed
    } else if (tlsSession != nullptr) {
      tlsSession->debugLog("FFmpegKitConfig::executeFFplay sessionId: %ld ffplay_init FAILED",
                           sessionId);
    }
    removeSession(sessionId);
    clearSessionFromThread();
    globalFFplaySessionId = 0;
    return -1;
  }

  if (tlsSession != nullptr) {
    tlsSession->debugLog("FFmpegKitConfig::executeFFplay sessionId: %ld ffplay_init SUCCESS",
                         sessionId);
  }

  // 4. Bind ffplay context to session
  if (session && session->isFFplay()) {
    std::static_pointer_cast<ffmpegkit::FFplaySession>(session)->setContext(
        ctx);
  }

  // 5. RUN
  int returnCode = ffplay_start(ctx);
  if (returnCode == 0) {
    if (tlsSession != nullptr) {
      tlsSession->debugLog("FFplayExecute: sessionId: %ld ffplay_start SUCCESS",
                           sessionId);
    }
    int stepCount = 0;
    while (ffplay_step(ctx) == 0) {
      if (cancelRequested(sessionId)) {
        ffplay_stop(ctx);
        break;
      }
      stepCount++;
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
  } else {
    if (tlsSession != nullptr) {
      tlsSession->debugLog("FFplayExecute: sessionId: %ld ffplay_start FAILED "
                           "(rc=%d), skipping step loop",
                           sessionId, returnCode);
    }
  }

  // 6. Unbind session context
  if (session && session->isFFplay()) {
    std::static_pointer_cast<ffmpegkit::FFplaySession>(session)->setContext(
        nullptr);
  }

  // 7. Remove from session map
  removeSession(sessionId);

  // 8. CLEANUP
  clearSessionFromThread();
  globalFFplaySessionId = 0;
  ffplay_free(ctx);
  restoreConfiguredLogState();

  session->debugLog("FFmpegKitConfig::executeFFplay end session_handle=%s session_id=%d", sessionStr.c_str(), sessionId);

  return returnCode;
}

void ffmpegkit::FFmpegKitConfig::joinAsyncFFplayThread() {
  if (asyncFFplayThread == 0) {
    return;
  }
  detachAsyncFFplayThread();
}

void ffmpegkit::FFmpegKitConfig::detachAsyncFFplayThread() {
  if (asyncFFplayThread != 0) {
    pthread_detach(asyncFFplayThread);
    asyncFFplayThread = 0;
  }
}

void *ffmpegKitInitialize() {
  std::call_once(ffmpegKitInitializerFlag, []() {
    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [INFO] Loading ffmpeg-kit." << std::endl;

    // Eagerly initialize all Meyers Singletons to establish a strict
    // happens-before edge prior to spawning any background threads.
    // This prevents ThreadSanitizer from flagging data races during
    // the lazy initialization of these static pointers.
    (void)getSessionMutex();
    (void)getSessionHistoryMap();
    (void)getSessionHistoryList();
    (void)getCallbackDataMutex();
    (void)getGlobalCallbacksMutex();
    (void)getCallbackMutex();
    (void)getCallbackMonitor();
    (void)getCallbackDataList();

    sessionHistorySize = 10;

    for (int i = 0; i < SESSION_MAP_SIZE; i++) {
      std::atomic_init(&sessionMap[i], (short)0);
      std::atomic_init(&sessionInTransitMessageCountMap[i], 0);
    }
    std::atomic_init(&unattributedMessagesInTransitCount, 0);

    logCallback = nullptr;
    statisticsCallback = nullptr;
    ffmpegSessionCompleteCallback = nullptr;
    ffprobeSessionCompleteCallback = nullptr;
    ffplaySessionCompleteCallback = nullptr;
    mediaInformationSessionCompleteCallback = nullptr;

    globalLogRedirectionStrategy =
        ffmpegkit::LogRedirectionStrategyPrintLogsWhenNoCallbacksDefined;

    ffmpegkit::FFmpegKitConfig::enableRedirection();

    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [INFO] Loaded ffmpeg-kit-"
              << ffmpegkit::Packages::getPackageName() << "-"
              << ffmpegkit::ArchDetect::getArch() << "-"
              << (ffmpegkit::Packages::getIsGpl()       ? "gpl"
                  : ffmpegkit::Packages::getIsNonFree() ? "nonfree"
                                                        : "lgpl")
              << "-" << ffmpegkit::FFmpegKitConfig::getVersion() << "-"
              << ffmpegkit::FFmpegKitConfig::getBuildDate() << "." << std::endl;
    static const char kStamp[] = __DATE__ " " __TIME__;
    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [INFO] Build timestamp: " << kStamp
              << std::endl;
  });

  std::lock_guard<KitMutex> lock(getCallbackDataMutex());

  return NULL;
}

void ffmpegkit::FFmpegKitConfig::enableRedirection() {
  std::unique_lock<KitMutex> lock(getCallbackDataMutex(), std::defer_lock);
  lock.lock();

  if (redirectionEnabled.load(std::memory_order_acquire) != 0) {
    lock.unlock();
    return;
  }
  redirectionEnabled.store(1, std::memory_order_release);

  lock.unlock();

  int rc = pthread_create(&callbackThread, NULL, callbackThreadFunction, NULL);
  if (rc != 0) {
    std::cout
        << "[" << getCurrentTimeStamp()
        << "] [ffmpeg-kit] [ERROR] Failed to create async callback block: %d"
        << rc << std::endl;
    lock.unlock();
    return;
  }

  ffmpegkit_set_log_delegate_callback(ffmpegkit_log_callback_function);
  av_log_set_callback(ffmpegkit_log_callback_function);
  set_report_callback(ffmpegkit_statistics_callback_function);
}

void ffmpegkit::FFmpegKitConfig::disableRedirection() {
  std::unique_lock<KitMutex> lock(getCallbackDataMutex(), std::defer_lock);

  lock.lock();

  if (redirectionEnabled.load(std::memory_order_relaxed) == 0) {
    lock.unlock();
    return;
  }
  redirectionEnabled.store(0, std::memory_order_release);

  lock.unlock();

  callbackNotify();

  // file-scope variable
  if (callbackThread != 0) {
#ifdef _WIN32
    // Windows implementation
    WaitForSingleObject((HANDLE)callbackThread, 5000);
    CloseHandle((HANDLE)callbackThread);
#else
    // Standard Linux/GLIBC
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    std::string timestamp = getCurrentTimeStamp();
    std::cout
        << "[" << timestamp
        << "] [ffmpeg-kit] [INFO] Attempting timed join for callback thread"
        << std::endl;
    ts.tv_sec += 5;
    int rc = pthread_timedjoin_np(callbackThread, nullptr, &ts);
    if (rc != 0) {
      // If tryjoin failed (thread still running) or isn't supported,
      // we must detach to prevent leaks and avoid blocking.
      timestamp = getCurrentTimeStamp();
      std::cout << "[" << timestamp
                << "] [ffmpeg-kit] [WARNING] Failed to join callback thread "
                   "(timeout or error: "
                << rc << ") at " << timestamp << ", detaching instead."
                << std::endl;
      pthread_detach(callbackThread);
    }
#endif
    callbackThread = 0;
  }

  ffmpegkit_set_log_delegate_callback(nullptr);
  av_log_set_callback(av_log_default_callback);
  set_report_callback(NULL);
}

int ffmpegkit::FFmpegKitConfig::setFontconfigConfigurationPath(
    const std::string &path) {
  return ffmpegkit::FFmpegKitConfig::setEnvironmentVariable("FONTCONFIG_PATH",
                                                            path);
}

void ffmpegkit::FFmpegKitConfig::setFontDirectory(
    const std::string &fontDirectoryPath,
    const std::map<std::string, std::string> &fontNameMapping) {
  ffmpegkit::FFmpegKitConfig::setFontDirectoryList(
      std::list<std::string>{fontDirectoryPath}, fontNameMapping);
}

void ffmpegkit::FFmpegKitConfig::setFontDirectoryList(
    const std::list<std::string> &fontDirectoryList,
    const std::map<std::string, std::string> &fontNameMapping) {
  int validFontNameMappingCount = 0;

  const char *parentDirectory = std::getenv("HOME");
  if (parentDirectory == NULL) {
    parentDirectory = std::getenv("TMPDIR");
    if (parentDirectory == NULL) {
      parentDirectory = ".";
    }
  }

  std::string cacheDir = std::string(parentDirectory) + "/.cache";
  std::string ffmpegKitDir = cacheDir + "/ffmpegkit";
  auto tempConfigurationDirectory = ffmpegKitDir + "/fontconfig";
  auto fontConfigurationFile =
      std::string(tempConfigurationDirectory) + "/fonts.conf";

  if (!fs_create_dir(cacheDir) || !fs_create_dir(ffmpegKitDir) ||
      !fs_create_dir(tempConfigurationDirectory)) {
    return;
  }
  std::cout
      << "[" << getCurrentTimeStamp()
      << "] [ffmpeg-kit] [INFO] Created temporary font conf directory: TRUE."
      << std::endl;

  if (fs_exists(fontConfigurationFile, true, false)) {
    bool fontConfigurationDeleted = std::remove(fontConfigurationFile.c_str());
    std::cout
        << "[" << getCurrentTimeStamp()
        << "] [ffmpeg-kit] [INFO] Deleted old temporary font configuration: "
        << (fontConfigurationDeleted == 0 ? "TRUE" : "FALSE") << "."
        << std::endl;
  }

  /* PROCESS MAPPINGS FIRST */
  std::string fontNameMappingBlock = "";
  for (auto const &pair : fontNameMapping) {
    if ((pair.first.size() > 0) && (pair.second.size() > 0)) {

      fontNameMappingBlock += "    <match target=\"pattern\">\n";
      fontNameMappingBlock += "        <test qual=\"any\" name=\"family\">\n";
      fontNameMappingBlock += "                <string>";
      fontNameMappingBlock += pair.first;
      fontNameMappingBlock += "</string>\n";
      fontNameMappingBlock += "        </test>\n";
      fontNameMappingBlock +=
          "        <edit name=\"family\" mode=\"assign\" binding=\"same\">\n";
      fontNameMappingBlock += "            <string>";
      fontNameMappingBlock += pair.second;
      fontNameMappingBlock += "</string>\n";
      fontNameMappingBlock += "        </edit>\n";
      fontNameMappingBlock += "    </match>\n";

      validFontNameMappingCount++;
    }
  }

  std::string fontConfiguration;
  fontConfiguration += "<?xml version=\"1.0\"?>\n";
  fontConfiguration += "<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">\n";
  fontConfiguration += "<fontconfig>\n";
  fontConfiguration += "    <dir prefix=\"cwd\">.</dir>\n";

  for (const auto &fontDirectoryPath : fontDirectoryList) {
    fontConfiguration += "    <dir>";
    fontConfiguration += fontDirectoryPath;
    fontConfiguration += "</dir>\n";
  }
  fontConfiguration += fontNameMappingBlock;
  fontConfiguration += "</fontconfig>\n";

  std::ofstream fontConfigurationStream(fontConfigurationFile,
                                        std::ios::out | std::ios::trunc);
  if (fontConfigurationStream) {
    fontConfigurationStream << fontConfiguration;
  }
  if (fontConfigurationStream.bad()) {
    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [ERROR] Failed to set font directory. Error "
                 "received while saving "
                 "font configuration: "
              << fontConfigurationStream.rdbuf() << "." << std::endl;
  }
  fontConfigurationStream.close();

  std::cout
      << "[" << getCurrentTimeStamp()
      << "] [ffmpeg-kit] [INFO] Saved new temporary font configuration with "
      << validFontNameMappingCount << " font name mappings." << std::endl;

  ffmpegkit::FFmpegKitConfig::setFontconfigConfigurationPath(
      tempConfigurationDirectory.c_str());

  for (const auto &fontDirectoryPath : fontDirectoryList) {
    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [INFO] Font directory " << fontDirectoryPath
              << " registered successfully." << std::endl;
  }
}

std::shared_ptr<std::string>
ffmpegkit::FFmpegKitConfig::registerNewFFmpegPipe() {
  const char *parentDirectory = std::getenv("HOME");
  if (parentDirectory == NULL) {
    parentDirectory = std::getenv("TMPDIR");
    if (parentDirectory == NULL) {
      parentDirectory = ".";
    }
  }

  // PIPES ARE CREATED UNDER THE PIPES DIRECTORY
  std::string cacheDir = std::string(parentDirectory) + "/.cache";
  std::string ffmpegKitDir = cacheDir + "/ffmpegkit";
  std::string pipesDir = ffmpegKitDir + "/pipes";

  if (!fs_create_dir(cacheDir) || !fs_create_dir(ffmpegKitDir) ||
      !fs_create_dir(pipesDir)) {
    return nullptr;
  }

  std::shared_ptr<std::string> newFFmpegPipePath =
      std::make_shared<std::string>(pipesDir + "/" + FFmpegKitNamedPipePrefix +
                                    std::to_string(pipeIndexGenerator++));

  // FIRST CLOSE OLD PIPES WITH THE SAME NAME
  ffmpegkit::FFmpegKitConfig::closeFFmpegPipe(newFFmpegPipePath->c_str());
  int rc = 0;
#ifdef _WIN32
  // Windows doesn't support mkfifo - use named pipes API
  HANDLE hPipe =
      CreateNamedPipeA(newFFmpegPipePath->c_str(), PIPE_ACCESS_DUPLEX,
                       PIPE_TYPE_BYTE | PIPE_WAIT,
                       1,    // Number of instances
                       1024, // Out buffer size
                       1024, // In buffer size
                       0,    // Default timeout
                       NULL  // Default security attributes
      );

  if (hPipe == INVALID_HANDLE_VALUE) {
    rc = -1;
  } else {
    CloseHandle(hPipe);
    rc = 0;
  }
#else
  rc = mkfifo(newFFmpegPipePath->c_str(), S_IRWXU | S_IRWXG | S_IROTH);
#endif

  if (rc == 0) {
    return newFFmpegPipePath;
  } else {
    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [ERROR] Failed to register new FFmpeg pipe "
              << newFFmpegPipePath << ". Operation failed with rc=" << rc << "."
              << std::endl;
    return nullptr;
  }
}

void ffmpegkit::FFmpegKitConfig::closeFFmpegPipe(
    const std::string &ffmpegPipePath) {
  std::remove(ffmpegPipePath.c_str());
}

std::string ffmpegkit::FFmpegKitConfig::getFFmpegVersion() {
  return FFMPEG_VERSION;
}

std::string ffmpegkit::FFmpegKitConfig::getFFmpegArchitecture() {
  return ffmpegkit::ArchDetect::getArch();
}

std::string ffmpegkit::FFmpegKitConfig::getVersion() {
  return FFmpegKitVersion;
}

std::string ffmpegkit::FFmpegKitConfig::getBuildDate() {
  char buildDate[10];
  sprintf(buildDate, "%d", FFMPEG_KIT_BUILD_DATE);
  return std::string(buildDate);
}

int ffmpegkit::FFmpegKitConfig::setEnvironmentVariable(
    const std::string &variableName, const std::string &variableValue) {
#ifdef _WIN32
  return _putenv_s(variableName.c_str(), variableValue.c_str());
#else
  return setenv(variableName.c_str(), variableValue.c_str(), 1);
#endif
}

void ffmpegkit::FFmpegKitConfig::ignoreSignal(const ffmpegkit::Signal signal) {
  if (signal == ffmpegkit::SignalQuit) {
    handleSIGQUIT = 0;
  } else if (signal == ffmpegkit::SignalInt) {
    handleSIGINT = 0;
  } else if (signal == ffmpegkit::SignalTerm) {
    handleSIGTERM = 0;
  } else if (signal == ffmpegkit::SignalXcpu) {
    handleSIGXCPU = 0;
  } else if (signal == ffmpegkit::SignalPipe) {
    handleSIGPIPE = 0;
  }
}

void ffmpegkit::FFmpegKitConfig::ffmpegExecute(
    const std::shared_ptr<ffmpegkit::FFmpegSession> ffmpegSession) {
  ffmpegSession->startRunning();
  bindSessionToThread(ffmpegSession);

  try {
    int returnCodeValue = executeFFmpeg(ffmpegSession, ffmpegSession->getArguments());

    // Wait for all logs/stats to be processed by the callback thread
    // Wait BEFORE completing so that the final output is ready when complete
    // callbacks fire
    ffmpegSession->waitForAsynchronousMessagesInTransmit(
        AbstractSession::DefaultTimeoutForAsynchronousMessagesInTransmit);
    ffmpegSession->debugLog("FFmpegKitConfig::ffmpegExecute after-wait session=%ld state=%d in_transit=%d",
                            ffmpegSession->getSessionId(),
                            ffmpegSession->getState(),
                            ffmpegSession->thereAreAsynchronousMessagesInTransmit());

    auto returnCode = std::make_shared<ffmpegkit::ReturnCode>(returnCodeValue);
    ffmpegSession->complete(returnCode);
    ffmpegSession->debugLog("FFmpegKitConfig::ffmpegExecute sessionId: %ld complete",
                            ffmpegSession->getSessionId());
    clearSessionFromThread();
  } catch (const std::exception &exception) {
    if (ffmpegSession != nullptr) {
      ffmpegSession->debugLog("FFmpegKitConfig::ffmpegExecute sessionId: %ld exception: %s",
                              ffmpegSession->getSessionId(), exception.what());
    }
    ffmpegSession->fail(exception.what());
    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [ERROR] FFmpeg execute failed: "
              << ffmpegkit::FFmpegKitConfig::argumentsToString(
                     ffmpegSession->getArguments())
              << "." << exception.what() << std::endl;
    clearSessionFromThread();
  }
}

void ffmpegkit::FFmpegKitConfig::ffprobeExecute(
    const std::shared_ptr<ffmpegkit::FFprobeSession> ffprobeSession) {
  ffprobeSession->startRunning();
  bindSessionToThread(ffprobeSession);

  try {
    int returnCodeValue =
        executeFFprobe(ffprobeSession, ffprobeSession->getArguments());

    auto returnCode = std::make_shared<ffmpegkit::ReturnCode>(returnCodeValue);
    ffprobeSession->complete(returnCode);

    // Generic FFprobe sessions should become terminal as soon as probing ends.
    // Drain any remaining asynchronous log traffic after the terminal state is
    // visible so concurrent tests and follow-on sessions are not blocked by
    // callback-thread backlog under heavy sanitizer load.
    ffprobeSession->waitForAsynchronousMessagesInTransmit(
        AbstractSession::DefaultTimeoutForAsynchronousMessagesInTransmit);

    ffprobeSession->debugLog("FFmpegKitConfig::ffprobeExecute sessionId: %ld complete",
                             ffprobeSession->getSessionId());
    clearSessionFromThread();
  } catch (const std::exception &exception) {
    if (ffprobeSession != nullptr) {
      ffprobeSession->debugLog("FFmpegKitConfig::ffprobeExecute sessionId: %ld exception: %s",
                               ffprobeSession->getSessionId(),
                               exception.what());
    }
    ffprobeSession->fail(exception.what());
    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [ERROR] FFprobe execute failed: "
              << ffmpegkit::FFmpegKitConfig::argumentsToString(
                     ffprobeSession->getArguments())
              << "." << exception.what() << std::endl;
    clearSessionFromThread();
  }
}

void ffmpegkit::FFmpegKitConfig::ffplayExecute(
    const std::shared_ptr<ffmpegkit::FFplaySession> ffplaySession,
    int waitTimeout) {

  // 1. START THE SESSION
  ffplaySession->startRunning();
  bindSessionToThread(ffplaySession);

  long sessionId = ffplaySession->getSessionId();

  // SINGLE SESSION ENFORCEMENT
  long previousSessionId = activeFFplaySessionId.exchange(sessionId);
  if (previousSessionId != 0) {
    cancelSession(previousSessionId);

    // Wait for previous session to fully complete cleanup
    auto prevSession = getSession(previousSessionId);
    if (prevSession) {
      if (!prevSession->waitFor(waitTimeout)) {
        std::cout << "[" << getCurrentTimeStamp()
                  << "] [ffmpeg-kit] [ERROR] FFplay execute failed: Timed out "
                     "waiting for previous "
                     "FFplay session "
                  << previousSessionId << " to complete." << std::endl;
        activeFFplaySessionId.compare_exchange_strong(sessionId, 0);
        ffplaySession->fail(
            "Timed out waiting for previous session to complete");
        return;
      }
    }
  }

  // 2. RUN
  try {
    int returnCodeValue =
        executeFFplay(sessionId, ffplaySession->getArguments());

    // RESET ACTIVE SESSION ID IF IT'S STILL US
    activeFFplaySessionId.compare_exchange_strong(sessionId, 0);

    auto returnCode = std::make_shared<ffmpegkit::ReturnCode>(returnCodeValue);
    ffplaySession->complete(returnCode);

    // FFplay controls and single-session handoff should observe terminal state
    // immediately after playback stops. Drain the callback backlog afterward so
    // verbose status lines do not keep the session in RUNNING under TSAN.
    ffplaySession->waitForAsynchronousMessagesInTransmit(
        AbstractSession::DefaultTimeoutForAsynchronousMessagesInTransmit);

    clearSessionFromThread();
  } catch (const std::exception &exception) {
    if (ffplaySession != nullptr) {
      ffplaySession->debugLog("FFmpegKitConfig::ffplayExecute sessionId: %ld exception: %s",
                              sessionId, exception.what());
    }
    activeFFplaySessionId.compare_exchange_strong(sessionId, 0);
    ffplaySession->fail(exception.what());
    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [ERROR] FFplay execute failed: "
              << exception.what() << std::endl;
    clearSessionFromThread();
  }
}

void ffmpegkit::FFmpegKitConfig::getMediaInformationExecute(
    const std::shared_ptr<ffmpegkit::MediaInformationSession>
        mediaInformationSession,
    const int waitTimeout) {
  mediaInformationSession->startRunning();

  try {
    std::string ffprobeJsonOutput;
    int returnCodeValue = executeFFprobe(mediaInformationSession,
                                         mediaInformationSession->getArguments(),
                                         &ffprobeJsonOutput);
    // Wait for all logs/stats to be processed by the callback thread
    mediaInformationSession->waitForAsynchronousMessagesInTransmit(
        AbstractSession::DefaultTimeoutForAsynchronousMessagesInTransmit);

    auto returnCode = std::make_shared<ffmpegkit::ReturnCode>(returnCodeValue);
    mediaInformationSession->complete(returnCode);
    if (returnCode->isValueSuccess()) {
      mediaInformationSession->debugLog(
          "FFmpegKitConfig::getMediaInformationExecute sessionId: %ld JSON length: %d",
          mediaInformationSession->getSessionId(),
          (int)ffprobeJsonOutput.length());

      if (ffprobeJsonOutput.empty()) {
        mediaInformationSession->debugLog(
            "FFmpegKitConfig::getMediaInformationExecute sessionId: %ld empty captured output",
            mediaInformationSession->getSessionId());
      }

      auto mediaInformation =
          ffmpegkit::MediaInformationJsonParser::fromWithError(
              ffprobeJsonOutput.c_str());
      mediaInformationSession->setMediaInformation(mediaInformation);

      if (mediaInformation != nullptr) {
        mediaInformationSession->debugLog(
            "FFmpegKitConfig::getMediaInformationExecute sessionId: %ld parsing SUCCESS",
            mediaInformationSession->getSessionId());
      }
    }
  } catch (const std::exception &exception) {
    mediaInformationSession->debugLog(
        "FFmpegKitConfig::getMediaInformationExecute sessionId: %ld exception: %s",
        mediaInformationSession->getSessionId(), exception.what());
    mediaInformationSession->fail(exception.what());
    std::cout << "[" << getCurrentTimeStamp()
              << "] [ffmpeg-kit] [ERROR] Get media information execute failed: "
              << ffmpegkit::FFmpegKitConfig::argumentsToString(
                     mediaInformationSession->getArguments())
              << "." << exception.what() << std::endl;
  }
}

struct AsyncFFmpegArgs {
  std::shared_ptr<ffmpegkit::FFmpegSession> session;
};

struct AsyncFFprobeArgs {
  std::shared_ptr<ffmpegkit::FFprobeSession> session;
};

struct AsyncFFplayArgs {
  std::shared_ptr<ffmpegkit::FFplaySession> session;
  int waitTimeout;
};

struct AsyncMediaInfoArgs {
  std::shared_ptr<ffmpegkit::MediaInformationSession> session;
  int waitTimeout;
};

void ffmpegkit::FFmpegKitConfig::asyncFFmpegExecute(
    const std::shared_ptr<ffmpegkit::FFmpegSession> ffmpegSession) {

  auto *args = new AsyncFFmpegArgs{ffmpegSession};
  pthread_t thread;
  pthread_create(
      &thread, nullptr,
      [](void *arg) -> void * {
        auto *a = static_cast<AsyncFFmpegArgs *>(arg);
        auto session = std::move(a->session);
        delete a;

        ffmpegkit::FFmpegKitConfig::ffmpegExecute(session);

        auto completeCallback = session->getCompleteCallback();
        if (completeCallback != nullptr) {
          try {
            completeCallback(session);
          } catch (const std::exception &e) {
            std::cout << "[" << getCurrentTimeStamp()
                      << "] [ffmpeg-kit] [ERROR] Exception in session complete "
                         "callback: "
                      << e.what() << std::endl;
          }
        }
        {
          std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
          auto globalCallback =
              ffmpegkit::FFmpegKitConfig::getFFmpegSessionCompleteCallback();
          if (globalCallback != nullptr) {
            try {
              globalCallback(session);
            } catch (const std::exception &e) {
              std::cout << "[" << getCurrentTimeStamp()
                        << "] [ffmpeg-kit] [ERROR] Exception in global "
                           "complete callback: "
                        << e.what() << std::endl;
            }
          }
        }
        return nullptr;
      },
      args);
  pthread_detach(thread);
}

void ffmpegkit::FFmpegKitConfig::asyncFFprobeExecute(
    const std::shared_ptr<ffmpegkit::FFprobeSession> ffprobeSession) {

  auto *args = new AsyncFFprobeArgs{ffprobeSession};
  pthread_t thread;
  pthread_create(
      &thread, nullptr,
      [](void *arg) -> void * {
        auto *a = static_cast<AsyncFFprobeArgs *>(arg);
        auto session = std::move(a->session);
        delete a;

        ffmpegkit::FFmpegKitConfig::ffprobeExecute(session);

        auto completeCallback = session->getCompleteCallback();
        if (completeCallback != nullptr) {
          try {
            completeCallback(session);
          } catch (const std::exception &e) {
            std::cout << "[" << getCurrentTimeStamp()
                      << "] [ffmpeg-kit] [ERROR] Exception in session complete "
                         "callback: "
                      << e.what() << std::endl;
          }
        }
        {
          std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
          auto globalCallback =
              ffmpegkit::FFmpegKitConfig::getFFprobeSessionCompleteCallback();
          if (globalCallback != nullptr) {
            try {
              globalCallback(session);
            } catch (const std::exception &e) {
              std::cout << "[" << getCurrentTimeStamp()
                        << "] [ffmpeg-kit] [ERROR] Exception in global "
                           "complete callback: "
                        << e.what() << std::endl;
            }
          }
        }
        return nullptr;
      },
      args);
  pthread_detach(thread);
}

void ffmpegkit::FFmpegKitConfig::asyncFFplayExecute(
    const std::shared_ptr<ffmpegkit::FFplaySession> ffplaySession,
    int waitTimeout) {
  // Join any previously completed async ffplay thread before launching a new
  // one
  if (asyncFFplayThread != 0) {
    auto activeSession = getActiveFFplaySession();
    if (activeSession != nullptr) {
      activeSession->close();
    }
    detachAsyncFFplayThread();
  }

  auto *args = new AsyncFFplayArgs{ffplaySession, waitTimeout};
  pthread_create(
      &asyncFFplayThread, nullptr,
      [](void *arg) -> void * {
        auto *a = static_cast<AsyncFFplayArgs *>(arg);
        auto session = std::move(a->session);
        int timeout = a->waitTimeout;
        delete a;

        ffmpegkit::FFmpegKitConfig::ffplayExecute(session, timeout);

        auto completeCallback = session->getCompleteCallback();
        if (completeCallback != nullptr) {
          try {
            completeCallback(session);
          } catch (const std::exception &e) {
            std::cout << "[" << getCurrentTimeStamp()
                      << "] [ffmpeg-kit] [ERROR] Exception in session complete "
                         "callback: "
                      << e.what() << std::endl;
          }
        }
        {
          std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
          auto globalCallback =
              ffmpegkit::FFmpegKitConfig::getFFplaySessionCompleteCallback();
          if (globalCallback != nullptr) {
            try {
              globalCallback(session);
            } catch (const std::exception &e) {
              std::cout << "[" << getCurrentTimeStamp()
                        << "] [ffmpeg-kit] [ERROR] Exception in global "
                           "complete callback: "
                        << e.what() << std::endl;
            }
          }
        }
        return nullptr;
      },
      args);
  // Do NOT detach: keep asyncFFplayThread joinable so we can wait for it at
  // program exit (in ~FFmpegKitConfig) and avoid ASAN/TLS teardown crashes.
}

void ffmpegkit::FFmpegKitConfig::asyncGetMediaInformationExecute(
    const std::shared_ptr<ffmpegkit::MediaInformationSession>
        mediaInformationSession,
    const int waitTimeout) {

  auto *args = new AsyncMediaInfoArgs{mediaInformationSession, waitTimeout};
  pthread_t thread;
  pthread_create(
      &thread, nullptr,
      [](void *arg) -> void * {
        auto *a = static_cast<AsyncMediaInfoArgs *>(arg);
        auto session = std::move(a->session);
        int timeout = a->waitTimeout;
        delete a;

        ffmpegkit::FFmpegKitConfig::getMediaInformationExecute(session,
                                                               timeout);

        auto completeCallback = session->getCompleteCallback();
        if (completeCallback != nullptr) {
          try {
            completeCallback(session);
          } catch (const std::exception &e) {
            std::cout << "[" << getCurrentTimeStamp()
                      << "] [ffmpeg-kit] [ERROR] Exception in session complete "
                         "callback: "
                      << e.what() << std::endl;
          }
        }
        {
          std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
          auto globalCallback = ffmpegkit::FFmpegKitConfig::
              getMediaInformationSessionCompleteCallback();
          if (globalCallback != nullptr) {
            try {
              globalCallback(session);
            } catch (const std::exception &e) {
              std::cout << "[" << getCurrentTimeStamp()
                        << "] [ffmpeg-kit] [ERROR] Exception in global "
                           "complete callback: "
                        << e.what() << std::endl;
            }
          }
        }
        return nullptr;
      },
      args);
  pthread_detach(thread);
}

void ffmpegkit::FFmpegKitConfig::enableLogCallback(
    const ffmpegkit::LogCallback callback) {
  std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
  logCallback = callback;
}

ffmpegkit::LogCallback ffmpegkit::FFmpegKitConfig::getLogCallback() {
  std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
  return logCallback;
}

void ffmpegkit::FFmpegKitConfig::enableStatisticsCallback(
    const ffmpegkit::StatisticsCallback callback) {
  std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
  statisticsCallback = callback;
}

void ffmpegkit::FFmpegKitConfig::enableFFmpegSessionCompleteCallback(
    const FFmpegSessionCompleteCallback completeCallback) {
  std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
  ffmpegSessionCompleteCallback = completeCallback;
}

ffmpegkit::FFmpegSessionCompleteCallback
ffmpegkit::FFmpegKitConfig::getFFmpegSessionCompleteCallback() {
  std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
  return ffmpegSessionCompleteCallback;
}

void ffmpegkit::FFmpegKitConfig::enableFFprobeSessionCompleteCallback(
    const FFprobeSessionCompleteCallback completeCallback) {
  std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
  ffprobeSessionCompleteCallback = completeCallback;
}

ffmpegkit::FFprobeSessionCompleteCallback
ffmpegkit::FFmpegKitConfig::getFFprobeSessionCompleteCallback() {
  std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
  return ffprobeSessionCompleteCallback;
}

void ffmpegkit::FFmpegKitConfig::enableFFplaySessionCompleteCallback(
    const FFplaySessionCompleteCallback completeCallback) {
  std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
  ffplaySessionCompleteCallback = completeCallback;
}

ffmpegkit::FFplaySessionCompleteCallback
ffmpegkit::FFmpegKitConfig::getFFplaySessionCompleteCallback() {
  std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
  return ffplaySessionCompleteCallback;
}

void ffmpegkit::FFmpegKitConfig::enableMediaInformationSessionCompleteCallback(
    const MediaInformationSessionCompleteCallback completeCallback) {
  std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
  mediaInformationSessionCompleteCallback = completeCallback;
}

ffmpegkit::MediaInformationSessionCompleteCallback
ffmpegkit::FFmpegKitConfig::getMediaInformationSessionCompleteCallback() {
  std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
  return mediaInformationSessionCompleteCallback;
}

ffmpegkit::Level ffmpegkit::FFmpegKitConfig::getLogLevel() {
  return static_cast<ffmpegkit::Level>(configuredLogLevel);
}

void ffmpegkit::FFmpegKitConfig::setLogLevel(const ffmpegkit::Level level) {
  configuredLogLevel = level;
  av_log_set_level((int)level);
}

std::string
ffmpegkit::FFmpegKitConfig::logLevelToString(const ffmpegkit::Level level) {
  switch (level) {
  case ffmpegkit::LevelAVLogStdErr:
    return "STDERR";
  case ffmpegkit::LevelAVLogTrace:
    return "TRACE";
  case ffmpegkit::LevelAVLogDebug:
    return "DEBUG";
  case ffmpegkit::LevelAVLogVerbose:
    return "VERBOSE";
  case ffmpegkit::LevelAVLogInfo:
    return "INFO";
  case ffmpegkit::LevelAVLogWarning:
    return "WARNING";
  case ffmpegkit::LevelAVLogError:
    return "ERROR";
  case ffmpegkit::LevelAVLogFatal:
    return "FATAL";
  case ffmpegkit::LevelAVLogPanic:
    return "PANIC";
  case ffmpegkit::LevelAVLogQuiet:
    return "QUIET";
  default:
    return "";
  }
}

int ffmpegkit::FFmpegKitConfig::getSessionHistorySize() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);
  lock.lock();
  int size = sessionHistorySize;
  lock.unlock();
  return size;
}

void ffmpegkit::FFmpegKitConfig::setSessionHistorySize(
    const int newSessionHistorySize) {
  if (newSessionHistorySize >= SESSION_MAP_SIZE) {

    /*
     * THERE IS A HARD LIMIT ON THE NATIVE SIDE. HISTORY SIZE MUST BE SMALLER
     * THAN SESSION_MAP_SIZE
     */
    av_log(nullptr, AV_LOG_WARNING,
           "[%s] [ffmpeg-kit] [WARNING] Session history size must not exceed "
           "the hard limit of %d!\n",
           getCurrentTimeStamp().c_str(), SESSION_MAP_SIZE);
    sessionHistorySize = SESSION_MAP_SIZE;
  } else if (newSessionHistorySize > 0) {
    sessionHistorySize = newSessionHistorySize;
  }
  
  // Call deleteExpiredSessions while holding the session mutex
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);
  lock.lock();
  deleteExpiredSessions();
  lock.unlock();
}

std::shared_ptr<ffmpegkit::Session>
ffmpegkit::FFmpegKitConfig::getSession(const long sessionId) {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);
  lock.lock();

  auto session = getSessionHistoryMap().find(sessionId);
  if (session != getSessionHistoryMap().end()) {
    return session->second;
  } else {
    return nullptr;
  }
}

std::shared_ptr<ffmpegkit::Session>
ffmpegkit::FFmpegKitConfig::getLastSession() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);

  lock.lock();

  if (getSessionHistoryList().empty()) {
    return nullptr;
  }

  return getSessionHistoryList().front();
}

std::shared_ptr<ffmpegkit::FFmpegSession>
ffmpegkit::FFmpegKitConfig::getLastFFmpegSession() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);

  lock.lock();

  if (getSessionHistoryList().empty()) {
    return nullptr;
  }

  for (auto rit = getSessionHistoryList().rbegin();
       rit != getSessionHistoryList().rend(); ++rit) {
    auto session = *rit;
    if (session->isFFmpeg()) {
      return std::dynamic_pointer_cast<ffmpegkit::FFmpegSession>(session);
    }
  }

  return nullptr;
}

std::shared_ptr<ffmpegkit::FFprobeSession>
ffmpegkit::FFmpegKitConfig::getLastFFprobeSession() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);

  lock.lock();

  if (getSessionHistoryList().empty()) {
    return nullptr;
  }

  for (auto rit = getSessionHistoryList().rbegin();
       rit != getSessionHistoryList().rend(); ++rit) {
    auto session = *rit;
    if (session->isFFprobe()) {
      return std::dynamic_pointer_cast<ffmpegkit::FFprobeSession>(session);
    }
  }

  return nullptr;
}

std::shared_ptr<ffmpegkit::FFplaySession>
ffmpegkit::FFmpegKitConfig::getLastFFplaySession() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);

  lock.lock();

  if (getSessionHistoryList().empty()) {
    return nullptr;
  }

  for (auto rit = getSessionHistoryList().rbegin();
       rit != getSessionHistoryList().rend(); ++rit) {
    auto session = *rit;
    if (session->isFFplay()) {
      return std::dynamic_pointer_cast<ffmpegkit::FFplaySession>(session);
    }
  }

  return nullptr;
}

std::shared_ptr<ffmpegkit::MediaInformationSession>
ffmpegkit::FFmpegKitConfig::getLastMediaInformationSession() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);

  lock.lock();

  if (getSessionHistoryList().empty()) {
    return nullptr;
  }

  for (auto rit = getSessionHistoryList().rbegin();
       rit != getSessionHistoryList().rend(); ++rit) {
    auto session = *rit;
    if (session->isMediaInformation()) {
      return std::dynamic_pointer_cast<ffmpegkit::MediaInformationSession>(
          session);
    }
  }

  return nullptr;
}

std::shared_ptr<ffmpegkit::Session>
ffmpegkit::FFmpegKitConfig::getLastCompletedSession() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);

  lock.lock();

  for (auto rit = getSessionHistoryList().rbegin();
       rit != getSessionHistoryList().rend(); ++rit) {
    auto session = *rit;
    if (session->getState() == SessionStateCompleted) {
      return session;
    }
  }

  return nullptr;
}

std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Session>>>
ffmpegkit::FFmpegKitConfig::getSessions() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);
  lock.lock();

  auto sessionHistoryListCopy =
      std::make_shared<std::list<std::shared_ptr<ffmpegkit::Session>>>(
          getSessionHistoryList());

  lock.unlock();

  return sessionHistoryListCopy;
}

void ffmpegkit::FFmpegKitConfig::clearSessions() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);
  lock.lock();

  getSessionHistoryList().clear();
  getSessionHistoryMap().clear();

  lock.unlock();
}

std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::FFmpegSession>>>
ffmpegkit::FFmpegKitConfig::getFFmpegSessions() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);
  const auto ffmpegSessions =
      std::make_shared<std::list<std::shared_ptr<ffmpegkit::FFmpegSession>>>();

  lock.lock();

  for (auto it = getSessionHistoryList().begin();
       it != getSessionHistoryList().end(); ++it) {
    auto session = *it;
    if (session->isFFmpeg()) {
      ffmpegSessions->push_back(
          std::static_pointer_cast<ffmpegkit::FFmpegSession>(session));
    }
  }

  lock.unlock();

  return ffmpegSessions;
}

std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::FFprobeSession>>>
ffmpegkit::FFmpegKitConfig::getFFprobeSessions() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);
  std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::FFprobeSession>>>
      result = std::make_shared<
          std::list<std::shared_ptr<ffmpegkit::FFprobeSession>>>();

  lock.lock();

  for (auto it = getSessionHistoryList().begin();
       it != getSessionHistoryList().end(); ++it) {
    if ((*it)->isFFprobe()) {
      result->push_back(
          std::static_pointer_cast<ffmpegkit::FFprobeSession>(*it));
    }
  }

  lock.unlock();

  return result;
}

std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::FFplaySession>>>
ffmpegkit::FFmpegKitConfig::getFFplaySessions() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);
  std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::FFplaySession>>> result =
      std::make_shared<std::list<std::shared_ptr<ffmpegkit::FFplaySession>>>();

  lock.lock();

  for (auto it = getSessionHistoryList().begin();
       it != getSessionHistoryList().end(); ++it) {
    if ((*it)->isFFplay()) {
      result->push_back(
          std::static_pointer_cast<ffmpegkit::FFplaySession>(*it));
    }
  }

  lock.unlock();

  return result;
}

std::shared_ptr<ffmpegkit::FFplaySession>
ffmpegkit::FFmpegKitConfig::getActiveFFplaySession() {
  long sessionId = activeFFplaySessionId.load();
  if (sessionId != 0) {
    return std::static_pointer_cast<FFplaySession>(getSession(sessionId));
  }
  return nullptr;
}

std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::MediaInformationSession>>>
ffmpegkit::FFmpegKitConfig::getMediaInformationSessions() {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);
  const auto mediaInformationSessions = std::make_shared<
      std::list<std::shared_ptr<ffmpegkit::MediaInformationSession>>>();

  lock.lock();

  for (auto it = getSessionHistoryList().begin();
       it != getSessionHistoryList().end(); ++it) {
    auto session = *it;
    if (session->isMediaInformation()) {
      mediaInformationSessions->push_back(
          std::static_pointer_cast<ffmpegkit::MediaInformationSession>(
              session));
    }
  }

  lock.unlock();

  return mediaInformationSessions;
}

std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Session>>>
ffmpegkit::FFmpegKitConfig::getSessionsByState(const SessionState state) {
  std::unique_lock<KitMutex> lock(getSessionMutex(), std::defer_lock);
  auto sessions =
      std::make_shared<std::list<std::shared_ptr<ffmpegkit::Session>>>();

  lock.lock();

  for (auto it = getSessionHistoryList().begin();
       it != getSessionHistoryList().end(); ++it) {
    auto session = *it;
    if (session->getState() == state) {
      sessions->push_back(session);
    }
  }

  lock.unlock();

  return sessions;
}

ffmpegkit::LogRedirectionStrategy
ffmpegkit::FFmpegKitConfig::getLogRedirectionStrategy() {
  return globalLogRedirectionStrategy;
}

void ffmpegkit::FFmpegKitConfig::setLogRedirectionStrategy(
    const LogRedirectionStrategy logRedirectionStrategy) {
  globalLogRedirectionStrategy = logRedirectionStrategy;
}

int ffmpegkit::FFmpegKitConfig::messagesInTransmit(const long sessionId) {
  if (sessionId == 0) {
    return 0;
  }

  return std::atomic_load(
      &sessionInTransitMessageCountMap[sessionId % SESSION_MAP_SIZE]);
}

bool ffmpegkit::FFmpegKitConfig::waitForSessionMessagesInTransmit(
    const long sessionId, const int timeout) {
  if (sessionId == 0 || messagesInTransmit(sessionId) == 0) {
    return true;
  }

  std::unique_lock<std::mutex> lock(getSessionMessageDrainMutex());
  return getSessionMessageDrainMonitor().wait_for(
      lock, std::chrono::milliseconds(timeout),
      [sessionId]() { return messagesInTransmit(sessionId) == 0; });
}

std::string
ffmpegkit::FFmpegKitConfig::sessionStateToString(SessionState state) {
  switch (state) {
  case SessionStateCreated:
    return "CREATED";
  case SessionStateRunning:
    return "RUNNING";
  case SessionStateFailed:
    return "FAILED";
  case SessionStateCompleted:
    return "COMPLETED";
  default:
    return "";
  }
}

std::list<std::string>
ffmpegkit::FFmpegKitConfig::parseArguments(const std::string &command) {
  std::list<std::string> argumentList;
  std::string currentArgument;

  bool singleQuoteStarted = false;
  bool doubleQuoteStarted = false;

  for (int i = 0; i < command.size(); i++) {
    char previousChar;
    if (i > 0) {
      previousChar = command[i - 1];
    } else {
      previousChar = 0;
    }
    char currentChar = command[i];

    if (currentChar == ' ') {
      if (singleQuoteStarted || doubleQuoteStarted) {
        currentArgument += currentChar;
      } else if (currentArgument.size() > 0) {
        argumentList.push_back(currentArgument);
        currentArgument = "";
      }
    } else if (currentChar == '\'' &&
               (previousChar == 0 || previousChar != '\\')) {
      if (singleQuoteStarted) {
        singleQuoteStarted = false;
      } else if (doubleQuoteStarted) {
        currentArgument += currentChar;
      } else {
        singleQuoteStarted = true;
      }
    } else if (currentChar == '\"' &&
               (previousChar == 0 || previousChar != '\\')) {
      if (doubleQuoteStarted) {
        doubleQuoteStarted = false;
      } else if (singleQuoteStarted) {
        currentArgument += currentChar;
      } else {
        doubleQuoteStarted = true;
      }
    } else {
      currentArgument += currentChar;
    }
  }

  if (currentArgument.size() > 0) {
    argumentList.push_back(currentArgument);
  }

  return argumentList;
}

std::string ffmpegkit::FFmpegKitConfig::argumentsToString(
    std::shared_ptr<std::list<std::string>> arguments) {
  if (arguments == nullptr) {
    return "null";
  }

  std::string string;
  for (auto it = arguments->begin(); it != arguments->end(); ++it) {
    auto argument = *it;
    if (it != arguments->begin()) {
      string += " ";
    }
    string += argument;
  }

  return string;
}

void ffmpegkit::FFmpegKitConfig::setAudioOutputDevice(
    const std::string &deviceName) {
  ffplay_set_audio_output_device(deviceName.empty() ? nullptr
                                                    : deviceName.c_str());
}

std::string ffmpegkit::FFmpegKitConfig::listAudioOutputDevices() {
  char *devices = ffplay_list_audio_devices();
  std::string result = "";
  if (devices) {
    result = std::string(devices);
    av_free(devices);
  }
  return result;
}

ffmpegkit::FFmpegKitConfig::~FFmpegKitConfig() {
  // 0. Join async ffplay thread so its TLS destructors run before ASAN/LLVM
  //    tears down during program exit (prevents __nptl_deallocate_tsd crash).
  if (asyncFFplayThread != 0) {
    auto activeSession = getActiveFFplaySession();
    if (activeSession != nullptr) {
      activeSession->close();
    }
    detachAsyncFFplayThread();
  }

  // 1. Stop background redirection thread first to prevent races on sessions
  disableRedirection();

  // 2. Clear session history
  clearSessions();
  // 2. Reset global callbacks with lock
  {
    std::lock_guard<KitMutex> lock(getGlobalCallbacksMutex());
    logCallback = nullptr;
    statisticsCallback = nullptr;
    ffmpegSessionCompleteCallback = nullptr;
    ffprobeSessionCompleteCallback = nullptr;
    ffplaySessionCompleteCallback = nullptr;
    mediaInformationSessionCompleteCallback = nullptr;
  }
  // 3. Clear remaining callback data raw pointers
  std::lock_guard<KitMutex> lock(getCallbackDataMutex());
  while (!getCallbackDataList().empty()) {
    delete getCallbackDataList().front();
    getCallbackDataList().pop_front();
  }
}

// At the very end of FFmpegKitConfig.cpp
namespace ffmpegkit {
static FFmpegKitConfig globalCleanupGuard;
}
