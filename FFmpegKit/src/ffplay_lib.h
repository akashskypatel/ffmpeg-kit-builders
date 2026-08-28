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

#ifndef FFPLAY_LIB_H
#define FFPLAY_LIB_H

#include "ffmpeg_tls.h"
#include <stdint.h>

#if defined(_WIN32)
#ifdef FFMPEG_KIT_BUILDING_DLL
#define FFMPEG_API __declspec(dllexport)
#else
#define FFMPEG_API __declspec(dllimport)
#endif
#else
#define FFMPEG_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FFplayContext FFplayContext;

// Event callbacks for library integration
typedef struct FFplayCallbacks {
    void (*on_frame_displayed)(void *userdata, const uint8_t *data, int width, int height, int linesize);
    void (*on_audio_samples)(void *userdata, const uint8_t *data, int size);
    void (*on_seek_complete)(void *userdata, double position);
    void (*on_error)(void *userdata, const char *error);
    void *userdata;
} FFplayCallbacks;

/**
 * Initializes ffplay with command-line arguments as a string.
 *
 * @param args_string the command-line arguments as a string
 * @param cb the callback
 * @return the ffplay context, or NULL on error
 */
FFMPEG_API FFplayContext* ffplay_init(const char* args_string, const FFplayCallbacks *cb);

/**
 * Initializes ffplay from an existing argument vector.
 * Arguments are copied verbatim and never serialized into command text.
 *
 * @param argc Argument count, including argv[0].
 * @param argv Argument vector.
 * @param cb the callback
 * @return the ffplay context, or NULL on error
 */
FFMPEG_API FFplayContext* ffplay_init_argv(int argc,
                                           const char *const *argv,
                                           const FFplayCallbacks *cb);

/**
 * Starts playback.
 *
 * @param ctx the ffplay context
 * @return 0 on success
 */
FFMPEG_API int ffplay_start(FFplayContext* ctx);

/**
 * Processes one event-loop iteration. Call regularly from the host event loop.
 *
 * @param ctx the ffplay context
 * @return 0 if running, 1 if quit/finished
 */
FFMPEG_API int ffplay_step(FFplayContext* ctx);
/**
 * Seeks to a specific position in the media.
 *
 * @param ctx the ffplay context
 * @param seconds the seconds to seek to
 * @param rel the relative position to seek to
 * @return 0 on success
 */
FFMPEG_API int ffplay_seek(FFplayContext* ctx, double seconds, double rel);

/**
 * Pauses playback.
 *
 * @param ctx the ffplay context
 * @return 0 on success
 */
FFMPEG_API int ffplay_pause(FFplayContext* ctx);

/**
 * Resumes playback.
 *
 * @param ctx the ffplay context
 * @return 0 on success
 */
FFMPEG_API int ffplay_resume(FFplayContext* ctx);

/**
 * Stops playback.
 *
 * @param ctx the ffplay context
 * @return 0 on success
 */
FFMPEG_API int ffplay_stop(FFplayContext* ctx);

// Get playback state
/**
 * Gets the playback position.
 *
 * @param ctx the ffplay context
 * @return the playback position
 */
FFMPEG_API double ffplay_get_position(FFplayContext* ctx);

/**
 * Gets the playback duration.
 *
 * @param ctx the ffplay context
 * @return the playback duration
 */
FFMPEG_API double ffplay_get_duration(FFplayContext* ctx);

/**
 * Checks if the playback is playing.
 *
 * @param ctx the ffplay context
 * @return 1 if playing, 0 otherwise
 */
FFMPEG_API int ffplay_is_playing(FFplayContext* ctx);

/**
 * Checks if the playback is paused.
 *
 * @param ctx the ffplay context
 * @return 1 if paused, 0 otherwise
 */
FFMPEG_API int ffplay_is_paused(FFplayContext* ctx);

/**
 * Sets the volume (0.0 to 1.0).
 *
 * @param ctx the ffplay context
 * @param volume the volume
 */
FFMPEG_API void ffplay_set_volume(FFplayContext* ctx, float volume);

/**
 * Gets the volume.
 *
 * @param ctx the ffplay context
 * @return the volume
 */
FFMPEG_API float ffplay_get_volume(FFplayContext* ctx);

/**
 * Sets the audio output device.
 * null for default device
 *
 * @param device_name the name of the audio device
 */
FFMPEG_API void ffplay_set_audio_output_device(const char* device_name);

/**
 * Returns a ';'-delimited string of available audio output device names.
 * Returns NULL on error. Caller must free.
 */
FFMPEG_API char* ffplay_list_audio_devices(void);

/**
 * Returns the current video stream dimensions.
 * Both values are 0 if no video stream has been opened yet.
 *
 * @param ctx    the ffplay context
 * @param width  out: video width in pixels
 * @param height out: video height in pixels
 */
FFMPEG_API void ffplay_get_video_size(FFplayContext* ctx, int *width, int *height);

/**
 * Frees all resources and stops playback.
 *
 * @param ctx the ffplay context
 */
FFMPEG_API void ffplay_free(FFplayContext* ctx);

/**
 * Closes the ffplay session.
 *
 * @param ctx the ffplay context
 */
FFMPEG_API void ffplay_close(FFplayContext* ctx);

/**
 * Probes [path] for at least one video stream without decoding.
 * Uses avformat_open_input + avformat_find_stream_info. Thread-safe.
 *
 * @param path  UTF-8 file path or URL
 * @return  1 video present, 0 audio-only, -1 on error
 */
FFMPEG_API int ffplay_has_video_stream(const char *path);

#ifdef __ANDROID__
#include <android/native_window.h>


/**
 * Sets the ANativeWindow for video output.
 * The function acquires its own ANativeWindow reference (ANativeWindow_acquire),
 * so callers MUST release their own reference after this call returns.
 * Passing NULL clears the window and releases the internally held reference.
 *
 * @param window ANativeWindow from ANativeWindow_fromSurface(), or NULL to clear.
 */
FFMPEG_API void ffplay_set_android_window(ANativeWindow *window);

#endif /* __ANDROID__ */

/**
 * Frame-ready callback for desktop video output. Fired inside ffplay_step().
 * Pixel format: RGBA8888 ([R][G][B][A] on little-endian), linesize == width * 4.
 * The pixel buffer is freed after the callback returns — copy if you need to retain it.
 *
 * @param userdata  opaque pointer from ffplay_set_frame_callback()
 * @param pixels    RGBA8888 rows, tightly packed
 * @param width     frame width in pixels
 * @param height    frame height in pixels
 * @param linesize  bytes per row
 */
typedef void (*FFplayFrameCallback)(void *userdata, const uint8_t *pixels,
                                    int width, int height, int linesize,
                                    const char *pixel_format);

/**
 * Registers a frame-ready callback for desktop video output. Call before ffplay_init().
 *
 * @param callback  frame callback, or NULL to clear
 * @param userdata  forwarded to every callback invocation
 */
FFMPEG_API void ffplay_set_frame_callback(FFplayFrameCallback callback,
                                           void *userdata) ;


/**
 * Internal helper to invoke the global frame callback (if set).
 * Called from ffplay_step() after each video frame is decoded.
 *
 * @param pixels    RGBA8888 rows, tightly packed
 * @param width     frame width in pixels
 * @param height    frame height in pixels
 * @param linesize  bytes per row
 * @param pixel_format  pixel format string (e.g., "rgba")
 */
FFMPEG_API void ffplay_lib_on_frame(const uint8_t *pixels, int width, int height,
                         int linesize, const char *pixel_format);


#ifdef __cplusplus
}
#endif

#endif // FFPLAY_LIB_H