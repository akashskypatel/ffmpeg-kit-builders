/*
 * Copyright (c) 2026 Akash Patel
 *
 * This file is part of FFmpegKit.
 *
 * FFmpegKit is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#ifndef FFMPEGKIT_ARG_PARSER_H
#define FFMPEGKIT_ARG_PARSER_H

#include <ctype.h>
#include <stddef.h>
#include <string.h>

#include "libavutil/mem.h"

/*
 * Splits an FFmpegKit compatibility command string into argv entries.
 *
 * This parser is intentionally shell-independent. Single and double quotes
 * group whitespace, quote delimiters are removed, empty quoted arguments are
 * preserved, and ordinary backslashes remain literal. A backslash only escapes
 * a double quote, an unquoted single quote, or unquoted whitespace. This mirrors
 * FFmpegKitConfig::parseArguments() and, importantly, makes \" inside a
 * double-quoted path produce a literal '"' rather than terminating the token.
 *
 * Prefer the *_init_argv APIs whenever the caller already has tokenized
 * arguments; this parser exists only for compatibility string entry points.
 */
static inline int ffmpegkit_split_command(const char *command,
                                          char ***argv_out) {
  if (!command || !argv_out)
    return -1;

  const size_t length = strlen(command);
  char **argv = av_calloc(length + 2, sizeof(*argv));
  char *token = av_malloc(length + 1);
  if (!argv || !token) {
    av_free(argv);
    av_free(token);
    return -1;
  }

  int argc = 0;
  size_t token_length = 0;
  char quote = 0;
  int token_started = 0;

  for (size_t i = 0; i < length; i++) {
    const char current = command[i];

    if (quote == '\'') {
      if (current == '\'') {
        quote = 0;
      } else {
        token[token_length++] = current;
      }
      token_started = 1;
      continue;
    }

    if (current == '\\' && i + 1 < length) {
      const char next = command[i + 1];
      const int escaped_quote = next == '"' || (!quote && next == '\'');
      const int escaped_whitespace =
          !quote && isspace((unsigned char)next) != 0;
      if (escaped_quote || escaped_whitespace) {
        token[token_length++] = next;
        token_started = 1;
        i++;
        continue;
      }
    }

    if (quote) {
      if (current == quote) {
        quote = 0;
      } else {
        token[token_length++] = current;
      }
      token_started = 1;
      continue;
    }

    if (current == '"' || current == '\'') {
      quote = current;
      token_started = 1;
      continue;
    }

    if (isspace((unsigned char)current) != 0) {
      if (token_started) {
        token[token_length] = '\0';
        argv[argc] = av_strdup(token);
        if (!argv[argc])
          goto fail;
        argc++;
        token_length = 0;
        token_started = 0;
      }
      continue;
    }

    token[token_length++] = current;
    token_started = 1;
  }

  if (token_started) {
    token[token_length] = '\0';
    argv[argc] = av_strdup(token);
    if (!argv[argc])
      goto fail;
    argc++;
  }

  av_free(token);
  *argv_out = argv;
  return argc;

fail:
  for (int i = 0; i < argc; i++)
    av_free(argv[i]);
  av_free(argv);
  av_free(token);
  return -1;
}

#endif /* FFMPEGKIT_ARG_PARSER_H */
