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

#include "ffmpeg_lib.h"
#include "ffmpeg.h"
#include "ffmpeg_sched.h"
#include "ffmpeg_kit_assert_override.h"
#include "ffmpegkit_arg_parser.h"
#include "ffmpegkit_session_context.h"
#include "cmdutils.h"
#include "libavformat/avio.h"
#include "libavutil/mem.h"
#include <stdatomic.h>
#include <errno.h>
#include <string.h>
#ifdef _WIN32
#include <io.h>
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

FFMPEG_WEAK_SYMBOL FFMPEG_THREAD_LOCAL const char *program_name = "ffmpeg";
FFMPEG_WEAK_SYMBOL FFMPEG_THREAD_LOCAL int program_birth_year = 2000;
void FFMPEG_THREAD_LOCAL (*show_help_default_func)(const char *opt, const char *arg);
extern void ffmpeg_show_help_default(const char *opt, const char *arg);

// Forward declare the auto-generated TLS initializer
extern void ffmpeg_tls_init_options(void);

// External function requirements from your modified ffmpeg.c
extern int ffmpeg_run_internal(FFmpegContext *ctx, int argc, char **argv);
extern void ffmpeg_reset_internal_state(void);
extern int cancelRequested(long sessionId);

static FFMPEG_THREAD_LOCAL FFmpegContext *current_ffmpeg_context = NULL;
static atomic_int ffmpeg_runtime_unrecoverable = 0;

struct FFmpegContext {
  _Atomic(Scheduler *) sch;
  int ret;
  int argc;
  char **argv;
  atomic_int cancelled;
  atomic_int shutdown_incomplete;
  atomic_uint output_dumped;
  int files_parsed;
  long session_id;
};

static int split_args(const char *args, char ***argv_out) {
  return ffmpegkit_split_command(args, argv_out);
}

FFmpegContext *ffmpeg_init(const char *args_string) {
  if (!args_string)
    return NULL;

  FFmpegContext *ctx = av_mallocz(sizeof(FFmpegContext));
  if (!ctx)
    return NULL;

  // Only parse arguments here. Logic happens in run() to be atomic.
  ctx->argc = split_args(args_string, &ctx->argv);
  if (ctx->argc < 0) {
    av_free(ctx);
    return NULL;
  }

  return ctx;
}

FFmpegContext *ffmpeg_init_argv(int argc, const char *const *argv) {
  if (argc <= 0 || !argv)
    return NULL;

  FFmpegContext *ctx = av_mallocz(sizeof(FFmpegContext));
  if (!ctx)
    return NULL;

  ctx->argv = av_mallocz(sizeof(char *) * (argc + 1));
  if (!ctx->argv) {
    av_free(ctx);
    return NULL;
  }

  ctx->argc = argc;
  for (int i = 0; i < argc; i++) {
    if (!argv[i]) {
      for (int j = 0; j < i; j++)
        av_free(ctx->argv[j]);
      av_free(ctx->argv);
      av_free(ctx);
      return NULL;
    }
    ctx->argv[i] = av_strdup(argv[i]);
    if (!ctx->argv[i]) {
      for (int j = 0; j < i; j++)
        av_free(ctx->argv[j]);
      av_free(ctx->argv);
      av_free(ctx);
      return NULL;
    }
  }

  return ctx;
}

void ffmpeg_set_session_id(FFmpegContext *ctx, long session_id) {
  if (!ctx)
    return;
  ctx->session_id = session_id;
}

int ffmpeg_cancel_requested(const FFmpegContext *ctx) {
  if (!ctx)
    return 0;
  int cancelled = atomic_load(&ctx->cancelled) || cancelRequested(ctx->session_id);
  if (cancelled) {
    av_log(NULL, AV_LOG_DEBUG,
           "[ffmpeg-kit] ffmpeg_cancel_requested: cancellation observed for session_id: %ld\n", ctx->session_id);
  }
  return cancelled;
}

long ffmpeg_get_session_id(const FFmpegContext *ctx) {
  return ctx ? ctx->session_id : 0;
}

void ffmpeg_set_scheduler(FFmpegContext *ctx, Scheduler *sch) {
  if (!ctx)
    return;
  Scheduler *previous = atomic_load(&ctx->sch);
  if (previous && previous != sch) {
    ffmpegkit_unregister_root_context(previous);
  }
  atomic_store(&ctx->sch, sch);
  if (sch) {
    ffmpegkit_register_root_context(sch, ctx->session_id);
  }
}

void ffmpeg_init_interrupt_callback(AVIOInterruptCB *cb) {
  if (!cb)
    return;

  *cb = int_cb;
  cb->opaque = ffmpeg_get_current_context();
}

void ffmpeg_bind_thread_context(FFmpegContext *ctx) {
  current_ffmpeg_context = ctx;
  ffmpegkit_bind_session_id(ctx ? ctx->session_id : 0);
}

void ffmpeg_unbind_thread_context(void) {
  current_ffmpeg_context = NULL;
  ffmpegkit_unbind_session_id();
}

FFmpegContext *ffmpeg_get_current_context(void) {
  return current_ffmpeg_context;
}

void ffmpeg_increment_output_dumped(void) {
  FFmpegContext *ctx = ffmpeg_get_current_context();
  if (ctx)
    atomic_fetch_add(&ctx->output_dumped, 1);
}

unsigned ffmpeg_get_output_dumped(FFmpegContext *ctx) {
  return ctx ? atomic_load(&ctx->output_dumped) : 0;
}

void ffmpeg_reset_output_dumped(FFmpegContext *ctx) {
  if (ctx)
    atomic_store(&ctx->output_dumped, 0);
}

void ffmpeg_mark_shutdown_incomplete(FFmpegContext *ctx) {
  if (!ctx)
    return;
  atomic_store(&ctx->shutdown_incomplete, 1);
}

int ffmpeg_shutdown_incomplete(const FFmpegContext *ctx) {
  return ctx ? atomic_load(&ctx->shutdown_incomplete) : 0;
}

void ffmpeg_mark_runtime_unrecoverable(void) {
  atomic_store(&ffmpeg_runtime_unrecoverable, 1);
}

int ffmpeg_runtime_is_unrecoverable(void) {
  return atomic_load(&ffmpeg_runtime_unrecoverable);
}

int ffmpeg_run(FFmpegContext *ctx) {
  if (!ctx)
    return AVERROR(EINVAL);
  if (ffmpeg_runtime_is_unrecoverable()) {
    av_log(NULL, AV_LOG_ERROR,
           "[ffmpeg-kit] ffmpeg_run: runtime is quarantined after an "
           "incomplete prior shutdown; restart the host process before "
           "starting a new FFmpeg session.\n");
    return AVERROR(ECANCELED);
  }

  ffmpeg_kit_assert_triggered = 0;

  // Establish recovery point for av_assert0 failures inside ffmpeg internals.
  // Without this, av_assert0 calls abort() which kills the Flutter host process.
  // Keep the jump target live until ffmpeg_run_internal() has returned.
  jmp_buf assert_jmp;
  ffmpeg_kit_assert_jmp_ptr = &assert_jmp;
  if (setjmp(assert_jmp)) {
    ffmpeg_kit_assert_jmp_ptr = NULL;
    ffmpeg_unbind_thread_context();
    ffmpeg_mark_shutdown_incomplete(ctx);
    ffmpeg_mark_runtime_unrecoverable();
    av_log(NULL, AV_LOG_ERROR,
           "[ffmpeg-kit] ffmpeg_run: recovered from internal assertion failure. "
           "Session will be marked as failed.\n");
    return AVERROR_EXIT;
  }

  avformat_network_init();

  ffmpeg_tls_init_options();
  show_help_default_func = ffmpeg_show_help_default;

  ffmpeg_bind_thread_context(ctx);
  ctx->ret = ffmpeg_run_internal(ctx, ctx->argc, ctx->argv);
  ffmpeg_unbind_thread_context();
  ffmpeg_kit_assert_jmp_ptr = NULL;
  ctx->files_parsed = (ctx->ret >= 0);

  return ctx->ret;
}

float ffmpeg_get_progress(FFmpegContext *ctx) {
  if (!ctx || !ctx->files_parsed)
    return 0.0f;

  if (nb_output_files > 0) {
    return (float)ffmpeg_get_output_dumped(ctx) / nb_output_files;
  }
  return 0.0f;
}

void ffmpeg_cancel(FFmpegContext *ctx) {
  if (!ctx)
    return;
  av_log(NULL, AV_LOG_DEBUG,
           "[ffmpeg-kit] ffmpeg_cancel: cancelling session for session_id: %ld\n", ctx->session_id);
  atomic_store(&ctx->cancelled, 1);

  // Signal scheduler if it exists
  Scheduler *sch = atomic_load(&ctx->sch);
  if (sch) {
    sch_request_stop(sch);
  }
}

void ffmpeg_free(FFmpegContext *ctx) {
  if (!ctx)
    return;

  // Wrapper context cleanup
  if (ctx->argv) {
    for (int i = 0; i < ctx->argc; i++) {
      av_free(ctx->argv[i]);
    }
    av_free(ctx->argv);
  }

  avformat_network_deinit();
  
  av_free(ctx);
}
