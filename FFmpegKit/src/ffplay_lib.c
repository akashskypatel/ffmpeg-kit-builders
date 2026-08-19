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

#include "ffplay_lib.h"
#include "ffmpeg_kit_assert_override.h"
#include <SDL.h>
#include <SDL_stdinc.h>

FFMPEG_WEAK_SYMBOL FFMPEG_THREAD_LOCAL const char *program_name = "ffplay";
FFMPEG_WEAK_SYMBOL FFMPEG_THREAD_LOCAL int program_birth_year = 2000;
extern void FFMPEG_THREAD_LOCAL (*show_help_default_func)(const char *opt, const char *arg);
extern void ffplay_show_help_default(const char *opt, const char *arg);

// Global state for audio device management
static char *requested_audio_device = NULL;
static SDL_AudioSpec captured_wanted_spec;
static int has_captured_spec = 0;
struct VideoState; // Forward declaration
static struct VideoState *active_audio_is = NULL;
static SDL_AudioDeviceID active_audio_dev_id = 0;

// Reusable pixel buffer for ffplay_step — resized only on dimension change.
// ffplay_step is called from a single background thread, so no lock needed.
static void   *g_pixel_buf      = NULL;
static size_t  g_pixel_buf_size = 0;

// Interception logic
static SDL_AudioDeviceID ffplay_kit_SDL_OpenAudioDevice(
    const char *device,
    int iscapture,
    const SDL_AudioSpec *desired,
    SDL_AudioSpec *obtained,
    int allowed_changes)
{
    const char *target = device;
    if (requested_audio_device && !iscapture) {
        target = requested_audio_device;
    }

    SDL_AudioDeviceID dev = SDL_OpenAudioDevice(target, iscapture, desired, obtained, allowed_changes);

    // Capture the spec if this is our main playback session opening
    if (desired && !iscapture && dev > 0) {
        captured_wanted_spec = *desired;
        has_captured_spec = 1;
        active_audio_is = (struct VideoState *)desired->userdata;
        active_audio_dev_id = dev;
    }

    return dev;
}

static void ffplay_kit_SDL_CloseAudioDevice(SDL_AudioDeviceID dev) {
    if (dev > 0 && dev == active_audio_dev_id) {
        active_audio_is = NULL;
        active_audio_dev_id = 0;
        has_captured_spec = 0;
    }
    SDL_CloseAudioDevice(dev);
}

// Redirection macro must be defined before including ffplay.c
#define SDL_OpenAudioDevice ffplay_kit_SDL_OpenAudioDevice
#define SDL_CloseAudioDevice ffplay_kit_SDL_CloseAudioDevice

/* Forward declarations — defined after #include "ffplay.c" below. */
static void lock_ffplay_api(void);
static void unlock_ffplay_api(void);

/* Global frame callback for non-Android video output (Linux, Windows, macOS, iOS).
 * Set by ffplay_set_frame_callback() before ffplay_init().
 * Called inside ffplay_step() with SDL_PIXELFORMAT_ABGR8888 pixel data after each video frame. */
static FFplayFrameCallback g_frame_callback = NULL;
static void *g_frame_callback_userdata = NULL;

#ifdef __ANDROID__
#include <android/native_window.h>
#include <android/log.h>

#define FFPLAY_LOG_TAG "FFplayLib"
#define FFPLAY_LOGI(...) __android_log_print(ANDROID_LOG_INFO,  FFPLAY_LOG_TAG, __VA_ARGS__)
#define FFPLAY_LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, FFPLAY_LOG_TAG, __VA_ARGS__)
#define FFPLAY_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, FFPLAY_LOG_TAG, __VA_ARGS__)

/* ANativeWindow set by the Java caller before ffplay_init().
   Owned reference: ffplay_set_android_window() calls ANativeWindow_acquire/release
   so all three caller paths (JNI, C++, FFI) share the same single retained ref. */
static ANativeWindow *g_android_native_window = NULL;
static ANativeWindow *g_owned_window = NULL;

void ffplay_set_android_window(ANativeWindow *nw) {
    FFPLAY_LOGI("ffplay_set_android_window: nw=%p (was %p)", nw, g_android_native_window);
    /* Acquire the new reference before taking the lock so it is valid the
     * instant another thread can observe it via g_android_native_window. */
    if (nw) ANativeWindow_acquire(nw);
    lock_ffplay_api();
    ANativeWindow *old = g_owned_window;
    g_owned_window = nw;
    g_android_native_window = nw;
    unlock_ffplay_api();
    /* Release after the lock so ffplay_step's transient blit reference (also
     * acquired under the same mutex) keeps the window alive if a blit is
     * already in flight. */
    if (old) ANativeWindow_release(old);
}

/* SDL_SetMainReady() is declared in SDL_main.h, but including that header
 * redirects `main` to `SDL_main` which breaks library-mode compilation.
 * Declare it directly instead. */
extern void SDL_SetMainReady(void);

/* SDL_CreateWindow interceptor — logs dimensions before forwarding to SDL. */
static SDL_Window *ffplay_kit_SDL_CreateWindow(
        const char *title, int x, int y, int w, int h, Uint32 flags)
{
    FFPLAY_LOGI("SDL_CreateWindow: %dx%d title=%s flags=0x%x",
        w, h, title ? title : "(null)", (unsigned)flags);
    SDL_Window *win = SDL_CreateWindow(title, x, y, w, h, flags);
    FFPLAY_LOGI("SDL_CreateWindow => win=%p err='%s'", win, SDL_GetError());
    return win;
}
#define SDL_CreateWindow ffplay_kit_SDL_CreateWindow

#elif defined(__APPLE__)
#include <TargetConditionals.h>
#include <os/log.h>

#define FFPLAY_LOG_TAG "FFplayLib"
/* os_log handle; created lazily in ffplay_init().  Falls back to OS_LOG_DEFAULT until then. */
static os_log_t _ffplay_apple_log = NULL;
#define FFPLAY_LOGI(fmt, ...) os_log_info(_ffplay_apple_log ? _ffplay_apple_log : OS_LOG_DEFAULT, fmt, ##__VA_ARGS__)
#define FFPLAY_LOGD(fmt, ...) os_log_debug(_ffplay_apple_log ? _ffplay_apple_log : OS_LOG_DEFAULT, fmt, ##__VA_ARGS__)
#define FFPLAY_LOGE(fmt, ...) os_log_error(_ffplay_apple_log ? _ffplay_apple_log : OS_LOG_DEFAULT, fmt, ##__VA_ARGS__)

/* SDL_SetMainReady() is declared in SDL_main.h, but including that header
 * redirects `main` to `SDL_main` which breaks library-mode compilation.
 * Declare it directly instead. */
extern void SDL_SetMainReady(void);

/* SDL_CreateWindow interceptor — logs dimensions before forwarding to SDL. */
static SDL_Window *ffplay_kit_SDL_CreateWindow(
        const char *title, int x, int y, int w, int h, Uint32 flags)
{
    FFPLAY_LOGI("[ffplay_lib] SDL_CreateWindow: %dx%d title=%{public}s flags=0x%x",
        w, h, title ? title : "(null)", (unsigned)flags);
    SDL_Window *win = SDL_CreateWindow(title, x, y, w, h, flags);
    FFPLAY_LOGI("[ffplay_lib] SDL_CreateWindow => win=%p err='%{public}s'", win, SDL_GetError());
    return win;
}
#define SDL_CreateWindow ffplay_kit_SDL_CreateWindow

#endif /* __APPLE__ */

// Keep the SDL window hidden and suppress SDL_RenderPresent: pixels are read via
// SDL_RenderReadPixels from the software back-buffer, so no X11/present needed.
#ifndef __ANDROID__
#define SDL_ShowWindow(w) ((void)(w))
#define SDL_RenderPresent(r) ((void)(r))
#endif
// At the top of ffplay_lib.c, before ffplay.c is included, declare the real symbol:
extern DECLSPEC void SDLCALL SDL_RenderPresent_real(SDL_Renderer *renderer);

static SDL_Renderer *ffplay_kit_SDL_CreateRenderer(
    SDL_Window *window,
    int index,
    Uint32 flags)
{
    const char *video_driver = SDL_GetCurrentVideoDriver();

    if (video_driver && SDL_strcmp(video_driver, "dummy") == 0) {
        index = -1;
        flags = SDL_RENDERER_SOFTWARE;
    }

    return SDL_CreateRenderer(window, index, flags);
}

#define SDL_CreateRenderer ffplay_kit_SDL_CreateRenderer

// Include the patched ffplay.c to access internal structures and static functions.
#include "ffplay.c"

// Forward declarations of symbols defined inside the included ffplay.c.
extern void ffplay_tls_init_options(void);
extern VideoState *ffplay_init_internal(int argc, char **argv);
extern void ffplay_reset_internal_state(void);

struct FFplayContext {
    VideoState *is;
    int argc;
    char **argv;
    FFplayCallbacks callbacks;
    int quit;
    /* High-water mark for the position returned by ffplay_get_position.
       Prevents the near-EOF clock jitter (audio buffer drain oscillation)
       from reaching callers.  Reset to 0 on every seek so backwards
       movement after a seek is still reported correctly. */
    double max_seen_pos;
};

#include <pthread.h>

// Global API Synchronization
static SDL_mutex *ffplay_api_mutex = NULL;
static SDL_SpinLock ffplay_init_lock = 0;
static FFplayContext *active_ffplay_ctx = NULL;

static void lock_ffplay_api(void) {
    // Double-checked locking for initialization
    if (!ffplay_api_mutex) {
        SDL_AtomicLock(&ffplay_init_lock);
        if (!ffplay_api_mutex) {
            ffplay_api_mutex = SDL_CreateMutex();
        }
        SDL_AtomicUnlock(&ffplay_init_lock);
    }
    
    // SDL Mutexes are recursive; simply lock.
    SDL_LockMutex(ffplay_api_mutex);
}

static void unlock_ffplay_api(void) {
    if (ffplay_api_mutex) {
        SDL_UnlockMutex(ffplay_api_mutex);
    }
}

void ffplay_lib_on_frame(const uint8_t *pixels, int width, int height,
                         int linesize, const char *pixel_format) {
  if (!pixels || width <= 0 || height <= 0) return;
#ifdef __ANDROID__
    FFplayContext *ctx = active_ffplay_ctx;
    if (!ctx) return;
    lock_ffplay_api();
    ANativeWindow *blit_window = g_android_native_window;
    if (blit_window) ANativeWindow_acquire(blit_window);
    unlock_ffplay_api();

    if (blit_window) {
        ANativeWindow_setBuffersGeometry(blit_window, width, height,
                                         WINDOW_FORMAT_RGBA_8888);
        ANativeWindow_Buffer anb;
        if (ANativeWindow_lock(blit_window, &anb, NULL) == 0) {
            const uint8_t *src = pixels;
            uint8_t *dst = (uint8_t *)anb.bits;
            int dst_stride = anb.stride * 4;
            int src_stride = linesize;
            for (int row = 0; row < height; row++) {
                memcpy(dst, src, width * 4);
                src += src_stride;
                dst += dst_stride;
            }
            ANativeWindow_unlockAndPost(blit_window);
            if (ctx->callbacks.on_frame_displayed)
                ctx->callbacks.on_frame_displayed(
                    ctx->callbacks.userdata, NULL, width, height, 0);
        } else {
            FFPLAY_LOGE("ANativeWindow_lock failed");
        }
        ANativeWindow_release(blit_window);
    }
#endif
    lock_ffplay_api();
    if (g_frame_callback)
      g_frame_callback(g_frame_callback_userdata, pixels, width, height,
                       linesize, pixel_format);
    unlock_ffplay_api();
}

void ffplay_set_frame_callback(FFplayFrameCallback callback, void *userdata) {
    /* Hold the API mutex so that when this returns with callback==NULL,
     * ffplay_step is guaranteed to have finished any in-flight call.
     * (ffplay_step holds this same mutex for the entire callback block.) */
    lock_ffplay_api();
    g_frame_callback = callback;
    g_frame_callback_userdata = userdata;
    unlock_ffplay_api();
}

/* Splits a command-line string into argc/argv. Caller frees with av_free(). */
static int split_args(const char *args, char ***argv_out) {
    if (!args || !argv_out) return -1;
    char *args_copy = av_strdup(args);
    if (!args_copy) return -1;

    int argc = 0;
    char *p = args_copy;
    int in_quotes = 0;

    // Count
    while (*p) {
        while (*p && !in_quotes && (*p == ' ' || *p == '\t' || *p == '\n')) p++;
        if (!*p) break;
        argc++;
        if (*p == '"') {
            in_quotes = 1;
            p++;
            while (*p && *p != '"') p++;
            if (*p) p++;
            in_quotes = 0;
        } else {
            while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
        }
    }

    char **argv = av_mallocz(sizeof(char *) * (argc + 1));
    if (!argv) {
        av_free(args_copy);
        return -1;
    }

    strcpy(args_copy, args);
    p = args_copy;
    int idx = 0;
    while (*p && idx < argc) {
        while (*p && (*p == ' ' || *p == '\t' || *p == '\n')) p++;
        if (!*p) break;
        char *start = p;
        if (*p == '"') {
            p++;
            start = p;
            while (*p && *p != '"') p++;
            if (*p) *p++ = '\0';
        } else {
            while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
            if (*p) *p++ = '\0';
        }
        argv[idx++] = av_strdup(start);
    }
    
    av_free(args_copy);
    *argv_out = argv;
    return argc;
}

FFplayContext* ffplay_init(const char* args_string, const FFplayCallbacks *cb) {
    // Ensure only one session is active at a time
    if (active_ffplay_ctx) {
        ffplay_stop(NULL);
        // Wait for it to clear
        int timeout = 5000; // 5s
        while (active_ffplay_ctx && timeout > 0) {
            SDL_PumpEvents(); // Ensure events are processed
            SDL_Delay(50);
            timeout -= 50;
        }
        if (active_ffplay_ctx) {
            av_log(NULL, AV_LOG_WARNING, "[ffplay_lib] Previous session did not close in time, forcing cleanup.\n");
        } else {
            av_log(NULL, AV_LOG_INFO,"[ffplay_lib] ffplay_init: previous session cleared\n");
        }
    }

    FFplayContext *ctx = av_mallocz(sizeof(FFplayContext));
    if (!ctx) return NULL;

    if (cb) {
        ctx->callbacks = *cb;
    }
    
#ifdef __ANDROID__
    // SDL used as a library — bypass SDLActivity requirements.
    SDL_SetMainReady();

    // 'dummy' video + 'software' render: pure CPU framebuffer, no EGL/JVM.
    // ffplay_step() blits pixels to g_android_native_window each frame.
    SDL_setenv("SDL_VIDEODRIVER", "dummy", 1);
    SDL_setenv("SDL_RENDER_DRIVER", "software", 1);

    if (!SDL_getenv("SDL_AUDIODRIVER"))
        SDL_setenv("SDL_AUDIODRIVER", "openslES", 1);

    FFPLAY_LOGI("ffplay_init: SDL_VIDEODRIVER='dummy' SDL_RENDER_DRIVER='software' "
        "SDL_AUDIODRIVER='%s' android_window=%p args='%.200s'",
        SDL_getenv("SDL_AUDIODRIVER") ? SDL_getenv("SDL_AUDIODRIVER") : "(null)",
        g_android_native_window,
        args_string ? args_string : "(null)");
#else /* !__ANDROID__ */
    // Use SDL_SetHintWithPriority (not SDL_setenv) so the hint lands in SDL's
    // own table, which is reliable across CRT instances on Windows.
#if defined(_WIN32)
    // Windows: 'dummy' driver provides an in-memory surface without a visible window.
    SDL_SetHintWithPriority(SDL_HINT_VIDEODRIVER, "dummy", SDL_HINT_OVERRIDE);
    SDL_SetHintWithPriority(SDL_HINT_RENDER_DRIVER, "software", SDL_HINT_OVERRIDE);
    if (!SDL_getenv("SDL_AUDIODRIVER"))
        SDL_setenv("SDL_AUDIODRIVER", "wasapi", 0);
#elif defined(__APPLE__)
    // iOS/macOS: SDL used as a library — bypass SDLUIKitDelegate/SDLAppDelegate
    // startup requirements (identical to the Android SDL_SetMainReady() call above).
    SDL_SetMainReady();
    // via the FFplayFrameCallback registered with ffplay_set_frame_callback().
    SDL_SetHintWithPriority(SDL_HINT_VIDEODRIVER, "dummy", SDL_HINT_OVERRIDE);
    SDL_SetHintWithPriority(SDL_HINT_RENDER_DRIVER, "software", SDL_HINT_OVERRIDE);
    // iOS/macOS: CoreAudio provides real audio output via the system audio stack.
    if (!SDL_getenv("SDL_AUDIODRIVER"))
        SDL_setenv("SDL_AUDIODRIVER", "coreaudio", 0);
    /* Initialise the os_log subsystem now that we have the args context. */
    if (!_ffplay_apple_log)
        _ffplay_apple_log = os_log_create("com.akashskypatel.ffmpegkit", FFPLAY_LOG_TAG);
    FFPLAY_LOGI("[ffplay_lib] ffplay_init: SDL_VIDEODRIVER='dummy' SDL_RENDER_DRIVER='software' "
        "SDL_AUDIODRIVER='%{public}s' args='%{public}.200s'",
        SDL_getenv("SDL_AUDIODRIVER") ? SDL_getenv("SDL_AUDIODRIVER") : "(null)",
        args_string ? args_string : "(null)");
#else
    SDL_SetHintWithPriority(SDL_HINT_VIDEODRIVER, "dummy", SDL_HINT_OVERRIDE);
    SDL_SetHintWithPriority(SDL_HINT_RENDER_DRIVER, "software", SDL_HINT_OVERRIDE);
    if (!SDL_getenv("SDL_AUDIODRIVER"))
        SDL_setenv("SDL_AUDIODRIVER", "dummy", 0);
#endif
#endif /* !__ANDROID__ */
        
    // Reset global state in ffplay.c
    ffplay_reset_internal_state();

    avformat_network_init();

    ffplay_tls_init_options();
    show_help_default_func = ffplay_show_help_default;

    ctx->argc = split_args(args_string, &ctx->argv);
    if (ctx->argc < 0) {
        av_free(ctx);
        return NULL;
    }

    VideoState *is = ffplay_init_internal(ctx->argc, ctx->argv);

    // Log the SDL drivers selected after SDL_Init to confirm the expected path.
    av_log(NULL, AV_LOG_INFO,
        "[ffplay_lib] post-init SDL_GetCurrentVideoDriver='%s' "
        "SDL_GetCurrentAudioDriver='%s'\n",
        SDL_GetCurrentVideoDriver() ? SDL_GetCurrentVideoDriver() : "(null)",
        SDL_GetCurrentAudioDriver() ? SDL_GetCurrentAudioDriver() : "(null)");

    if (!is) {
        // Init failed
#ifdef __ANDROID__
        FFPLAY_LOGE("ffplay_init_internal FAILED (argc=%d) SDL_GetError='%s'",
            ctx->argc, SDL_GetError());
#endif
        av_log(NULL, AV_LOG_ERROR,
            "[ffplay_lib] ffplay_init_internal failed (argc=%d)\n", ctx->argc);
        for (int i=0; i<ctx->argc; i++) av_free(ctx->argv[i]);
        av_free(ctx->argv);
        av_free(ctx);
        return NULL;
    }

    ctx->is = is;

    // Safely publish the context
    lock_ffplay_api();
    active_ffplay_ctx = ctx;
    unlock_ffplay_api();

#ifdef __ANDROID__
    FFPLAY_LOGI("ffplay_init SUCCESS: ctx=%p is=%p", ctx, is);
#endif
    return ctx;
}

// Custom events for thread-safe control
#define FF_PLAY_SEEK_EVENT      (SDL_USEREVENT + 3)
#define FF_PLAY_PAUSE_EVENT     (SDL_USEREVENT + 4)
#define FF_PLAY_RESUME_EVENT    (SDL_USEREVENT + 5)
#define FF_PLAY_VOLUME_EVENT    (SDL_USEREVENT + 6)
#define FF_PLAY_SPEED_EVENT     (SDL_USEREVENT + 7)

// Data structures for events
typedef struct SeekEventData {
    double seconds;
    double rel;
} SeekEventData;

typedef struct SpeedEventData {
    double speed;
} SpeedEventData;

typedef struct VolumeEventData {
    float volume;
} VolumeEventData;

static char *base_afilters = NULL;
static char *allocated_afilters = NULL;

int ffplay_start(FFplayContext* ctx) {
    int ret = -1;

    ffmpeg_kit_assert_triggered = 0;

    // Establish recovery point for av_assert0 failures inside ffplay internals.
    // Keep ffmpeg_kit_assert_jmp_ptr live for the entire body of this function
    // so the lock/check block below is also protected.  Clear it before every
    // return path so a dangling pointer to this stack frame is never left behind.
    jmp_buf assert_jmp;
    ffmpeg_kit_assert_jmp_ptr = &assert_jmp;
    ffmpeg_kit_assert_triggered = 0;
    if (setjmp(assert_jmp)) {
        av_log(NULL, AV_LOG_ERROR,
               "[ffmpeg-kit] ffplay_start: recovered from internal assertion "
               "failure. Session will be marked as failed.\n");
        unlock_ffplay_api();
        ffmpeg_kit_assert_jmp_ptr = NULL;
        return AVERROR_EXIT;
    }

    lock_ffplay_api();
    if (ctx && active_ffplay_ctx == ctx && ctx->is) ret = 0;
#ifdef __ANDROID__
    FFPLAY_LOGI("ffplay_start: ctx=%p active_ctx=%p is=%p quit=%d => ret=%d",
        ctx, active_ffplay_ctx,
        ctx ? ctx->is : NULL,
        ctx ? ctx->quit : -1,
        ret);
    if (ret != 0) {
        if (!ctx)                              FFPLAY_LOGE("  reason: ctx is NULL");
        else if (active_ffplay_ctx != ctx)     FFPLAY_LOGE("  reason: active_ffplay_ctx(%p) != ctx(%p)", active_ffplay_ctx, ctx);
        else if (!ctx->is)                     FFPLAY_LOGE("  reason: ctx->is is NULL");
    }
#endif
    av_log(NULL, AV_LOG_INFO,
        "[ffplay_lib] ffplay_start: ctx=%p active=%p is=%p quit=%d => %d\n",
        ctx, active_ffplay_ctx,
        ctx ? ctx->is : NULL,
        ctx ? ctx->quit : -1,
        ret);
    unlock_ffplay_api();
    ffmpeg_kit_assert_jmp_ptr = NULL;
    return ret;
}

int ffplay_step(FFplayContext* ctx) {
    if (!ctx) return 1;
    if (ctx->quit || !ctx->is) return 1;

    // Establish recovery point for av_assert0 failures inside the decode,
    // filter, and render pipelines invoked during this step.  The ptr is kept
    // live for the entire function body and cleared on every exit path.
    int step_ret = 1;
    jmp_buf assert_jmp;
    ffmpeg_kit_assert_jmp_ptr = &assert_jmp;
    ffmpeg_kit_assert_triggered = 0;
    if (setjmp(assert_jmp)) {
        av_log(NULL, AV_LOG_ERROR,
               "[ffmpeg-kit] ffplay_step: recovered from internal assertion "
               "failure. Stopping playback.\n");
        // Reentrant lock management: simply call unlock to decrement count.
        // unlock_ffplay_api() handles recursion and state.
        unlock_ffplay_api();
        goto step_done;
    }

    SDL_Event event;
    double remaining_time = 0.0; // Instant return if possible

    SDL_PumpEvents();

    // Peep events
    while (SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_FIRSTEVENT, SDL_LASTEVENT) > 0) {
         switch (event.type) {
        case SDL_KEYDOWN:
            if (exit_on_keydown || event.key.keysym.sym == SDLK_ESCAPE || event.key.keysym.sym == SDLK_q) {
                lock_ffplay_api();
                if (ctx->is) {
                    do_exit(ctx->is);
                    ctx->is = NULL;
                }
                ctx->quit = 1;
                unlock_ffplay_api();
                goto step_done;
            }
            if (!ctx->is->width) continue;
            switch (event.key.keysym.sym) {
            case SDLK_f:
                toggle_full_screen(ctx->is);
                ctx->is->force_refresh = 1;
                break;
            case SDLK_p:
            case SDLK_SPACE:
                lock_ffplay_api();
                toggle_pause(ctx->is);
                unlock_ffplay_api();
                break;
            case SDLK_m:
                toggle_mute(ctx->is);
                break;
            case SDLK_KP_MULTIPLY:
            case SDLK_0:
                lock_ffplay_api();
                update_volume(ctx->is, 1, SDL_VOLUME_STEP);
                unlock_ffplay_api();
                break;
            case SDLK_KP_DIVIDE:
            case SDLK_9:
                lock_ffplay_api();
                update_volume(ctx->is, -1, SDL_VOLUME_STEP);
                unlock_ffplay_api();
                break;
            case SDLK_s: // S: Step to next frame
                step_to_next_frame(ctx->is);
                break;
            case SDLK_a:
                stream_cycle_channel(ctx->is, AVMEDIA_TYPE_AUDIO);
                break;
            case SDLK_v:
                stream_cycle_channel(ctx->is, AVMEDIA_TYPE_VIDEO);
                break;
            case SDLK_c:
                stream_cycle_channel(ctx->is, AVMEDIA_TYPE_VIDEO);
                stream_cycle_channel(ctx->is, AVMEDIA_TYPE_AUDIO);
                stream_cycle_channel(ctx->is, AVMEDIA_TYPE_SUBTITLE);
                break;
            case SDLK_t:
                stream_cycle_channel(ctx->is, AVMEDIA_TYPE_SUBTITLE);
                break;
            case SDLK_w:
                if (ctx->is->show_mode == SHOW_MODE_VIDEO && ctx->is->vfilter_idx < nb_vfilters - 1) {
                    if (++ctx->is->vfilter_idx >= nb_vfilters)
                        ctx->is->vfilter_idx = 0;
                } else {
                    ctx->is->vfilter_idx = 0;
                    toggle_audio_display(ctx->is);
                }
                break;
            default:
                break;
            }
            break;
        case SDL_QUIT:
        case FF_QUIT_EVENT:
            lock_ffplay_api();
            if (ctx->is) {
                do_exit(ctx->is);
                ctx->is = NULL;
            }
            ctx->quit = 1;
            unlock_ffplay_api();
            goto step_done;
        
        // Custom Events Handling
        case FF_PLAY_SEEK_EVENT: {
            SeekEventData *data = (SeekEventData*)event.user.data1;
            if (data) {
                int64_t pos = (int64_t)(data->seconds * AV_TIME_BASE);
                int64_t rel_pts = (int64_t)(data->rel * AV_TIME_BASE);
                stream_seek(ctx->is, pos, rel_pts, 0);
                av_free(data);
            }
            break;
        }
        case FF_PLAY_PAUSE_EVENT:
            lock_ffplay_api();
            if (ctx->is && !ctx->is->paused)
                stream_toggle_pause(ctx->is);
            unlock_ffplay_api();
            break;
        case FF_PLAY_RESUME_EVENT:
            lock_ffplay_api();
            if (ctx->is && ctx->is->paused)
                stream_toggle_pause(ctx->is);
            unlock_ffplay_api();
            break;
        case FF_PLAY_VOLUME_EVENT: {
            VolumeEventData *data = (VolumeEventData*)event.user.data1;
            if (data) {
                int vol = av_clip(data->volume * 100, 0, 100);
                vol = av_clip(SDL_MIX_MAXVOLUME * vol / 100, 0, SDL_MIX_MAXVOLUME);
                
                lock_ffplay_api();
                if (ctx->is) {
                    atomic_store(&ctx->is->audio_volume, vol);
                }
                unlock_ffplay_api();
                
                av_free(data);
            }
            break;
        }
        case FF_PLAY_SPEED_EVENT: {
            SpeedEventData *data = (SpeedEventData*)event.user.data1;
            if (data) {
                double speed = data->speed;

                // Capture base filters consistently
                if (!base_afilters) {
                    if (afilters) {
                        base_afilters = av_strdup(afilters);
                    } else {
                        base_afilters = av_strdup("");
                    }
                }

                char filters_buf[1024] = "";
                if (base_afilters && strlen(base_afilters) > 0)
                    av_strlcat(filters_buf, base_afilters, sizeof(filters_buf));

                if (speed != 1.0) {
                   double s = speed;
                   // Chain atempo
                   while (s > 2.0) {
                       if (strlen(filters_buf) > 0) av_strlcat(filters_buf, ",", sizeof(filters_buf));
                       av_strlcat(filters_buf, "atempo=2.0", sizeof(filters_buf));
                       s /= 2.0;
                   }
                   while (s < 0.5) {
                       if (strlen(filters_buf) > 0) av_strlcat(filters_buf, ",", sizeof(filters_buf));
                       av_strlcat(filters_buf, "atempo=0.5", sizeof(filters_buf));
                       s /= 0.5;
                   }
                   if (s != 1.0) {
                       if (strlen(filters_buf) > 0) av_strlcat(filters_buf, ",", sizeof(filters_buf));
                       char atempo_args[32];
                       snprintf(atempo_args, sizeof(atempo_args), "atempo=%g", s);
                       av_strlcat(filters_buf, atempo_args, sizeof(filters_buf));
                   }
                }

                if (allocated_afilters) {
                    av_free(allocated_afilters);
                    allocated_afilters = NULL;
                }
                
                allocated_afilters = av_strdup(filters_buf);
                afilters = allocated_afilters;

                // Force reconfiguration of audio filters
                ctx->is->audio_filter_src.freq = 0;
                
                av_free(data);
            }
            break;
        }

        default:
            break;
        }
    }
    
    // Refresh video if needed (from refresh_loop_wait_event logic)
    if (!cursor_hidden) {
        if (av_gettime_relative() - cursor_last_shown > CURSOR_HIDE_DELAY) {
            SDL_ShowCursor(0);
            cursor_hidden = 1;
        }
    }
    
    if (ctx->is && ctx->is->show_mode != SHOW_MODE_NONE && (!ctx->is->paused || ctx->is->force_refresh)) {
         video_refresh(ctx->is, &remaining_time);
    }
    step_ret = ctx->quit;

step_done:
    ffmpeg_kit_assert_jmp_ptr = NULL;
    return step_ret;
}

void ffplay_get_video_size(FFplayContext* ctx, int *width, int *height) {
    if (width)  *width  = 0;
    if (height) *height = 0;
    lock_ffplay_api();
    if (ctx && active_ffplay_ctx == ctx && ctx->is && ctx->is->video_st) {
        if (width)  *width  = ctx->is->width;
        if (height) *height = ctx->is->height;
    }
    unlock_ffplay_api();
}

int ffplay_seek(FFplayContext* ctx, double seconds, double rel) {
    int ret = -1;
    lock_ffplay_api();
    if (ctx && active_ffplay_ctx == ctx && ctx->is) {
        SeekEventData *data = av_malloc(sizeof(SeekEventData));
        if (data) {
            data->seconds = seconds;
            data->rel = rel;

            SDL_Event event;
            event.type = FF_PLAY_SEEK_EVENT;
            event.user.data1 = data;
            SDL_PushEvent(&event);
            /* Reset the position high-water mark so the post-seek position
               (which may be lower than the pre-seek value) is reported
               correctly instead of being suppressed. */
            ctx->max_seen_pos = 0.0;
            ret = 0;
        }
    }
    unlock_ffplay_api();
    return ret;
}

int ffplay_pause(FFplayContext* ctx) {
    int ret = -1;
    lock_ffplay_api();
    if (ctx && active_ffplay_ctx == ctx && ctx->is) {
        SDL_Event event;
        event.type = FF_PLAY_PAUSE_EVENT;
        SDL_PushEvent(&event);
        ret = 0;
    }
    unlock_ffplay_api();
    return ret;
}

int ffplay_resume(FFplayContext* ctx) {
    int ret = -1;
    lock_ffplay_api();
    if (ctx && active_ffplay_ctx == ctx && ctx->is) {
        SDL_Event event;
        event.type = FF_PLAY_RESUME_EVENT;
        SDL_PushEvent(&event);
        ret = 0;
    }
    unlock_ffplay_api();
    return ret;
}

int ffplay_stop(FFplayContext* ctx) {
    int ret = -1;
    lock_ffplay_api();
    FFplayContext *target = ctx ? ctx : active_ffplay_ctx;
    if (target && target->is) {
        SDL_Event event;
        event.type = FF_QUIT_EVENT;
        event.user.data1 = target->is; 
        SDL_PushEvent(&event);
        ret = 0;
    } else {
        av_log(NULL, AV_LOG_INFO, "[ffplay_lib] ffplay_stop: nothing to stop (target=%p)\n", target);
    }
    unlock_ffplay_api();
    return ret;
}

double ffplay_get_position(FFplayContext* ctx) {
    double pos = 0.0;
    lock_ffplay_api();
    if (ctx && active_ffplay_ctx == ctx && ctx->is) {
        pos = get_master_clock(ctx->is);
        /* During seek the master clock is NaN — propagate as-is so the
           Dart layer can detect and skip the transient. */
        if (!isnan(pos)) {
            /* Clamp to duration so position never exceeds the media length.
               Both values are read under the same lock, so they're consistent. */
            if (ctx->is->ic && ctx->is->ic->duration != AV_NOPTS_VALUE) {
                double dur = (double)ctx->is->ic->duration / AV_TIME_BASE;
                if (dur > 0.0 && pos > dur)
                    pos = dur;
            }
            /* High-water mark: suppress the backwards oscillation that
               occurs as the audio buffer drains near EOF.  Only move
               forward; seek resets max_seen_pos to 0. */
            if (pos > ctx->max_seen_pos)
                ctx->max_seen_pos = pos;
            else
                pos = ctx->max_seen_pos;
        }
    }
    unlock_ffplay_api();
    return pos;
}

double ffplay_get_duration(FFplayContext* ctx) {
    double dur = 0.0;
    lock_ffplay_api();
    if (ctx && active_ffplay_ctx == ctx && ctx->is && ctx->is->ic && ctx->is->ic->duration != AV_NOPTS_VALUE) {
        dur = (double)ctx->is->ic->duration / AV_TIME_BASE;
    }
    unlock_ffplay_api();
    return dur;
}

int ffplay_is_playing(FFplayContext* ctx) {
    int playing = 0;
    lock_ffplay_api();
    if (ctx && active_ffplay_ctx == ctx && ctx->is) {
        playing = !ctx->is->paused && !ctx->quit;
    }
    unlock_ffplay_api();
    return playing;
}

int ffplay_is_paused(FFplayContext* ctx) {
    int paused = 0;
    lock_ffplay_api();
    if (ctx && active_ffplay_ctx == ctx && ctx->is) {
        paused = ctx->is->paused;
    }
    unlock_ffplay_api();
    return paused;
}

void ffplay_set_volume(FFplayContext* ctx, float volume) {
    lock_ffplay_api();
    if (ctx && active_ffplay_ctx == ctx && ctx->is) {
        VolumeEventData *data = av_malloc(sizeof(VolumeEventData));
        if (data) {
            data->volume = volume;
            SDL_Event event;
            event.type = FF_PLAY_VOLUME_EVENT;
            event.user.data1 = data;
            SDL_PushEvent(&event);
        }
    }
    unlock_ffplay_api();
}

float ffplay_get_volume(FFplayContext* ctx) {
    float vol = 0.0;
    lock_ffplay_api();
    if (ctx && active_ffplay_ctx == ctx && ctx->is) {
        vol = (float)atomic_load(&ctx->is->audio_volume) / SDL_MIX_MAXVOLUME;
    }
    unlock_ffplay_api();
    return vol;
}

void ffplay_set_audio_output_device(const char* device_name) {
    // Update global requested name
    if (requested_audio_device) {
        av_free(requested_audio_device);
        requested_audio_device = NULL;
    }
    if (device_name) {
        requested_audio_device = av_strdup(device_name);
    }

    // Hot-swap if active
    if (active_audio_is && active_audio_is->audio_dev > 0 && has_captured_spec) {
        struct VideoState *local_is = active_audio_is;
        SDL_CloseAudioDevice(local_is->audio_dev); 
        // Note: active_audio_is is cleared by interception here!
        
        SDL_AudioSpec obtained_spec;
        local_is->audio_dev = SDL_OpenAudioDevice(requested_audio_device, 0, &captured_wanted_spec, &obtained_spec, 0);
        
        if (local_is->audio_dev) {
            SDL_PauseAudioDevice(local_is->audio_dev, 0);
        } else {
            av_log(NULL, AV_LOG_ERROR, "Failed to switch audio device: %s\n", SDL_GetError());
            if (device_name) {
                 local_is->audio_dev = SDL_OpenAudioDevice(NULL, 0, &captured_wanted_spec, &obtained_spec, 0);
                 if (local_is->audio_dev) SDL_PauseAudioDevice(local_is->audio_dev, 0);
            }
        }
    }

}

char* ffplay_list_audio_devices(void) {
    if (SDL_InitSubSystem(SDL_INIT_AUDIO) < 0) {
        return NULL;
    }

    int count = SDL_GetNumAudioDevices(0);
    if (count <= 0) {
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
        return NULL;
    }

    size_t total_len = 0;
    for (int i=0; i<count; i++) {
        const char *name = SDL_GetAudioDeviceName(i, 0);
        if (name) {
            total_len += strlen(name) + 1;
        }
    }
    
    if (total_len == 0) {
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
        return NULL;
    }

    char *result = av_malloc(total_len + 1);
    if (!result) {
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
        return NULL;
    }
    result[0] = '\0';
    
    for (int i=0; i<count; i++) {
        const char *name = SDL_GetAudioDeviceName(i, 0);
        if (name) {
            strcat(result, name);
            if (i < count - 1) {
                strcat(result, ";");
            }
        }
    }

    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    return result;
}

void ffplay_free(FFplayContext* ctx) {
    if (!ctx) return;
    
    lock_ffplay_api();
    if (active_ffplay_ctx == ctx) {
        active_ffplay_ctx = NULL;
    }
    if (!ctx->quit && ctx->is) {
        do_exit(ctx->is);
        ctx->is = NULL;
        ctx->quit = 1;
    }
    unlock_ffplay_api();
    
    // Force full SDL shutdown in case multiple inits increased refcount
    while (SDL_WasInit(0)) {
      SDL_Quit();
    }

    // Cleanup globals
    if (allocated_afilters) {
        av_free(allocated_afilters);
        allocated_afilters = NULL;
    }
    if (base_afilters) {
        av_free(base_afilters);
        base_afilters = NULL;
    }

    if (requested_audio_device) {
        av_free(requested_audio_device);
        requested_audio_device = NULL;
    }

    av_free(g_pixel_buf);
    g_pixel_buf = NULL;
    g_pixel_buf_size = 0;

    // argv freed
    if (ctx->argv) {
        for (int i=0; i<ctx->argc; i++) av_free(ctx->argv[i]);
        av_free(ctx->argv);
    }

    avformat_network_deinit();

    av_free(ctx);
}

void ffplay_close(FFplayContext* ctx) {
    ffplay_free(ctx);
}

int ffplay_has_video_stream(const char *path) {
    if (!path) return -1;
    AVFormatContext *fmt_ctx = NULL;
    int ret = avformat_open_input(&fmt_ctx, path, NULL, NULL);
    if (ret < 0) return -1;
    ret = avformat_find_stream_info(fmt_ctx, NULL);
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
}
