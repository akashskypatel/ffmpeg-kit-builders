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

#include "ffprobe_lib.h"
#include "ffprobe.c"
#include "ffmpeg_kit_assert_override.h"
#include "libavutil/mem.h"
#include "libavutil/bprint.h"
#include <stdatomic.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#ifdef _WIN32
  #include <windows.h>
  #include <io.h>
#else
  #include <pthread.h>
  #include <unistd.h>
#endif

FFMPEG_WEAK_SYMBOL FFMPEG_THREAD_LOCAL const char *program_name = "ffprobe";
FFMPEG_WEAK_SYMBOL FFMPEG_THREAD_LOCAL int program_birth_year = 2000;
extern void FFMPEG_THREAD_LOCAL (*show_help_default_func)(const char *opt, const char *arg);
extern void ffprobe_show_help_default(const char *opt, const char *arg);

// Forward declare the auto-generated TLS initializer
extern void ffprobe_tls_init_options(void);
extern int cancelRequested(long sessionId);

extern int ffprobe_run_internal(int argc, char **argv, AVBPrint *output_buf);
extern void ffprobe_reset_internal_state(void);

static FFMPEG_THREAD_LOCAL FFprobeContext *current_ffprobe_context = NULL;

struct FFprobeContext
{
  int ret;
  int argc;
  char **argv;
  AVBPrint output;
  char *output_filename;
  atomic_int cancelled;
  long session_id;
};

// Convert string to argc/argv format with proper quoting
static int split_args(const char *args, char ***argv_out)
{
  if (!args || !argv_out)
    return -1;

  char *args_copy = av_strdup(args);
  if (!args_copy)
    return -1;

  // Count arguments first
  int argc = 0;
  char *p = args_copy;
  int in_quotes = 0;

  while (*p)
  {
    // Skip whitespace
    while (*p && !in_quotes && (*p == ' ' || *p == '\t' || *p == '\n'))
      p++;
    if (!*p)
      break;

    argc++;
    // Find end of argument
    if (*p == '"')
    {
      in_quotes = 1;
      p++;
      while (*p && *p != '"')
        p++;
      if (*p)
        p++;
      in_quotes = 0;
    }
    else
    {
      while (*p && *p != ' ' && *p != '\t' && *p != '\n')
        p++;
    }
  }

  // Allocate argv array
  char **argv = av_mallocz(sizeof(char *) * (argc + 1));
  if (!argv)
  {
    av_free(args_copy);
    return -1;
  }

  // Extract arguments
  strcpy(args_copy, args);
  p = args_copy;
  int idx = 0;

  while (*p && idx < argc)
  {
    // Skip whitespace
    while (*p && (*p == ' ' || *p == '\t' || *p == '\n'))
      p++;
    if (!*p)
      break;

    char *start = p;

    if (*p == '"')
    {
      p++; // Skip opening quote
      start = p;
      while (*p && *p != '"')
        p++;
      if (*p)
        *p++ = '\0'; // Replace closing quote
    }
    else
    {
      while (*p && *p != ' ' && *p != '\t' && *p != '\n')
        p++;
      if (*p)
        *p++ = '\0';
    }

    argv[idx++] = av_strdup(start);
  }

  av_free(args_copy);
  *argv_out = argv;
  return argc;
}

// Custom writer that captures output to AVBPrint
static int write_packet(void *opaque, const uint8_t *buf, int buf_size)
{
  AVBPrint *bp = (AVBPrint *)opaque;
  av_bprint_append_data(bp, (const char *)buf, buf_size);
  return buf_size;
}

FFprobeContext *ffprobe_init_argv(int argc, const char *const *argv)
{
  if (argc <= 0 || !argv)
    return NULL;

  FFprobeContext *ctx = av_mallocz(sizeof(FFprobeContext));
  if (!ctx)
    return NULL;

  av_bprint_init(&ctx->output, 0, AV_BPRINT_SIZE_UNLIMITED);

  ctx->argv = av_mallocz(sizeof(char *) * (argc + 1));
  if (!ctx->argv)
  {
    ffprobe_free(ctx);
    return NULL;
  }

  ctx->argc = argc;
  for (int i = 0; i < argc; i++)
  {
    if (!argv[i])
    {
      ffprobe_free(ctx);
      return NULL;
    }
    ctx->argv[i] = av_strdup(argv[i]);
    if (!ctx->argv[i])
    {
      ffprobe_free(ctx);
      return NULL;
    }
  }

  avformat_network_init();

  ctx->output_filename = av_strdup("buffer:");
  if (!ctx->output_filename)
  {
    ffprobe_free(ctx);
    return NULL;
  }

  return ctx;
}

FFprobeContext *ffprobe_init(const char *args_string)
{
  if (!args_string)
    return NULL;

  FFprobeContext *ctx = av_mallocz(sizeof(FFprobeContext));
  if (!ctx)
    return NULL;

  // Initialize output buffer
  av_bprint_init(&ctx->output, 0, AV_BPRINT_SIZE_UNLIMITED);

  // Convert string to argc/argv
  ctx->argc = split_args(args_string, &ctx->argv);
  if (ctx->argc < 0)
  {
    ffprobe_free(ctx);
    return NULL;
  }

  // Initialize FFmpeg libraries
  avformat_network_init();

  // Set up custom output capture
  ctx->output_filename = av_strdup("buffer:");
  if (!ctx->output_filename)
  {
    ffprobe_free(ctx);
    return NULL;
  }

  return ctx;
}

void ffprobe_set_session_id(FFprobeContext *ctx, long session_id)
{
  if (!ctx)
    return;
  ctx->session_id = session_id;
}

long ffprobe_get_session_id(const FFprobeContext *ctx)
{
  return ctx ? ctx->session_id : 0;
}

void ffprobe_cancel(FFprobeContext *ctx)
{
  if (!ctx)
    return;
  av_log(NULL, AV_LOG_DEBUG,
           "[ffmpeg-kit] ffprobe_cancel: cancelling session for session_id: %ld\n", ctx->session_id);
  atomic_store(&ctx->cancelled, 1);
}

int ffprobe_cancel_requested(const FFprobeContext *ctx)
{
  if (!ctx)
    return 0;
  int cancelled = atomic_load(&ctx->cancelled) || cancelRequested(ctx->session_id);
  if (cancelled) {
    av_log(NULL, AV_LOG_DEBUG,
           "[ffmpeg-kit] ffprobe_cancel_requested: cancellation observed for session_id: %ld\n", ctx->session_id);
  }
  return cancelled;
}

void ffprobe_bind_thread_context(FFprobeContext *ctx)
{
  current_ffprobe_context = ctx;
}

void ffprobe_unbind_thread_context(void)
{
  current_ffprobe_context = NULL;
}

FFprobeContext *ffprobe_get_current_context(void)
{
  return current_ffprobe_context;
}

int ffprobe_run(FFprobeContext *ctx)
{
  if (!ctx)
    return AVERROR(EINVAL);

  ffmpeg_kit_assert_triggered = 0;

  // Establish recovery point for av_assert0 failures inside ffprobe internals.
  jmp_buf assert_jmp;
  ffmpeg_kit_assert_jmp_ptr = &assert_jmp;
  ffmpeg_kit_assert_triggered = 0;
  if (setjmp(assert_jmp)) {
    ffprobe_unbind_thread_context();
    av_log(NULL, AV_LOG_ERROR,
           "[ffmpeg-kit] ffprobe_run: recovered from internal assertion failure. "
           "Session will be marked as failed.\n");
    return AVERROR_EXIT;
  }
  ffmpeg_kit_assert_jmp_ptr = NULL;

  ffprobe_tls_init_options();
  show_help_default_func = ffprobe_show_help_default;

  ffprobe_bind_thread_context(ctx);
  ctx->ret = ffprobe_run_internal(ctx->argc, ctx->argv, &ctx->output);
  ffprobe_unbind_thread_context();

  return ctx->ret;
}

char *ffprobe_get_output(FFprobeContext *ctx)
{
  if (!ctx || !ctx->output.str)
    return NULL;

  // Finalize the buffer and return a copy
  if (!av_bprint_is_complete(&ctx->output))
  {
    // If truncation occurred, we still want to return what we have
    // but av_bprint_finalize would be needed if we wanted to free internal buffers
    // Here we just duplicate what we have.
  }

  return av_strdup(ctx->output.str);
}

size_t ffprobe_get_output_size(FFprobeContext *ctx)
{
  if (!ctx)
    return 0;
  return ctx->output.len;
}

void ffprobe_free(FFprobeContext *ctx)
{
  if (!ctx)
    return;

  // Free argv array
  if (ctx->argv)
  {
    for (int i = 0; i < ctx->argc; i++)
    {
      av_free(ctx->argv[i]);
    }
    av_free(ctx->argv);
  }

  // Free output buffer
  av_bprint_finalize(&ctx->output, NULL);

  // Free output filename
  av_freep(&ctx->output_filename);

  // Clean up FFmpeg
  avformat_network_deinit();

  av_free(ctx);
}
