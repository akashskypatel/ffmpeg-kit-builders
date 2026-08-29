#include "ffmpegkit_wrapper.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <gtest/gtest.h>
#include <iterator>
#include <memory>
#include <mutex>
#include <optional>
#include <sstream>
#include <vector>

#ifdef _WIN32
#include <process.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <thread>
#include <unistd.h>
#endif

#ifndef FFMPEG_KIT_TEST_DIR
#define FFMPEG_KIT_TEST_DIR "."
#endif
#define TEST_VIDEO_FILE FFMPEG_KIT_TEST_DIR "/dummy_video.mp4"
#define TEST_AUDIO_FILE FFMPEG_KIT_TEST_DIR "/dummy_audio.wav"
#define FFMPEG_KIT_REMOTE_STREAM_URL                                           \
  "https://cdn.flowplayer.com/a30bd6bc-f98b-47bc-abf5-97633d4faea0/hls/"       \
  "de3f6ca7-2db3-4689-8160-0f574a5996ad/playlist.m3u8"

// Helper log callback for tests
void test_log_callback(FFmpegSessionHandle session, const char *message,
                       void *data) {
  // Optional: verify log output if needed
  printf("Log: %s\n", message);
}

namespace {

struct CompletionSignal {
  std::mutex mutex;
  std::condition_variable cv;
  bool completed = false;
};

#ifdef _WIN32
class TestThread {
public:
  TestThread() = default;

  template <typename Callable> explicit TestThread(Callable &&callable) {
    start(std::forward<Callable>(callable));
  }

  TestThread(const TestThread &) = delete;
  TestThread &operator=(const TestThread &) = delete;

  TestThread(TestThread &&other) noexcept : handle_(other.handle_) {
    other.handle_ = nullptr;
  }

  TestThread &operator=(TestThread &&other) noexcept {
    if (this != &other) {
      join();
      handle_ = other.handle_;
      other.handle_ = nullptr;
    }
    return *this;
  }

  ~TestThread() { join(); }

  template <typename Callable> void start(Callable &&callable) {
    using Task = std::function<void()>;
    auto *task = new Task(std::forward<Callable>(callable));
    unsigned thread_id = 0;
    handle_ = reinterpret_cast<HANDLE>(
        _beginthreadex(nullptr, 0, &TestThread::run, task, 0, &thread_id));
  }

  bool joinable() const { return handle_ != nullptr; }

  void join() {
    if (!handle_) {
      return;
    }
    WaitForSingleObject(handle_, INFINITE);
    CloseHandle(handle_);
    handle_ = nullptr;
  }

private:
  static unsigned __stdcall run(void *arg) {
    using Task = std::function<void()>;
    std::unique_ptr<Task> task(static_cast<Task *>(arg));
    (*task)();
    return 0;
  }

  HANDLE handle_{nullptr};
};
#else
using TestThread = std::thread;
#endif

static void test_sleep_for_ms(int milliseconds) {
#ifdef _WIN32
  Sleep(static_cast<DWORD>(milliseconds));
#else
  std::this_thread::sleep_for(std::chrono::milliseconds(milliseconds));
#endif
}

static void complete_callback(FFmpegSessionHandle session, void *user_data);
static void probe_complete_callback(FFprobeSessionHandle session,
                                    void *user_data);

class ScopedFFmpegCompleteCallback {
public:
  ScopedFFmpegCompleteCallback(FFmpegSessionHandle session,
                               std::shared_ptr<CompletionSignal> signal)
      : session_(session), signal_(std::move(signal)) {
    if (session_) {
      ffmpeg_kit_set_complete_callback(session_, complete_callback,
                                       signal_.get());
    }
  }

  ~ScopedFFmpegCompleteCallback() {
    if (session_) {
      ffmpeg_kit_set_complete_callback(session_, nullptr, nullptr);
    }
  }

  ScopedFFmpegCompleteCallback(const ScopedFFmpegCompleteCallback &) = delete;
  ScopedFFmpegCompleteCallback &
  operator=(const ScopedFFmpegCompleteCallback &) = delete;

private:
  FFmpegSessionHandle session_{nullptr};
  std::shared_ptr<CompletionSignal> signal_;
};

class ScopedFFprobeCompleteCallback {
public:
  ScopedFFprobeCompleteCallback(FFprobeSessionHandle session,
                                std::shared_ptr<CompletionSignal> signal)
      : session_(session), signal_(std::move(signal)) {
    if (session_) {
      ffprobe_kit_set_complete_callback(session_, probe_complete_callback,
                                        signal_.get());
    }
  }

  ~ScopedFFprobeCompleteCallback() {
    if (session_) {
      ffprobe_kit_set_complete_callback(session_, nullptr, nullptr);
    }
  }

  ScopedFFprobeCompleteCallback(const ScopedFFprobeCompleteCallback &) = delete;
  ScopedFFprobeCompleteCallback &
  operator=(const ScopedFFprobeCompleteCallback &) = delete;

private:
  FFprobeSessionHandle session_{nullptr};
  std::shared_ptr<CompletionSignal> signal_;
};

static bool tsan_active() {
#if defined(__SANITIZE_THREAD__)
  return true;
#elif defined(__has_feature)
#if __has_feature(thread_sanitizer)
  return true;
#else
  return false;
#endif
#else
  return false;
#endif
}

static void complete_callback(FFmpegSessionHandle session, void *user_data) {
  (void)session;
  auto *signal = static_cast<CompletionSignal *>(user_data);
  if (!signal) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(signal->mutex);
    if (signal->completed) {
      return;
    }
    signal->completed = true;
  }
  signal->cv.notify_all();
}

static void probe_complete_callback(FFprobeSessionHandle session,
                                    void *user_data) {
  (void)session;
  auto *signal = static_cast<CompletionSignal *>(user_data);
  if (!signal) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(signal->mutex);
    if (signal->completed) {
      return;
    }
    signal->completed = true;
  }
  signal->cv.notify_all();
}

static bool
wait_for_completion_signal(const std::shared_ptr<CompletionSignal> &signal,
                           int timeout_ms) {
  if (!signal) {
    return false;
  }
  std::unique_lock<std::mutex> lock(signal->mutex);
  return signal->cv.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                             [&signal]() { return signal->completed; });
}

static bool wait_for_running_state(void *session_handle, int timeout_ms) {
  int waited = 0;
  while (waited < timeout_ms) {
    if (ffmpeg_kit_session_get_state(session_handle) ==
        FFMPEG_KIT_SESSION_STATE_RUNNING) {
      return true;
    }
    test_sleep_for_ms(50);
    waited += 50;
  }
  return ffmpeg_kit_session_get_state(session_handle) ==
         FFMPEG_KIT_SESSION_STATE_RUNNING;
}

static std::string session_logs_as_string(void *session_handle) {
  char *logs = ffmpeg_kit_session_get_logs_as_string(session_handle);
  if (logs == nullptr) {
    return {};
  }

  std::string result(logs);
  free(logs);
  return result;
}

static void expect_logs_isolated(void *session_handle, const char *expected,
                                 const char *unexpected) {
  const std::string logs = session_logs_as_string(session_handle);
  ASSERT_FALSE(logs.empty());
  EXPECT_NE(logs.find(expected), std::string::npos)
      << "Expected to find log signature: " << expected << "\nLogs:\n"
      << logs;
  EXPECT_EQ(logs.find(unexpected), std::string::npos)
      << "Unexpectedly found foreign log signature: " << unexpected
      << "\nLogs:\n"
      << logs;
}

static std::string quote_path(const std::filesystem::path &path) {
  return "\"" + path.string() + "\"";
}

static std::string quote_argument(const std::string &value) {
  return "\"" + value + "\"";
}

static std::optional<std::string> remote_stream_url() {
  const char *value = std::getenv("FFMPEG_KIT_REMOTE_STREAM_URL");
  if (value != nullptr && *value != '\0') {
    return std::string(value);
  }
  return std::string(FFMPEG_KIT_REMOTE_STREAM_URL);
}

static std::string
remote_recording_command(const std::string &url,
                         const std::filesystem::path &output) {
  std::ostringstream command;
  command << "-y -nostdin -hide_banner -loglevel debug "
          << "-reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 "
          << "-reconnect_delay_max 5 -rw_timeout 5000000 "
          << "-i " << quote_argument(url) << " "
          << "-map 0 -c copy -f mpegts " << quote_path(output);
  return command.str();
}

static bool wait_for_file_size_at_least(const std::filesystem::path &path,
                                        uintmax_t min_size, int timeout_ms) {
  int waited = 0;
  while (waited < timeout_ms) {
    std::error_code ec;
    if (std::filesystem::exists(path, ec) && !ec) {
      const auto size = std::filesystem::file_size(path, ec);
      if (!ec && size >= min_size) {
        return true;
      }
    }
    test_sleep_for_ms(50);
    waited += 50;
  }
  std::error_code ec;
  return std::filesystem::exists(path, ec) && !ec &&
         std::filesystem::file_size(path, ec) >= min_size;
}

#ifdef _WIN32
using SocketType = SOCKET;
static constexpr SocketType kInvalidSocket = INVALID_SOCKET;
static void close_socket(SocketType socket) {
  if (socket != INVALID_SOCKET) {
    closesocket(socket);
  }
}
#else
using SocketType = int;
static constexpr SocketType kInvalidSocket = -1;
static void close_socket(SocketType socket) {
  if (socket >= 0) {
    close(socket);
  }
}
#endif

class LocalHttpStallServer {
public:
  enum class StreamEndMode {
    StallAfterBody,
    CloseAfterBody,
  };

  explicit LocalHttpStallServer(
      const std::string &asset_path,
      StreamEndMode stream_end_mode = StreamEndMode::StallAfterBody)
      : asset_path_(asset_path), stream_end_mode_(stream_end_mode) {}

  bool start() {
    if (!load_asset()) {
      last_error_ = "failed to load asset";
      return false;
    }

#ifdef _WIN32
    static std::once_flag winsock_once;
    static bool winsock_ready = false;
    std::call_once(winsock_once, []() {
      WSADATA wsaData;
      winsock_ready = (WSAStartup(MAKEWORD(2, 2), &wsaData) == 0);
    });
    if (!winsock_ready) {
      last_error_ = "winsock initialization failed";
      return false;
    }
#endif

    listen_socket_.store(::socket(AF_INET, SOCK_STREAM, 0));
    if (listen_socket_.load() == kInvalidSocket) {
      last_error_ = "socket creation failed";
      return false;
    }

    int reuse = 1;
    setsockopt(listen_socket_.load(), SOL_SOCKET, SO_REUSEADDR,
               reinterpret_cast<const char *>(&reuse), sizeof(reuse));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(0);

    if (bind(listen_socket_.load(), reinterpret_cast<sockaddr *>(&addr),
             sizeof(addr)) != 0) {
      last_error_ = "bind failed";
      cleanup_socket();
      return false;
    }

    if (listen(listen_socket_.load(), 1) != 0) {
      last_error_ = "listen failed";
      cleanup_socket();
      return false;
    }

    sockaddr_in bound_addr{};
    socklen_t bound_len = sizeof(bound_addr);
    if (getsockname(listen_socket_.load(),
                    reinterpret_cast<sockaddr *>(&bound_addr),
                    &bound_len) != 0) {
      last_error_ = "getsockname failed";
      cleanup_socket();
      return false;
    }
    port_ = ntohs(bound_addr.sin_port);

    server_thread_ = TestThread([this]() { run(); });

    std::unique_lock<std::mutex> lock(state_mutex_);
    ready_cv_.wait(lock, [this]() {
      return ready_.load(std::memory_order_acquire) ||
             failed_.load(std::memory_order_acquire);
    });
    const bool started = ready_.load(std::memory_order_acquire) &&
                         !failed_.load(std::memory_order_acquire);
    if (!started && last_error_.empty()) {
      last_error_ = "server thread did not become ready";
    }
    return started;
  }

  void stop() {
    stop_requested_.store(true);
    close_socket(client_socket_.exchange(kInvalidSocket));
    close_socket(listen_socket_.exchange(kInvalidSocket));
    if (server_thread_.joinable()) {
      server_thread_.join();
    }
    cleanup_socket();
  }

  ~LocalHttpStallServer() { stop(); }

  std::string url(const std::string &path) const {
    return "http://127.0.0.1:" + std::to_string(port_) + path;
  }

  const std::string &last_error() const { return last_error_; }

  bool wait_for_segment_request(const std::string &segment_path,
                                int timeout_ms) {
    std::unique_lock<std::mutex> lock(state_mutex_);
    return request_cv_.wait_for(
        lock, std::chrono::milliseconds(timeout_ms), [&]() {
          return requested_path_ == segment_path ||
                 failed_.load(std::memory_order_acquire);
        });
  }

  bool wait_for_body_bytes(size_t minimum_bytes, int timeout_ms) {
    std::unique_lock<std::mutex> lock(state_mutex_);
    return request_cv_.wait_for(
        lock, std::chrono::milliseconds(timeout_ms), [&]() {
          return body_bytes_sent_ >= minimum_bytes ||
                 failed_.load(std::memory_order_acquire);
        });
  }

private:
  bool load_asset() {
    for (int waited = 0; waited <= 2000; waited += 50) {
      std::ifstream file(asset_path_, std::ios::binary);
      if (file) {
        std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(file)),
                                   std::istreambuf_iterator<char>());
        if (!bytes.empty()) {
          file_bytes_ = std::move(bytes);
          return true;
        }
      }
      test_sleep_for_ms(50);
    }
    return false;
  }

  void cleanup_socket() {
    close_socket(listen_socket_.exchange(kInvalidSocket));
    close_socket(client_socket_.exchange(kInvalidSocket));
  }

  static bool path_contains(const std::string &request, const char *needle) {
    return request.find(needle) != std::string::npos;
  }

  std::string read_request(SocketType client) {
    std::string request;
    char buffer[1024];
    for (;;) {
      int received = recv(client, buffer, sizeof(buffer), 0);
      if (received <= 0) {
        break;
      }
      request.append(buffer, buffer + received);
      if (request.find("\r\n\r\n") != std::string::npos) {
        break;
      }
    }
    return request;
  }

  size_t send_all(SocketType client, const char *data, size_t size) {
    size_t written = 0;
    while (written < size && !stop_requested_.load()) {
      int sent =
          send(client, data + written, static_cast<int>(size - written), 0);
      if (sent <= 0) {
        break;
      }
      written += static_cast<size_t>(sent);
    }
    return written;
  }

  void handle_client(SocketType client) {
    const std::string request = read_request(client);
    if (request.empty()) {
      return;
    }

    if (path_contains(request, "GET /segment0.ts")) {
      {
        std::lock_guard<std::mutex> lock(state_mutex_);
        requested_path_ = "/segment0.ts";
      }
      request_cv_.notify_all();
      std::ostringstream headers;
      headers << "HTTP/1.1 200 OK\r\n"
              << "Content-Type: video/MP2T\r\n"
              << "Connection: keep-alive\r\n"
              << "Content-Length: " << file_bytes_.size() << "\r\n\r\n";
      const std::string header_blob = headers.str();
      send_all(client, header_blob.c_str(), header_blob.size());
      const size_t initial_bytes = std::min<size_t>(
          file_bytes_.size(),
          std::max<size_t>(128 * 1024, file_bytes_.size() / 2));
      const size_t body_bytes =
          send_all(client, reinterpret_cast<const char *>(file_bytes_.data()),
                   initial_bytes);
      {
        std::lock_guard<std::mutex> lock(state_mutex_);
        body_bytes_sent_ = body_bytes;
      }
      request_cv_.notify_all();
      if (stream_end_mode_ == StreamEndMode::CloseAfterBody) {
        return;
      }
      while (!stop_requested_.load()) {
        test_sleep_for_ms(100);
      }
    } else if (path_contains(request, "GET /segment1.ts")) {
      {
        std::lock_guard<std::mutex> lock(state_mutex_);
        requested_path_ = "/segment1.ts";
      }
      request_cv_.notify_all();
      std::ostringstream headers;
      headers << "HTTP/1.1 200 OK\r\n"
              << "Content-Type: video/MP2T\r\n"
              << "Connection: keep-alive\r\n"
              << "Content-Length: " << file_bytes_.size() << "\r\n\r\n";
      const std::string header_blob = headers.str();
      send_all(client, header_blob.c_str(), header_blob.size());
      while (!stop_requested_.load()) {
        test_sleep_for_ms(100);
      }

    } else if (path_contains(request, "GET /master.m3u8")) {
      const std::string playlist = "#EXTM3U\r\n"
                                   "#EXT-X-VERSION:3\r\n"
                                   "#EXT-X-TARGETDURATION:6\r\n"
                                   "#EXT-X-MEDIA-SEQUENCE:0\r\n"
                                   "#EXTINF:6.0,\r\n"
                                   "/segment0.ts\r\n"
                                   "#EXTINF:6.0,\r\n"
                                   "/segment1.ts\r\n";
      std::ostringstream headers;
      headers << "HTTP/1.1 200 OK\r\n"
              << "Content-Type: application/vnd.apple.mpegurl\r\n"
              << "Connection: close\r\n"
              << "Content-Length: " << playlist.size() << "\r\n\r\n";
      const std::string header_blob = headers.str();
      send_all(client, header_blob.c_str(), header_blob.size());
      send_all(client, playlist.c_str(), playlist.size());
    } else {
      const std::string not_found = "HTTP/1.1 404 Not Found\r\nConnection: "
                                    "close\r\nContent-Length: 0\r\n\r\n";
      send_all(client, not_found.c_str(), not_found.size());
    }
  }

  void run() {
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      ready_.store(true, std::memory_order_release);
    }
    ready_cv_.notify_all();

    while (!stop_requested_.load()) {
      const SocketType listen_socket = listen_socket_.load();
      if (listen_socket == kInvalidSocket) {
        break;
      }
      fd_set readfds;
      FD_ZERO(&readfds);
      FD_SET(listen_socket, &readfds);
      timeval timeout{};
      timeout.tv_sec = 0;
      timeout.tv_usec = 100000;
      int ready = select(static_cast<int>(listen_socket) + 1, &readfds, nullptr,
                         nullptr, &timeout);
      if (ready <= 0 || !FD_ISSET(listen_socket, &readfds)) {
        continue;
      }

      sockaddr_in client_addr{};
      socklen_t client_len = sizeof(client_addr);
      SocketType client_socket =
          accept(listen_socket, reinterpret_cast<sockaddr *>(&client_addr),
                 &client_len);
      if (client_socket == kInvalidSocket) {
        continue;
      }

      client_socket_.store(client_socket);
      handle_client(client_socket);
      close_socket(client_socket_.exchange(kInvalidSocket));
    }
  }

  std::string asset_path_;
  StreamEndMode stream_end_mode_;
  std::vector<uint8_t> file_bytes_;
  std::atomic<SocketType> listen_socket_{kInvalidSocket};
  std::atomic<SocketType> client_socket_{kInvalidSocket};
  int port_{0};
  TestThread server_thread_;
  std::atomic<bool> stop_requested_{false};
  std::mutex state_mutex_;
  std::condition_variable ready_cv_;
  std::condition_variable request_cv_;
  std::atomic<bool> ready_{false};
  std::atomic<bool> failed_{false};
  std::string requested_path_;
  size_t body_bytes_sent_{0};
  std::string last_error_;
};

static void remove_matching_files(const std::filesystem::path &dir,
                                  const std::string &prefix) {
  if (!std::filesystem::exists(dir)) {
    return;
  }
  for (const auto &entry : std::filesystem::directory_iterator(dir)) {
    const std::string filename = entry.path().filename().string();
    if (filename.rfind(prefix, 0) == 0) {
      std::error_code ec;
      std::filesystem::remove(entry.path(), ec);
    }
  }
}

} // namespace

TEST(FFmpegKitTest, VersionCheck) {
  char *version = ffmpeg_kit_config_get_ffmpeg_version();
  printf("Version: %s\n", version);
  ASSERT_NE(version, nullptr);
  EXPECT_STRNE(version, "");
  printf("FFmpeg Version: %s\n", version);
  free(version);
}

TEST(FFmpegKitTest, SplitSessionExecution) {
  FFmpegSessionHandle session =
      ffmpeg_kit_create_session("-hide_banner -loglevel fatal -version");
  printf("Session: %p\n", session);
  ASSERT_NE(session, nullptr);

  FFmpegKitSessionState state = ffmpeg_kit_session_get_state(session);
  printf("State: %d\n", state);
  EXPECT_EQ(state, FFMPEG_KIT_SESSION_STATE_CREATED);

  ffmpeg_kit_session_execute(session);

  state = ffmpeg_kit_session_get_state(session);

  printf("Session state: %d\n", state);

  if (state != FFMPEG_KIT_SESSION_STATE_COMPLETED) {
    printf("Session failed with state: %d\n", state);
    // Print return code
    int returnCode = ffmpeg_kit_session_get_return_code(session);
    printf("Return Code: %d\n", returnCode);

    // Print logs
    char *logs = ffmpeg_kit_session_get_logs_as_string(session);
    if (logs) {
      printf("Logs:\n%s\n", logs);
      free(logs);
    }

    char *failStackTrace = ffmpeg_kit_session_get_fail_stack_trace(session);
    if (failStackTrace) {
      printf("Fail Stack Trace:\n%s\n", failStackTrace);
      free(failStackTrace);
    }
  }
  printf("State: %d\n", state);
  EXPECT_EQ(state, FFMPEG_KIT_SESSION_STATE_COMPLETED);

  // Cleanup
  ffmpeg_kit_handle_release(session);
}

TEST(FFmpegKitTest, DebugLog) {
  FFmpegSessionHandle session =
      ffmpeg_kit_create_session("-hide_banner -loglevel fatal -version");
  printf("Session: %p\n", session);
  ASSERT_NE(session, nullptr);

  FFmpegKitSessionState state = ffmpeg_kit_session_get_state(session);
  printf("State: %d\n", state);
  EXPECT_EQ(state, FFMPEG_KIT_SESSION_STATE_CREATED);

  ffmpeg_kit_config_enable_debug_log(session);
  printf("Debug log enabled: %d\n",
         ffmpeg_kit_config_is_debug_log_enabled(session));
  EXPECT_TRUE(ffmpeg_kit_config_is_debug_log_enabled(session));

  ffmpeg_kit_session_execute(session);

  state = ffmpeg_kit_session_get_state(session);

  printf("Session state: %d\n", state);

  if (state != FFMPEG_KIT_SESSION_STATE_COMPLETED) {
    printf("Session failed with state: %d\n", state);
    // Print return code
    int returnCode = ffmpeg_kit_session_get_return_code(session);
    printf("Return Code: %d\n", returnCode);

    // Print logs
    char *logs = ffmpeg_kit_session_get_logs_as_string(session);
    if (logs) {
      printf("Logs:\n%s\n", logs);
      free(logs);
    }

    char *failStackTrace = ffmpeg_kit_session_get_fail_stack_trace(session);
    if (failStackTrace) {
      printf("Fail Stack Trace:\n%s\n", failStackTrace);
      free(failStackTrace);
    }
  }

  char *debugLog = ffmpeg_kit_config_get_debug_log(session);
  printf("Debug Log: %s\n", debugLog);
  EXPECT_NE(debugLog, nullptr);
  printf("Debug Log:\n%s\n", debugLog);
  free(debugLog);

  ffmpeg_kit_config_disable_debug_log(session);
  printf("Debug log enabled: %d\n",
         ffmpeg_kit_config_is_debug_log_enabled(session));
  EXPECT_FALSE(ffmpeg_kit_config_is_debug_log_enabled(session));

  ffmpeg_kit_config_clear_debug_log(session);
  debugLog = ffmpeg_kit_config_get_debug_log(session);
  printf("Debug Log: %s\n", debugLog);
  EXPECT_EQ(strlen(debugLog), 0);
  free(debugLog);
  printf("State: %d\n", state);
  EXPECT_EQ(state, FFMPEG_KIT_SESSION_STATE_COMPLETED);

  // Cleanup
  ffmpeg_kit_handle_release(session);
}

TEST(FFmpegKitTest, ConfigurationSetters) {
  ffmpeg_kit_config_set_log_level(FFMPEG_KIT_LOG_LEVEL_QUIET);
  // ffmpeg_kit_config_enable_log_callback(test_log_callback, nullptr);
  // No easy way to verify these without internal access or observing side
  // effects, assuming no crash is success for now.
  EXPECT_EQ(ffmpeg_kit_config_get_log_level(), FFMPEG_KIT_LOG_LEVEL_QUIET);
}

TEST(FFmpegKitTest, SessionHistory) {
  ffmpeg_kit_set_session_history_size(10);
  int history_size = ffmpeg_kit_get_session_history_size();
  printf("History size: %d\n", history_size);
  EXPECT_EQ(history_size, 10);

  // Create a few sessions to populate history
  int initial_count = 0;
  FFmpegSessionHandle *initial_sessions = ffmpeg_kit_get_sessions();
  if (initial_sessions) {
    while (initial_sessions[initial_count]) {
      ffmpeg_kit_handle_release(initial_sessions[initial_count]);
      initial_count++;
    }
    free(initial_sessions);
  }

  for (int i = 0; i < 3; i++) {
    FFmpegSessionHandle s =
        ffmpeg_kit_create_session("-hide_banner -loglevel fatal -version");
    ffmpeg_kit_session_execute(s);
    ffmpeg_kit_handle_release(s);
  }

  FFmpegSessionHandle *sessions = ffmpeg_kit_get_sessions();
  printf("Sessions: %p\n", sessions);
  ASSERT_NE(sessions, nullptr);

  int count = 0;
  while (sessions[count]) {
    ffmpeg_kit_handle_release(sessions[count]);
    count++;
  }
  free(sessions);
  printf("Count: %d, Initial Count: %d\n", count, initial_count);
  EXPECT_GT(count, initial_count);
}

TEST(FFmpegKitTest, GenerateTestVideoFile) {
  FFmpegSessionHandle session = ffmpeg_kit_create_session(
      "-hide_banner -loglevel fatal -f lavfi -i "
      "testsrc=duration=15:size=512x512:rate=30 -f lavfi -i sine=duration=15 "
      "-y " TEST_VIDEO_FILE);
  ffmpeg_kit_session_execute(session);
  printf("Session: %p\n", session);
  EXPECT_EQ(ffmpeg_kit_session_get_state(session),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  ffmpeg_kit_handle_release(session);
  printf("File exists: %d\n", access(TEST_VIDEO_FILE, F_OK) == 0);
  printf("File location: %s\n", TEST_VIDEO_FILE);
  EXPECT_TRUE(access(TEST_VIDEO_FILE, F_OK) == 0);
}

TEST(FFmpegKitTest, GenerateTestAudioFile) {
  FFmpegSessionHandle session = ffmpeg_kit_create_session(
      "-hide_banner -loglevel fatal -f lavfi -i sine=frequency=1000:duration=5 "
      "-y " TEST_AUDIO_FILE);
  ffmpeg_kit_session_execute(session);
  printf("Session: %p\n", session);
  EXPECT_EQ(ffmpeg_kit_session_get_state(session),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  ffmpeg_kit_handle_release(session);
  printf("File exists: %d\n", access(TEST_AUDIO_FILE, F_OK) == 0);
  printf("File location: %s\n", TEST_AUDIO_FILE);
  EXPECT_TRUE(access(TEST_AUDIO_FILE, F_OK) == 0);
}

TEST(FFmpegKitTest, MediaInformation) {
  ffmpeg_kit_config_set_log_level(FFMPEG_KIT_LOG_LEVEL_DEBUG);
  MediaInformationSessionHandle media_session =
      ffprobe_kit_get_media_information(TEST_VIDEO_FILE);
  printf("Media Session: %p\n", media_session);
  ASSERT_NE(media_session, nullptr);

  FFmpegKitSessionState state = ffmpeg_kit_session_get_state(media_session);

  if (state != FFMPEG_KIT_SESSION_STATE_COMPLETED) {
    printf("Media Session failed with state: %d\n", state);
    char *logs = ffmpeg_kit_session_get_logs_as_string(media_session);
    if (logs) {
      printf("Logs:\n%s\n", logs);
      free(logs);
    }
  }
  printf("State: %d\n", state);
  EXPECT_EQ(state, FFMPEG_KIT_SESSION_STATE_COMPLETED);

  long create_time = ffmpeg_kit_session_get_create_time(media_session);
  printf("Create Time: %ld\n", create_time);
  EXPECT_GT(create_time, 0);

  char *cmd = ffmpeg_kit_session_get_command(media_session);
  printf("Command: %s\n", cmd);
  EXPECT_NE(cmd, nullptr);
  free(cmd);

  // Logs
  int log_count = ffmpeg_kit_session_get_logs_count(media_session);
  printf("Log Count: %d\n", log_count);
  EXPECT_GE(log_count, 0);

  MediaInformationHandle info =
      media_information_session_get_media_information(media_session);
  printf("Media Information: %p\n", info);
  ASSERT_NE(info, nullptr);

  char *filename = media_information_get_filename(info);
  printf("Filename: %s\n", filename);
  EXPECT_NE(filename, nullptr);
  if (filename)
    free(filename);

  char *duration = media_information_get_duration(info);
  printf("Duration: %s\n", duration);
  EXPECT_NE(duration, nullptr);
  if (duration)
    free(duration);

  char *bitrate = media_information_get_bitrate(info);
  printf("Bitrate: %s\n", bitrate);
  EXPECT_NE(bitrate, nullptr);
  if (bitrate)
    free(bitrate);

  char *size = media_information_get_size(info);
  printf("Size: %s\n", size);
  EXPECT_NE(size, nullptr);
  if (size)
    free(size);

  int streams_count = media_information_get_streams_count(info);
  printf("Streams Count: %d\n", streams_count);
  EXPECT_GE(streams_count, 1);

  if (streams_count > 0) {
    StreamInformationHandle stream = media_information_get_stream_at(info, 0);
    printf("Stream: %p\n", stream);
    EXPECT_NE(stream, nullptr);

    long index = stream_information_get_index(stream);
    printf("Index: %ld\n", index);
    EXPECT_GE(index, 0);

    char *type = stream_information_get_type(stream);
    printf("Type: %s\n", type);
    EXPECT_NE(type, nullptr);
    if (type)
      free(type);

    char *codec = stream_information_get_codec(stream);
    printf("Codec: %s\n", codec);
    EXPECT_NE(codec, nullptr);
    if (codec)
      free(codec);

    char *codec_long = stream_information_get_codec_long(stream);
    printf("Codec Long: %s\n", codec_long);
    if (codec_long)
      free(codec_long);

    char *format = stream_information_get_format(stream);
    printf("Format: %s\n", format);
    if (format)
      free(format);

    char *bitrate_s = stream_information_get_bitrate(stream);
    printf("Bitrate: %s\n", bitrate_s);
    if (bitrate_s)
      free(bitrate_s);

    char *sample_rate = stream_information_get_sample_rate(stream);
    printf("Sample Rate: %s\n", sample_rate);
    if (sample_rate)
      free(sample_rate);

    int width = stream_information_get_width(stream);
    printf("Width: %d\n", width);
    EXPECT_GE(width, 0);

    int height = stream_information_get_height(stream);
    printf("Height: %d\n", height);
    EXPECT_GE(height, 0);

    char *tags = stream_information_get_tags_json(stream);
    printf("Tags: %s\n", tags);
    if (tags)
      free(tags);

    char *sample_format = stream_information_get_sample_format(stream);
    printf("Sample Format: %s\n", sample_format);
    if (sample_format)
      free(sample_format);

    char *display_aspect_ratio =
        stream_information_get_display_aspect_ratio(stream);
    printf("Display Aspect Ratio: %s\n", display_aspect_ratio);
    if (display_aspect_ratio)
      free(display_aspect_ratio);

    char *avg_frame_rate = stream_information_get_average_frame_rate(stream);
    printf("Average Frame Rate: %s\n", avg_frame_rate);
    if (avg_frame_rate)
      free(avg_frame_rate);

    char *real_frame_rate = stream_information_get_real_frame_rate(stream);
    printf("Real Frame Rate: %s\n", real_frame_rate);
    if (real_frame_rate)
      free(real_frame_rate);

    char *time_base = stream_information_get_time_base(stream);
    printf("Time Base: %s\n", time_base);
    if (time_base)
      free(time_base);

    char *channel_layout = stream_information_get_channel_layout(stream);
    printf("Channel Layout: %s\n", channel_layout);
    if (channel_layout)
      free(channel_layout);

    char *sample_aspect_ratio =
        stream_information_get_sample_aspect_ratio(stream);
    printf("Sample Aspect Ratio: %s\n", sample_aspect_ratio);
    if (sample_aspect_ratio)
      free(sample_aspect_ratio);

    char *codec_time_base = stream_information_get_codec_time_base(stream);
    printf("Codec Time Base: %s\n", codec_time_base);
    if (codec_time_base)
      free(codec_time_base);

    char *string_property =
        stream_information_get_string_property(stream, "codec_name");
    printf("String Property: %s\n", string_property);
    if (string_property)
      free(string_property);

    long number_property =
        stream_information_get_number_property(stream, "index");
    printf("Number Property: %ld\n", number_property);
    EXPECT_GE(number_property, 0);

    char *all_props = stream_information_get_all_properties_json(stream);
    printf("All Props: %s\n", all_props);
    if (all_props)
      free(all_props);

    ffmpeg_kit_handle_release(stream);
  }

  int chapters_count = media_information_get_chapters_count(info);
  printf("Chapters Count: %d\n", chapters_count);
  EXPECT_GE(chapters_count, 0);
  // TODO generate or find video with chapters to test this
  if (chapters_count > 0) {
    ChapterHandle chapter = media_information_get_chapter_at(info, 0);
    printf("Chapter: %p\n", chapter);
    EXPECT_NE(chapter, nullptr);

    long id = chapter_get_id(chapter);
    printf("Chapter ID: %ld\n", id);
    EXPECT_GE(id, 0);

    char *start_time = chapter_get_start_time(chapter);
    printf("Chapter Start Time: %s\n", start_time);
    if (start_time)
      free(start_time);

    char *end_time = chapter_get_end_time(chapter);
    printf("Chapter End Time: %s\n", end_time);
    if (end_time)
      free(end_time);

    ffmpeg_kit_handle_release(chapter);
  }

  char *all_props = media_information_get_all_properties_json(info);
  printf("All Props: %s\n", all_props);
  EXPECT_NE(all_props, nullptr);
  if (all_props)
    free(all_props);

  ffmpeg_kit_handle_release(info);
  ffmpeg_kit_handle_release(media_session);
}

#ifndef _WIN32
TEST(FFmpegKitTest, MediaInformationQuotedFilename) {
  const std::filesystem::path source(TEST_VIDEO_FILE);
  const std::filesystem::path quoted_path =
      source.parent_path() / "dummy copy - \"extra chars\".mp4";
  std::error_code ec;
  std::filesystem::copy_file(source, quoted_path,
                             std::filesystem::copy_options::overwrite_existing,
                             ec);
  ASSERT_FALSE(ec) << ec.message();

  const std::string input = quoted_path.string();
  const std::string command =
      "-v error -hide_banner -print_format json -show_format "
      "-show_streams -show_chapters -i '" +
      input + "'";

  MediaInformationSessionHandle command_session =
      media_information_create_session(command.c_str());
  ASSERT_NE(command_session, nullptr);
  media_information_session_execute(command_session, 5000);
  EXPECT_EQ(ffmpeg_kit_session_get_state(command_session),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  MediaInformationHandle command_info =
      media_information_session_get_media_information(command_session);
  EXPECT_NE(command_info, nullptr);
  if (command_info)
    ffmpeg_kit_handle_release(command_info);
  ffmpeg_kit_handle_release(command_session);

  const char *ffmpeg_argv[] = {"-v", "error", "-i", input.c_str(),
                               "-f", "null", "-"};
  FFmpegSessionHandle ffmpeg_session = ffmpeg_kit_create_session_from_argv(
      static_cast<int>(sizeof(ffmpeg_argv) / sizeof(ffmpeg_argv[0])),
      ffmpeg_argv);
  ASSERT_NE(ffmpeg_session, nullptr);
  ffmpeg_kit_session_execute(ffmpeg_session);
  EXPECT_EQ(ffmpeg_kit_session_get_state(ffmpeg_session),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  ffmpeg_kit_handle_release(ffmpeg_session);

  const char *argv[] = {"-v",            "error",          "-hide_banner",
                        "-print_format", "json",           "-show_format",
                        "-show_streams", "-show_chapters", "-i",
                        input.c_str()};
  MediaInformationSessionHandle argv_session =
      media_information_create_session_from_argv(
          static_cast<int>(sizeof(argv) / sizeof(argv[0])), argv);
  ASSERT_NE(argv_session, nullptr);
  media_information_session_execute(argv_session, 5000);
  EXPECT_EQ(ffmpeg_kit_session_get_state(argv_session),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  MediaInformationHandle argv_info =
      media_information_session_get_media_information(argv_session);
  EXPECT_NE(argv_info, nullptr);
  if (argv_info)
    ffmpeg_kit_handle_release(argv_info);
  ffmpeg_kit_handle_release(argv_session);

  std::filesystem::remove(quoted_path, ec);
}
#endif

TEST(FFmpegKitTest, MediaInformationSessionAPIs) {
  char command[512];
  snprintf(command, sizeof(command),
           "-v error -hide_banner -print_format json -show_format "
           "-show_streams -show_chapters -i %s",
           TEST_VIDEO_FILE);
  MediaInformationSessionHandle session =
      media_information_create_session(command);
  printf("Media Information Session: %p\n", session);
  ASSERT_NE(session, nullptr);

  media_information_session_execute_async(session, 1000);
  test_sleep_for_ms(2000);
  printf("Media Information Session State: %d\n",
         ffmpeg_kit_session_get_state(session));
  EXPECT_EQ(ffmpeg_kit_session_get_state(session),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  MediaInformationHandle info =
      media_information_session_get_media_information(session);
  printf("Media Information: %p\n", info);
  ASSERT_NE(info, nullptr);
  char *all_props = media_information_get_all_properties_json(info);
  printf("All Props: %s\n", all_props);
  EXPECT_NE(all_props, nullptr);
  if (all_props)
    free(all_props);
  ffmpeg_kit_handle_release(info);
  ffmpeg_kit_handle_release(session);
}

TEST(FFplayKitTest, FFplaySession) {
  // Set SDL drivers to dummy for headless execution
  // This allows ffplay to initializing audio/video "devices" without a real
  // display/speaker
#ifdef _WIN32
  _putenv("SDL_VIDEODRIVER=dummy");
  _putenv("SDL_AUDIODRIVER=dummy");
  _putenv("DISPLAY=:0");
#elif defined(__APPLE__)
  setenv("SDL_VIDEODRIVER", "offscreen", 1);
  setenv("SDL_AUDIODRIVER", "dummy", 1);
  setenv("DISPLAY", ":0", 1);
#else
  setenv("SDL_VIDEODRIVER", "dummy", 1);
  setenv("SDL_AUDIODRIVER", "dummy", 1);
  setenv("DISPLAY", ":0", 1);
#endif
  // 2. Run ffplay
  // -autoexit: exit when done
  // -t 2: limit duration just in case
  char command[512];
  snprintf(command, sizeof(command),
           "-loglevel fatal -nodisp -autoexit -t 2 %s", TEST_VIDEO_FILE);
  FFplaySessionHandle play_session = ffplay_kit_execute(command, 1000);
  printf("FFplay Session: %p\n", play_session);
  ASSERT_NE(play_session, nullptr);

  FFmpegKitSessionState state = ffmpeg_kit_session_get_state(play_session);
  if (state != FFMPEG_KIT_SESSION_STATE_COMPLETED) {
    printf("FFplay Session failed with state: %d\n", state);
    char *logs = ffmpeg_kit_session_get_logs_as_string(play_session);
    if (logs) {
      printf("Logs:\n%s\n", logs);
      free(logs);
    }
  }
  printf("State: %d\n", state);
  EXPECT_EQ(state, FFMPEG_KIT_SESSION_STATE_COMPLETED);
  printf("Return Code: %ld\n",
         ffmpeg_kit_session_get_return_code(play_session));
  EXPECT_EQ(ffmpeg_kit_session_get_return_code(play_session), 0);

  ffmpeg_kit_handle_release(play_session);
}

class FFplayKitInteractiveTest : public ::testing::Test {
protected:
  void SetUp() override {
#ifdef _WIN32
    _putenv("SDL_VIDEODRIVER=dummy");
    _putenv("SDL_AUDIODRIVER=dummy");
    _putenv("DISPLAY=:0");
#elif defined(__APPLE__)
    setenv("SDL_VIDEODRIVER", "offscreen", 1);
    setenv("SDL_AUDIODRIVER", "dummy", 1);
    setenv("DISPLAY", ":0", 1);
#else
    setenv("SDL_VIDEODRIVER", "dummy", 1);
    setenv("SDL_AUDIODRIVER", "dummy", 1);
    setenv("DISPLAY", ":0", 1);
#endif
  }

  void TearDown() override { ffplay_kit_stop(); }

  void WaitForSeconds(int seconds) { test_sleep_for_ms(seconds * 1000); }
};

TEST_F(FFplayKitInteractiveTest, PlayPauseResume) {
  const char *video_file = TEST_VIDEO_FILE;
  char command[256];
  snprintf(command, sizeof(command), "-loglevel fatal -nodisp -autoexit -i %s",
           video_file);
  const char *ext_libraries = ffmpeg_kit_packages_get_external_libraries();
  printf("Linked External Libraries: %s\n", ext_libraries);
  FFplaySessionHandle session =
      ffplay_kit_execute_async(command, nullptr, nullptr, 1000);
  printf("FFplay Session: %p\n", session);
  ASSERT_NE(session, nullptr);

  WaitForSeconds(2);
  printf("Is Playing: %d\n", ffplay_kit_session_is_playing(session));
  EXPECT_EQ(ffplay_kit_session_is_playing(session), 1);

  ffplay_kit_session_pause(session);
  WaitForSeconds(1);
  printf("Is Paused: %d\n", ffplay_kit_session_is_paused(session));
  EXPECT_EQ(ffplay_kit_session_is_paused(session), 1);

  ffplay_kit_session_resume(session);
  WaitForSeconds(1);
  printf("Is Paused: %d\n", ffplay_kit_session_is_paused(session));
  EXPECT_EQ(ffplay_kit_session_is_paused(session), 0);
  printf("Is Playing: %d\n", ffplay_kit_session_is_playing(session));
  EXPECT_EQ(ffplay_kit_session_is_playing(session), 1);

  // Stop session before cleanup to ensure all pending events are processed
  printf("Stopping session...\n");
  ffplay_kit_session_stop(session);
  WaitForSeconds(1);

  // Validate session completed
  FFmpegKitSessionState state = ffmpeg_kit_session_get_state(session);
  printf("State: %d\n", state);

  while (state == FFMPEG_KIT_SESSION_STATE_RUNNING) {
    state = ffmpeg_kit_session_get_state(session);
  }
  EXPECT_EQ(state, FFMPEG_KIT_SESSION_STATE_COMPLETED);
  ffmpeg_kit_handle_release(session);
  printf("Session released successfully\n");
}

TEST_F(FFplayKitInteractiveTest, Seek) {
  const char *video_file = TEST_VIDEO_FILE;
  char command[256];
  snprintf(command, sizeof(command), "-loglevel fatal -nodisp -autoexit -i %s",
           video_file);

  FFplaySessionHandle session =
      ffplay_kit_execute_async(command, nullptr, nullptr, 1000);
  printf("FFplay Session: %p\n", session);
  ASSERT_NE(session, nullptr);
  WaitForSeconds(2);

  // Validate session is in valid state before seeking
  FFmpegKitSessionState state = ffmpeg_kit_session_get_state(session);
  ASSERT_EQ(state, FFMPEG_KIT_SESSION_STATE_RUNNING);

  // Verify session is actually playing before seeking
  int is_playing = ffplay_kit_session_is_playing(session);
  ASSERT_TRUE(is_playing) << "Session must be playing before seek";

  // Seek Absolute - with validation
  printf("Seeking to position 10.0...\n");
  ffplay_kit_session_seek(session, 10.0);
  WaitForSeconds(2); // Increased wait time for seek to complete

  // Validate session is still valid after seek
  state = ffmpeg_kit_session_get_state(session);
  ASSERT_EQ(state, FFMPEG_KIT_SESSION_STATE_RUNNING);

  double pos = ffplay_kit_session_get_position(session);
  printf("Position after seek: %f\n", pos);
  EXPECT_GE(pos, 5.0);

  // Seek Relative Backward - with validation
  printf("Seeking backward by 5.0...\n");
  ffplay_kit_session_seek(session, -5.0);
  WaitForSeconds(2); // Increased wait time for seek to complete

  // Validate session is still valid
  state = ffmpeg_kit_session_get_state(session);
  ASSERT_EQ(state, FFMPEG_KIT_SESSION_STATE_RUNNING);

  double new_pos = ffplay_kit_session_get_position(session);
  printf("New Position: %f\n", new_pos);
  EXPECT_LT(new_pos, pos);

  // Stop session before cleanup
  printf("Stopping session...\n");
  ffplay_kit_session_stop(session);
  WaitForSeconds(1); // Wait for stop to complete

  // Validate session completed
  state = ffmpeg_kit_session_get_state(session);
  EXPECT_EQ(state, FFMPEG_KIT_SESSION_STATE_COMPLETED);

  ffmpeg_kit_handle_release(session);
  printf("Session released successfully\n");
}

TEST_F(FFplayKitInteractiveTest, ConcurrentSessions) {
  const char *video_file = TEST_VIDEO_FILE;
  char command[256];
  snprintf(command, sizeof(command),
           "-hide_banner -loglevel verbose -nodisp -autoexit -i %s",
           video_file);

  FFplaySessionHandle session1 =
      ffplay_kit_execute_async(command, nullptr, nullptr, 1000);
  printf("FFplay Session 1: %p\n", session1);
  ASSERT_NE(session1, nullptr);
  WaitForSeconds(2);

  // Session 2 should stop Session 1
  FFplaySessionHandle session2 =
      ffplay_kit_execute_async(command, nullptr, nullptr, 1000);
  printf("FFplay Session 2: %p\n", session2);
  ASSERT_NE(session2, nullptr);
  WaitForSeconds(2);

  FFmpegKitSessionState state1 = ffmpeg_kit_session_get_state(session1);
  printf("State 1: %d\n", state1);
  EXPECT_EQ(state1, FFMPEG_KIT_SESSION_STATE_COMPLETED);
  printf("Is Playing: %d\n", ffplay_kit_session_is_playing(session2));
  EXPECT_EQ(ffplay_kit_session_is_playing(session2), 1);

  // ffplay_kit_session_close(session2);

  ffmpeg_kit_handle_release(session1);
  ffmpeg_kit_handle_release(session2);
}

TEST_F(FFplayKitInteractiveTest, GlobalControls) {
  const char *video_file = TEST_VIDEO_FILE;
  char command[256];
  snprintf(command, sizeof(command), "-loglevel fatal -nodisp -autoexit -i %s",
           video_file);

  FFplaySessionHandle session =
      ffplay_kit_execute_async(command, nullptr, nullptr, 1000);
  printf("FFplay Session: %p\n", session);
  ASSERT_NE(session, nullptr);
  WaitForSeconds(2);

  ffplay_kit_pause();
  WaitForSeconds(1);
  printf("Is Paused: %d\n", ffplay_kit_is_paused());
  EXPECT_EQ(ffplay_kit_is_paused(), 1);

  ffplay_kit_resume();
  WaitForSeconds(1);
  printf("Is Paused: %d\n", ffplay_kit_is_paused());
  EXPECT_EQ(ffplay_kit_is_paused(), 0);

  ffplay_kit_stop();
  WaitForSeconds(1);
  FFmpegKitSessionState state = ffmpeg_kit_session_get_state(session);
  printf("State: %d\n", state);
  EXPECT_EQ(state, FFMPEG_KIT_SESSION_STATE_COMPLETED);

  ffmpeg_kit_handle_release(session);
}

TEST_F(FFplayKitInteractiveTest, GlobalSeek) {
  const char *video_file = TEST_VIDEO_FILE;
  char command[256];
  snprintf(command, sizeof(command), "-loglevel fatal -nodisp -autoexit -i %s",
           video_file);

  FFplaySessionHandle session =
      ffplay_kit_execute_async(command, nullptr, nullptr, 1000);
  printf("FFplay Session: %p\n", session);
  ASSERT_NE(session, nullptr);
  WaitForSeconds(2);

  // Validate session is in valid state before using global controls
  FFmpegKitSessionState state = ffmpeg_kit_session_get_state(session);
  ASSERT_EQ(state, FFMPEG_KIT_SESSION_STATE_RUNNING);

  // Global Set Position - with validation
  printf("Setting global position to 10.0...\n");
  ffplay_kit_set_position(10.0);
  WaitForSeconds(2); // Increased wait time

  double pos = ffplay_kit_get_position();
  printf("Position: %f\n", pos);
  EXPECT_GE(pos, 9.0); // Allow some tolerance

  // Global Seek - with validation
  printf("Global seeking backward by 5.0...\n");
  ffplay_kit_seek(-5.0);
  WaitForSeconds(2); // Increased wait time

  // Validate session is still valid
  state = ffmpeg_kit_session_get_state(session);
  ASSERT_EQ(state, FFMPEG_KIT_SESSION_STATE_RUNNING);

  double new_pos = ffplay_kit_get_position();
  printf("New Position: %f\n", new_pos);
  EXPECT_LT(new_pos, pos);

  // Stop session before cleanup
  printf("Stopping session...\n");
  ffplay_kit_stop();
  WaitForSeconds(1); // Wait for stop to complete

  // Validate session completed
  state = ffmpeg_kit_session_get_state(session);
  EXPECT_EQ(state, FFMPEG_KIT_SESSION_STATE_COMPLETED);

  ffmpeg_kit_handle_release(session);
  printf("Session released successfully\n");
}

TEST_F(FFplayKitInteractiveTest, SessionAPIs) {
  const char *video_file = TEST_VIDEO_FILE;
  char command[256];
  snprintf(command, sizeof(command), "-loglevel fatal -nodisp -autoexit -i %s",
           video_file);

  FFplaySessionHandle session = ffplay_kit_create_session(command);
  printf("Session: %p\n", session);
  ASSERT_NE(session, nullptr);

  ffplay_kit_session_execute_async(session, 1000);
  WaitForSeconds(2);

  ffplay_kit_session_set_volume(session, 0.5f);
  WaitForSeconds(1); // Wait for async event loop to process volume change
  printf("Volume: %f\n", ffplay_kit_session_get_volume(session));
  EXPECT_FLOAT_EQ(ffplay_kit_session_get_volume(session), 0.5f);

  ffplay_kit_session_set_position(session, 5.0);
  WaitForSeconds(1);
  printf("Position: %f\n", ffplay_kit_session_get_position(session));
  EXPECT_GE(ffplay_kit_session_get_position(session), 4.0);

  printf("Duration: %f\n", ffplay_kit_session_get_duration(session));
  EXPECT_GT(ffplay_kit_session_get_duration(session), 0.0);

  ffplay_kit_session_stop(session);
  WaitForSeconds(1);
  printf("State: %d\n", ffmpeg_kit_session_get_state(session));
  EXPECT_EQ(ffmpeg_kit_session_get_state(session),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);

  // Call close (no-op or similar cleanup in some contexts, but verifies it
  // doesn't crash)
  ffplay_kit_session_close(session);

  // Create and manual start test
  FFplaySessionHandle session2 = ffplay_kit_create_session(command);
  printf("Session2: %p\n", session2);
  ASSERT_NE(session2, nullptr);
  ffplay_kit_session_execute_async(session2, 1000);
  WaitForSeconds(2);
  ffplay_kit_session_pause(session2);
  WaitForSeconds(1);
  ffplay_kit_session_resume(session2);
  WaitForSeconds(1);
  printf("Session2 is playing: %d\n", ffplay_kit_session_is_playing(session2));
  EXPECT_EQ(ffplay_kit_session_is_playing(session2), 1);
  ffmpeg_kit_handle_release(session2);

  ffmpeg_kit_handle_release(session);
}

TEST_F(FFplayKitInteractiveTest, GlobalAPIs) {
  const char *video_file = TEST_VIDEO_FILE;
  char command[256];
  snprintf(command, sizeof(command), "-loglevel fatal -nodisp -autoexit -i %s",
           video_file);

  FFplaySessionHandle session =
      ffplay_kit_execute_async(command, nullptr, nullptr, 1000);
  printf("Session: %p\n", session);
  ASSERT_NE(session, nullptr);
  WaitForSeconds(2);

  ffplay_kit_set_volume(0.5f);
  WaitForSeconds(1);
  printf("Volume: %f\n", ffplay_kit_get_volume());
  EXPECT_FLOAT_EQ(ffplay_kit_get_volume(), 0.5f);

  printf("Duration: %f\n", ffplay_kit_get_duration());
  EXPECT_GT(ffplay_kit_get_duration(), 0.0);

  // Since it's already running, start() is a no-op or resume. Test no crash.
  ffplay_kit_start();
  WaitForSeconds(1);

  // Stop to end process
  ffplay_kit_stop();
  WaitForSeconds(1);

  ffplay_kit_close();

  ffmpeg_kit_handle_release(session);
}

TEST(FFmpegKitTest, PackageName) {
  char *pkg = ffmpeg_kit_packages_get_package_name();
  // Default might be "ffmpeg-kit" or similar
  printf("Package Name: %s\n", pkg);
  EXPECT_NE(pkg, nullptr);
  EXPECT_STRNE(pkg, "");
  printf("Package Name: %s\n", pkg);
  free(pkg);
}

TEST(FFmpegKitTest, AudioDeviceManagement) {
// Force dummy audio for headless environments
#ifdef _WIN32
  _putenv("SDL_AUDIODRIVER=dummy");
  _putenv("SDL_VIDEODRIVER=dummy");
  _putenv("DISPLAY=:0");
#elif defined(__APPLE__)
  setenv("SDL_AUDIODRIVER", "dummy", 1);
  setenv("SDL_VIDEODRIVER", "offscreen", 1);
  setenv("DISPLAY", ":0", 1);
#else
  setenv("SDL_AUDIODRIVER", "dummy", 1);
  setenv("SDL_VIDEODRIVER", "dummy", 1);
  setenv("DISPLAY", ":0", 1);
#endif

  // 1. List devices
  char *devices = ffmpeg_kit_config_list_audio_output_devices();
  if (devices) {
    printf("Audio Devices: %s\n", devices);
    free(devices);
  }

  // 2. Set Device (API Verification)
  ffmpeg_kit_config_set_audio_output_device("Test Device");

  // [CRITICAL FIX] Reset to default before playback!
  // Otherwise ffplay tries to open "Test Device", fails, crashes, and leaks.
  ffmpeg_kit_config_set_audio_output_device(nullptr);

  // 3. Verify Playback Path
  if (access(TEST_AUDIO_FILE, F_OK) != 0) {
    GTEST_SKIP() << "Skipping playback check: " << TEST_AUDIO_FILE
                 << " not found.";
  }

  char command[512];
  // Use -an (disable audio) if you want to be absolutely safe in headless,
  // but resetting to nullptr should allow the dummy driver to work.
  snprintf(command, sizeof(command),
           "-loglevel fatal -nodisp -autoexit -t 0.5 %s", TEST_AUDIO_FILE);

  FFplaySessionHandle session = ffplay_kit_execute(command, 2000);

  if (session) {
    ffmpeg_kit_handle_release(session);
  }
  ffmpeg_kit_config_set_audio_output_device(nullptr);
  SUCCEED();
}
TEST(FFmpegKitTest, ConcurrentOperations) {
  // 1. Create a slow FFmpeg session (e.g., generating a long video)
  FFmpegSessionHandle ffmpeg_session = ffmpeg_kit_create_session(
      "-hide_banner -loglevel fatal -f lavfi -i "
      "testsrc=duration=5:size=128x128:rate=10 -y concurrent_output.mp4");
  printf("FFmpeg Session: %p\n", ffmpeg_session);
  ASSERT_NE(ffmpeg_session, nullptr);

  // 2. Create a FFprobe session to run at the same time
  FFprobeSessionHandle ffprobe_session = ffprobe_kit_create_session(
      "-hide_banner -loglevel fatal -show_format -i " TEST_VIDEO_FILE);
  printf("FFprobe Session: %p\n", ffprobe_session);
  ASSERT_NE(ffprobe_session, nullptr);

  // 3. Execute both asynchronously
  ffmpeg_kit_session_execute_async(ffmpeg_session);
  ffprobe_kit_session_execute_async(ffprobe_session);

  // 4. Wait for both to complete
  int total_wait = 0;
  while (total_wait < 10000) { // 10s max
    FFmpegKitSessionState state1 = ffmpeg_kit_session_get_state(ffmpeg_session);
    FFmpegKitSessionState state2 =
        ffmpeg_kit_session_get_state(ffprobe_session);

    if (state1 == FFMPEG_KIT_SESSION_STATE_COMPLETED &&
        state2 == FFMPEG_KIT_SESSION_STATE_COMPLETED) {
      break;
    }

    if (state1 == FFMPEG_KIT_SESSION_STATE_FAILED ||
        state2 == FFMPEG_KIT_SESSION_STATE_FAILED) {
      break;
    }

    test_sleep_for_ms(100);
    total_wait += 100;
  }

  // 5. Verify results
  printf("FFmpeg Session State: %d\n",
         ffmpeg_kit_session_get_state(ffmpeg_session));
  printf("FFprobe Session State: %d\n",
         ffmpeg_kit_session_get_state(ffprobe_session));
  EXPECT_EQ(ffmpeg_kit_session_get_state(ffmpeg_session),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  EXPECT_EQ(ffmpeg_kit_session_get_state(ffprobe_session),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);

  // Cleanup
  ffmpeg_kit_handle_release(ffmpeg_session);
  ffmpeg_kit_handle_release(ffprobe_session);

  // Remove temporary file
  std::remove("concurrent_output.mp4");
}

TEST(FFmpegKitTest, ConcurrentFFmpegSessions) {
  // 1. Create two FFmpeg sessions
  FFmpegSessionHandle ffmpeg_session1 = ffmpeg_kit_create_session(
      "-hide_banner -loglevel fatal -f lavfi -i "
      "testsrc=duration=3:size=128x128:rate=10 -y concurrent1.mp4");
  FFmpegSessionHandle ffmpeg_session2 = ffmpeg_kit_create_session(
      "-hide_banner -loglevel fatal -f lavfi -i "
      "testsrc=duration=3:size=128x128:rate=10 -y concurrent2.mp4");
  printf("FFmpeg Session 1: %p\n", ffmpeg_session1);
  printf("FFmpeg Session 2: %p\n", ffmpeg_session2);
  ASSERT_NE(ffmpeg_session1, nullptr);
  ASSERT_NE(ffmpeg_session2, nullptr);

  // 2. Execute both asynchronously
  ffmpeg_kit_session_execute_async(ffmpeg_session1);
  ffmpeg_kit_session_execute_async(ffmpeg_session2);

  // 3. Wait for both to complete
  int total_wait = 0;
  while (total_wait < 10000) {
    FFmpegKitSessionState state1 =
        ffmpeg_kit_session_get_state(ffmpeg_session1);
    FFmpegKitSessionState state2 =
        ffmpeg_kit_session_get_state(ffmpeg_session2);

    if (state1 == FFMPEG_KIT_SESSION_STATE_COMPLETED &&
        state2 == FFMPEG_KIT_SESSION_STATE_COMPLETED) {
      break;
    }

    if (state1 == FFMPEG_KIT_SESSION_STATE_FAILED ||
        state2 == FFMPEG_KIT_SESSION_STATE_FAILED) {
      break;
    }

    test_sleep_for_ms(100);
    total_wait += 100;
  }

  // 4. Verify results
  printf("FFmpeg Session 1 State: %d\n",
         ffmpeg_kit_session_get_state(ffmpeg_session1));
  printf("FFmpeg Session 2 State: %d\n",
         ffmpeg_kit_session_get_state(ffmpeg_session2));
  EXPECT_EQ(ffmpeg_kit_session_get_state(ffmpeg_session1),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  EXPECT_EQ(ffmpeg_kit_session_get_state(ffmpeg_session2),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);

  // Cleanup
  ffmpeg_kit_handle_release(ffmpeg_session1);
  ffmpeg_kit_handle_release(ffmpeg_session2);

  std::remove("concurrent1.mp4");
  std::remove("concurrent2.mp4");
}

TEST_F(FFplayKitInteractiveTest, FFplayWithFFmpegConcurrency) {
  // 1. Start a slow FFmpeg session
  FFmpegSessionHandle ffmpeg_session = ffmpeg_kit_create_session(
      "-hide_banner -loglevel fatal -f lavfi -i "
      "testsrc=duration=5:size=128x128:rate=10 -y ffplay_concurrent.mp4");
  ffmpeg_kit_session_execute_async(ffmpeg_session);

  // 2. Start FFplay session
  char command[256];
  snprintf(command, sizeof(command), "-loglevel fatal -nodisp -autoexit -i %s",
           TEST_VIDEO_FILE);
  FFplaySessionHandle play_session =
      ffplay_kit_execute_async(command, nullptr, nullptr, 1000);
  printf("FFplay Session: %p\n", play_session);
  ASSERT_NE(play_session, nullptr);

  WaitForSeconds(2);

  // 3. Verify both are running (FFplay should be playing, FFmpeg should be
  // RUNNING or COMPLETED if it's fast)
  printf("FFplay Session State: %d\n",
         ffplay_kit_session_is_playing(play_session));
  EXPECT_EQ(ffplay_kit_session_is_playing(play_session), 1);
  FFmpegKitSessionState ffmpeg_state =
      ffmpeg_kit_session_get_state(ffmpeg_session);
  printf("FFmpeg Session State: %d\n", ffmpeg_state);
  EXPECT_TRUE(ffmpeg_state == FFMPEG_KIT_SESSION_STATE_RUNNING ||
              ffmpeg_state == FFMPEG_KIT_SESSION_STATE_COMPLETED);

  // 4. Cleanup
  ffmpeg_kit_handle_release(play_session);

  // Wait for FFmpeg to finish if it hasn't
  int wait_total = 0;
  while (ffmpeg_kit_session_get_state(ffmpeg_session) ==
             FFMPEG_KIT_SESSION_STATE_RUNNING &&
         wait_total < 5000) {
    WaitForSeconds(1);
    wait_total += 1000;
  }

  ffmpeg_kit_handle_release(ffmpeg_session);
  std::remove("ffplay_concurrent.mp4");
}

TEST_F(FFplayKitInteractiveTest, FFplayWithFFprobeConcurrency) {
  // 1. Start FFplay session
  char command[256];
  snprintf(command, sizeof(command), "-loglevel fatal -nodisp -autoexit -i %s",
           TEST_VIDEO_FILE);
  FFplaySessionHandle play_session =
      ffplay_kit_execute_async(command, nullptr, nullptr, 1000);
  printf("FFplay Session: %p\n", play_session);
  ASSERT_NE(play_session, nullptr);
  WaitForSeconds(1);

  // 2. Run FFprobe session concurrently
  FFprobeSessionHandle probe_session = ffprobe_kit_execute(
      "-hide_banner -loglevel fatal -show_format -i " TEST_VIDEO_FILE);
  printf("FFprobe Session: %p\n", probe_session);
  ASSERT_NE(probe_session, nullptr);

  // 3. Verify FFplay is still playing and probe finished
  printf("FFplay Session State: %d\n",
         ffplay_kit_session_is_playing(play_session));
  EXPECT_EQ(ffplay_kit_session_is_playing(play_session), 1);
  printf("FFprobe Session State: %d\n",
         ffmpeg_kit_session_get_state(probe_session));
  EXPECT_EQ(ffmpeg_kit_session_get_state(probe_session),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);

  // 4. Cleanup
  ffmpeg_kit_handle_release(play_session);
  ffmpeg_kit_handle_release(probe_session);
}

TEST(FFmpegKitTest, ConcurrentFFprobeSessions) {
  // 1. Create two FFprobe sessions
  FFprobeSessionHandle ffprobe_session1 = ffprobe_kit_create_session(
      "-hide_banner -loglevel fatal -show_format -i " TEST_VIDEO_FILE);
  FFprobeSessionHandle ffprobe_session2 = ffprobe_kit_create_session(
      "-hide_banner -loglevel fatal -show_format -i " TEST_VIDEO_FILE);
  printf("FFprobe Session 1: %p\n", ffprobe_session1);
  ASSERT_NE(ffprobe_session1, nullptr);
  printf("FFprobe Session 2: %p\n", ffprobe_session2);
  ASSERT_NE(ffprobe_session2, nullptr);

  // 2. Execute both asynchronously
  ffprobe_kit_session_execute_async(ffprobe_session1);
  ffprobe_kit_session_execute_async(ffprobe_session2);

  // 3. Wait for both to complete
  int total_wait = 0;
  while (total_wait < 5000) {
    if (ffmpeg_kit_session_get_state(ffprobe_session1) ==
            FFMPEG_KIT_SESSION_STATE_COMPLETED &&
        ffmpeg_kit_session_get_state(ffprobe_session2) ==
            FFMPEG_KIT_SESSION_STATE_COMPLETED) {
      break;
    }
    test_sleep_for_ms(100);
    total_wait += 100;
  }

  // 4. Verify results
  printf("FFprobe Session 1 State: %d\n",
         ffmpeg_kit_session_get_state(ffprobe_session1));
  EXPECT_EQ(ffmpeg_kit_session_get_state(ffprobe_session1),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  printf("FFprobe Session 2 State: %d\n",
         ffmpeg_kit_session_get_state(ffprobe_session2));
  EXPECT_EQ(ffmpeg_kit_session_get_state(ffprobe_session2),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);

  // Cleanup
  ffmpeg_kit_handle_release(ffprobe_session1);
  ffmpeg_kit_handle_release(ffprobe_session2);
}

TEST(FFmpegKitTest, ConcurrentLongRunningFFmpegSessions) {
  const std::filesystem::path output_dir =
      std::filesystem::temp_directory_path() / "ffmpegkit_parallel_ffmpeg";
  std::error_code ec;
  std::filesystem::create_directories(output_dir, ec);
  ASSERT_FALSE(ec) << "Failed to create temporary output directory";

  const std::filesystem::path output1 = output_dir / "parallel_ffmpeg_1.mp4";
  const std::filesystem::path output2 = output_dir / "parallel_ffmpeg_2.mp4";
  auto signal1 = std::make_shared<CompletionSignal>();
  auto signal2 = std::make_shared<CompletionSignal>();

  std::ostringstream command1;
  command1 << "-y -nostdin -hide_banner -loglevel warning -re "
           << "-f lavfi -i testsrc=duration=12:size=320x240:rate=30 "
           << "-threads 1 -pix_fmt yuv420p -c:v mpeg4 -q:v 5 -an "
           << quote_path(output1);

  std::ostringstream command2;
  command2 << "-y -nostdin -hide_banner -loglevel warning -re "
           << "-f lavfi -i testsrc2=duration=12:size=352x288:rate=24 "
           << "-threads 1 -pix_fmt yuv420p -c:v mpeg4 -q:v 5 -an "
           << quote_path(output2);

  FFmpegSessionHandle session1 =
      ffmpeg_kit_create_session(command1.str().c_str());
  FFmpegSessionHandle session2 =
      ffmpeg_kit_create_session(command2.str().c_str());
  ASSERT_NE(session1, nullptr);
  ASSERT_NE(session2, nullptr);
  ScopedFFmpegCompleteCallback callback1(session1, signal1);
  ScopedFFmpegCompleteCallback callback2(session2, signal2);

  ffmpeg_kit_session_execute_async(session1);
  ffmpeg_kit_session_execute_async(session2);

  auto wait_for_running = [](FFmpegSessionHandle handle, int timeout_ms) {
    int waited = 0;
    while (waited < timeout_ms) {
      if (ffmpeg_kit_session_get_state(handle) ==
          FFMPEG_KIT_SESSION_STATE_RUNNING) {
        return true;
      }
      test_sleep_for_ms(50);
      waited += 50;
    }
    return ffmpeg_kit_session_get_state(handle) ==
           FFMPEG_KIT_SESSION_STATE_RUNNING;
  };

  EXPECT_TRUE(wait_for_running(session1, 5000));
  EXPECT_TRUE(wait_for_running(session2, 5000));

  ASSERT_TRUE(wait_for_completion_signal(signal1, 30000));
  ASSERT_TRUE(wait_for_completion_signal(signal2, 30000));

  EXPECT_EQ(ffmpeg_kit_session_get_state(session1),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  EXPECT_EQ(ffmpeg_kit_session_get_state(session2),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);

  ffmpeg_kit_handle_release(session1);
  ffmpeg_kit_handle_release(session2);
  remove_matching_files(output_dir, "parallel_ffmpeg_");
  std::filesystem::remove_all(output_dir, ec);
}

TEST(FFmpegKitTest, ConcurrentFFmpegCancellationIsolation) {
  auto signal1 = std::make_shared<CompletionSignal>();
  auto signal2 = std::make_shared<CompletionSignal>();

  std::ostringstream command1;
  command1 << "-y -nostdin -hide_banner -loglevel debug "
           << "-re -f lavfi -i testsrc2=size=320x240:rate=30 "
           << "-an -c:v mpeg4 -f null -";

  std::ostringstream command2;
  command2 << "-y -nostdin -hide_banner -loglevel debug "
           << "-re -f lavfi -i sine=frequency=1000:sample_rate=44100 "
           << "-vn -c:a aac -f null -";

  FFmpegSessionHandle session1 =
      ffmpeg_kit_create_session(command1.str().c_str());
  FFmpegSessionHandle session2 =
      ffmpeg_kit_create_session(command2.str().c_str());
  ASSERT_NE(session1, nullptr);
  ASSERT_NE(session2, nullptr);
  ScopedFFmpegCompleteCallback callback1(session1, signal1);
  ScopedFFmpegCompleteCallback callback2(session2, signal2);

  ffmpeg_kit_session_execute_async(session1);
  ffmpeg_kit_session_execute_async(session2);

  EXPECT_TRUE(wait_for_running_state(session1, 5000));
  EXPECT_TRUE(wait_for_running_state(session2, 5000));
  ASSERT_EQ(ffmpeg_kit_session_get_state(session1),
            FFMPEG_KIT_SESSION_STATE_RUNNING);
  ASSERT_EQ(ffmpeg_kit_session_get_state(session2),
            FFMPEG_KIT_SESSION_STATE_RUNNING);

  test_sleep_for_ms(1000);
  ffmpeg_kit_session_cancel(session2);
  ASSERT_TRUE(wait_for_completion_signal(signal2, 30000));
  EXPECT_EQ(ffmpeg_kit_session_get_state(session1),
            FFMPEG_KIT_SESSION_STATE_RUNNING);
  EXPECT_NE(ffmpeg_kit_session_get_state(session2),
            FFMPEG_KIT_SESSION_STATE_RUNNING);

  test_sleep_for_ms(1000);
  ffmpeg_kit_session_cancel(session1);
  ASSERT_TRUE(wait_for_completion_signal(signal1, 30000));
  EXPECT_NE(ffmpeg_kit_session_get_state(session1),
            FFMPEG_KIT_SESSION_STATE_RUNNING);

  ffmpeg_kit_handle_release(session1);
  ffmpeg_kit_handle_release(session2);
}

TEST(FFmpegKitTest, ParallelFFmpegLogAttributionIsolation) {
  auto signal1 = std::make_shared<CompletionSignal>();
  auto signal2 = std::make_shared<CompletionSignal>();

  const char *signature1 = "testsrc2=size=176x144:rate=12:duration=3";
  const char *signature2 = "color=c=blue:size=160x120:rate=10:duration=3";

  std::ostringstream command1;
  command1 << "-y -nostdin -hide_banner -loglevel info "
           << "-re -f lavfi -i " << signature1 << " "
           << "-an -frames:v 24 -f null -";

  std::ostringstream command2;
  command2 << "-y -nostdin -hide_banner -loglevel info "
           << "-re -f lavfi -i " << signature2 << " "
           << "-an -frames:v 20 -f null -";

  FFmpegSessionHandle session1 =
      ffmpeg_kit_create_session(command1.str().c_str());
  FFmpegSessionHandle session2 =
      ffmpeg_kit_create_session(command2.str().c_str());
  ASSERT_NE(session1, nullptr);
  ASSERT_NE(session2, nullptr);

  ScopedFFmpegCompleteCallback callback1(session1, signal1);
  ScopedFFmpegCompleteCallback callback2(session2, signal2);

  ffmpeg_kit_session_execute_async(session1);
  ffmpeg_kit_session_execute_async(session2);

  EXPECT_TRUE(wait_for_running_state(session1, 5000));
  EXPECT_TRUE(wait_for_running_state(session2, 5000));

  ASSERT_TRUE(wait_for_completion_signal(signal1, 30000));
  ASSERT_TRUE(wait_for_completion_signal(signal2, 30000));
  EXPECT_EQ(ffmpeg_kit_session_get_state(session1),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  EXPECT_EQ(ffmpeg_kit_session_get_state(session2),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);

  expect_logs_isolated(session1, signature1, signature2);
  expect_logs_isolated(session2, signature2, signature1);

  ffmpeg_kit_handle_release(session1);
  ffmpeg_kit_handle_release(session2);
}

TEST(FFmpegKitTest, ParallelFFprobeLogAttributionIsolation) {
  auto signal1 = std::make_shared<CompletionSignal>();
  auto signal2 = std::make_shared<CompletionSignal>();

  const char *signature1 = "testsrc2=size=123x77:rate=7:duration=2";
  const char *signature2 = "sine=frequency=777:sample_rate=22050:duration=2";

  std::ostringstream command1;
  command1 << "-hide_banner -loglevel info -show_streams -show_format "
           << "-f lavfi -i " << signature1;

  std::ostringstream command2;
  command2 << "-hide_banner -loglevel info -show_streams -show_format "
           << "-f lavfi -i " << signature2;

  FFprobeSessionHandle session1 =
      ffprobe_kit_create_session(command1.str().c_str());
  FFprobeSessionHandle session2 =
      ffprobe_kit_create_session(command2.str().c_str());
  ASSERT_NE(session1, nullptr);
  ASSERT_NE(session2, nullptr);

  ScopedFFprobeCompleteCallback callback1(session1, signal1);
  ScopedFFprobeCompleteCallback callback2(session2, signal2);

  ffprobe_kit_session_execute_async(session1);
  ffprobe_kit_session_execute_async(session2);

  ASSERT_TRUE(wait_for_completion_signal(signal1, 30000));
  ASSERT_TRUE(wait_for_completion_signal(signal2, 30000));
  EXPECT_EQ(ffmpeg_kit_session_get_state(session1),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);
  EXPECT_EQ(ffmpeg_kit_session_get_state(session2),
            FFMPEG_KIT_SESSION_STATE_COMPLETED);

  expect_logs_isolated(session1, signature1, signature2);
  expect_logs_isolated(session2, signature2, signature1);

  ffmpeg_kit_handle_release(session1);
  ffmpeg_kit_handle_release(session2);
}

TEST(FFmpegKitTest, FFprobeShowLogPreservesCompletionCallback) {
  std::ostringstream command;
  command << "-hide_banner -loglevel info -show_frames -show_log 48 "
          << "-read_intervals 0%+1 -select_streams v:0 -i " << TEST_VIDEO_FILE;

  FFprobeSessionHandle session =
      ffprobe_kit_create_session(command.str().c_str());
  ASSERT_NE(session, nullptr);

  auto signal = std::make_shared<CompletionSignal>();
  ScopedFFprobeCompleteCallback callback(session, signal);

  ffprobe_kit_session_execute_async(session);

  ASSERT_TRUE(wait_for_completion_signal(signal, 30000))
      << "Timed out waiting for ffprobe -show_log completion callback";

  const int final_state = ffmpeg_kit_session_get_state(session);
  EXPECT_EQ(final_state, FFMPEG_KIT_SESSION_STATE_COMPLETED);

  const std::string logs = session_logs_as_string(session);
  EXPECT_FALSE(logs.empty());

  ffmpeg_kit_handle_release(session);
}

TEST(FFmpegKitTest, MixedParallelFFmpegAndFFprobeExecutionCancellation) {
  auto ffmpeg_signal = std::make_shared<CompletionSignal>();
  auto ffprobe_signal = std::make_shared<CompletionSignal>();

  std::ostringstream ffmpeg_command;
  ffmpeg_command << "-y -nostdin -hide_banner -loglevel debug "
                 << "-re -f lavfi -i testsrc2=size=320x240:rate=30 "
                 << "-an -c:v mpeg4 -f null -";

  std::ostringstream ffprobe_command;
  ffprobe_command << "-hide_banner -loglevel warning -select_streams v:0 "
                     "-count_frames -show_streams "
                  << "-f lavfi -i testsrc2=size=160x120:rate=5";

  FFmpegSessionHandle ffmpeg_session =
      ffmpeg_kit_create_session(ffmpeg_command.str().c_str());
  FFprobeSessionHandle ffprobe_session =
      ffprobe_kit_create_session(ffprobe_command.str().c_str());

  ASSERT_NE(ffmpeg_session, nullptr);
  ASSERT_NE(ffprobe_session, nullptr);
  ScopedFFmpegCompleteCallback ffmpeg_callback(ffmpeg_session, ffmpeg_signal);
  ScopedFFprobeCompleteCallback ffprobe_callback(ffprobe_session,
                                                 ffprobe_signal);

  ffmpeg_kit_session_execute_async(ffmpeg_session);
  ffprobe_kit_session_execute_async(ffprobe_session);

  EXPECT_TRUE(wait_for_running_state(ffmpeg_session, 5000));
  EXPECT_TRUE(wait_for_running_state(ffprobe_session, 5000));
  ASSERT_EQ(ffmpeg_kit_session_get_state(ffmpeg_session),
            FFMPEG_KIT_SESSION_STATE_RUNNING);
  ASSERT_EQ(ffmpeg_kit_session_get_state(ffprobe_session),
            FFMPEG_KIT_SESSION_STATE_RUNNING);
  test_sleep_for_ms(1000);
  ffmpeg_kit_session_cancel(ffmpeg_session);

  EXPECT_EQ(ffmpeg_kit_session_get_state(ffprobe_session),
            FFMPEG_KIT_SESSION_STATE_RUNNING);
  test_sleep_for_ms(1000);
  ffprobe_kit_cancel_session(
      ffmpeg_kit_session_get_session_id(ffprobe_session));

  ASSERT_TRUE(wait_for_completion_signal(ffmpeg_signal, 30000));
  ASSERT_TRUE(wait_for_completion_signal(ffprobe_signal, 30000));

  EXPECT_NE(ffmpeg_kit_session_get_state(ffmpeg_session),
            FFMPEG_KIT_SESSION_STATE_RUNNING);
  EXPECT_NE(ffmpeg_kit_session_get_state(ffprobe_session),
            FFMPEG_KIT_SESSION_STATE_RUNNING);

  ffmpeg_kit_handle_release(ffmpeg_session);
  ffmpeg_kit_handle_release(ffprobe_session);
}

TEST(FFmpegKitTest, UnattributedCallbacksDoNotBlockSessionCompletion) {
  auto signal = std::make_shared<CompletionSignal>();

  std::ostringstream command;
  command << "-y -nostdin -hide_banner -loglevel debug "
          << "-re -f lavfi -i testsrc2=size=320x240:rate=30 "
          << "-an -c:v mpeg4 -f null -";

  FFmpegSessionHandle session =
      ffmpeg_kit_create_session(command.str().c_str());
  ASSERT_NE(session, nullptr);

  ScopedFFmpegCompleteCallback callback(session, signal);
  ffmpeg_kit_session_execute_async(session);

  ASSERT_TRUE(wait_for_running_state(session, 5000));
  ASSERT_EQ(ffmpeg_kit_session_get_state(session),
            FFMPEG_KIT_SESSION_STATE_RUNNING);

  const char *foreign_signature = "synthetic-unattributed-log";
  std::atomic<bool> stop_emitter{false};
  TestThread emitter([&stop_emitter, foreign_signature]() {
    int emitted = 0;
    while (!stop_emitter.load() && emitted < 100) {
      ffmpeg_kit_test_emit_unattributed_log(foreign_signature);
      test_sleep_for_ms(10);
      emitted++;
    }
  });

  test_sleep_for_ms(500);
  ffmpeg_kit_session_cancel(session);

  ASSERT_TRUE(wait_for_completion_signal(signal, 30000));
  EXPECT_NE(ffmpeg_kit_session_get_state(session),
            FFMPEG_KIT_SESSION_STATE_RUNNING);

  stop_emitter.store(true);
  emitter.join();

  const std::string logs = session_logs_as_string(session);
  EXPECT_EQ(logs.find(foreign_signature), std::string::npos)
      << "Unattributed log leaked into real session log:\n"
      << logs;

  ffmpeg_kit_handle_release(session);
}

TEST(FFmpegKitTest, CancelStalledHttpStream) {
  const std::filesystem::path output_dir =
      std::filesystem::temp_directory_path() / "ffmpegkit_cancel";
  std::error_code ec;
  std::filesystem::create_directories(output_dir, ec);
  ASSERT_FALSE(ec) << "Failed to create temporary output directory";

  const std::filesystem::path segment_path = output_dir / "segment.ts";
  {
    std::ostringstream setup_command;
    setup_command << "-y -hide_banner -loglevel fatal "
                  << "-f lavfi -i testsrc=duration=8:size=128x128:rate=10 "
                  << "-f lavfi -i sine=frequency=1000:duration=8 "
                  << "-shortest -c:v mpeg2video -c:a mp2 -f mpegts "
                  << "\"" << segment_path.string() << "\"";

    FFmpegSessionHandle setup_session =
        ffmpeg_kit_execute(setup_command.str().c_str());
    ASSERT_NE(setup_session, nullptr);
    EXPECT_EQ(ffmpeg_kit_session_get_state(setup_session),
              FFMPEG_KIT_SESSION_STATE_COMPLETED);
    ffmpeg_kit_handle_release(setup_session);
  }

  LocalHttpStallServer server(segment_path.string());
  ASSERT_TRUE(server.start());

  const std::string user_agent = "FFmpegKit-Issue8-Test";
  const std::string url = server.url("/segment0.ts");
  const std::string output_prefix = "cancel_midstream_";
  const std::string output_pattern =
      (output_dir / (output_prefix + "%03d.ts")).string();
  auto completion_signal = std::make_shared<CompletionSignal>();

  std::ostringstream command;
  command << "-y -nostdin -xerror -hide_banner -loglevel warning "
          << "-reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 "
             "-reconnect_delay_max 5 "
          << "-rw_timeout 5000000 "
          << "-max_delay 5000000 -thread_queue_size 512 "
          << "-user_agent \"" << user_agent << "\" "
          << "-i \"" << url << "\" "
          << "-map 0:v:0 -map 0:a:0 -c copy "
          << "-f segment -segment_time 2 -reset_timestamps 1 "
          << "\"" << output_pattern << "\"";

  FFmpegSessionHandle session =
      ffmpeg_kit_create_session(command.str().c_str());
  ASSERT_NE(session, nullptr);
  ScopedFFmpegCompleteCallback callback(session, completion_signal);

  ffmpeg_kit_session_execute_async(session);

  int64_t session_id = ffmpeg_kit_session_get_session_id(session);
  ASSERT_GT(session_id, 0);

  auto wait_for_state = [&](FFmpegKitSessionState target_a,
                            FFmpegKitSessionState target_b, int timeout_ms) {
    int waited = 0;
    while (waited < timeout_ms) {
      FFmpegKitSessionState state = ffmpeg_kit_session_get_state(session);
      if (state == target_a || state == target_b) {
        return state;
      }
      test_sleep_for_ms(50);
      waited += 50;
    }
    return ffmpeg_kit_session_get_state(session);
  };

  FFmpegKitSessionState initial_state = wait_for_state(
      FFMPEG_KIT_SESSION_STATE_RUNNING, FFMPEG_KIT_SESSION_STATE_FAILED, 5000);
  ASSERT_EQ(initial_state, FFMPEG_KIT_SESSION_STATE_RUNNING);

  ASSERT_TRUE(server.wait_for_segment_request("/segment0.ts", 15000));
  ASSERT_TRUE(server.wait_for_body_bytes(128 * 1024, 15000));
  ASSERT_EQ(ffmpeg_kit_session_get_state(session),
            FFMPEG_KIT_SESSION_STATE_RUNNING)
      << "Session ended before mid-stream cancellation was issued";
  ffmpeg_kit_session_cancel(session);

  const bool completed = wait_for_completion_signal(completion_signal, 120000);
  ASSERT_TRUE(completed)
      << "Timed out waiting for onComplete callback after mid-stream cancel";
  FFmpegKitSessionState final_state = ffmpeg_kit_session_get_state(session);
  EXPECT_NE(final_state, FFMPEG_KIT_SESSION_STATE_RUNNING);
  EXPECT_TRUE(final_state == FFMPEG_KIT_SESSION_STATE_COMPLETED ||
              final_state == FFMPEG_KIT_SESSION_STATE_FAILED);
  ffmpeg_kit_handle_release(session);
  remove_matching_files(output_dir, output_prefix);
  std::filesystem::remove_all(output_dir, ec);
}

TEST(FFmpegKitTest, UnexpectedMidStreamEndCallsOnComplete) {
  const std::filesystem::path output_dir =
      std::filesystem::temp_directory_path() / "ffmpegkit_unexpected_end";
  std::error_code ec;
  std::filesystem::create_directories(output_dir, ec);
  ASSERT_FALSE(ec) << "Failed to create temporary output directory";

  const std::filesystem::path segment_path = output_dir / "segment.ts";
  {
    std::ostringstream setup_command;
    setup_command << "-y -hide_banner -loglevel fatal "
                  << "-f lavfi -i testsrc=duration=8:size=128x128:rate=10 "
                  << "-f lavfi -i sine=frequency=1000:duration=8 "
                  << "-shortest -c:v mpeg2video -c:a mp2 -f mpegts "
                  << "\"" << segment_path.string() << "\"";

    FFmpegSessionHandle setup_session =
        ffmpeg_kit_execute(setup_command.str().c_str());
    ASSERT_NE(setup_session, nullptr);
    EXPECT_EQ(ffmpeg_kit_session_get_state(setup_session),
              FFMPEG_KIT_SESSION_STATE_COMPLETED);
    ffmpeg_kit_handle_release(setup_session);
  }

  LocalHttpStallServer server(
      segment_path.string(),
      LocalHttpStallServer::StreamEndMode::CloseAfterBody);
  ASSERT_TRUE(server.start()) << server.last_error();

  const std::string url = server.url("/segment0.ts");
  auto completion_signal = std::make_shared<CompletionSignal>();

  std::ostringstream command;
  command << "-y -nostdin -xerror -hide_banner -loglevel warning "
          << "-rw_timeout 5000000 "
          << "-i \"" << url << "\" "
          << "-map 0:v:0 -map 0:a:0 -c copy -f null -";

  FFmpegSessionHandle session =
      ffmpeg_kit_create_session(command.str().c_str());
  ASSERT_NE(session, nullptr);
  ScopedFFmpegCompleteCallback callback(session, completion_signal);

  ffmpeg_kit_session_execute_async(session);

  ASSERT_TRUE(server.wait_for_segment_request("/segment0.ts", 15000));
  ASSERT_TRUE(server.wait_for_body_bytes(128 * 1024, 15000));

  const bool completed = wait_for_completion_signal(completion_signal, 120000);
  ASSERT_TRUE(completed) << "Timed out waiting for onComplete callback after "
                            "unexpected stream end";
  FFmpegKitSessionState final_state = ffmpeg_kit_session_get_state(session);
  EXPECT_NE(final_state, FFMPEG_KIT_SESSION_STATE_RUNNING);
  EXPECT_TRUE(final_state == FFMPEG_KIT_SESSION_STATE_COMPLETED ||
              final_state == FFMPEG_KIT_SESSION_STATE_FAILED);

  ffmpeg_kit_handle_release(session);
  remove_matching_files(output_dir, "");
  std::filesystem::remove_all(output_dir, ec);
}

TEST(FFmpegKitTest, RemoteStreamParallelRecordingCancellationIsolation) {
  auto url = remote_stream_url();
  if (!url) {
    GTEST_SKIP() << "Set FFMPEG_KIT_REMOTE_STREAM_URL to enable remote stream "
                    "recording tests.";
  }

  const std::filesystem::path output_dir =
      std::filesystem::temp_directory_path() /
      "ffmpegkit_remote_recording_parallel";
  std::error_code ec;
  std::filesystem::create_directories(output_dir, ec);
  ASSERT_FALSE(ec) << "Failed to create temporary output directory";

  const std::filesystem::path output1 = output_dir / "remote_recording_1.ts";
  const std::filesystem::path output2 = output_dir / "remote_recording_2.ts";
  auto signal1 = std::make_shared<CompletionSignal>();
  auto signal2 = std::make_shared<CompletionSignal>();

  FFmpegSessionHandle session1 = ffmpeg_kit_create_session(
      remote_recording_command(*url, output1).c_str());
  FFmpegSessionHandle session2 = ffmpeg_kit_create_session(
      remote_recording_command(*url, output2).c_str());
  ASSERT_NE(session1, nullptr);
  ASSERT_NE(session2, nullptr);

  ScopedFFmpegCompleteCallback callback1(session1, signal1);
  ScopedFFmpegCompleteCallback callback2(session2, signal2);

  ffmpeg_kit_session_execute_async(session1);
  ffmpeg_kit_session_execute_async(session2);

  ASSERT_TRUE(wait_for_running_state(session1, 15000));
  ASSERT_TRUE(wait_for_running_state(session2, 15000));
  ASSERT_TRUE(wait_for_file_size_at_least(output1, 188, 30000))
      << "Remote stream session 1 never reached mid-stream output";
  ASSERT_TRUE(wait_for_file_size_at_least(output2, 188, 30000))
      << "Remote stream session 2 never reached mid-stream output";

  ffmpeg_kit_session_cancel(session1);
  ffmpeg_kit_session_cancel(session2);

  ASSERT_TRUE(wait_for_completion_signal(signal1, 120000))
      << "Timed out waiting for remote recording session 1 completion";
  ASSERT_TRUE(wait_for_completion_signal(signal2, 120000))
      << "Timed out waiting for remote recording session 2 completion";

  EXPECT_NE(ffmpeg_kit_session_get_state(session1),
            FFMPEG_KIT_SESSION_STATE_RUNNING);
  EXPECT_NE(ffmpeg_kit_session_get_state(session2),
            FFMPEG_KIT_SESSION_STATE_RUNNING);

  ffmpeg_kit_handle_release(session1);
  ffmpeg_kit_handle_release(session2);
  remove_matching_files(output_dir, "remote_recording_");
  std::filesystem::remove_all(output_dir, ec);
}

TEST(FFmpegKitTest, RemoteStreamCancelAndImmediateRestart) {
  auto url = remote_stream_url();
  if (!url) {
    GTEST_SKIP() << "Set FFMPEG_KIT_REMOTE_STREAM_URL to enable remote stream "
                    "recording tests.";
  }

  const std::filesystem::path output_dir =
      std::filesystem::temp_directory_path() /
      "ffmpegkit_remote_recording_restart";
  std::error_code ec;
  std::filesystem::create_directories(output_dir, ec);
  ASSERT_FALSE(ec) << "Failed to create temporary output directory";

  const std::filesystem::path output1 = output_dir / "remote_restart_1.ts";
  const std::filesystem::path output2 = output_dir / "remote_restart_2.ts";
  auto signal1 = std::make_shared<CompletionSignal>();
  auto signal2 = std::make_shared<CompletionSignal>();

  FFmpegSessionHandle session1 = ffmpeg_kit_create_session(
      remote_recording_command(*url, output1).c_str());
  ASSERT_NE(session1, nullptr);
  ScopedFFmpegCompleteCallback callback1(session1, signal1);

  ffmpeg_kit_session_execute_async(session1);
  ASSERT_TRUE(wait_for_running_state(session1, 15000));
  ASSERT_TRUE(wait_for_file_size_at_least(output1, 188, 30000))
      << "Remote stream session 1 never reached mid-stream output";

  ffmpeg_kit_session_cancel(session1);

  FFmpegSessionHandle session2 = ffmpeg_kit_create_session(
      remote_recording_command(*url, output2).c_str());
  ASSERT_NE(session2, nullptr);
  ScopedFFmpegCompleteCallback callback2(session2, signal2);

  ffmpeg_kit_session_execute_async(session2);
  ASSERT_TRUE(wait_for_running_state(session2, 15000));
  ASSERT_TRUE(wait_for_file_size_at_least(output2, 188, 30000))
      << "Remote stream session 2 never reached mid-stream output";

  ASSERT_TRUE(wait_for_completion_signal(signal1, 120000))
      << "Timed out waiting for first remote recording completion";
  ffmpeg_kit_session_cancel(session2);
  ASSERT_TRUE(wait_for_completion_signal(signal2, 120000))
      << "Timed out waiting for restart remote recording completion";

  EXPECT_NE(ffmpeg_kit_session_get_state(session1),
            FFMPEG_KIT_SESSION_STATE_RUNNING);
  EXPECT_NE(ffmpeg_kit_session_get_state(session2),
            FFMPEG_KIT_SESSION_STATE_RUNNING);

  ffmpeg_kit_handle_release(session1);
  ffmpeg_kit_handle_release(session2);
  remove_matching_files(output_dir, "remote_restart_");
  std::filesystem::remove_all(output_dir, ec);
}

TEST(FFmpegKitTest, RemoteStreamRepeatedCancelRequestsAreIgnored) {
  auto url = remote_stream_url();
  if (!url) {
    GTEST_SKIP() << "Set FFMPEG_KIT_REMOTE_STREAM_URL to enable remote stream "
                    "recording tests.";
  }

  const std::filesystem::path output_dir =
      std::filesystem::temp_directory_path() /
      "ffmpegkit_remote_recording_repeated_cancel";
  std::error_code ec;
  std::filesystem::create_directories(output_dir, ec);
  ASSERT_FALSE(ec) << "Failed to create temporary output directory";

  const std::filesystem::path output = output_dir / "remote_repeated_cancel.ts";
  auto signal = std::make_shared<CompletionSignal>();

  FFmpegSessionHandle session =
      ffmpeg_kit_create_session(remote_recording_command(*url, output).c_str());
  ASSERT_NE(session, nullptr);
  ScopedFFmpegCompleteCallback callback(session, signal);

  ffmpeg_kit_session_execute_async(session);
  ASSERT_TRUE(wait_for_running_state(session, 15000));
  ASSERT_TRUE(wait_for_file_size_at_least(output, 188, 30000))
      << "Remote stream session never reached mid-stream output";

  for (int i = 0; i < 5; ++i) {
    ffmpeg_kit_session_cancel(session);
    test_sleep_for_ms(50);
  }

  ASSERT_TRUE(wait_for_completion_signal(signal, 120000))
      << "Timed out waiting for completion after repeated cancel requests";
  EXPECT_NE(ffmpeg_kit_session_get_state(session),
            FFMPEG_KIT_SESSION_STATE_RUNNING);
  EXPECT_TRUE(ffmpeg_kit_session_get_state(session) ==
                  FFMPEG_KIT_SESSION_STATE_COMPLETED ||
              ffmpeg_kit_session_get_state(session) ==
                  FFMPEG_KIT_SESSION_STATE_FAILED);

  ffmpeg_kit_handle_release(session);
  remove_matching_files(output_dir, "remote_repeated_cancel");
  std::filesystem::remove_all(output_dir, ec);
}

TEST(FFmpegKitTest, SessionManagement) {
  ffmpeg_kit_clear_sessions();

  // Create multiple types of sessions
  FFmpegSessionHandle ffmpeg = ffmpeg_kit_create_session("-version");
  FFprobeSessionHandle ffprobe = ffprobe_kit_create_session("-version");
  FFplaySessionHandle ffplay = ffplay_kit_create_session("-version");
  char media_cmd[512];
  snprintf(media_cmd, sizeof(media_cmd),
           "-v error -hide_banner -print_format json -show_format "
           "-show_streams -show_chapters -i %s",
           TEST_VIDEO_FILE);
  MediaInformationSessionHandle media =
      media_information_create_session(media_cmd);

  // Check last session
  FFmpegSessionHandle last = ffmpeg_kit_get_last_session();
  printf("Last Session: %p\n", last);
  EXPECT_NE(last, nullptr);
  if (last)
    ffmpeg_kit_handle_release(last);

  FFmpegSessionHandle last_ffmpeg = ffmpeg_kit_get_last_ffmpeg_session();
  printf("Last FFmpeg Session: %p\n", last_ffmpeg);
  EXPECT_NE(last_ffmpeg, nullptr);
  if (last_ffmpeg)
    ffmpeg_kit_handle_release(last_ffmpeg);

  FFprobeSessionHandle last_ffprobe = ffmpeg_kit_get_last_ffprobe_session();
  printf("Last FFprobe Session: %p\n", last_ffprobe);
  EXPECT_NE(last_ffprobe, nullptr);
  if (last_ffprobe)
    ffmpeg_kit_handle_release(last_ffprobe);

  FFplaySessionHandle last_ffplay = ffmpeg_kit_get_last_ffplay_session();
  printf("Last FFplay Session: %p\n", last_ffplay);
  EXPECT_NE(last_ffplay, nullptr);
  if (last_ffplay)
    ffmpeg_kit_handle_release(last_ffplay);

  MediaInformationSessionHandle last_media =
      ffmpeg_kit_get_last_media_information_session();
  printf("Last Media Information Session: %p\n", last_media);
  EXPECT_NE(last_media, nullptr);
  if (last_media)
    ffmpeg_kit_handle_release(last_media);

  // List sessions
  FFmpegSessionHandle *sessions = ffmpeg_kit_get_sessions();
  int count = 0;
  if (sessions) {
    while (sessions[count]) {
      ffmpeg_kit_handle_release(sessions[count]);
      count++;
    }
    free(sessions);
  }
  printf("Session Count: %d\n", count);
  EXPECT_GE(count, 4);

  FFmpegSessionHandle *ffmpeg_sessions = ffmpeg_kit_get_ffmpeg_sessions();
  int ffmpeg_count = 0;
  if (ffmpeg_sessions) {
    while (ffmpeg_sessions[ffmpeg_count]) {
      ffmpeg_kit_handle_release(ffmpeg_sessions[ffmpeg_count]);
      ffmpeg_count++;
    }
    free(ffmpeg_sessions);
  }
  printf("FFmpeg Session Count: %d\n", ffmpeg_count);
  EXPECT_GE(ffmpeg_count, 1);

  // Cleanup
  ffmpeg_kit_handle_release(ffmpeg);
  ffmpeg_kit_handle_release(ffprobe);
  ffmpeg_kit_handle_release(ffplay);
  ffmpeg_kit_handle_release(media);
}

TEST(FFmpegKitTest, LastCompletedSession) {
  ffmpeg_kit_clear_sessions();

  FFmpegSessionHandle session = ffmpeg_kit_execute("-version");
  ASSERT_NE(session, nullptr);

  FFmpegSessionHandle last_completed = ffmpeg_kit_get_last_completed_session();
  EXPECT_NE(last_completed, nullptr);

  if (last_completed) {
    EXPECT_EQ(ffmpeg_kit_session_get_state(last_completed),
              FFMPEG_KIT_SESSION_STATE_COMPLETED);
    ffmpeg_kit_handle_release(last_completed);
  }

  ffmpeg_kit_handle_release(session);
}

TEST(FFmpegKitTest, SessionProperties) {
  FFmpegSessionHandle session =
      ffmpeg_kit_execute("-hide_banner -loglevel fatal -f lavfi -i "
                         "sine=frequency=1000:duration=1 -y test_props.wav");
  ASSERT_NE(session, nullptr);

  long create_time = ffmpeg_kit_session_get_create_time(session);
  long start_time = ffmpeg_kit_session_get_start_time(session);
  long end_time = ffmpeg_kit_session_get_end_time(session);
  long duration = ffmpeg_kit_session_get_duration(session);

  printf("Create Time: %ld\n", create_time);
  printf("Start Time: %ld\n", start_time);
  printf("End Time: %ld\n", end_time);
  printf("Duration: %ld\n", duration);

  EXPECT_GT(create_time, 0);
  EXPECT_GT(start_time, 0);
  EXPECT_GT(end_time, 0);
  EXPECT_GE(end_time, start_time);
  EXPECT_GE(duration, 0);

  ffmpeg_kit_handle_release(session);
  remove("test_props.wav");
}

TEST(FFmpegKitTest, Statistics) {
  // Generate a file and check statistics
  FFmpegSessionHandle session =
      ffmpeg_kit_execute("-hide_banner -loglevel fatal -f lavfi -i "
                         "testsrc=duration=2:size=128x128:rate=30 -vcodec "
                         "mpeg4 -y test_stats.mp4");
  ASSERT_NE(session, nullptr);

  int stats_count = ffmpeg_kit_session_get_statistics_count(session);
  printf("Statistics Count: %d\n", stats_count);

  if (stats_count > 0) {
    StatisticsHandle stats = ffmpeg_kit_session_get_statistics_at(session, 0);
    EXPECT_NE(stats, nullptr);

    int frame_number = ffmpeg_kit_statistics_get_video_frame_number(stats);
    float fps = ffmpeg_kit_statistics_get_video_fps(stats);
    double time = ffmpeg_kit_statistics_get_time(stats);

    printf("Frame Number: %d\n", frame_number);
    printf("FPS: %f\n", fps);
    printf("Time: %f\n", time);

    EXPECT_GE(frame_number, 0);
    EXPECT_GE(fps, 0.0f);
    EXPECT_GE(time, 0.0);

    ffmpeg_kit_handle_release(stats);
  }

  ffmpeg_kit_handle_release(session);
  remove("test_stats.mp4");
}

TEST(FFprobeKitTest, LastSessionAliases) {
  ffmpeg_kit_clear_sessions();

  FFprobeSessionHandle session = ffprobe_kit_execute("-hide_banner -version");
  ASSERT_NE(session, nullptr);

  FFprobeSessionHandle last = ffprobe_kit_get_last_session();
  EXPECT_NE(last, nullptr);
  if (last)
    ffmpeg_kit_handle_release(last);

  FFprobeSessionHandle last_comp = ffprobe_kit_get_last_completed_session();
  EXPECT_NE(last_comp, nullptr);
  if (last_comp)
    ffmpeg_kit_handle_release(last_comp);

  ffmpeg_kit_handle_release(session);
}

TEST(FFmpegKitTest, SessionListingAliases) {
  ffmpeg_kit_clear_sessions();

  // 1. FFmpeg Listing
  FFmpegSessionHandle ffmpeg = ffmpeg_kit_create_session("-version");
  FFmpegSessionHandle *ffmpeg_list = ffmpeg_kit_list_sessions();
  int ffmpeg_count = 0;
  if (ffmpeg_list) {
    while (ffmpeg_list[ffmpeg_count]) {
      ffmpeg_kit_handle_release(ffmpeg_list[ffmpeg_count]);
      ffmpeg_count++;
    }
    free(ffmpeg_list);
  }
  EXPECT_GE(ffmpeg_count, 1);
  printf("FFmpeg List Count: %d\n", ffmpeg_count);

  // 2. FFprobe Listing
  FFprobeSessionHandle ffprobe = ffprobe_kit_create_session("-version");
  FFprobeSessionHandle *ffprobe_list = ffprobe_kit_list_sessions();
  int ffprobe_count = 0;
  if (ffprobe_list) {
    while (ffprobe_list[ffprobe_count]) {
      ffmpeg_kit_handle_release(ffprobe_list[ffprobe_count]);
      ffprobe_count++;
    }
    free(ffprobe_list);
  }
  EXPECT_GE(ffprobe_count, 1);
  printf("FFprobe List Count: %d\n", ffprobe_count);

  // 3. Media Information Listing
  char media_cmd[512];
  snprintf(media_cmd, sizeof(media_cmd), "-v error -i %s", TEST_VIDEO_FILE);
  MediaInformationSessionHandle media =
      media_information_create_session(media_cmd);
  MediaInformationSessionHandle *media_list =
      media_information_kit_list_sessions();
  int media_count = 0;
  if (media_list) {
    while (media_list[media_count]) {
      ffmpeg_kit_handle_release(media_list[media_count]);
      media_count++;
    }
    free(media_list);
  }
  EXPECT_GE(media_count, 1);
  printf("Media Info List Count: %d\n", media_count);

  // Cleanup
  ffmpeg_kit_handle_release(ffmpeg);
  ffmpeg_kit_handle_release(ffprobe);
  ffmpeg_kit_handle_release(media);
}

TEST(FFmpegKitTest, HandleManagement) {
  // 1. Create a session and get a handle
  FFmpegSessionHandle session = ffmpeg_kit_create_session("-version");
  ASSERT_NE(session, nullptr);

  // 2. First release - should work normally
  ffmpeg_kit_handle_release(session);
  SUCCEED();

  // 3. Second release (Double Free) - should be caught by protection and NOT
  // crash
  ffmpeg_kit_handle_release(session);
  SUCCEED();

  // 4. Release nullptr - should be no-op
  ffmpeg_kit_handle_release(nullptr);
  SUCCEED();
}

TEST(FFmpegKitTest, ConcurrentHandleRelease) {
  // Create a session
  FFmpegSessionHandle session = ffmpeg_kit_create_session("-version");
  ASSERT_NE(session, nullptr);

  // Multiple threads trying to release the SAME handle simultaneously
  const int thread_count = 10;
  std::vector<TestThread> threads;
  for (int i = 0; i < thread_count; ++i) {
    threads.emplace_back([session]() { ffmpeg_kit_handle_release(session); });
  }

  for (auto &t : threads) {
    t.join();
  }

  // If we reached here without crashing/hanging, the test passed
  SUCCEED();
}

TEST(FFmpegKitTest, RobustnessTest) {
  // 1. Create a session and execute it to ensure it's in history
  FFmpegSessionHandle session = ffmpeg_kit_create_session("-version");
  ASSERT_NE(session, nullptr);
  ffmpeg_kit_session_execute(session);

  // 2. Get session ID
  int64_t id = ffmpeg_kit_session_get_session_id(session);
  EXPECT_GT(id, 0);

  // 3. Release handle
  ffmpeg_kit_handle_release(session);

  // 4. Try to use released handle (should NOT crash)
  // It should return -1 or nullptr because the handle is no longer in
  // g_active_handles and it's too large to be a "fake" ID.
  EXPECT_EQ(ffmpeg_kit_session_get_session_id(session), -1);
  EXPECT_EQ(ffmpeg_kit_session_get_output(session), nullptr);
  EXPECT_EQ(ffmpeg_kit_session_get_logs_count(session), -1);
  EXPECT_EQ(ffmpeg_kit_session_get_command(session), nullptr);
  EXPECT_EQ(ffmpeg_kit_session_get_log_at(session, 0), nullptr);
  EXPECT_EQ(ffmpeg_kit_session_get_statistics_count(session), -1);
  EXPECT_EQ(ffmpeg_kit_session_get_statistics_at(session, 0), nullptr);

  // 5. Try with "fake" handle (ID as pointer)
  // This should work because get_ptr_internal now supports looking up by ID in
  // history
  void *fake_handle = (void *)(uintptr_t)id;
  EXPECT_EQ(ffmpeg_kit_session_get_session_id(fake_handle), id);

  char *output = ffmpeg_kit_session_get_output(fake_handle);
  EXPECT_NE(output, nullptr);
  if (output) {
    printf("Output from fake handle: %s\n", output);
    free(output);
  }
}
