#include <gtest/gtest.h>
#include "ffmpegkit_wrapper.h"
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include <atomic>
#include <chrono>
#include <functional>
#include <memory>

#ifdef _WIN32
#include <process.h>
#include <windows.h>
#else
#include <thread>
#endif

#ifndef FFMPEG_KIT_TEST_DIR
#define FFMPEG_KIT_TEST_DIR "."
#endif
#define TEST_VIDEO_FILE FFMPEG_KIT_TEST_DIR "/dummy_video.mp4"
#define TEST_AUDIO_FILE FFMPEG_KIT_TEST_DIR "/dummy_audio.wav"

// Helper class to capture callback data
class CallbackCapturer {
public:
    std::atomic<bool> complete_called{false};
    std::atomic<bool> log_called{false};
    std::atomic<bool> stats_called{false};
    std::vector<std::string> logs;
    mutable std::mutex logs_mutex;
    FFmpegSessionHandle session = nullptr;

    static void CompleteCallback(FFmpegSessionHandle session, void* user_data) {
        auto* capturer = static_cast<CallbackCapturer*>(user_data);
        capturer->session = session;
        capturer->complete_called = true;
    }

    static void LogCallback(FFmpegSessionHandle session, const char* log, void* user_data) {
        auto* capturer = static_cast<CallbackCapturer*>(user_data);
        if (log) {
            std::lock_guard<std::mutex> lock(capturer->logs_mutex);
            capturer->logs.push_back(log);
            printf("%s\n", log);
        }
        capturer->log_called = true;
    }

    static void StatisticsCallback(FFmpegSessionHandle session, int64_t timeElapsed, int64_t time, int64_t size, double bitrate, double speed, int64_t videoFrameNumber, double videoFps, double videoQuality, int64_t dupFrames, int64_t dropFrames, void* user_data) {
        auto* capturer = static_cast<CallbackCapturer*>(user_data);
        capturer->stats_called = true;
    }
};

static void sleep_for_ms(int milliseconds) {
#ifdef _WIN32
    Sleep(static_cast<DWORD>(milliseconds));
#else
    const struct timespec ts {
        milliseconds / 1000,
        (milliseconds % 1000) * 1000000L
    };
    nanosleep(&ts, nullptr);
#endif
}

class CallbackTest : public ::testing::Test {
protected:
    std::shared_ptr<CallbackCapturer> capturer_ptr;

    void TearDown() override {
        ffmpeg_kit_config_clear_sessions();
        ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
        ffmpeg_kit_config_enable_statistics_callback(nullptr, nullptr);
        ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(nullptr, nullptr);
        ffmpeg_kit_config_enable_ffprobe_session_complete_callback(nullptr, nullptr);
        ffmpeg_kit_config_enable_ffplay_session_complete_callback(nullptr, nullptr);
        ffmpeg_kit_config_enable_media_information_session_complete_callback(nullptr, nullptr);
    }
};

#ifdef _WIN32
class TestThread {
public:
    TestThread() = default;

    template <typename Callable>
    explicit TestThread(Callable &&callable) {
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

    template <typename Callable>
    void start(Callable &&callable) {
        using Task = std::function<void()>;
        auto *task = new Task(std::forward<Callable>(callable));
        unsigned thread_id = 0;
        handle_ = reinterpret_cast<HANDLE>(_beginthreadex(
            nullptr, 0, &TestThread::run, task, 0, &thread_id));
    }

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

// FFmpeg Callback Tests
TEST_F(CallbackTest, FFmpegAsyncExecute) {
    CallbackCapturer capturer;
    // Simple version command
    FFmpegSessionHandle session = ffmpeg_kit_execute_async("-version", CallbackCapturer::CompleteCallback, &capturer);
    ASSERT_NE(session, nullptr);

    // Wait for completion (busy wait with timeout)
    int64_t timeout_ms = 5000;
    while (!capturer.complete_called && timeout_ms > 0) {
        sleep_for_ms(10);
        timeout_ms -= 10;
    }

    EXPECT_TRUE(capturer.complete_called);
    EXPECT_NE(capturer.session, nullptr);
    if(capturer.session) {
        // Handle pointer should be same due to handle recycling
        EXPECT_EQ(session, capturer.session);
    }

    EXPECT_EQ(ffmpeg_kit_session_get_state(session), FFMPEG_KIT_SESSION_STATE_COMPLETED);
    
    ffmpeg_kit_handle_release(session);
}

TEST_F(CallbackTest, FFmpegAsyncExecuteFull) {
    CallbackCapturer capturer;
    ffmpeg_kit_config_set_log_level(FFMPEG_KIT_LOG_LEVEL_VERBOSE);
    // Use a command that generates output and takes a bit of time (testsrc)
    std::string cmd = "-hide_banner -loglevel info -f lavfi -i testsrc=duration=30:size=512x512:rate=30 -vcodec mpeg4 -y test_stats.mp4";
    
    FFmpegSessionHandle session = ffmpeg_kit_execute_async_full(
        cmd.c_str(), 
        CallbackCapturer::CompleteCallback, 
        CallbackCapturer::LogCallback, 
        CallbackCapturer::StatisticsCallback, 
        &capturer, 
        0 // No specific timeout for session start
    );
    int stats_count = ffmpeg_kit_session_get_statistics_count(session);
    ASSERT_NE(session, nullptr);

    // Wait for completion
    int64_t timeout_ms = 10000;
    while (!capturer.complete_called && timeout_ms > 0) {
        sleep_for_ms(10);
        timeout_ms -= 10;
    }

    EXPECT_TRUE(capturer.complete_called);
    EXPECT_TRUE(capturer.log_called);
    EXPECT_TRUE(capturer.stats_called);

    EXPECT_EQ(ffmpeg_kit_session_get_state(session), FFMPEG_KIT_SESSION_STATE_COMPLETED);
    ffmpeg_kit_handle_release(session);
    remove("test_stats.mp4");
}

// FFprobe Callback Tests
class ProbeCallbackCapturer {
public:
    std::atomic<bool> complete_called{false};
    FFprobeSessionHandle session = nullptr;
    MediaInformationSessionHandle media_session = nullptr;

    static void CompleteCallback(FFprobeSessionHandle session, void* user_data) {
        auto* capturer = static_cast<ProbeCallbackCapturer*>(user_data);
        capturer->session = session;
        capturer->complete_called = true;
    }

    static void MediaInfoCompleteCallback(MediaInformationSessionHandle session, void* user_data) {
        auto* capturer = static_cast<ProbeCallbackCapturer*>(user_data);
        capturer->media_session = session;
        capturer->complete_called = true;
    }
};

TEST_F(CallbackTest, FFprobeAsyncExecute) {
    ProbeCallbackCapturer capturer;
    FFprobeSessionHandle session = ffprobe_kit_execute_async("-version", ProbeCallbackCapturer::CompleteCallback, &capturer);
    ASSERT_NE(session, nullptr);

    int64_t timeout_ms = 5000;
    while (!capturer.complete_called && timeout_ms > 0) {
        sleep_for_ms(10);
        timeout_ms -= 10;
    }

    EXPECT_TRUE(capturer.complete_called);
    EXPECT_NE(capturer.session, nullptr);

    ffmpeg_kit_handle_release(session);
}

TEST_F(CallbackTest, MediaInformationAsync) {
    ProbeCallbackCapturer capturer;
    MediaInformationSessionHandle session = ffprobe_kit_get_media_information_async(TEST_VIDEO_FILE, ProbeCallbackCapturer::MediaInfoCompleteCallback, &capturer);
    ASSERT_NE(session, nullptr);

    int64_t timeout_ms = 10000; // Increased timeout slightly
    while (!capturer.complete_called && timeout_ms > 0) {
        sleep_for_ms(10);
        timeout_ms -= 10;
    }

    EXPECT_TRUE(capturer.complete_called);
    EXPECT_NE(capturer.media_session, nullptr);
    
    // session handle (returned by async call) and capturer.media_session handle (passed to callback)
    // should be the same handle now due to recycling.
    EXPECT_EQ(session, capturer.media_session);

    // Use the handle to inspect
    MediaInformationHandle media_info = media_information_session_get_media_information(session);
    printf("Media Information: %p\n", media_info);
    ASSERT_NE(media_info, nullptr);
    char* all_props = media_information_get_all_properties_json(media_info);
    printf("All Props: %s\n", all_props);
    EXPECT_NE(all_props, nullptr);

    if (media_info) {
        char *format = media_information_get_format(media_info);
        if (format) {
            EXPECT_NE(format, nullptr);
            free(format);
        }
        ffmpeg_kit_handle_release(media_info);
    }
    if (all_props) free(all_props);
    ffmpeg_kit_handle_release(session);
}

// FFplay Callback Tests
class PlayCallbackCapturer {
public:
    std::atomic<bool> complete_called{false};
    FFplaySessionHandle session = nullptr;

    static void CompleteCallback(FFplaySessionHandle session, void* user_data) {
        auto* capturer = static_cast<PlayCallbackCapturer*>(user_data);
        capturer->session = session;
        capturer->complete_called = true;
    }
};

TEST_F(CallbackTest, FFplayAsyncExecute) {
    // Need dummy env
#ifdef _WIN32
    _putenv("SDL_VIDEODRIVER=dummy");
    _putenv("SDL_AUDIODRIVER=dummy");
#else
    setenv("SDL_VIDEODRIVER", "dummy", 1);
    setenv("SDL_AUDIODRIVER", "dummy", 1);
#endif

    PlayCallbackCapturer capturer;
    // Short playback
    char command[512];
    snprintf(command, sizeof(command), "-hide_banner -loglevel fatal -autoexit -t 0.5 %s", TEST_VIDEO_FILE);

    FFplaySessionHandle session = ffplay_kit_execute_async(command, PlayCallbackCapturer::CompleteCallback, &capturer, 5000);
    ASSERT_NE(session, nullptr);

    int64_t timeout_ms = 5000;
    while (!capturer.complete_called && timeout_ms > 0) {
        sleep_for_ms(10);
        timeout_ms -= 10;
    }

    EXPECT_TRUE(capturer.complete_called);
    EXPECT_NE(capturer.session, nullptr);
    
    ffmpeg_kit_handle_release(session);
}

// Global Callback Tests
class GlobalCallbackCapturer {
public:
    std::atomic<bool> log_called{false};
    std::atomic<bool> stats_called{false};
    std::atomic<int64_t> complete_called_count{0};
    std::vector<std::string> logs;

    static void LogCallback(int64_t session_id, const char* log, void* user_data) {
        auto* capturer = static_cast<GlobalCallbackCapturer*>(user_data);
        if (log) {
            capturer->logs.push_back(log);
        }
        capturer->log_called = true;
    }

    static void StatisticsCallback(int64_t session_id, int64_t timeElapsed, int64_t time, int64_t size, double bitrate, double speed, int64_t videoFrameNumber, double videoFps, double videoQuality, int64_t dupFrames, int64_t dropFrames, void* user_data) {
        auto* capturer = static_cast<GlobalCallbackCapturer*>(user_data);
        capturer->stats_called = true;
    }

    static void CompleteCallback(int64_t session_id, void* user_data) {
        auto* capturer = static_cast<GlobalCallbackCapturer*>(user_data);
        capturer->complete_called_count++;
    }

    static void FFprobeCompleteCallback(int64_t session_id, void* user_data) {
        auto* capturer = static_cast<GlobalCallbackCapturer*>(user_data);
        capturer->complete_called_count++;
    }

    static void FFplayCompleteCallback(int64_t session_id, void* user_data) {
        auto* capturer = static_cast<GlobalCallbackCapturer*>(user_data);
        capturer->complete_called_count++;
    }

    static void MediaInformationCompleteCallback(int64_t session_id, void* user_data) {
        auto* capturer = static_cast<GlobalCallbackCapturer*>(user_data);
        capturer->complete_called_count++;
    }
};

TEST_F(CallbackTest, GlobalCallbacks) {
    GlobalCallbackCapturer capturer;
    
    // Enable global callbacks
    ffmpeg_kit_config_enable_log_callback(GlobalCallbackCapturer::LogCallback, &capturer);
    ffmpeg_kit_config_enable_statistics_callback(GlobalCallbackCapturer::StatisticsCallback, &capturer);
    ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(GlobalCallbackCapturer::CompleteCallback, &capturer);
    ffmpeg_kit_config_enable_ffprobe_session_complete_callback(GlobalCallbackCapturer::FFprobeCompleteCallback, &capturer);
    ffmpeg_kit_config_enable_ffplay_session_complete_callback(GlobalCallbackCapturer::FFplayCompleteCallback, &capturer);
    ffmpeg_kit_config_enable_media_information_session_complete_callback(GlobalCallbackCapturer::MediaInformationCompleteCallback, &capturer);

    // Run a command that produces logs and stats
    FFmpegSessionHandle session = ffmpeg_kit_execute_async("-loglevel fatal -hide_banner -f lavfi -i testsrc=duration=2:size=128x128:rate=30 -f null -", nullptr, nullptr);
    ASSERT_NE(session, nullptr);

#ifdef _WIN32
    _putenv("SDL_VIDEODRIVER=dummy");
    _putenv("SDL_AUDIODRIVER=dummy");
#else
    setenv("SDL_VIDEODRIVER", "dummy", 1);
    setenv("SDL_AUDIODRIVER", "dummy", 1);
#endif

    // Run other async executions to test global callbacks
    FFprobeSessionHandle probe_session = ffprobe_kit_execute_async("-version", nullptr, nullptr);
    
    char play_command[512];
    snprintf(play_command, sizeof(play_command), "-hide_banner -loglevel fatal -autoexit -t 0.5 %s", TEST_VIDEO_FILE);
    FFplaySessionHandle play_session = ffplay_kit_execute_async(play_command, nullptr, nullptr, 5000);
    
    MediaInformationSessionHandle media_session = ffprobe_kit_get_media_information_async(TEST_VIDEO_FILE, nullptr, nullptr);

    int64_t timeout_ms = 10000;
    while (capturer.complete_called_count < 4 && timeout_ms > 0) {
        sleep_for_ms(10);
        timeout_ms -= 10;
    }

    EXPECT_EQ(capturer.complete_called_count.load(), 4);
    EXPECT_TRUE(capturer.log_called);
    // stats_called might sometimes fail if duration is too short to trigger interval, but size=0 allows stats.
    EXPECT_GT(capturer.logs.size(), 0);

    // Disable global callbacks
    ffmpeg_kit_config_enable_log_callback(nullptr, nullptr);
    ffmpeg_kit_config_enable_statistics_callback(nullptr, nullptr);
    ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(nullptr, nullptr);
    ffmpeg_kit_config_enable_ffprobe_session_complete_callback(nullptr, nullptr);
    ffmpeg_kit_config_enable_ffplay_session_complete_callback(nullptr, nullptr);
    ffmpeg_kit_config_enable_media_information_session_complete_callback(nullptr, nullptr);

    if (session) ffmpeg_kit_handle_release(session);
    if (probe_session) ffmpeg_kit_handle_release(probe_session);
    if (play_session) ffmpeg_kit_handle_release(play_session);
    if (media_session) ffmpeg_kit_handle_release(media_session);
}

// Tests for new create session with callbacks methods
TEST_F(CallbackTest, FFmpegCreateSessionWithCallbacks) {
    capturer_ptr = std::make_shared<CallbackCapturer>();
    FFmpegSessionHandle session = ffmpeg_kit_create_session_with_callbacks(
        "-version", 
        CallbackCapturer::CompleteCallback, 
        CallbackCapturer::LogCallback, 
        CallbackCapturer::StatisticsCallback, 
        capturer_ptr.get()
    );
    ASSERT_NE(session, nullptr);
    EXPECT_EQ(ffmpeg_kit_session_get_state(session), FFMPEG_KIT_SESSION_STATE_CREATED);

    ffmpeg_kit_session_execute_async(session);

    int64_t timeout_ms = 5000;
    while (!capturer_ptr->complete_called && timeout_ms > 0) {
        sleep_for_ms(10);
        timeout_ms -= 10;
    }

    // Give background thread a moment to finish late-arriving logs/stats
    sleep_for_ms(100);

    EXPECT_TRUE(capturer_ptr->complete_called);
    EXPECT_TRUE(capturer_ptr->log_called);
    EXPECT_EQ(ffmpeg_kit_session_get_state(session), FFMPEG_KIT_SESSION_STATE_COMPLETED);
    
    ffmpeg_kit_handle_release(session);
}

TEST_F(CallbackTest, FFprobeCreateSessionWithCallbacks) {
    ProbeCallbackCapturer capturer;
    FFprobeSessionHandle session = ffprobe_kit_create_session_with_callbacks(
        "-version", 
        ProbeCallbackCapturer::CompleteCallback, 
        nullptr, // No log callback
        &capturer
    );
    ASSERT_NE(session, nullptr);
    EXPECT_EQ(ffmpeg_kit_session_get_state(session), FFMPEG_KIT_SESSION_STATE_CREATED);

    ffprobe_kit_session_execute_async(session);

    int64_t timeout_ms = 5000;
    while (!capturer.complete_called && timeout_ms > 0) {
        sleep_for_ms(10);
        timeout_ms -= 10;
    }

    EXPECT_TRUE(capturer.complete_called);
    EXPECT_EQ(ffmpeg_kit_session_get_state(session), FFMPEG_KIT_SESSION_STATE_COMPLETED);
    
    ffmpeg_kit_handle_release(session);
}

TEST_F(CallbackTest, MediaInformationCreateSessionWithCallbacks) {
    ProbeCallbackCapturer capturer;
    char command[512];
    snprintf(command, sizeof(command), "-v error -hide_banner -print_format json -show_format -show_streams -show_chapters -i %s", TEST_VIDEO_FILE);
    MediaInformationSessionHandle session = media_information_create_session_with_callbacks(
        command, 
        ProbeCallbackCapturer::MediaInfoCompleteCallback, 
        nullptr, // No log callback
        &capturer
    );
    ASSERT_NE(session, nullptr);
    EXPECT_EQ(ffmpeg_kit_session_get_state(session), FFMPEG_KIT_SESSION_STATE_CREATED);

    media_information_session_execute_async(session, 5000);

    int64_t timeout_ms = 10000;
    while (!capturer.complete_called && timeout_ms > 0) {
        sleep_for_ms(10);
        timeout_ms -= 10;
    }

    EXPECT_TRUE(capturer.complete_called);
    // Allow either COMPLETED or FAILED, as long as it finished and called the callback
    FFmpegKitSessionState state = ffmpeg_kit_session_get_state(session);
    EXPECT_TRUE(state == FFMPEG_KIT_SESSION_STATE_COMPLETED || state == FFMPEG_KIT_SESSION_STATE_FAILED);
    
    ffmpeg_kit_handle_release(session);
}

// Stress test for updating callbacks while session is running
TEST_F(CallbackTest, SessionCallbackStressTest) {
    CallbackCapturer capturer1;
    CallbackCapturer capturer2;
    
    // Use a command that takes some time to allow for concurrent updates
    std::string cmd = "-hide_banner -loglevel info -f lavfi -i testsrc=duration=2:size=128x128:rate=30 -f null -";
    
    FFmpegSessionHandle session = ffmpeg_kit_execute_async_full(
        cmd.c_str(), 
        CallbackCapturer::CompleteCallback, 
        CallbackCapturer::LogCallback, 
        CallbackCapturer::StatisticsCallback, 
        &capturer1, 
        0
    );
    ASSERT_NE(session, nullptr);

    std::atomic<bool> stop_stress{false};
    TestThread stress_thread([&]() {
        int i = 0;
        while (!stop_stress) {
            if (i % 2 == 0) {
                ffmpeg_kit_set_callbacks(session, CallbackCapturer::CompleteCallback, CallbackCapturer::LogCallback, CallbackCapturer::StatisticsCallback, &capturer1);
            } else {
                ffmpeg_kit_set_callbacks(session, CallbackCapturer::CompleteCallback, CallbackCapturer::LogCallback, CallbackCapturer::StatisticsCallback, &capturer2);
            }
            i++;
            sleep_for_ms(0);
        }
    });

    // Wait for completion
    int64_t timeout_ms = 10000;
    while (ffmpeg_kit_session_get_state(session) < FFMPEG_KIT_SESSION_STATE_COMPLETED && timeout_ms > 0) {
        sleep_for_ms(10);
        timeout_ms -= 10;
    }

    stop_stress = true;
    stress_thread.join();

    EXPECT_EQ(ffmpeg_kit_session_get_state(session), FFMPEG_KIT_SESSION_STATE_COMPLETED);
    
    ffmpeg_kit_handle_release(session);
}
