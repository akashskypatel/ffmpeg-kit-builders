/*
 * Private browser HTTP input for FFmpegKit's Emscripten build.
 *
 * This is an internal integration point, not part of the exported C ABI.
 */
#ifndef FFMPEGKIT_WASM_HTTP_IO_H
#define FFMPEGKIT_WASM_HTTP_IO_H

#if defined(__EMSCRIPTEN__)

#include <libavformat/avformat.h>

typedef struct FFmpegKitWasmHttpSession FFmpegKitWasmHttpSession;

__attribute__((visibility("hidden")))
int ffmpegkit_wasm_http_install(AVFormatContext *context, long session_id,
                                FFmpegKitWasmHttpSession **session_out);

/* Call after the owning AVFormatContext has closed all of its AVIO streams. */
__attribute__((visibility("hidden")))
void ffmpegkit_wasm_http_session_free(FFmpegKitWasmHttpSession *session);

#endif

#endif
