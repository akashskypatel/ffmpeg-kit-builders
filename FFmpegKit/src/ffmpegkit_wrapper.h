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

#ifndef FFMPEG_KIT_WRAPPER_H
#define FFMPEG_KIT_WRAPPER_H

#include "ffmpeg_tls.h"
#include <stdbool.h>
#include <stdint.h>

#ifndef FFMPEG_KIT_C_EXPORT
#if defined(_WIN32)
#define FFMPEG_KIT_C_EXPORT __declspec(dllexport)
#else
#define FFMPEG_KIT_C_EXPORT                                                    \
  __attribute__((visibility("default"))) __attribute__((used))
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handles
/**
 * @brief Opaque FFmpeg session handle used to reference a specific FFmpeg session
 * 
 */
typedef void *FFmpegSessionHandle;
/**
 * @brief Opaque FFprobe session handle used to reference a specific FFprobe session
 * 
 */
typedef void *FFprobeSessionHandle;
/**
 * @brief Opaque FFplay session handle used to reference a specific FFplay session
 * 
 */
typedef void *FFplaySessionHandle;
/**
 * @brief Opaque media information session handle used to reference a specific media information session
 * 
 */
typedef void *MediaInformationSessionHandle;
/**
 * @brief Opaque media information handle used to reference a specific media information
 * 
 */
typedef void *MediaInformationHandle;
/**
 * @brief Opaque stream information handle used to reference a specific stream information
 * 
 */
typedef void *StreamInformationHandle;
/**
 * @brief Opaque chapter handle used to reference a specific chapter
 * 
 */
typedef void *ChapterHandle;
/**
 * @brief Opaque statistics handle used to reference a specific statistics
 * 
 */
typedef void *StatisticsHandle;

// Callback function types
typedef void (*FFmpegKitCompleteCallback)(FFmpegSessionHandle session,
                                          void *user_data);
/**
 * @brief Log callback function type
 * 
 * @param session The FFmpeg session handle
 * @param log The log message
 * @param user_data User data passed to the callback
 */
typedef void (*FFmpegKitLogCallback)(FFmpegSessionHandle session,
                                     const char *log, void *user_data);
/**
 * @brief Statistics callback function type
 * 
 * @param session The FFmpeg session handle
 * @param time_elapsed Time elapsed in milliseconds
 * @param time Time in milliseconds
 * @param size Size in bytes
 * @param bitrate Bitrate in kbps
 * @param speed Speed in x
 * @param videoFrameNumber Video frame number
 * @param videoFps Video frame rate
 * @param videoQuality Video quality
 * @param dupFrames Duplicate frames
 * @param dropFrames Dropped frames
 * @param user_data User data passed to the callback
 */
typedef void (*FFmpegKitStatisticsCallback)(
    FFmpegSessionHandle session, int64_t time_elapsed, int64_t time,
    int64_t size, double bitrate, double speed, int64_t videoFrameNumber,
    double videoFps, double videoQuality, int64_t dupFrames,
    int64_t dropFrames, void *user_data);
/**
 * @brief FFprobe complete callback function type
 * 
 * @param session The FFprobe session handle
 * @param user_data User data passed to the callback
 */
typedef void (*FFprobeKitCompleteCallback)(FFprobeSessionHandle session,
                                           void *user_data);
/**
 * @brief FFplay complete callback function type
 * 
 * @param session The FFplay session handle
 * @param user_data User data passed to the callback
 */
typedef void (*FFplayKitCompleteCallback)(FFplaySessionHandle session,
                                          void *user_data);
/**
 * @brief Media information session complete callback function type
 * 
 * @param session The media information session handle
 * @param user_data User data passed to the callback
 */
typedef void (*MediaInformationSessionCompleteCallback)(
    MediaInformationSessionHandle session, void *user_data);

/**
 * Frame-ready callback type for desktop (Linux/Windows) video output.
*
 * Fired inside ffplay_step() on every rendered video frame.
 * Pixel format: RGBA8888 — bytes [R][G][B][A] on little-endian, compatible
 * with Flutter's FlutterDesktopPixelBuffer.
 * The pixel buffer is valid only for the duration of the call — copy it
 * (e.g. into a pre-allocated FlutterDesktopPixelBuffer) before returning.
 *
 * WARNING: The callback is invoked while the internal ffplay API mutex is
 * held. Do NOT call any ffplay API function (ffplay_pause, ffplay_seek,
 * ffplay_get_position, etc.) from within the callback — doing so will
 * deadlock. Perform only lightweight, non-blocking work (e.g. memcpy into a
 * pre-allocated buffer and signal a separate rendering thread).
 *
 * Not used on Android; Android video output goes to the ANativeWindow set via
 * ffplay_kit_set_android_surface_ptr().
 *
 * @param userdata  opaque pointer registered with
 * ffplay_kit_register_frame_callback()
 * @param pixels    RGBA8888 pixels, width*4 bytes per row (linesize == width*4)
 * @param width     frame width in pixels
 * @param height    frame height in pixels
 * @param linesize  bytes per row
 * @param format    pixel format string (e.g., "rgba", "bgra", etc.)
 */
typedef void (*FFplayKitFrameCallback)(void *userdata, const uint8_t *pixels,
                                       int width, int height, int linesize,
                                       const char *format);

// Enums
typedef enum {
  FFMPEG_KIT_SESSION_STATE_CREATED = 0,
  FFMPEG_KIT_SESSION_STATE_RUNNING = 1,
  FFMPEG_KIT_SESSION_STATE_COMPLETED = 2,
  FFMPEG_KIT_SESSION_STATE_FAILED = 3
} FFmpegKitSessionState;

typedef enum {
  FFMPEG_KIT_LOG_LEVEL_STDERR = -16,
  FFMPEG_KIT_LOG_LEVEL_QUIET = -8,
  FFMPEG_KIT_LOG_LEVEL_PANIC = 0,
  FFMPEG_KIT_LOG_LEVEL_FATAL = 8,
  FFMPEG_KIT_LOG_LEVEL_ERROR = 16,
  FFMPEG_KIT_LOG_LEVEL_WARNING = 24,
  FFMPEG_KIT_LOG_LEVEL_INFO = 32,
  FFMPEG_KIT_LOG_LEVEL_VERBOSE = 40,
  FFMPEG_KIT_LOG_LEVEL_DEBUG = 48,
  FFMPEG_KIT_LOG_LEVEL_TRACE = 56,
  FFMPEG_KIT_LOG_LEVEL_AV_LOG_MAX_OFFSET = 10
} FFmpegKitLogLevel;

typedef enum {
  FFMPEG_KIT_LOG_REDIRECTION_STRATEGY_ALWAYS_PRINT_LOGS = 0,
  FFMPEG_KIT_LOG_REDIRECTION_STRATEGY_PRINT_LOGS_WHEN_NO_CALLBACK_DEFINED = 1,
  FFMPEG_KIT_LOG_REDIRECTION_STRATEGY_PRINT_LOGS_WHEN_GLOBAL_CALLBACK_NOT_DEFINED =
      2,
  FFMPEG_KIT_LOG_REDIRECTION_STRATEGY_PRINT_LOGS_WHEN_SESSION_CALLBACK_NOT_DEFINED =
      3,
  FFMPEG_KIT_LOG_REDIRECTION_STRATEGY_NEVER_PRINT_LOGS = 4
} FFmpegKitLogRedirectionStrategy;

typedef enum {
  FFMPEG_KIT_SIGNAL_SIGINT,
  FFMPEG_KIT_SIGNAL_SIGQUIT,
  FFMPEG_KIT_SIGNAL_SIGPIPE,
  FFMPEG_KIT_SIGNAL_SIGTERM,
  FFMPEG_KIT_SIGNAL_SIGXCPU
} FFmpegKitSignal;

/* FFmpegKit (FFmpeg Execution) */

/**
 * Initializes the library and FFmpeg backend.
 * Should be called once immediately after loading the DLL.
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_initialize();

/**
 * Returns a NUL-terminated build-stamp string of the form
 * "YYYY-MM-DD HH:MM:SS" (compile-time __DATE__ and __TIME__).
 *
 * Call this immediately after loading the DLL to confirm you are running the
 * expected build.  If this symbol itself is missing the DLL is too old.
 */
FFMPEG_KIT_C_EXPORT const char *ffmpeg_kit_get_build_stamp(void);

/**
 * Executes the given FFmpeg command.
 *
 * @param command the FFmpeg command to execute
 * @return the FFmpeg session handle
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle ffmpeg_kit_execute(const char *command);

/**
 * Executes the given FFmpeg command asynchronously.
 *
 * @param command the FFmpeg command to execute
 * @param complete_cb the callback to be called when the FFmpeg session is
 * completed
 * @param user_data the user data to be passed to the callback
 * @return the FFmpeg session handle
 * @note The user data is owned by the callback and should be freed by the
 * callback owner including the handle.
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle ffmpeg_kit_execute_async(
    const char *command, FFmpegKitCompleteCallback complete_cb,
    void *user_data);

/**
 * Executes the given FFmpeg command asynchronously.
 *
 * @param command the FFmpeg command to execute
 * @param complete_cb the callback to be called when the FFmpeg session is
 * completed
 * @param log_cb the callback to be called when a log is generated
 * @param stats_cb the callback to be called when statistics are generated
 * @param user_data the user data to be passed to the callback
 * @param waitTimeout the timeout in milliseconds
 * @return the FFmpeg session handle
 * @note The user data is owned by the callback and should be freed by the
 * callback owner including the handle.
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle ffmpeg_kit_execute_async_full(
    const char *command, FFmpegKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, FFmpegKitStatisticsCallback stats_cb,
    void *user_data, int64_t waitTimeout);

/**
 * Cancels all running FFmpeg sessions.
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_cancel(void);

/**
 * Cancels the FFmpeg session with the given session ID.
 *
 * @param session_id the session ID of the FFmpeg session to cancel
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_cancel_session(int64_t session_id);

// Session Creation and Execution Separation

/**
 * Creates a new FFmpeg session with the given command.
 *
 * @param command the FFmpeg command to execute
 * @return the FFmpeg session handle
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle
ffmpeg_kit_create_session(const char *command);

/**
 * Creates a new FFmpeg session with the given command.
 *
 * @param command the FFmpeg command to execute
 * @return the FFmpeg session handle
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle
ffmpeg_kit_create_session_with_callbacks(const char *command,
                                         FFmpegKitCompleteCallback complete_cb,
                                         FFmpegKitLogCallback log_cb,
                                         FFmpegKitStatisticsCallback stats_cb,
                                         void *user_data);

/**
 * Creates a new FFmpeg session with the given argument array.
 * This function prevents C++ objects from crossing the DLL boundary.
 *
 * @param argc the number of arguments
 * @param argv the argument array
 * @return the FFmpeg session handle
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle
ffmpeg_kit_create_session_from_argv(int argc, const char **argv);

/**
 * Creates a new FFmpeg session with the given argument array and callbacks.
 * This function prevents C++ objects from crossing the DLL boundary.
 *
 * @param argc the number of arguments
 * @param argv the argument array
 * @param complete_cb the callback to be called when the FFmpeg session is
 * completed
 * @param log_cb the callback to be called when a log is generated
 * @param stats_cb the callback to be called when statistics are generated
 * @param user_data the user data to be passed to the callbacks
 * @return the FFmpeg session handle
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle
ffmpeg_kit_create_session_from_argv_with_callbacks(
    int argc, const char **argv, FFmpegKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, FFmpegKitStatisticsCallback stats_cb,
    void *user_data);

/**
 * Closes and releases a session created by ffmpeg_kit_create_session_from_argv.
 *
 * @param handle the session handle to close
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_close_session(FFmpegSessionHandle handle);

/**
 * Debug function to verify stack alignment.
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_debug_print_stack();

/**
 * Emits a synthetic unattributed log through the shared FFmpeg log callback.
 *
 * Test-only helper used by wrapper regression tests to verify that callbacks
 * routed to session `0` do not interfere with real session completion.
 *
 * @param message the message to emit
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_test_emit_unattributed_log(const char *message);
/**
 * Sets the log callback for all FFmpeg sessions.
 *
 * @param log_cb the callback to be called when a log is generated
 * @param user_data the user data to be passed to the callback
 */
void FFMPEG_KIT_C_EXPORT ffmpeg_kit_set_log_callback(
    FFmpegSessionHandle session, FFmpegKitLogCallback log_cb, void *user_data);

/**
 * Sets the statistics callback for all FFmpeg sessions.
 *
 * @param stats_cb the callback to be called when statistics are generated
 * @param user_data the user data to be passed to the callback
 */
void FFMPEG_KIT_C_EXPORT ffmpeg_kit_set_statistics_callback(
    FFmpegSessionHandle session, FFmpegKitStatisticsCallback stats_cb,
    void *user_data);

/**
 * Sets the complete callback for all FFmpeg sessions.
 *
 * @param complete_cb the callback to be called when the FFmpeg session is
 * completed
 * @param user_data the user data to be passed to the callback
 */
void FFMPEG_KIT_C_EXPORT ffmpeg_kit_set_complete_callback(
    FFmpegSessionHandle session, FFmpegKitCompleteCallback complete_cb,
    void *user_data);

/**
 * Sets the complete callback, log callback, statistics callback, and user data
 * for all FFmpeg sessions.
 *
 * @param complete_cb the callback to be called when the FFmpeg session is
 * completed
 * @param log_cb the callback to be called when a log is generated
 * @param stats_cb the callback to be called when statistics are generated
 * @param user_data the user data to be passed to the callbacks
 */
void FFMPEG_KIT_C_EXPORT ffmpeg_kit_set_callbacks(
    FFmpegSessionHandle session, FFmpegKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, FFmpegKitStatisticsCallback stats_cb,
    void *user_data);

/**
 * Executes the FFmpeg session.
 *
 * @param session the FFmpeg session to execute
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_session_execute(FFmpegSessionHandle session);

/**
 * Executes the FFmpeg session asynchronously.
 *
 * @param session the FFmpeg session to execute
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_session_execute_async(FFmpegSessionHandle session);

/**
 * Cancels the FFmpeg session.
 *
 * @param session the FFmpeg session to cancel
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_session_cancel(FFmpegSessionHandle session);

/* FFprobeKit (FFprobe Execution) */

/**
 * Executes the given FFprobe command.
 *
 * @param command the FFprobe command to execute
 * @return the FFprobe session handle
 */
FFMPEG_KIT_C_EXPORT FFprobeSessionHandle
ffprobe_kit_execute(const char *command);

/**
 * Executes the given FFprobe command asynchronously.
 *
 * @param command the FFprobe command to execute
 * @param complete_cb the callback to be called when the FFprobe session is
 * completed
 * @param user_data the user data to be passed to the callback
 * @return the FFprobe session handle
 * @note The user data is owned by the callback and should be freed by the
 * callback owner including the handle.
 */
FFMPEG_KIT_C_EXPORT FFprobeSessionHandle ffprobe_kit_execute_async(
    const char *command, FFprobeKitCompleteCallback complete_cb,
    void *user_data);

/**
 * Cancels all running FFprobe sessions.
 */
FFMPEG_KIT_C_EXPORT void ffprobe_kit_cancel(void);

/**
 * Cancels the FFprobe session with the given session ID.
 *
 * @param session_id the session ID of the FFprobe session to cancel
 */
FFMPEG_KIT_C_EXPORT void ffprobe_kit_cancel_session(int64_t session_id);

// FFprobe Session Creation and Execution Separation

/**
 * Creates a new FFprobe session with the given command.
 *
 * @param command the FFprobe command to execute
 * @return the FFprobe session handle
 */
FFMPEG_KIT_C_EXPORT FFprobeSessionHandle
ffprobe_kit_create_session(const char *command);

/**
 * Creates a new FFprobe session with the given command.
 *
 * @param command the FFprobe command to execute
 * @return the FFprobe session handle
 */
FFMPEG_KIT_C_EXPORT FFprobeSessionHandle
ffprobe_kit_create_session_with_callbacks(
    const char *command, FFprobeKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data);

/**
 * Creates a new FFprobe session with the given argument array.
 * This function prevents C++ objects from crossing the DLL boundary.
 *
 * @param argc the number of arguments
 * @param argv the argument array
 * @return the FFprobe session handle
 */
FFMPEG_KIT_C_EXPORT FFprobeSessionHandle
ffprobe_kit_create_session_from_argv(int argc, const char **argv);

/**
 * Creates a new FFprobe session with the given argument array and callbacks.
 * This function prevents C++ objects from crossing the DLL boundary.
 *
 * @param argc the number of arguments
 * @param argv the argument array
 * @param complete_cb the callback to be called when the FFprobe session is
 * completed
 * @param log_cb the callback to be called when a log is generated
 * @param user_data the user data to be passed to the callbacks
 * @return the FFprobe session handle
 */
FFMPEG_KIT_C_EXPORT FFprobeSessionHandle
ffprobe_kit_create_session_from_argv_with_callbacks(
    int argc, const char **argv, FFprobeKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data);

/**
 * Closes and releases a session created by
 * ffprobe_kit_create_session_from_argv.
 *
 * @param handle the session handle to close
 */
FFMPEG_KIT_C_EXPORT void ffprobe_kit_close_session(FFprobeSessionHandle handle);

/**
 * Sets the log callback for all FFprobe sessions.
 *
 * @param log_cb the callback to be called when a log is generated
 * @param user_data the user data to be passed to the callback
 */
void FFMPEG_KIT_C_EXPORT ffprobe_kit_set_log_callback(
    FFprobeSessionHandle session, FFmpegKitLogCallback log_cb, void *user_data);

/**
 * Sets the complete callback for all FFprobe sessions.
 *
 * @param complete_cb the callback to be called when the FFprobe session is
 * completed
 * @param user_data the user data to be passed to the callback
 */
void FFMPEG_KIT_C_EXPORT ffprobe_kit_set_complete_callback(
    FFprobeSessionHandle session, FFprobeKitCompleteCallback complete_cb,
    void *user_data);

/**
 * Sets the complete callback, log callback, and user data for all FFprobe
 * sessions.
 *
 * @param complete_cb the callback to be called when the FFprobe session is
 * completed
 * @param log_cb the callback to be called when a log is generated
 * @param user_data the user data to be passed to the callbacks
 */
void FFMPEG_KIT_C_EXPORT ffprobe_kit_set_callbacks(
    FFprobeSessionHandle session, FFprobeKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data);

/**
 * Executes the FFprobe session.
 *
 * @param session the FFprobe session to execute
 */
FFMPEG_KIT_C_EXPORT void
ffprobe_kit_session_execute(FFprobeSessionHandle session);

/**
 * Executes the FFprobe session asynchronously.
 *
 * @param session the FFprobe session to execute
 */
FFMPEG_KIT_C_EXPORT void
ffprobe_kit_session_execute_async(FFprobeSessionHandle session);

/**
 * Gets the media information for the given path.
 *
 * @param path the path of the media file
 * @return the media information session handle
 */
FFMPEG_KIT_C_EXPORT MediaInformationSessionHandle
ffprobe_kit_get_media_information(const char *path);

/**
 * Gets the media information for the given path asynchronously.
 *
 * @param path the path of the media file
 * @param complete_cb the callback to be called when the media information
 * session is completed
 * @param user_data the user data to be passed to the callback
 * @return the media information session handle
 * @note The user data is owned by the callback and should be freed by the
 * callback owner including the handle.
 */
FFMPEG_KIT_C_EXPORT MediaInformationSessionHandle
ffprobe_kit_get_media_information_async(
    const char *path, MediaInformationSessionCompleteCallback complete_cb,
    void *user_data);

/* FFplayKit (FFplay Execution) */

/**
 * Executes the given FFplay command.
 *
 * @param command the FFplay command to execute
 * @param timeout the timeout in milliseconds
 * @return the FFplay session handle
 */
FFMPEG_KIT_C_EXPORT FFplaySessionHandle ffplay_kit_execute(const char *command,
                                                           int64_t timeout);

/**
 * Executes the given FFplay command asynchronously.
 *
 * @param command the FFplay command to execute
 * @param complete_cb the callback to be called when the FFplay session is
 * completed
 * @param user_data the user data to be passed to the callback
 * @param waitTimeout the timeout in milliseconds
 * @return the FFplay session handle
 * @note The user data is owned by the callback and should be freed by the
 * callback owner including the handle.
 */
FFMPEG_KIT_C_EXPORT FFplaySessionHandle ffplay_kit_execute_async(
    const char *command, FFplayKitCompleteCallback complete_cb, void *user_data,
    int64_t waitTimeout);

// FFplay Session Creation and Execution Separation

/**
 * Creates a new FFplay session with the given command.
 *
 * @param command the FFplay command to execute
 * @return the FFplay session handle
 */
FFMPEG_KIT_C_EXPORT FFplaySessionHandle
ffplay_kit_create_session(const char *command);

/**
 * Creates a new FFplay session with the given command.
 *
 * @param command the FFplay command to execute
 * @return the FFplay session handle
 */
FFMPEG_KIT_C_EXPORT FFplaySessionHandle
ffplay_kit_create_session_with_callbacks(const char *command,
                                         FFplayKitCompleteCallback complete_cb,
                                         FFmpegKitLogCallback log_cb,
                                         void *user_data);

/**
 * Creates a new FFplay session with the given argument array.
 * This function prevents C++ objects from crossing the DLL boundary.
 *
 * @param argc the number of arguments
 * @param argv the argument array
 * @return the FFplay session handle
 */
FFMPEG_KIT_C_EXPORT FFplaySessionHandle
ffplay_kit_create_session_from_argv(int argc, const char **argv);

/**
 * Creates a new FFplay session with the given argument array and callbacks.
 * This function prevents C++ objects from crossing the DLL boundary.
 *
 * @param argc the number of arguments
 * @param argv the argument array
 * @param complete_cb the callback to be called when the FFplay session is
 * completed
 * @param log_cb the callback to be called when a log is generated
 * @param user_data the user data to be passed to the callbacks
 * @return the FFplay session handle
 */
FFMPEG_KIT_C_EXPORT FFplaySessionHandle
ffplay_kit_create_session_from_argv_with_callbacks(
    int argc, const char **argv, FFplayKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data);

/**
 * Closes and releases a session created by ffplay_kit_create_session_from_argv.
 *
 * @param handle the session handle to close
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_close_session(FFplaySessionHandle handle);

/**
 * Sets the log callback for all FFplay sessions.
 *
 * @param log_cb the callback to be called when a log is generated
 * @param user_data the user data to be passed to the callback
 */
void FFMPEG_KIT_C_EXPORT ffplay_kit_set_log_callback(
    FFplaySessionHandle session, FFmpegKitLogCallback log_cb, void *user_data);

/**
 * Sets the complete callback for all FFplay sessions.
 *
 * @param complete_cb the callback to be called when the FFplay session is
 * completed
 * @param user_data the user data to be passed to the callback
 */
void FFMPEG_KIT_C_EXPORT ffplay_kit_set_complete_callback(
    FFplaySessionHandle session, FFplayKitCompleteCallback complete_cb,
    void *user_data);

/**
 * Sets the complete callback, log callback, and user data for all FFplay
 * sessions.
 *
 * @param complete_cb the callback to be called when the FFplay session is
 * completed
 * @param log_cb the callback to be called when a log is generated
 * @param user_data the user data to be passed to the callbacks
 */
void FFMPEG_KIT_C_EXPORT ffplay_kit_set_callbacks(
    FFplaySessionHandle session, FFplayKitCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data);

/**
 * Executes the FFplay session.
 *
 * @param session the FFplay session to execute
 * @param timeout the timeout in milliseconds
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_session_execute(FFplaySessionHandle session,
                                                    int64_t timeout);

/**
 * Gets the current FFplay session.
 *
 * @return the FFplay session handle
 */
FFMPEG_KIT_C_EXPORT FFplaySessionHandle ffplay_kit_get_current_session(void);

/**
 * Executes the FFplay session asynchronously.
 *
 * @param session the FFplay session to execute
 * @param timeout the timeout in milliseconds
 */
FFMPEG_KIT_C_EXPORT void
ffplay_kit_session_execute_async(FFplaySessionHandle session, int64_t timeout);

/**
 * Seeks to the given position in the FFplay session.
 *
 * @param session the FFplay session to seek
 * @param seconds the position to seek to
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_session_seek(FFplaySessionHandle session,
                                                 double seconds);

/**
 * Starts the FFplay session.
 *
 * @param session the FFplay session to start
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_session_start(FFplaySessionHandle session);

/**
 * Pauses the FFplay session.
 *
 * @param session the FFplay session to pause
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_session_pause(FFplaySessionHandle session);

/**
 * Resumes the FFplay session.
 *
 * @param session the FFplay session to resume
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_session_resume(FFplaySessionHandle session);

/**
 * Stops the FFplay session.
 *
 * @param session the FFplay session to stop
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_session_stop(FFplaySessionHandle session);

/**
 * Closes the FFplay session.
 *
 * @param session the FFplay session to close
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_session_close(FFplaySessionHandle session);

/**
 * Gets the position of the FFplay session.
 *
 * @param session the FFplay session to get the position of
 * @return the position of the FFplay session
 */
FFMPEG_KIT_C_EXPORT double
ffplay_kit_session_get_position(FFplaySessionHandle session);

/**
 * Sets the position of the FFplay session.
 *
 * @param session the FFplay session to set the position of
 * @param seconds the position to set
 */
FFMPEG_KIT_C_EXPORT void
ffplay_kit_session_set_position(FFplaySessionHandle session, double seconds);

/**
 * Gets the duration of the FFplay session.
 *
 * @param session the FFplay session to get the duration of
 * @return the duration of the FFplay session
 */
FFMPEG_KIT_C_EXPORT double
ffplay_kit_session_get_duration(FFplaySessionHandle session);

/**
 * Returns the video width of the FFplay session in pixels.
 * Returns 0 if no video stream is active yet.
 *
 * @param session the FFplay session
 * @return video width in pixels, or 0
 */
FFMPEG_KIT_C_EXPORT int
ffplay_kit_session_get_video_width(FFplaySessionHandle session);

/**
 * Returns the video height of the FFplay session in pixels.
 * Returns 0 if no video stream is active yet.
 *
 * @param session the FFplay session
 * @return video height in pixels, or 0
 */
FFMPEG_KIT_C_EXPORT int
ffplay_kit_session_get_video_height(FFplaySessionHandle session);

/**
 * Checks if the FFplay session is playing.
 *
 * @param session the FFplay session to check
 * @return true if the FFplay session is playing, false otherwise
 */
FFMPEG_KIT_C_EXPORT bool
ffplay_kit_session_is_playing(FFplaySessionHandle session);

/**
 * Checks if the FFplay session is paused.
 *
 * @param session the FFplay session to check
 * @return true if the FFplay session is paused, false otherwise
 */
FFMPEG_KIT_C_EXPORT bool
ffplay_kit_session_is_paused(FFplaySessionHandle session);

/**
 * Sets the volume of the FFplay session.
 *
 * @param session the FFplay session to set the volume of
 * @param volume the volume to set
 */
FFMPEG_KIT_C_EXPORT void
ffplay_kit_session_set_volume(FFplaySessionHandle session, double volume);

/**
 * Gets the volume of the FFplay session.
 *
 * @param session the FFplay session to get the volume of
 * @return volume in [0.0, 1.0], or -1.0 if the session handle is invalid or
 *         the native playback context is not yet ready (called before the
 *         session has started executing, or after it has completed).
 *         Callers should treat any negative value as "not available" and
 *         fall back to a cached or default value.
 */
FFMPEG_KIT_C_EXPORT double
ffplay_kit_session_get_volume(FFplaySessionHandle session);

/* FFplayKit Global Proxies */

/**
 * Seeks to the given position in the current FFplay session.
 *
 * @param seconds the position in seconds
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_seek(double seconds);

/**
 * Starts the current FFplay session.
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_start(void);

/**
 * Pauses the current FFplay session.
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_pause(void);

/**
 * Resumes the current FFplay session.
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_resume(void);

/**
 * Stops the current FFplay session.
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_stop(void);

/**
 * Closes the current FFplay session.
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_close(void);

/**
 * Returns the position of the current FFplay session.
 *
 * @return the position in seconds
 */
FFMPEG_KIT_C_EXPORT double ffplay_kit_get_position(void);

/**
 * Sets the position of the current FFplay session.
 *
 * @param seconds the position in seconds
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_set_position(double seconds);

/**
 * Returns the duration of the current FFplay session.
 *
 * @return the duration in seconds
 */
FFMPEG_KIT_C_EXPORT double ffplay_kit_get_duration(void);

/**
 * Checks if the current FFplay session is playing.
 *
 * @return true if playing, false otherwise
 */
FFMPEG_KIT_C_EXPORT bool ffplay_kit_is_playing(void);

/**
 * Checks if the current FFplay session is paused.
 *
 * @return true if paused, false otherwise
 */
FFMPEG_KIT_C_EXPORT bool ffplay_kit_is_paused(void);

/**
 * Sets the volume of the current FFplay session.
 *
 * @param volume the volume (0.0 to 1.0)
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_set_volume(double volume);

/**
 * Gets the volume of the current FFplay session.
 *
 * @return volume in [0.0, 1.0], or -1.0 if there is no active session or
 *         the native context is not yet ready. See
 * ffplay_kit_session_get_volume.
 */
FFMPEG_KIT_C_EXPORT double ffplay_kit_get_volume(void);

/**
 * Sets the Android ANativeWindow for FFplay video output.
 *
 * Pass the ANativeWindow* obtained via ANativeWindow_fromSurface() cast to
 * int64_t. On Android this must be called before executing an FFplay session;
 * on all other platforms this function is a no-op.
 *
 * The caller is responsible for ensuring the window remains valid for the
 * duration of playback. Call ffplay_kit_clear_android_surface() when the
 * Surface is destroyed to avoid use-after-free.
 *
 * Dart bridge: use FFplayKitAndroid.setAndroidSurface(nativeWindowPtr).
 *
 * @param native_window_ptr ANativeWindow* cast to int64_t, or 0 to clear
 */
FFMPEG_KIT_C_EXPORT void
ffplay_kit_set_android_surface_ptr(int64_t native_window_ptr);

/**
 * Clears the Android ANativeWindow, stopping video output.
 *
 * Call when the Surface is destroyed (e.g. in surfaceDestroyed()).
 * Equivalent to ffplay_kit_set_android_surface_ptr(0).
 * On non-Android platforms this is a no-op.
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_clear_android_surface(void);

/**
 * Registers a global frame-ready callback for desktop video output
 * (Linux/Windows).
 *
 * Must be called before ffplay_kit_session_execute() / ffplay_kit_execute().
 * On Android this is a no-op; video output is delivered to the ANativeWindow.
 *
 * Dart FFI usage:
 *   ffplay_kit_register_frame_callback(Pointer.fromFunction(myCallback),
 * nullptr);
 *
 * @param callback  frame callback function; NULL clears any previous
 * registration
 * @param userdata  opaque pointer forwarded to every callback invocation
 */
FFMPEG_KIT_C_EXPORT void
ffplay_kit_register_frame_callback(FFplayKitFrameCallback callback,
                                   void *userdata);

/**
 * Clears the global frame callback, stopping desktop pixel delivery.
 * Equivalent to ffplay_kit_register_frame_callback(NULL, NULL).
 * On Android this is a no-op.
 */
FFMPEG_KIT_C_EXPORT void ffplay_kit_unregister_frame_callback(void);

/**
 * Probes [path] for at least one video stream without decoding.
 * Uses avformat_open_input + avformat_find_stream_info. Thread-safe.
 *
 * @param path  UTF-8 file path or URL
 * @return  1 video present, 0 audio-only, -1 on error
 */
FFMPEG_KIT_C_EXPORT int ffplay_kit_has_video_stream(const char *path);

/* Config & Global Functions */

/**
 * Enables redirection of FFmpeg output to files.
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_config_enable_redirection(void);

/**
 * Disables redirection of FFmpeg output to files.
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_config_disable_redirection(void);

/**
 * Sets the log level for FFmpegKit.
 *
 * @param level the log level to set
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_config_set_log_level(FFmpegKitLogLevel level);

/**
 * Gets the log level for FFmpegKit.
 *
 * @return the log level for FFmpegKit
 */
FFMPEG_KIT_C_EXPORT FFmpegKitLogLevel ffmpeg_kit_config_get_log_level(void);

/**
 * Converts the log level to a string.
 *
 * @param level the log level to convert
 * @return the string representation of the log level
 */
FFMPEG_KIT_C_EXPORT char *
ffmpeg_kit_config_log_level_to_string(FFmpegKitLogLevel level);

/**
 * Sets the font directory for FFmpegKit.
 *
 * @param path the path to the font directory
 * @param name_mappings_json the name mappings JSON
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_config_set_font_directory(
    const char *path,
    const char *name_mappings_json); // Simplified mapping

/**
 * Sets an environment variable for FFmpegKit.
 *
 * @param name the name of the environment variable
 * @param value the value of the environment variable
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_config_set_environment_variable(const char *name, const char *value);

/**
 * Ignores the given signal for FFmpegKit.
 *
 * @param signal the signal to ignore
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_config_ignore_signal(FFmpegKitSignal signal);

/**
 * Gets the FFmpeg version.
 *
 * @return the FFmpeg version
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_config_get_ffmpeg_version(void);

/**
 * Gets the architecture of FFmpeg bundled within FFmpegKit library.
 *
 * @return the architecture of FFmpeg
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_config_get_ffmpeg_architecture(void);

/**
 * Gets the version of FFmpegKit.
 *
 * @return the version of FFmpegKit
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_config_get_version(void);

/**
 * Sets the audio output device for the ffplay session.
 *
 * @param device_name the name of the audio output device
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_config_set_audio_output_device(const char *device_name);

/**
 * Returns a semi-colon separated list of audio output devices.
 *
 * @return a semi-colon separated list of audio output devices
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_config_list_audio_output_devices(void);

/* Packages */

/**
 * Gets the name of the package.
 *
 * @return the name of the package
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_packages_get_package_name(void);

/**
 * Gets the external libraries bundled within FFmpegKit library.
 *
 * @return the external libraries for the package
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_packages_get_external_libraries(void);

/**
 * Gets the FFmpegKit bundle type.
 *
 * @return the bundle type
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_packages_get_bundle_type(void);

/**
 * Gets whether GPL is enabled.
 *
 * @return 1 if GPL is enabled, 0 otherwise
 */
FFMPEG_KIT_C_EXPORT bool ffmpeg_kit_packages_get_is_gpl(void);

/**
 * Gets whether non-free is enabled.
 *
 * @return 1 if non-free is enabled, 0 otherwise
 */
FFMPEG_KIT_C_EXPORT bool ffmpeg_kit_packages_get_is_nonfree(void);

/**
 * Gets all registered codecs.
 *
 * @return comma-separated list of codec names
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_packages_get_registered_codecs(void);

/**
 * Gets all registered encoders.
 *
 * @return comma-separated list of encoder names
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_packages_get_registered_encoders(void);

/**
 * Gets all registered decoders.
 *
 * @return comma-separated list of decoder names
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_packages_get_registered_decoders(void);

/**
 * Gets all registered muxers.
 *
 * @return comma-separated list of muxer names
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_packages_get_registered_muxers(void);

/**
 * Gets all registered demuxers.
 *
 * @return comma-separated list of demuxer names
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_packages_get_registered_demuxers(void);

/**
 * Gets all registered filters.
 *
 * @return comma-separated list of filter names
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_packages_get_registered_filters(void);

/**
 * Gets all registered protocols.
 *
 * @return comma-separated list of protocol names
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_packages_get_registered_protocols(void);

/**
 * Gets all registered bitstream filters.
 *
 * @return comma-separated list of bitstream filter names
 */
FFMPEG_KIT_C_EXPORT char *
ffmpeg_kit_packages_get_registered_bitstream_filters(void);

/**
 * Gets the FFmpeg build configuration.
 *
 * @return the build configuration string
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_packages_get_build_configuration(void);

/* Session Management (Base) */

/**
 * Gets the session ID.
 *
 * @param session_handle the session handle
 * @return the session ID
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_session_get_session_id(void *session_handle);

/**
 * Gets the state of the session.
 *
 * @param session_handle the session handle
 * @return the state of the session
 */
FFMPEG_KIT_C_EXPORT FFmpegKitSessionState
ffmpeg_kit_session_get_state(void *session_handle);

/**
 * Gets the return code of the session.
 *
 * @param session_handle the session handle
 * @return the return code of the session
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_session_get_return_code(void *session_handle);

/**
 * Gets the output of the session.
 *
 * @param session_handle the session handle
 * @return the output of the session
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_session_get_output(void *session_handle);

/**
 * Gets the logs of the session as a string.
 *
 * @param session_handle the session handle
 * @return the logs of the session as a string
 */
FFMPEG_KIT_C_EXPORT char *
ffmpeg_kit_session_get_logs_as_string(void *session_handle);

/**
 * Gets the fail stack trace of the session.
 *
 * @param session_handle the session handle
 * @return the fail stack trace of the session
 */
FFMPEG_KIT_C_EXPORT char *
ffmpeg_kit_session_get_fail_stack_trace(void *session_handle);

// Generic release for any opaque handle created by this wrapper
/**
 * Releases the handle.
 *
 * @param handle the handle to release
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_handle_release(void *handle);

/**
 * Clears all active and history sessions.
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_config_clear_sessions();

/* MediaInformation Session specific */

/**
 * Creates a new MediaInformation session with the given command.
 *
 * @param command the MediaInformation command to execute
 * @return the MediaInformation session handle
 */
FFMPEG_KIT_C_EXPORT MediaInformationSessionHandle
media_information_create_session(const char *command);

/**
 * Creates a new MediaInformation session from an argument array.
 * Each argument is copied verbatim and no command-string parsing is
 * performed.
 *
 * @param argc the number of arguments
 * @param argv the argument array
 * @return the MediaInformation session handle
 */
FFMPEG_KIT_C_EXPORT MediaInformationSessionHandle
media_information_create_session_from_argv(int argc,
                                           const char **argv);

/**
 * Creates a new MediaInformation session with the given command.
 *
 * @param command the MediaInformation command to execute
 * @return the MediaInformation session handle
 */
FFMPEG_KIT_C_EXPORT MediaInformationSessionHandle
media_information_create_session_with_callbacks(
    const char *command, MediaInformationSessionCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data);

/**
 * Sets the log callback for all MediaInformation sessions.
 *
 * @param log_cb the callback to be called when a log is generated
 * @param user_data the user data to be passed to the callback
 */
void FFMPEG_KIT_C_EXPORT media_information_kit_set_log_callback(
    MediaInformationSessionHandle session, FFmpegKitLogCallback log_cb,
    void *user_data);

/**
 * Sets the complete callback for all MediaInformation sessions.
 *
 * @param complete_cb the callback to be called when the MediaInformation
 * session is completed
 * @param user_data the user data to be passed to the callback
 */
void FFMPEG_KIT_C_EXPORT media_information_kit_set_complete_callback(
    MediaInformationSessionHandle session,
    MediaInformationSessionCompleteCallback complete_cb, void *user_data);

/**
 * Sets the complete callback, log callback, and user data for all
 * MediaInformation sessions.
 *
 * @param complete_cb the callback to be called when the MediaInformation
 * session is completed
 * @param log_cb the callback to be called when a log is generated
 * @param user_data the user data to be passed to the callbacks
 */
void FFMPEG_KIT_C_EXPORT media_information_kit_set_callbacks(
    MediaInformationSessionHandle session,
    MediaInformationSessionCompleteCallback complete_cb,
    FFmpegKitLogCallback log_cb, void *user_data);

/**
 * Executes the MediaInformation session.
 *
 * @param session the MediaInformation session to execute
 * @param timeout the timeout in milliseconds
 */
FFMPEG_KIT_C_EXPORT void
media_information_session_execute(MediaInformationSessionHandle session,
                                  int64_t timeout);

/**
 * Executes the MediaInformation session asynchronously.
 *
 * @param session the MediaInformation session to execute
 * @param timeout the timeout in milliseconds
 */
FFMPEG_KIT_C_EXPORT void
media_information_session_execute_async(MediaInformationSessionHandle session,
                                        int64_t timeout);

/**
 * Gets the media information from the session.
 *
 * @param session the session to get the media information from
 * @return the media information
 */
FFMPEG_KIT_C_EXPORT MediaInformationHandle
media_information_session_get_media_information(
    MediaInformationSessionHandle session);

/* MediaInformation */

/**
 * Gets the filename of the media information.
 *
 * @param handle the media information handle
 * @return the filename of the media information
 */
FFMPEG_KIT_C_EXPORT char *
media_information_get_filename(MediaInformationHandle handle);

/**
 * Gets the format of the media information.
 *
 * @param handle the media information handle
 * @return the format of the media information
 */
FFMPEG_KIT_C_EXPORT char *
media_information_get_format(MediaInformationHandle handle);

/**
 * Gets the int64_t format of the media information.
 *
 * @param handle the media information handle
 * @return the int64_t format of the media information
 */
FFMPEG_KIT_C_EXPORT char *
media_information_get_long_format(MediaInformationHandle handle);

/**
 * Gets the duration of the media information.
 *
 * @param handle the media information handle
 * @return the duration of the media information
 */
FFMPEG_KIT_C_EXPORT char *
media_information_get_duration(MediaInformationHandle handle);

/**
 * Gets the bitrate of the media information.
 *
 * @param handle the media information handle
 * @return the bitrate of the media information
 */
FFMPEG_KIT_C_EXPORT char *
media_information_get_bitrate(MediaInformationHandle handle);

/**
 * Gets the size of the media information.
 *
 * @param handle the media information handle
 * @return the size of the media information
 */
FFMPEG_KIT_C_EXPORT char *
media_information_get_size(MediaInformationHandle handle);

/**
 * Gets the tags of the media information as a JSON string.
 *
 * @param handle the media information handle
 * @return the tags of the media information as a JSON string
 */
FFMPEG_KIT_C_EXPORT char *media_information_get_tags_json(
    MediaInformationHandle handle); // Returns JSON string

/**
 * Gets the number of streams in the media information.
 *
 * @param handle the media information handle
 * @return the number of streams in the media information
 */
FFMPEG_KIT_C_EXPORT int64_t
media_information_get_streams_count(MediaInformationHandle handle);

/**
 * Gets the stream at the given index.
 *
 * @param handle the media information handle
 * @param index the index of the stream
 * @return the stream at the given index
 */
FFMPEG_KIT_C_EXPORT StreamInformationHandle
media_information_get_stream_at(MediaInformationHandle handle, int64_t index);

/**
 * Gets the number of chapters in the media information.
 *
 * @param handle the media information handle
 * @return the number of chapters in the media information
 */
FFMPEG_KIT_C_EXPORT int64_t
media_information_get_chapters_count(MediaInformationHandle handle);

/**
 * Gets the chapter at the given index.
 *
 * @param handle the media information handle
 * @param index the index of the chapter
 * @return the chapter at the given index
 */
FFMPEG_KIT_C_EXPORT ChapterHandle
media_information_get_chapter_at(MediaInformationHandle handle, int64_t index);

/* StreamInformation */

/**
 * Gets the index of the stream information.
 *
 * @param handle the stream information handle
 * @return the index of the stream information
 */
FFMPEG_KIT_C_EXPORT int64_t
stream_information_get_index(StreamInformationHandle handle);

/**
 * Gets the type of the stream information.
 *
 * @param handle the stream information handle
 * @return the type of the stream information
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_type(StreamInformationHandle handle);

/**
 * Gets the codec of the stream information.
 *
 * @param handle the stream information handle
 * @return the codec of the stream information
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_codec(StreamInformationHandle handle);

/**
 * Gets the int64_t codec of the stream information.
 *
 * @param handle the stream information handle
 * @return the int64_t codec of the stream information
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_codec_long(StreamInformationHandle handle);

/**
 * Gets the format of the stream information.
 *
 * @param handle the stream information handle
 * @return the format of the stream information
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_format(StreamInformationHandle handle);

/**
 * Gets the width of the stream information.
 *
 * @param handle the stream information handle
 * @return the width of the stream information
 */
FFMPEG_KIT_C_EXPORT int64_t
stream_information_get_width(StreamInformationHandle handle);

/**
 * Gets the height of the stream information.
 *
 * @param handle the stream information handle
 * @return the height of the stream information
 */
FFMPEG_KIT_C_EXPORT int64_t
stream_information_get_height(StreamInformationHandle handle);

/**
 * Gets the bitrate of the stream information.
 *
 * @param handle the stream information handle
 * @return the bitrate of the stream information
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_bitrate(StreamInformationHandle handle);

/**
 * Gets the sample rate of the stream information.
 *
 * @param handle the stream information handle
 * @return the sample rate of the stream information
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_sample_rate(StreamInformationHandle handle);

/**
 * Gets the sample format of the stream information.
 *
 * @param handle the stream information handle
 * @return the sample format of the stream information
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_sample_format(StreamInformationHandle handle);

/**
 * Gets the display aspect ratio of the stream information.
 *
 * @param handle the stream information handle
 * @return the display aspect ratio of the stream information
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_display_aspect_ratio(StreamInformationHandle handle);

/**
 * Gets the average frame rate of the stream information.
 *
 * @param handle the stream information handle
 * @return the average frame rate of the stream information
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_average_frame_rate(StreamInformationHandle handle);

/**
 * Gets the real frame rate of the stream information.
 *
 * @param handle the stream information handle
 * @return the real frame rate of the stream information
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_real_frame_rate(StreamInformationHandle handle);

/**
 * Gets the time base of the stream information.
 *
 * @param handle the stream information handle
 * @return the time base of the stream information
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_time_base(StreamInformationHandle handle);

/**
 * Gets the tags of the stream information as a JSON string.
 *
 * @param handle the stream information handle
 * @return the tags of the stream information as a JSON string
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_tags_json(StreamInformationHandle handle);

/* Chapter */

/**
 * Gets the ID of the chapter.
 *
 * @param handle the chapter handle
 * @return the ID of the chapter
 */
FFMPEG_KIT_C_EXPORT int64_t chapter_get_id(ChapterHandle handle);

/**
 * Gets the time base of the chapter.
 *
 * @param handle the chapter handle
 * @return the time base of the chapter
 */
FFMPEG_KIT_C_EXPORT char *chapter_get_time_base(ChapterHandle handle);

/**
 * Gets the start of the chapter.
 *
 * @param handle the chapter handle
 * @return the start of the chapter
 */
FFMPEG_KIT_C_EXPORT int64_t chapter_get_start(ChapterHandle handle);

/**
 * Gets the start time of the chapter.
 *
 * @param handle the chapter handle
 * @return the start time of the chapter
 */
FFMPEG_KIT_C_EXPORT char *chapter_get_start_time(ChapterHandle handle);

/**
 * Gets the end of the chapter.
 *
 * @param handle the chapter handle
 * @return the end of the chapter
 */
FFMPEG_KIT_C_EXPORT int64_t chapter_get_end(ChapterHandle handle);

/**
 * Gets the end time of the chapter.
 *
 * @param handle the chapter handle
 * @return the end time of the chapter
 */
FFMPEG_KIT_C_EXPORT char *chapter_get_end_time(ChapterHandle handle);

/**
 * Gets the tags of the chapter as a JSON string.
 *
 * @param handle the chapter handle
 * @return the tags of the chapter as a JSON string
 */
FFMPEG_KIT_C_EXPORT char *chapter_get_tags_json(ChapterHandle handle);

/* Session History */

/**
 * Gets the sessions.
 *
 * @return the sessions
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle *ffmpeg_kit_get_sessions(void);

/**
 * Gets the sessions.
 *
 * @return the sessions
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle *ffmpeg_kit_list_sessions(void);

/**
 * Gets the FFmpeg sessions.
 *
 * @return the FFmpeg sessions
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle *ffmpeg_kit_get_ffmpeg_sessions(void);

/**
 * Gets the FFmpeg sessions.
 *
 * @return the FFmpeg sessions
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle *ffmpeg_kit_get_ffmpeg_sessions(void);

/**
 * Gets the FFprobe sessions.
 *
 * @return the FFprobe sessions
 */
FFMPEG_KIT_C_EXPORT FFprobeSessionHandle *ffmpeg_kit_get_ffprobe_sessions(void);

/**
 * Gets the FFprobe sessions.
 *
 * @return the FFprobe sessions
 */
FFMPEG_KIT_C_EXPORT FFprobeSessionHandle *ffprobe_kit_list_sessions(void);

/**
 * Gets the FFplay sessions.
 *
 * @return the FFplay sessions
 */
FFMPEG_KIT_C_EXPORT FFplaySessionHandle *ffmpeg_kit_get_ffplay_sessions(void);

/**
 * Gets the media information sessions.
 *
 * @return the media information sessions
 */
FFMPEG_KIT_C_EXPORT MediaInformationSessionHandle *
ffmpeg_kit_get_media_information_sessions(void);

/**
 * Gets the media information sessions.
 *
 * @return the media information sessions
 */
FFMPEG_KIT_C_EXPORT MediaInformationSessionHandle *
media_information_kit_list_sessions(void);

/**
 * Gets the session.
 *
 * @param session_id the session ID
 * @return the session
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle
ffmpeg_kit_get_session(int64_t session_id);

/**
 * Gets the last session.
 *
 * @return the last session
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle ffmpeg_kit_get_last_session(void);

/**
 * Gets the last FFmpeg session.
 *
 * @return the last FFmpeg session
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle
ffmpeg_kit_get_last_ffmpeg_session(void);

/**
 * Gets the last FFprobe session.
 *
 * @return the last FFprobe session
 */
FFMPEG_KIT_C_EXPORT FFprobeSessionHandle
ffmpeg_kit_get_last_ffprobe_session(void);

/**
 * Gets the last FFprobe session.
 *
 * @return the last FFprobe session
 */
FFMPEG_KIT_C_EXPORT FFprobeSessionHandle ffprobe_kit_get_last_session(void);

/**
 * Gets the last completed FFprobe session.
 *
 * @return the last completed FFprobe session
 */
FFMPEG_KIT_C_EXPORT FFprobeSessionHandle
ffprobe_kit_get_last_completed_session(void);

/**
 * Gets the last FFplay session.
 *
 * @return the last FFplay session
 */
FFMPEG_KIT_C_EXPORT FFplaySessionHandle
ffmpeg_kit_get_last_ffplay_session(void);

/**
 * Gets the last media information session.
 *
 * @return the last media information session
 */
FFMPEG_KIT_C_EXPORT MediaInformationSessionHandle
ffmpeg_kit_get_last_media_information_session(void);

/**
 * Gets the last completed session.
 *
 * @return the last completed session
 */
FFMPEG_KIT_C_EXPORT FFmpegSessionHandle
ffmpeg_kit_get_last_completed_session(void);

/**
 * Gets the session history size.
 *
 * @return the session history size, should be smaller than 1000
 */
FFMPEG_KIT_C_EXPORT int64_t ffmpeg_kit_get_session_history_size(void);

/**
 * Sets the session history size.
 *
 * @param size the session history size
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_set_session_history_size(int64_t size);

/**
 * Clears the sessions.
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_clear_sessions(void);

/* Global Callbacks */

/**
 * Enables the log callback.
 *
 * @param log_cb the log callback
 * @param user_data the user data
 * @note The user data is owned by the callback and should be freed by the
 * callback owner including the handle.
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_config_enable_log_callback(FFmpegKitLogCallback log_cb,
                                      void *user_data);

/**
 * Enables the statistics callback.
 *
 * @param stats_cb the statistics callback
 * @param user_data the user data
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_config_enable_statistics_callback(
    FFmpegKitStatisticsCallback stats_cb, void *user_data);

/**
 * Enables the FFmpeg session complete callback.
 *
 * @param complete_cb the FFmpeg session complete callback
 * @param user_data the user data
 * @note The user data is owned by the callback and should be freed by the
 * callback owner including the handle.
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_config_enable_ffmpeg_session_complete_callback(
    FFmpegKitCompleteCallback complete_cb, void *user_data);

/**
 * Enables the FFprobe session complete callback.
 *
 * @param complete_cb the FFprobe session complete callback
 * @param user_data the user data
 * @note The user data is owned by the callback and should be freed by the
 * callback owner including the handle.
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_config_enable_ffprobe_session_complete_callback(
    FFprobeKitCompleteCallback complete_cb, void *user_data);

/**
 * Enables the FFplay session complete callback.
 *
 * @param complete_cb the FFplay session complete callback
 * @param user_data the user data
 * @note The user data is owned by the callback and should be freed by the
 * callback owner including the handle.
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_config_enable_ffplay_session_complete_callback(
    FFplayKitCompleteCallback complete_cb, void *user_data);

/**
 * Enables the media information session complete callback.
 *
 * @param complete_cb the media information session complete callback
 * @param user_data the user data
 * @note The user data is owned by the callback and should be freed by the
 * callback owner including the handle.
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_config_enable_media_information_session_complete_callback(
    MediaInformationSessionCompleteCallback complete_cb, void *user_data);

/* Utils */

/**
 * Registers a new FFmpeg pipe.
 *
 * @return the pipe path
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_config_register_new_ffmpeg_pipe(void);

/**
 * Closes the FFmpeg pipe.
 *
 * @param pipe_path the pipe path
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_config_close_ffmpeg_pipe(const char *pipe_path);

/**
 * Sets the font directory list.
 *
 * @param font_directory_list the font directory list
 * @param list_size the list size
 * @param name_mappings_json the name mappings JSON
 */
FFMPEG_KIT_C_EXPORT void
ffmpeg_kit_config_set_font_directory_list(const char **font_directory_list,
                                          int64_t list_size,
                                          const char *name_mappings_json);

/**
 * Gets the build date.
 *
 * @return the build date
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_config_get_build_date(void);

/**
 * Gets the session state to string.
 *
 * @param state the session state
 * @return the session state to string
 */
FFMPEG_KIT_C_EXPORT char *
ffmpeg_kit_config_session_state_to_string(FFmpegKitSessionState state);

/**
 * Parses the arguments.
 *
 * @param command the command
 * @param arg_count the argument count
 * @return the parsed arguments
 */
FFMPEG_KIT_C_EXPORT char **
ffmpeg_kit_config_parse_arguments(const char *command, int64_t *arg_count);

/**
 * Converts the arguments to string.
 *
 * @param arguments the arguments
 * @param arg_count the argument count
 * @return the arguments to string
 */
FFMPEG_KIT_C_EXPORT char *
ffmpeg_kit_config_arguments_to_string(char **arguments, int64_t arg_count);

/**
 * Gets the messages in transmit.
 *
 * @param session_id the session ID
 * @return the messages in transmit
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_config_messages_in_transmit(int64_t session_id);

/* Session Management Extended */

/**
 * Gets the create time.
 *
 * @param session_handle the session handle
 * @return the create time
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_session_get_create_time(void *session_handle);

/**
 * Gets the start time.
 *
 * @param session_handle the session handle
 * @return the start time
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_session_get_start_time(void *session_handle);

/**
 * Gets the end time.
 *
 * @param session_handle the session handle
 * @return the end time
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_session_get_end_time(void *session_handle);

/**
 * Gets the duration.
 *
 * @param session_handle the session handle
 * @return the duration
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_session_get_duration(void *session_handle);

/**
 * Gets the command.
 *
 * @param session_handle the session handle
 * @return the command
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_session_get_command(void *session_handle);

/**
 * Gets the logs count.
 *
 * @param session_handle the session handle
 * @return the logs count
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_session_get_logs_count(void *session_handle);

/**
 * Gets the log at.
 *
 * @param session_handle the session handle
 * @param index the index
 * @return the log at
 */
FFMPEG_KIT_C_EXPORT char *
ffmpeg_kit_session_get_log_at(void *session_handle,
                              int64_t index); // Returns log message

/**
 * Gets the log level at.
 *
 * @param session_handle the session handle
 * @param index the index
 * @return the log level at
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_session_get_log_level_at(void *session_handle, int64_t index);

/**
 * Gets the statistics count.
 *
 * @param session_handle the session handle
 * @return the statistics count
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_session_get_statistics_count(void *session_handle);

/**
 * Gets the statistics at.
 *
 * @param session_handle the session handle
 * @param index the index
 * @return the statistics at
 */
FFMPEG_KIT_C_EXPORT StatisticsHandle
ffmpeg_kit_session_get_statistics_at(void *session_handle, int64_t index);

/* Statistics Getters */

/**
 * Gets the video frame number.
 *
 * @param handle the statistics handle
 * @return the video frame number
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_statistics_get_video_frame_number(StatisticsHandle handle);

/**
 * Gets the video FPS.
 *
 * @param handle the statistics handle
 * @return the video FPS
 */
FFMPEG_KIT_C_EXPORT double
ffmpeg_kit_statistics_get_video_fps(StatisticsHandle handle);

/**
 * Gets the video quality.
 *
 * @param handle the statistics handle
 * @return the video quality
 */
FFMPEG_KIT_C_EXPORT double
ffmpeg_kit_statistics_get_video_quality(StatisticsHandle handle);

/**
 * Gets the size.
 *
 * @param handle the statistics handle
 * @return the size
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_statistics_get_size(StatisticsHandle handle);

/**
 * Gets the time in milliseconds.
 *
 * @param handle the statistics handle
 * @return the time in milliseconds (consistent with the time argument passed
 *         to FFmpegKitStatisticsCallback)
 */
FFMPEG_KIT_C_EXPORT double
ffmpeg_kit_statistics_get_time(StatisticsHandle handle);

/**
 * Gets the time elapsed in milliseconds.
 *
 * @param handle the statistics handle
 * @return the time elapsed in milliseconds (consistent with the time argument passed
 *         to FFmpegKitStatisticsCallback)
 */
FFMPEG_KIT_C_EXPORT double
ffmpeg_kit_statistics_get_time_elapsed(StatisticsHandle handle);

/**
 * Gets the bitrate.
 *
 * @param handle the statistics handle
 * @return the bitrate
 */
FFMPEG_KIT_C_EXPORT double
ffmpeg_kit_statistics_get_bitrate(StatisticsHandle handle);

/**
 * Gets the speed.
 *
 * @param handle the statistics handle
 * @return the speed
 */
FFMPEG_KIT_C_EXPORT double
ffmpeg_kit_statistics_get_speed(StatisticsHandle handle);

/**
 * Returns the duplicated frame count from a statistics entry.
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_statistics_get_dup_frames(StatisticsHandle handle);

/**
 * Returns the dropped frame count from a statistics entry.
 */
FFMPEG_KIT_C_EXPORT int64_t
ffmpeg_kit_statistics_get_drop_frames(StatisticsHandle handle);

/* Entity Properties Extended */

/**
 * Gets the start time.
 *
 * @param handle the handle
 * @return the start time
 */
FFMPEG_KIT_C_EXPORT char *
media_information_get_start_time(MediaInformationHandle handle);

/**
 * Gets the string property.
 *
 * @param handle the handle
 * @param key the key
 * @return the string property
 */
FFMPEG_KIT_C_EXPORT char *
media_information_get_string_property(MediaInformationHandle handle,
                                      const char *key);

/**
 * Gets the number property.
 *
 * @param handle the handle
 * @param key the key
 * @return the number property
 */
FFMPEG_KIT_C_EXPORT int64_t media_information_get_number_property(
    MediaInformationHandle handle, const char *key);

/**
 * Gets the all properties JSON.
 *
 * @param handle the handle
 * @return the all properties JSON
 */
FFMPEG_KIT_C_EXPORT char *
media_information_get_all_properties_json(MediaInformationHandle handle);

/**
 * Gets the channel layout.
 *
 * @param handle the handle
 * @return the channel layout
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_channel_layout(StreamInformationHandle handle);

/**
 * Gets the sample aspect ratio.
 *
 * @param handle the handle
 * @return the sample aspect ratio
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_sample_aspect_ratio(StreamInformationHandle handle);

/**
 * Gets the codec time base.
 *
 * @param handle the handle
 * @return the codec time base
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_codec_time_base(StreamInformationHandle handle);

/**
 * Gets the string property.
 *
 * @param handle the handle
 * @param key the key
 * @return the string property
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_string_property(StreamInformationHandle handle,
                                       const char *key);

/**
 * Gets the number property.
 *
 * @param handle the handle
 * @param key the key
 * @return the number property
 */
FFMPEG_KIT_C_EXPORT int64_t stream_information_get_number_property(
    StreamInformationHandle handle, const char *key);

/**
 * Gets the all properties JSON.
 *
 * @param handle the handle
 * @return the all properties JSON
 */
FFMPEG_KIT_C_EXPORT char *
stream_information_get_all_properties_json(StreamInformationHandle handle);

/**
 * Gets the string property.
 *
 * @param handle the handle
 * @param key the key
 * @return the string property
 */
FFMPEG_KIT_C_EXPORT char *chapter_get_string_property(ChapterHandle handle,
                                                      const char *key);

/**
 * Gets the number property.
 *
 * @param handle the handle
 * @param key the key
 * @return the number property
 */
FFMPEG_KIT_C_EXPORT int64_t chapter_get_number_property(ChapterHandle handle,
                                                        const char *key);

/**
 * Gets the all properties JSON.
 *
 * @param handle the handle
 * @return the all properties JSON
 */
FFMPEG_KIT_C_EXPORT char *chapter_get_all_properties_json(ChapterHandle handle);

/**
 * Checks if the session is a FFmpeg session.
 *
 * @param session the session to check
 * @return true if the session is a FFmpeg session, false otherwise
 */
FFMPEG_KIT_C_EXPORT bool session_is_ffmpeg_session(void *session);

/**
 * Checks if the session is a FFprobe session.
 *
 * @param session the session to check
 * @return true if the session is a FFprobe session, false otherwise
 */
FFMPEG_KIT_C_EXPORT bool session_is_ffprobe_session(void *session);

/**
 * Checks if the session is a FFplay session.
 *
 * @param session the session to check
 * @return true if the session is a FFplay session, false otherwise
 */
FFMPEG_KIT_C_EXPORT bool session_is_ffplay_session(void *session);

/**
 * Checks if the session is a FFmpegKit session.
 *
 * @param session the session to check
 * @return true if the session is a MediaInformation session, false otherwise
 */
FFMPEG_KIT_C_EXPORT bool session_is_media_information_session(void *session);

/**
 * Enables the debug log.
 *
 * @param session the session to enable the debug log for
 */
FFMPEG_KIT_C_EXPORT void session_enable_debug_log(void *session);

/**
 * Disables the debug log.
 *
 * @param session the session to disable the debug log for
 */
FFMPEG_KIT_C_EXPORT void session_disable_debug_log(void *session);

/**
 * Checks if the debug log is enabled.
 *
 * @param session the session to check
 * @return true if the debug log is enabled, false otherwise
 */
FFMPEG_KIT_C_EXPORT bool session_is_debug_log_enabled(void *session);

/**
 * Gets the debug log.
 *
 * @param session the session to get the debug log for
 * @return the debug log
 */
FFMPEG_KIT_C_EXPORT char *session_get_debug_log(void *session);

/**
 * Clears the debug log.
 *
 * @param session the session to clear the debug log for
 */
FFMPEG_KIT_C_EXPORT void session_clear_debug_log(void *session);

/**
 * Frees the memory allocated for the pointer.
 *
 * @param ptr the pointer to free
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_free(void *ptr);

/**
 * Enables the debug log for the session.
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_config_enable_debug_log(void *session);

/**
 * Disables the debug log for the session.
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_config_disable_debug_log(void *session);

/**
 * Checks if the debug log is enabled for the session.
 *
 * @return true if the debug log is enabled, false otherwise
 */
FFMPEG_KIT_C_EXPORT bool ffmpeg_kit_config_is_debug_log_enabled(void *session);

/**
 * Gets the debug log for the session.
 *
 * @return the debug log
 */
FFMPEG_KIT_C_EXPORT char *ffmpeg_kit_config_get_debug_log(void *session);

/**
 * Clears the debug log for the session.
 */
FFMPEG_KIT_C_EXPORT void ffmpeg_kit_config_clear_debug_log(void *session);

#ifdef __cplusplus
}
#endif

#endif // FFMPEG_KIT_WRAPPER_H
