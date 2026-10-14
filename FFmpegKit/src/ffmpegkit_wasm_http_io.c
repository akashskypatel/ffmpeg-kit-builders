/*
 * Browser HTTP/HTTPS input for FFmpegKit's WebAssembly build.
 *
 * All HTTP access stays inside FFmpegKit-owned code. Reads are issued as
 * bounded byte ranges through Emscripten Fetch and are waited on only by a
 * pthread worker. Local paths continue through FFmpeg's existing public
 * avio_open2 callback. No FFmpeg URLProtocol implementation is registered.
 */
#include "ffmpegkit_wasm_http_io.h"

#if defined(__EMSCRIPTEN__)

#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <math.h>
#if defined(FFMPEG_KIT_TEST_HOOKS)
#include <malloc.h>
#endif
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>

#include <emscripten/fetch.h>
#include <emscripten/emscripten.h>
#include <emscripten/threading.h>
#include <emscripten/proxying.h>

#include <libavformat/avio.h>
#include <libavutil/avstring.h>
#include <libavutil/error.h>
#include <libavutil/macros.h>
#include <libavutil/mem.h>
#include <libavutil/opt.h>

#define WASM_HTTP_MAGIC 0x5741534d48545450ULL
#define WASM_HTTP_READ_BUFFER_SIZE (16 * 1024)
#define WASM_HTTP_RANGE_SIZE (64 * 1024)
#define WASM_HTTP_MAX_BUFFERED_BYTES (1024 * 1024)
#define WASM_HTTP_MAX_OPEN_STREAMS 8
#define WASM_HTTP_MAX_INFLIGHT 4
#define WASM_HTTP_TIMEOUT_MS 30000
#define WASM_HTTP_HEADER_BLOCK_SIZE 8192
#define WASM_HTTP_URL_SIZE 8192
#define WASM_HTTP_LOG_URL_SIZE 512
#define WASM_HTTP_MAX_HEADERS 24

typedef struct WasmHttpIO WasmHttpIO;

enum FetchAbortReason {
    FETCH_ABORT_NONE = 0,
    FETCH_ABORT_LIMIT,
    FETCH_ABORT_TIMEOUT,
    FETCH_ABORT_INTERRUPT,
    FETCH_ABORT_INVALID_RESPONSE,
    FETCH_ABORT_MEMORY
};

typedef struct FetchRequest {
    unsigned int references;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    int done;
    int success;
    int start_complete;
    int mutex_initialized;
    int cond_initialized;
    int headers_seen;
    int fetch_closed;
    int fetch_close_complete;
    int close_requested;
    int close_enqueued;
    int fetch_reference_held;
    int request_acquired;
    int abort_reason;
    int pending_reserved;
    int fetch_buffer_reserved;
    unsigned short status;
    int has_content_length;
    uint64_t content_length;
    size_t pending_size;
    char *headers;
    char *response_url;
    char *username;
    char *password;
    char *request_url;
    char *header_values[WASM_HTTP_MAX_HEADERS * 2];
    const char *request_headers[WASM_HTTP_MAX_HEADERS * 2 + 1];
    size_t request_header_count;
    FFmpegKitWasmHttpSession *session;
    unsigned int timeout_ms;
    int with_credentials;
    uint8_t *data;
    size_t data_size;
    emscripten_fetch_t *fetch;
} FetchRequest;

typedef struct WasmHttpBudget {
    long session_id;
    unsigned int references;
    uint64_t request_count;
    int active_requests;
    int open_streams;
    size_t buffered_bytes;
    size_t pending_bytes;
    size_t peak_retained_bytes;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    struct WasmHttpBudget *next;
} WasmHttpBudget;

struct FFmpegKitWasmHttpSession {
    unsigned int references;
    uint64_t magic;
    uint64_t generation;
    long session_id;
    WasmHttpBudget *budget;
    int budget_registered;
    int with_credentials;
    int (*previous_io_open)(AVFormatContext *, AVIOContext **, const char *,
                            int, AVDictionary **);
    int (*previous_io_close2)(AVFormatContext *, AVIOContext *);
};

struct WasmHttpIO {
    const AVClass *av_class;
    FFmpegKitWasmHttpSession *session;
    AVIOInterruptCB interrupt_callback;
    AVDictionary *options;
    char *url;
    char *location;
    char *headers;
    char *etag;
    char *last_modified;
    int64_t rw_timeout;
    uint8_t *cache;
    size_t cache_size;
    int64_t cache_start;
    int64_t position;
    int64_t length;
    unsigned int timeout_ms;
    int with_credentials;
    int allow_seek;
    int length_known;
    int range_supported;
    int full_response_cached;
    int size_query_logged;
    int browser_header_warning_logged;
};

static pthread_mutex_t generation_mutex = PTHREAD_MUTEX_INITIALIZER;
static uint64_t next_generation = 1;
static pthread_mutex_t budget_registry_mutex = PTHREAD_MUTEX_INITIALIZER;
static WasmHttpBudget *budget_registry = NULL;
static pthread_mutex_t request_queue_mutex = PTHREAD_MUTEX_INITIALIZER;
static em_proxying_queue *request_queue;
#if defined(FFMPEG_KIT_TEST_HOOKS)
static int wasm_http_wait_probe_fail_close_proxy;
static int wasm_http_wait_probe_forced_close_failures;
#endif

static void request_onsuccess(emscripten_fetch_t *fetch);
static void request_onerror(emscripten_fetch_t *fetch);
static void request_onprogress(emscripten_fetch_t *fetch);
static void request_onreadystatechange(emscripten_fetch_t *fetch);
static void request_start_fetch_on_main(void *opaque);
static void request_close_fetch_on_main(void *opaque);
static void request_release(FetchRequest *request);
static void session_release_request(FFmpegKitWasmHttpSession *session);
static int session_reserve_pending(FFmpegKitWasmHttpSession *session,
                                  size_t size);
static void session_release_pending(FFmpegKitWasmHttpSession *session,
                                   size_t size);

static void *wasm_http_io_child_next(void *object, void *previous)
{
    AVIOContext *pb = object;

    if (!pb || previous)
        return NULL;
    return pb->opaque;
}

static const AVClass wasm_http_io_av_class = {
    .class_name = "FFmpegKit WASM HTTP AVIO",
    .version = LIBAVUTIL_VERSION_INT,
    .child_next = wasm_http_io_child_next,
};

static const AVOption wasm_http_io_options[] = {
    { "location", "Effective URL after browser redirects",
      offsetof(WasmHttpIO, location), AV_OPT_TYPE_STRING,
      { .str = NULL }, 0, 0, 0 },
    { "headers", "HTTP headers for nested HLS requests",
      offsetof(WasmHttpIO, headers), AV_OPT_TYPE_STRING,
      { .str = NULL }, 0, 0, 0 },
    { "rw_timeout", "HTTP request timeout in microseconds",
      offsetof(WasmHttpIO, rw_timeout), AV_OPT_TYPE_INT64,
      { .i64 = WASM_HTTP_TIMEOUT_MS * 1000LL }, 0, (double)INT64_MAX, 0 },
    { NULL }
};

static const AVClass wasm_http_io_child_class = {
    .class_name = "FFmpegKit WASM HTTP AVIO state",
    .option = wasm_http_io_options,
    .version = LIBAVUTIL_VERSION_INT,
};

static int interrupt_requested(const AVIOInterruptCB *callback)
{
    return callback && callback->callback &&
           callback->callback(callback->opaque);
}

static int is_http_url(const char *url)
{
    return url && (av_stristart(url, "http://", NULL) ||
                   av_stristart(url, "https://", NULL));
}

static int is_crypto_http_url(const char *url)
{
    return url && (av_stristart(url, "crypto+http://", NULL) ||
                   av_stristart(url, "crypto+https://", NULL));
}

static int is_local_url(const char *url)
{
    const char *colon;
    size_t length;

    if (!url)
        return 0;
    colon = strchr(url, ':');
    if (!colon)
        return 1;
    length = (size_t)(colon - url);
    if (length == 4 && !av_strncasecmp(url, "file", length))
        return 1;
    if (length == 4 && !av_strncasecmp(url, "pipe", length))
        return 1;
    if (length == 2 && !av_strncasecmp(url, "fd", length))
        return 1;
    return 0;
}

static const char *safe_url_for_log(const char *url, char *buffer,
                                    size_t buffer_size)
{
    const char *authority, *authority_end, *at;
    size_t prefix_size, authority_size, suffix_size;

    if (!url || !buffer || !buffer_size)
        return "(null)";
    if (strlen(url) >= buffer_size)
        return "(URL redacted; truncated)";
    av_strlcpy(buffer, url, buffer_size);
    authority = strstr(buffer, "://");
    if (authority) {
        authority += 3;
        authority_end = strpbrk(authority, "/?#");
        if (!authority_end)
            authority_end = buffer + strlen(buffer);
        at = memchr(authority, '@', (size_t)(authority_end - authority));
        if (at) {
            prefix_size = (size_t)(authority - buffer);
            authority_size = (size_t)(authority_end - at - 1);
            suffix_size = strlen(authority_end);
            if (prefix_size + authority_size + suffix_size + 1 > buffer_size)
                return "(URL redacted)";
            memmove(buffer + prefix_size, at + 1,
                    authority_size + suffix_size);
            buffer[prefix_size + authority_size + suffix_size] = '\0';
        }
    }
    {
        char *query = strpbrk(buffer, "?#");
        if (query)
            *query = '\0';
    }
    return buffer;
}

static int map_http_status(unsigned short status)
{
    if (status == 401 || status == 403)
        return AVERROR(EACCES);
    if (status == 404)
        return AVERROR(ENOENT);
    if (status == 416)
        return AVERROR(ERANGE);
    if (status >= 400)
        return AVERROR(EIO);
    return AVERROR(EIO);
}

static int parse_unsigned(const char *value, uint64_t *result)
{
    char *end = NULL;
    unsigned long long parsed;

    if (!value || !*value)
        return AVERROR(EINVAL);
    errno = 0;
    parsed = strtoull(value, &end, 10);
    if (errno || end == value || *end)
        return AVERROR(EINVAL);
    *result = (uint64_t)parsed;
    return 0;
}

static int find_header(const char *headers, const char *name,
                       char *value, size_t value_size)
{
    const char *line = headers;
    size_t name_size = strlen(name);

    if (!headers || !value || !value_size)
        return 0;
    value[0] = '\0';
    while (*line) {
        const char *end = strstr(line, "\r\n");
        const char *colon;
        size_t line_size = end ? (size_t)(end - line) : strlen(line);

        if (!line_size)
            break;
        colon = memchr(line, ':', line_size);
        if (colon && (size_t)(colon - line) == name_size &&
            !strncasecmp(line, name, name_size)) {
            const char *start = colon + 1;
            const char *finish = line + line_size;
            size_t copy_size;

            while (start < finish && (*start == ' ' || *start == '\t'))
                start++;
            while (finish > start && (finish[-1] == ' ' || finish[-1] == '\t'))
                finish--;
            copy_size = FFMIN((size_t)(finish - start), value_size - 1);
            memcpy(value, start, copy_size);
            value[copy_size] = '\0';
            return 1;
        }
        if (!end)
            break;
        line = end + 2;
    }
    return 0;
}

static int parse_content_range(const char *headers, int *present,
                               uint64_t *start, uint64_t *end,
                               uint64_t *total, int *unsatisfied)
{
    char value[192];
    unsigned long long first, last, size;
    int matched;

    *present = 0;
    *unsatisfied = 0;
    if (!find_header(headers, "Content-Range", value, sizeof(value)))
        return 0;
    *present = 1;
    if (av_stristart(value, "bytes */", NULL)) {
        if (parse_unsigned(value + 8, total) < 0)
            return AVERROR_INVALIDDATA;
        if (*total > INT64_MAX)
            return AVERROR(EOVERFLOW);
        *unsatisfied = 1;
        return 0;
    }
    if (!av_stristart(value, "bytes ", NULL))
        return AVERROR_INVALIDDATA;
    {
        int consumed = 0;
        matched = sscanf(value + 6, "%llu-%llu/%llu%n", &first, &last,
                         &size, &consumed);
        if (matched != 3 || !consumed || value[6 + consumed] != '\0' ||
            last < first || size <= last)
            return AVERROR_INVALIDDATA;
    }
    if (size > INT64_MAX)
        return AVERROR(EOVERFLOW);
    *start = first;
    *end = last;
    *total = size;
    return 0;
}

static int request_add_header(FetchRequest *request, const char *name,
                              const char *value)
{
    size_t index = request->request_header_count;

    if (index + 2 > FF_ARRAY_ELEMS(request->request_headers) - 1)
        return AVERROR(ENOBUFS);
    request->header_values[index] = av_strdup(name);
    request->header_values[index + 1] = av_strdup(value);
    if (!request->header_values[index] || !request->header_values[index + 1])
        return AVERROR(ENOMEM);
    request->request_headers[index] = request->header_values[index];
    request->request_headers[index + 1] = request->header_values[index + 1];
    request->request_header_count += 2;
    request->request_headers[request->request_header_count] = NULL;
    return 0;
}

static int utf8_next_codepoint(const unsigned char **text, uint32_t *codepoint)
{
    const unsigned char *p = *text;
    uint32_t value;
    unsigned int continuation_count;
    uint32_t minimum;
    unsigned int i;

    if (!*p)
        return 0;
    if (p[0] < 0x80) {
        *codepoint = p[0];
        *text = p + 1;
        return 1;
    }
    if (p[0] >= 0xC2 && p[0] <= 0xDF) {
        value = p[0] & 0x1F;
        continuation_count = 1;
        minimum = 0x80;
    } else if (p[0] >= 0xE0 && p[0] <= 0xEF) {
        value = p[0] & 0x0F;
        continuation_count = 2;
        minimum = 0x800;
    } else if (p[0] >= 0xF0 && p[0] <= 0xF4) {
        value = p[0] & 0x07;
        continuation_count = 3;
        minimum = 0x10000;
    } else {
        return 0;
    }
    for (i = 1; i <= continuation_count; i++) {
        if (!p[i] || (p[i] & 0xC0) != 0x80)
            return 0;
        value = (value << 6) | (p[i] & 0x3F);
    }
    if (value < minimum || value > 0x10FFFF ||
        (value >= 0xD800 && value <= 0xDFFF))
        return 0;
    *codepoint = value;
    *text = p + continuation_count + 1;
    return 1;
}

static int valid_http_header_name(const char *name)
{
    const unsigned char *p = (const unsigned char *)name;

    if (!p || !*p)
        return 0;
    for (; *p; p++) {
        unsigned char c = *p;
        if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
            (c >= 'a' && c <= 'z') || c == '!' || c == '#' || c == '$' ||
            c == '%' || c == '&' || c == '\'' || c == '*' || c == '+' ||
            c == '-' || c == '.' || c == '^' || c == '_' || c == '`' ||
            c == '|' || c == '~')
            continue;
        return 0;
    }
    return 1;
}

static int valid_http_header_value(const char *value)
{
    const unsigned char *p = (const unsigned char *)value;
    uint32_t codepoint;

    while (*p) {
        if (!utf8_next_codepoint(&p, &codepoint) || codepoint > 0xFF ||
            codepoint == '\r' || codepoint == '\n' ||
            (codepoint < 0x20 && codepoint != '\t') || codepoint == 0x7F)
            return 0;
    }
    return 1;
}

static int fetch_forbidden_header(const char *name)
{
    static const char *const exact_names[] = {
        "accept-charset", "accept-encoding", "access-control-request-headers",
        "access-control-request-method", "connection", "content-length",
        "cookie", "cookie2", "date", "dnt", "expect", "host",
        "keep-alive", "origin", "referer", "range", "set-cookie", "te",
        "trailer", "transfer-encoding", "upgrade", "user-agent", "via"
    };
    size_t i;

    if (!strncasecmp(name, "proxy-", 6) || !strncasecmp(name, "sec-", 4))
        return 1;
    for (i = 0; i < FF_ARRAY_ELEMS(exact_names); i++)
        if (!strcasecmp(name, exact_names[i]))
            return 1;
    return 0;
}

static void append_ignored_header(char *list, size_t list_size,
                                  const char *name)
{
    size_t used = strlen(list);
    size_t i;

    if (used && used + 2 < list_size) {
        list[used++] = ',';
        list[used++] = ' ';
        list[used] = '\0';
    }
    for (i = 0; name[i] && i < 48 && used + 1 < list_size; i++) {
        unsigned char c = (unsigned char)name[i];
        list[used++] = c >= 0x20 && c <= 0x7E ? (char)c : '?';
    }
    if (name[i] && used + 4 < list_size) {
        memcpy(list + used, "...", 4);
    } else {
        list[used] = '\0';
    }
}

static void log_invalid_header(const char *name)
{
    char safe_name[128];
    size_t i;

    if (!name) {
        av_log(NULL, AV_LOG_ERROR,
               "WASM browser transport rejected a malformed request header line\n");
        return;
    }
    for (i = 0; name[i] && i + 1 < sizeof(safe_name); i++) {
        unsigned char c = (unsigned char)name[i];
        safe_name[i] = c >= 0x20 && c <= 0x7E ? (char)c : '?';
    }
    if (name[i]) {
        safe_name[i++] = '.';
        if (i + 1 < sizeof(safe_name)) safe_name[i++] = '.';
        if (i + 1 < sizeof(safe_name)) safe_name[i++] = '.';
    }
    safe_name[i] = '\0';
    av_log(NULL, AV_LOG_ERROR,
           "WASM browser transport rejected invalid request header name/value: %s\n",
           safe_name);
}

static int invalid_http_url_character(const char *url)
{
    const unsigned char *p = (const unsigned char *)url;
    uint32_t codepoint;

    while (*p) {
        if (!utf8_next_codepoint(&p, &codepoint))
            return 1;
        if (codepoint <= 0x20 || (codepoint >= 0x7F && codepoint <= 0x9F) ||
            codepoint == 0xA0 || codepoint == 0x1680 ||
            (codepoint >= 0x2000 && codepoint <= 0x200A) ||
            codepoint == 0x2028 || codepoint == 0x2029 ||
            codepoint == 0x202F || codepoint == 0x205F ||
            codepoint == 0x3000)
            return 1;
    }
    return 0;
}

static emscripten_fetch_t *ffkit_emscripten_fetch_call(
    emscripten_fetch_attr_t *attributes, const char *url)
{
    return emscripten_fetch(attributes, url);
}

EM_JS(uintptr_t, ffkit_emscripten_fetch_catching_exceptions,
      (emscripten_fetch_attr_t *attributes, const char *url,
       uintptr_t fetch_function), {
    try {
        return getWasmTableEntry(fetch_function)(attributes, url);
    } catch (error) {
        return 0;
    }
});

static int request_add_option_headers(FetchRequest *request,
                                      const AVDictionary *options,
                                      WasmHttpIO *io)
{
    const AVDictionaryEntry *entry = av_dict_get(options, "headers", NULL, 0);
    char *headers, *save = NULL, *line;
    char ignored_headers[256] = { 0 };
    int ret = 0;

    if (!entry || !entry->value || !*entry->value)
        return 0;
    headers = av_strdup(entry->value);
    if (!headers)
        return AVERROR(ENOMEM);
    line = av_strtok(headers, "\r\n", &save);
    while (line) {
        char *colon = strchr(line, ':');
        char *name = line;
        char *value;
        char *end;

        if (!colon || colon == line) {
            log_invalid_header(colon ? line : NULL);
            ret = AVERROR(EINVAL);
            break;
        }
        *colon = '\0';
        value = colon + 1;
        while (*value == ' ' || *value == '\t')
            value++;
        end = value + strlen(value);
        while (end > value && (end[-1] == ' ' || end[-1] == '\t'))
            *--end = '\0';
        if (!valid_http_header_name(name) || !valid_http_header_value(value)) {
            log_invalid_header(name);
            ret = AVERROR(EINVAL);
            break;
        }
        if (fetch_forbidden_header(name)) {
            append_ignored_header(ignored_headers, sizeof(ignored_headers), name);
        } else {
            ret = request_add_header(request, name, value);
            if (ret < 0)
                break;
        }
        line = av_strtok(NULL, "\r\n", &save);
    }
    av_free(headers);
    if (ignored_headers[0] &&
        !__atomic_exchange_n(&io->browser_header_warning_logged, 1,
                             __ATOMIC_ACQ_REL))
        av_log(NULL, AV_LOG_WARNING,
               "WASM browser transport ignored browser-controlled request header(s): %s\n",
               ignored_headers);
    return ret;
}

static int split_url_credentials(FetchRequest *request, const char *url)
{
    const char *authority, *authority_end, *at, *colon;
    size_t prefix_size, suffix_size, authority_size;
    char *sanitized;

    request->request_url = av_strdup(url);
    if (!request->request_url)
        return AVERROR(ENOMEM);
    authority = strstr(url, "://");
    if (!authority)
        return 0;
    authority += 3;
    authority_end = strpbrk(authority, "/?#");
    if (!authority_end)
        authority_end = url + strlen(url);
    at = memchr(authority, '@', (size_t)(authority_end - authority));
    if (!at)
        return 0;

    colon = memchr(authority, ':', (size_t)(at - authority));
    request->username = av_strndup(authority,
                                   colon ? (size_t)(colon - authority) :
                                           (size_t)(at - authority));
    if (colon)
        request->password = av_strndup(colon + 1, (size_t)(at - colon - 1));
    if (!request->username || (colon && !request->password))
        return AVERROR(ENOMEM);

    prefix_size = (size_t)(authority - url);
    suffix_size = strlen(at + 1);
    authority_size = (size_t)(authority_end - at - 1);
    sanitized = av_malloc(prefix_size + authority_size + suffix_size + 1);
    if (!sanitized)
        return AVERROR(ENOMEM);
    memcpy(sanitized, url, prefix_size);
    memcpy(sanitized + prefix_size, at + 1, authority_size);
    memcpy(sanitized + prefix_size + authority_size, authority_end,
           suffix_size);
    sanitized[prefix_size + authority_size + suffix_size] = '\0';
    av_freep(&request->request_url);
    request->request_url = sanitized;
    return 0;
}

static int request_add_range(FetchRequest *request, int64_t start,
                             size_t length)
{
    char range[96];
    uint64_t range_length = (uint64_t)length;
    uint64_t end;

    if (start < 0 || !range_length || range_length > INT64_MAX ||
        (uint64_t)start > (uint64_t)INT64_MAX - range_length)
        return AVERROR(EINVAL);
    end = (uint64_t)start + range_length - 1;
    snprintf(range, sizeof(range), "bytes=%" PRId64 "-%" PRIu64, start, end);
    return request_add_header(request, "Range", range);
}

static void request_retain(FetchRequest *request)
{
    __atomic_add_fetch(&request->references, 1, __ATOMIC_RELAXED);
}

/* Each queued task owns a reference until its main-thread entry returns. */
static int request_proxy(FetchRequest *request, void (*function)(void *))
{
    em_proxying_queue *queue;
    /* Retry a failed first allocation on the next request. A transient OOM
     * must not permanently disable transport through a completed once flag. */
    pthread_mutex_lock(&request_queue_mutex);
    if (!request_queue)
        request_queue = em_proxying_queue_create();
    queue = request_queue;
    pthread_mutex_unlock(&request_queue_mutex);
    if (!queue)
        return AVERROR(ENOMEM);
#if defined(FFMPEG_KIT_TEST_HOOKS)
    if (function == request_close_fetch_on_main &&
        __atomic_exchange_n(&wasm_http_wait_probe_fail_close_proxy, 0,
                             __ATOMIC_ACQ_REL)) {
        __atomic_add_fetch(&wasm_http_wait_probe_forced_close_failures, 1,
                           __ATOMIC_RELAXED);
        return AVERROR(ENOMEM);
    }
#endif
    request_retain(request);
    if (!emscripten_proxy_async(queue,
                                emscripten_main_runtime_thread_id(),
                                function, request)) {
        request_release(request);
        return AVERROR(ENOMEM);
    }
    return 0;
}

static void request_close_fetch(FetchRequest *request)
{
    emscripten_fetch_t *fetch = NULL;
    int release_fetch_reference = 0;

    pthread_mutex_lock(&request->mutex);
    if (request->fetch_close_complete) {
        pthread_mutex_unlock(&request->mutex);
        return;
    }
    if (!request->done) {
        request->success = 0;
        request->done = 1;
    }
    if (!request->start_complete) {
        pthread_cond_broadcast(&request->cond);
        pthread_mutex_unlock(&request->mutex);
        return;
    }
    if (request->fetch && !request->fetch_closed) {
        request->fetch_closed = 1;
        fetch = request->fetch;
        request->fetch = NULL;
    }
    pthread_mutex_unlock(&request->mutex);

    if (fetch)
        emscripten_fetch_close(fetch);

    pthread_mutex_lock(&request->mutex);
    if (request->fetch_buffer_reserved) {
        session_release_pending(request->session, WASM_HTTP_RANGE_SIZE);
        request->fetch_buffer_reserved = 0;
    }
    if (request->request_acquired) {
        session_release_request(request->session);
        request->request_acquired = 0;
    }
    if (request->fetch_reference_held) {
        request->fetch_reference_held = 0;
        release_fetch_reference = 1;
    }
    request->fetch_close_complete = 1;
    pthread_cond_broadcast(&request->cond);
    pthread_mutex_unlock(&request->mutex);
    if (release_fetch_reference)
        request_release(request);
}

static void request_close_fetch_on_main(void *opaque)
{
    FetchRequest *request = opaque;
    request_close_fetch(request);
    request_release(request);
}

static void request_schedule_close(FetchRequest *request)
{
    int close_inline = 0;

    pthread_mutex_lock(&request->mutex);
    request->close_requested = 1;
    if (!request->close_enqueued && !request->fetch_closed &&
        !request->fetch_close_complete) {
        request->close_enqueued = 1;
        if (emscripten_is_main_runtime_thread()) {
            close_inline = 1;
        } else if (request_proxy(request, request_close_fetch_on_main) < 0) {
            /* Publish enqueue failure before a callback can observe the flag.
             * The queued start or next Fetch callback then closes inline. */
            request->close_enqueued = 0;
        }
    }
    pthread_mutex_unlock(&request->mutex);

    if (close_inline)
        request_close_fetch(request);
}

static void request_start_fetch_on_main(void *opaque)
{
    FetchRequest *request = opaque;
    emscripten_fetch_attr_t attributes;
    int close_after_start;
    int release_fetch_reference = 0;

    pthread_mutex_lock(&request->mutex);
    if (request->close_requested) {
        request->done = 1;
        request->success = 0;
        request->start_complete = 1;
        pthread_cond_broadcast(&request->cond);
        pthread_mutex_unlock(&request->mutex);
        request_close_fetch(request);
        request_release(request);
        return;
    }
    /* The Fetch object owns this reference across all of its callbacks. Each
     * callback additionally retains the request across a reentrant close. */
    request_retain(request);
    request->fetch_reference_held = 1;
    pthread_mutex_unlock(&request->mutex);

    emscripten_fetch_attr_init(&attributes);
    strcpy(attributes.requestMethod, "GET");
    attributes.userData = request;
    attributes.onsuccess = request_onsuccess;
    attributes.onerror = request_onerror;
    attributes.onprogress = request_onprogress;
    attributes.onreadystatechange = request_onreadystatechange;
    attributes.attributes = EMSCRIPTEN_FETCH_LOAD_TO_MEMORY |
                            EMSCRIPTEN_FETCH_REPLACE;
    attributes.timeoutMSecs = request->timeout_ms > UINT_MAX - 1000
                                  ? UINT_MAX : request->timeout_ms + 1000;
    attributes.requestHeaders = request->request_headers;
    attributes.userName = request->username;
    attributes.password = request->password;
    attributes.withCredentials = request->with_credentials;

    request->fetch = (emscripten_fetch_t *)(uintptr_t)
        ffkit_emscripten_fetch_catching_exceptions(
            &attributes, request->request_url,
            (uintptr_t)ffkit_emscripten_fetch_call);

    pthread_mutex_lock(&request->mutex);
    request->start_complete = 1;
    close_after_start = request->close_requested;
    if (!request->fetch) {
        request->status = 0;
        if (request->abort_reason == FETCH_ABORT_NONE)
            request->abort_reason = FETCH_ABORT_INVALID_RESPONSE;
        request->success = 0;
        request->done = 1;
        request->fetch_reference_held = 0;
        release_fetch_reference = 1;
        close_after_start = 1;
    }
    pthread_cond_broadcast(&request->cond);
    pthread_mutex_unlock(&request->mutex);
    if (close_after_start)
        request_close_fetch(request);
    if (release_fetch_reference)
        request_release(request);
    request_release(request);
}

static void request_capture_headers(FetchRequest *request,
                                    emscripten_fetch_t *fetch)
{
    size_t length;
    const char *response_url;

    if (request->close_requested || request->headers_seen || fetch->readyState < 2)
        return;
    request->headers_seen = 1;
    request->status = fetch->status;
    length = emscripten_fetch_get_response_headers_length(fetch);
    if (length >= WASM_HTTP_HEADER_BLOCK_SIZE) {
        request->abort_reason = FETCH_ABORT_INVALID_RESPONSE;
        return;
    }
    request->headers = av_mallocz(length + 1);
    if (!request->headers) {
        request->abort_reason = FETCH_ABORT_MEMORY;
        return;
    }
    if (length)
        emscripten_fetch_get_response_headers(fetch, request->headers, length + 1);
    {
        char content_length[64];
        if (find_header(request->headers, "Content-Length", content_length,
                        sizeof(content_length)) &&
            parse_unsigned(content_length, &request->content_length) == 0)
            request->has_content_length = 1;
    }
    response_url = fetch->responseUrl ? fetch->responseUrl : request->request_url;
    if (response_url) {
        if (strlen(response_url) >= WASM_HTTP_URL_SIZE) {
            request->abort_reason = FETCH_ABORT_INVALID_RESPONSE;
            return;
        }
        request->response_url = av_strdup(response_url);
        if (!request->response_url)
            request->abort_reason = FETCH_ABORT_MEMORY;
    }
}

static void request_onreadystatechange(emscripten_fetch_t *fetch)
{
    FetchRequest *request = fetch->userData;
    int should_abort = 0;

    if (!request)
        return;
    request_retain(request);
    pthread_mutex_lock(&request->mutex);
    request_capture_headers(request, fetch);
    if (request->abort_reason != FETCH_ABORT_NONE || request->close_requested) {
        should_abort = 1;
    } else if (request->headers_seen && request->status >= 400) {
        /* Error bodies are not needed; stop before XHR buffers them. */
        should_abort = 1;
    } else if (request->headers_seen &&
               request->has_content_length &&
               request->content_length > WASM_HTTP_RANGE_SIZE) {
        request->abort_reason = FETCH_ABORT_LIMIT;
        should_abort = 1;
    }
    pthread_mutex_unlock(&request->mutex);

    if (should_abort)
        request_schedule_close(request);
    request_release(request);
}

static void request_onprogress(emscripten_fetch_t *fetch)
{
    FetchRequest *request = fetch->userData;
    int should_abort = 0;

    if (!request)
        return;
    request_retain(request);
    pthread_mutex_lock(&request->mutex);
    request_capture_headers(request, fetch);
    if (request->abort_reason != FETCH_ABORT_NONE || request->close_requested) {
        should_abort = 1;
    } else if (request->status >= 400) {
        should_abort = 1;
    } else if (fetch->totalBytes > WASM_HTTP_RANGE_SIZE ||
               fetch->dataOffset > WASM_HTTP_RANGE_SIZE ||
               fetch->numBytes > WASM_HTTP_RANGE_SIZE) {
        if (request->abort_reason == FETCH_ABORT_NONE)
            request->abort_reason = FETCH_ABORT_LIMIT;
        should_abort = 1;
    }
    pthread_mutex_unlock(&request->mutex);

    if (should_abort)
        request_schedule_close(request);
    request_release(request);
}

static void request_onsuccess(emscripten_fetch_t *fetch)
{
    FetchRequest *request = fetch->userData;
    uint8_t *data = NULL;
    int valid = 1;

    if (!request)
        return;
    request_retain(request);
    pthread_mutex_lock(&request->mutex);
    request_capture_headers(request, fetch);
    valid = request->abort_reason == FETCH_ABORT_NONE && !request->close_requested;
    if (request->has_content_length &&
        request->content_length > WASM_HTTP_RANGE_SIZE) {
        request->abort_reason = FETCH_ABORT_LIMIT;
        valid = 0;
    }
    if (valid && (fetch->numBytes > WASM_HTTP_RANGE_SIZE ||
                  fetch->numBytes > SIZE_MAX ||
                  (fetch->numBytes && !fetch->data))) {
        request->abort_reason = FETCH_ABORT_LIMIT;
        valid = 0;
    } else if (valid && fetch->numBytes) {
        size_t data_size = (size_t)fetch->numBytes;
        size_t reserve_size = data_size;
        int ret = session_reserve_pending(request->session, reserve_size);
        if (ret < 0) {
            request->abort_reason = FETCH_ABORT_LIMIT;
            valid = 0;
        } else {
            request->pending_reserved = 1;
            request->pending_size = reserve_size;
            data = av_memdup(fetch->data, data_size);
            if (!data) {
                session_release_pending(request->session, reserve_size);
                request->pending_reserved = 0;
                request->pending_size = 0;
                request->abort_reason = FETCH_ABORT_MEMORY;
                valid = 0;
            }
        }
    }
    request->data = data;
    request->data_size = valid ? (size_t)fetch->numBytes : 0;
    request->status = fetch->status;
    request->success = valid;
    request->done = 1;
    pthread_cond_broadcast(&request->cond);
    pthread_mutex_unlock(&request->mutex);
    request_schedule_close(request);
    request_release(request);
}

static void request_onerror(emscripten_fetch_t *fetch)
{
    FetchRequest *request = fetch->userData;

    if (!request)
        return;
    request_retain(request);
    pthread_mutex_lock(&request->mutex);
    /* fetch_close invokes onerror with an unsigned -1 status. Preserve the
     * response status and the reason already recorded by our close path. */
    if (!request->close_requested && fetch->status != (unsigned short)-1) {
        request_capture_headers(request, fetch);
        if (fetch->status < 400 || request->status < 400)
            request->status = fetch->status;
    }
    request->success = 0;
    request->done = 1;
    pthread_cond_broadcast(&request->cond);
    pthread_mutex_unlock(&request->mutex);
    request_schedule_close(request);
    request_release(request);
}

static void request_release(FetchRequest *request)
{
    size_t i;

    if (__atomic_sub_fetch(&request->references, 1, __ATOMIC_ACQ_REL))
        return;
    for (i = 0; i < FF_ARRAY_ELEMS(request->header_values); i++)
        av_freep(&request->header_values[i]);
    av_freep(&request->data);
    if (request->pending_reserved)
        session_release_pending(request->session, request->pending_size);
    if (request->fetch_buffer_reserved)
        session_release_pending(request->session, WASM_HTTP_RANGE_SIZE);
    if (request->request_acquired)
        session_release_request(request->session);
    av_freep(&request->headers);
    av_freep(&request->response_url);
    av_freep(&request->username);
    av_freep(&request->password);
    av_freep(&request->request_url);
    if (request->cond_initialized)
        pthread_cond_destroy(&request->cond);
    if (request->mutex_initialized)
        pthread_mutex_destroy(&request->mutex);
    ffmpegkit_wasm_http_session_free(request->session);
    av_free(request);
}

static int wasm_http_budget_create(long session_id, WasmHttpBudget **budget_out)
{
    WasmHttpBudget *budget;
    int ret;

    *budget_out = NULL;
    budget = av_mallocz(sizeof(*budget));
    if (!budget)
        return AVERROR(ENOMEM);
    ret = pthread_mutex_init(&budget->mutex, NULL);
    if (ret) {
        av_free(budget);
        return AVERROR(ret);
    }
    ret = pthread_cond_init(&budget->cond, NULL);
    if (ret) {
        pthread_mutex_destroy(&budget->mutex);
        av_free(budget);
        return AVERROR(ret);
    }
    budget->session_id = session_id;
    budget->references = 1;
    *budget_out = budget;
    return 0;
}

static int session_budget_acquire(FFmpegKitWasmHttpSession *session)
{
    WasmHttpBudget *budget;
    int ret;

    if (!session->session_id) {
        ret = wasm_http_budget_create(0, &session->budget);
        return ret;
    }

    pthread_mutex_lock(&budget_registry_mutex);
    for (budget = budget_registry; budget; budget = budget->next) {
        if (budget->session_id == session->session_id) {
            if (budget->references == UINT_MAX) {
                pthread_mutex_unlock(&budget_registry_mutex);
                return AVERROR(EOVERFLOW);
            }
            budget->references++;
            session->budget = budget;
            session->budget_registered = 1;
            pthread_mutex_unlock(&budget_registry_mutex);
            return 0;
        }
    }

    ret = wasm_http_budget_create(session->session_id, &budget);
    if (ret >= 0) {
        budget->next = budget_registry;
        budget_registry = budget;
        session->budget = budget;
        session->budget_registered = 1;
    }
    pthread_mutex_unlock(&budget_registry_mutex);
    return ret;
}

static void session_budget_release(FFmpegKitWasmHttpSession *session)
{
    WasmHttpBudget *budget = session->budget;
    int destroy = 0;

    if (!budget)
        return;
    if (session->budget_registered) {
        WasmHttpBudget **link;
        pthread_mutex_lock(&budget_registry_mutex);
        if (budget->references > 0)
            budget->references--;
        if (!budget->references) {
            for (link = &budget_registry; *link; link = &(*link)->next) {
                if (*link == budget) {
                    *link = budget->next;
                    break;
                }
            }
            destroy = 1;
        }
        pthread_mutex_unlock(&budget_registry_mutex);
    } else {
        destroy = 1;
    }

    if (destroy) {
        av_log(NULL, AV_LOG_DEBUG,
               "WASM HTTP budget complete session=%ld requests=%" PRIu64
               " peak_retained=%zu cached=%zu pending=%zu open_streams=%d active_requests=%d\n",
               session->session_id,
               budget->request_count, budget->peak_retained_bytes,
               budget->buffered_bytes, budget->pending_bytes,
               budget->open_streams,
               budget->active_requests);
        pthread_cond_destroy(&budget->cond);
        pthread_mutex_destroy(&budget->mutex);
        av_free(budget);
    }
    session->budget = NULL;
}

static int session_acquire_request(FFmpegKitWasmHttpSession *session,
                                   const AVIOInterruptCB *interrupt,
                                   unsigned int timeout_ms)
{
    WasmHttpBudget *budget = session->budget;
    struct timespec deadline;
    int ret = 0;

    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += timeout_ms / 1000;
    deadline.tv_nsec += (timeout_ms % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec++;
        deadline.tv_nsec -= 1000000000L;
    }

    pthread_mutex_lock(&budget->mutex);
    while (budget->active_requests >= WASM_HTTP_MAX_INFLIGHT) {
        struct timespec short_deadline;
        if (interrupt_requested(interrupt)) {
            ret = AVERROR_EXIT;
            break;
        }
        clock_gettime(CLOCK_REALTIME, &short_deadline);
        short_deadline.tv_nsec += 100000000L;
        if (short_deadline.tv_nsec >= 1000000000L) {
            short_deadline.tv_sec++;
            short_deadline.tv_nsec -= 1000000000L;
        }
        if (short_deadline.tv_sec > deadline.tv_sec ||
            (short_deadline.tv_sec == deadline.tv_sec &&
             short_deadline.tv_nsec > deadline.tv_nsec))
            short_deadline = deadline;
        ret = pthread_cond_timedwait(&budget->cond, &budget->mutex,
                                     &short_deadline);
        if (ret == ETIMEDOUT) {
            struct timespec now;
            clock_gettime(CLOCK_REALTIME, &now);
            if (now.tv_sec > deadline.tv_sec ||
                (now.tv_sec == deadline.tv_sec && now.tv_nsec >= deadline.tv_nsec)) {
                ret = AVERROR(ETIMEDOUT);
                break;
            }
            ret = 0;
        } else if (ret) {
            ret = AVERROR(ret);
            break;
        }
    }
    if (!ret) {
        if (budget->buffered_bytes > WASM_HTTP_MAX_BUFFERED_BYTES ||
            budget->pending_bytes > WASM_HTTP_MAX_BUFFERED_BYTES -
                                    budget->buffered_bytes ||
            WASM_HTTP_RANGE_SIZE > WASM_HTTP_MAX_BUFFERED_BYTES -
                                   budget->buffered_bytes -
                                   budget->pending_bytes) {
            ret = AVERROR(ENOBUFS);
        } else {
            budget->active_requests++;
            budget->request_count++;
            budget->pending_bytes += WASM_HTTP_RANGE_SIZE;
            if (budget->buffered_bytes + budget->pending_bytes >
                budget->peak_retained_bytes)
                budget->peak_retained_bytes = budget->buffered_bytes +
                                              budget->pending_bytes;
        }
    }
    pthread_mutex_unlock(&budget->mutex);
    return ret;
}

static void session_release_request(FFmpegKitWasmHttpSession *session)
{
    WasmHttpBudget *budget = session->budget;
    pthread_mutex_lock(&budget->mutex);
    if (budget->active_requests > 0)
        budget->active_requests--;
    pthread_cond_broadcast(&budget->cond);
    pthread_mutex_unlock(&budget->mutex);
}

static int session_reserve_pending(FFmpegKitWasmHttpSession *session,
                                  size_t size)
{
    WasmHttpBudget *budget = session->budget;
    int ret = 0;

    pthread_mutex_lock(&budget->mutex);
    if (budget->buffered_bytes > WASM_HTTP_MAX_BUFFERED_BYTES ||
        budget->pending_bytes > WASM_HTTP_MAX_BUFFERED_BYTES -
                                budget->buffered_bytes ||
        size > WASM_HTTP_MAX_BUFFERED_BYTES - budget->buffered_bytes -
               budget->pending_bytes) {
        ret = AVERROR(ENOBUFS);
    } else {
        budget->pending_bytes += size;
        if (budget->buffered_bytes + budget->pending_bytes >
            budget->peak_retained_bytes)
            budget->peak_retained_bytes = budget->buffered_bytes +
                                          budget->pending_bytes;
    }
    pthread_mutex_unlock(&budget->mutex);
    return ret;
}

static int session_transfer_pending_to_cache(
    FFmpegKitWasmHttpSession *session, size_t size)
{
    WasmHttpBudget *budget = session->budget;
    int ret = 0;

    pthread_mutex_lock(&budget->mutex);
    if (budget->buffered_bytes > WASM_HTTP_MAX_BUFFERED_BYTES ||
        size > budget->pending_bytes ||
        size > WASM_HTTP_MAX_BUFFERED_BYTES - budget->buffered_bytes) {
        ret = AVERROR(ENOBUFS);
    } else {
        budget->pending_bytes -= size;
        budget->buffered_bytes += size;
    }
    pthread_mutex_unlock(&budget->mutex);
    return ret;
}

static void session_release_pending(FFmpegKitWasmHttpSession *session,
                                    size_t size)
{
    WasmHttpBudget *budget = session->budget;
    pthread_mutex_lock(&budget->mutex);
    if (size <= budget->pending_bytes)
        budget->pending_bytes -= size;
    else
        budget->pending_bytes = 0;
    pthread_mutex_unlock(&budget->mutex);
}

static void session_release_cache(FFmpegKitWasmHttpSession *session,
                                  size_t size)
{
    WasmHttpBudget *budget = session->budget;
    pthread_mutex_lock(&budget->mutex);
    if (size <= budget->buffered_bytes)
        budget->buffered_bytes -= size;
    else
        budget->buffered_bytes = 0;
    pthread_mutex_unlock(&budget->mutex);
}

static int session_open_stream(FFmpegKitWasmHttpSession *session)
{
    WasmHttpBudget *budget = session->budget;
    int ret = 0;

    pthread_mutex_lock(&budget->mutex);
    if (budget->open_streams >= WASM_HTTP_MAX_OPEN_STREAMS)
        ret = AVERROR(ENOBUFS);
    else
        budget->open_streams++;
    pthread_mutex_unlock(&budget->mutex);
    return ret;
}

static void session_close_stream(FFmpegKitWasmHttpSession *session)
{
    WasmHttpBudget *budget = session->budget;
    pthread_mutex_lock(&budget->mutex);
    if (budget->open_streams > 0)
        budget->open_streams--;
    pthread_mutex_unlock(&budget->mutex);
}

static int fetch_range(WasmHttpIO *io, int64_t start, size_t length,
                       FetchRequest *request)
{
    int ret;
    uint64_t started_ms;
    pthread_condattr_t condition_attributes;

    request->session = io->session;
    __atomic_add_fetch(&request->session->references, 1, __ATOMIC_RELAXED);
    request->timeout_ms = io->timeout_ms;
    request->with_credentials = io->with_credentials;
    ret = pthread_mutex_init(&request->mutex, NULL);
    if (ret)
        return AVERROR(ret);
    request->mutex_initialized = 1;
    ret = pthread_condattr_init(&condition_attributes);
    if (ret)
        return AVERROR(ret);
    ret = pthread_condattr_setclock(&condition_attributes, CLOCK_MONOTONIC);
    if (!ret)
        ret = pthread_cond_init(&request->cond, &condition_attributes);
    pthread_condattr_destroy(&condition_attributes);
    if (ret)
        return AVERROR(ret);
    request->cond_initialized = 1;

    ret = split_url_credentials(request, io->url);
    if (ret < 0)
        goto end;
    ret = request_add_option_headers(request, io->options, io);
    if (ret < 0)
        goto end;
    ret = request_add_range(request, start, length);
    if (ret < 0)
        goto end;

    started_ms = (uint64_t)emscripten_get_now();
    ret = session_acquire_request(io->session, &io->interrupt_callback,
                                  io->timeout_ms);
    if (ret < 0)
        goto end;
    request->fetch_buffer_reserved = 1;
    request->request_acquired = 1;
    ret = request_proxy(request, request_start_fetch_on_main);
    if (ret < 0)
        goto end;

    pthread_mutex_lock(&request->mutex);
    while (!request->done || !request->start_complete ||
           !request->fetch_close_complete) {
        struct timespec short_deadline;
        int wait_ret;
        int should_abort = 0;

        if (interrupt_requested(&io->interrupt_callback)) {
            request->abort_reason = FETCH_ABORT_INTERRUPT;
            should_abort = 1;
        } else if ((uint64_t)emscripten_get_now() - started_ms >= io->timeout_ms) {
            request->abort_reason = FETCH_ABORT_TIMEOUT;
            should_abort = 1;
        }
        if (should_abort) {
            request->success = 0;
            request->done = 1;
            pthread_mutex_unlock(&request->mutex);
            request_schedule_close(request);
            pthread_mutex_lock(&request->mutex);
            /* Queued work and Fetch own their references and session snapshot.
             * The worker must not wait for a busy main thread to release them. */
            break;
        }
        if (request->done && !request->close_requested) {
            pthread_mutex_unlock(&request->mutex);
            request_schedule_close(request);
            pthread_mutex_lock(&request->mutex);
            continue;
        }

        clock_gettime(CLOCK_MONOTONIC, &short_deadline);
        short_deadline.tv_nsec += 100000000L;
        if (short_deadline.tv_nsec >= 1000000000L) {
            short_deadline.tv_sec++;
            short_deadline.tv_nsec -= 1000000000L;
        }
        wait_ret = pthread_cond_timedwait(&request->cond, &request->mutex,
                                          &short_deadline);
        if (wait_ret && wait_ret != ETIMEDOUT) {
            request->abort_reason = FETCH_ABORT_INVALID_RESPONSE;
            request->success = 0;
            pthread_mutex_unlock(&request->mutex);
            request_schedule_close(request);
            pthread_mutex_lock(&request->mutex);
            break;
        }
    }

    ret = 0;
    if (!request->success) {
        switch (request->abort_reason) {
        case FETCH_ABORT_LIMIT:
            ret = AVERROR(ENOBUFS);
            break;
        case FETCH_ABORT_TIMEOUT:
            ret = AVERROR(ETIMEDOUT);
            break;
        case FETCH_ABORT_INTERRUPT:
            ret = AVERROR_EXIT;
            break;
        case FETCH_ABORT_MEMORY:
            ret = AVERROR(ENOMEM);
            break;
        case FETCH_ABORT_INVALID_RESPONSE:
            ret = AVERROR_INVALIDDATA;
            break;
        default:
            ret = request->status == 416 ? 0 : map_http_status(request->status);
            break;
        }
    }
    pthread_mutex_unlock(&request->mutex);

end:
    {
        char safe_url[WASM_HTTP_LOG_URL_SIZE];
        const char *log_url = safe_url_for_log(io->url, safe_url,
                                              sizeof(safe_url));
        if (ret == AVERROR(ENOBUFS))
            av_log(NULL, AV_LOG_ERROR,
                   "WASM HTTP response exceeded or could not fit the configured range/session buffer limits for %s\n",
                   log_url);
        else if (ret == AVERROR(ETIMEDOUT))
            av_log(NULL, AV_LOG_ERROR,
                   "WASM HTTP request timed out for %s\n", log_url);
        else if (ret == AVERROR_EXIT)
            av_log(NULL, AV_LOG_DEBUG,
                   "WASM HTTP request interrupted for %s\n", log_url);
        else if (ret == AVERROR(ENOMEM))
            av_log(NULL, AV_LOG_ERROR,
                   "WASM HTTP request allocation failed for %s\n", log_url);
        else if (request->abort_reason == FETCH_ABORT_INVALID_RESPONSE)
            av_log(NULL, AV_LOG_ERROR,
                   "WASM browser request could not be started or returned invalid data for %s\n",
                   log_url);
        else if (ret < 0 && request->status >= 400)
            av_log(NULL, AV_LOG_ERROR,
                   "WASM HTTP request failed: HTTP %u for %s\n",
                   request->status, log_url);
        else if (ret == AVERROR(EIO) && request->status == 0)
            av_log(NULL, AV_LOG_ERROR,
                   "WASM browser fetch failed (CORS, offline, or network error): %s\n",
                   log_url);
    }
    return ret;
}

static void cache_clear(WasmHttpIO *io)
{
    if (io->cache) {
        session_release_cache(io->session, io->cache_size);
        av_freep(&io->cache);
    }
    io->cache_size = 0;
    io->cache_start = 0;
}

static int response_header_dup(const char *headers, const char *name,
                               char **value)
{
    size_t size;

    *value = NULL;
    if (!headers)
        return 0;
    size = strlen(headers) + 1;
    *value = av_malloc(size);
    if (!*value)
        return AVERROR(ENOMEM);
    if (!find_header(headers, name, *value, size))
        av_freep(value);
    return 0;
}

static int check_response_consistency(WasmHttpIO *io,
                                      const FetchRequest *request,
                                      int64_t response_length)
{
    char *etag = NULL;
    char *last_modified = NULL;
    int ret;

    ret = response_header_dup(request->headers, "ETag", &etag);
    if (ret >= 0)
        ret = response_header_dup(request->headers, "Last-Modified",
                                  &last_modified);
    if (ret < 0) {
        av_free(etag);
        av_free(last_modified);
        return ret;
    }

    if (io->length_known && io->length != response_length) {
        char safe_url[WASM_HTTP_LOG_URL_SIZE];
        av_log(NULL, AV_LOG_ERROR,
               "WASM HTTP resource length changed across ranges for %s: expected=%" PRId64
               " received=%" PRId64 "; refusing mixed bytes\n",
               safe_url_for_log(io->url, safe_url, sizeof(safe_url)),
               io->length, response_length);
        av_free(etag);
        av_free(last_modified);
        return AVERROR(EIO);
    }
    if (io->etag && etag && strcmp(io->etag, etag)) {
        char safe_url[WASM_HTTP_LOG_URL_SIZE];
        av_log(NULL, AV_LOG_ERROR,
               "WASM HTTP ETag changed across ranges for %s; refusing mixed bytes\n",
               safe_url_for_log(io->url, safe_url, sizeof(safe_url)));
        av_free(etag);
        av_free(last_modified);
        return AVERROR(EIO);
    }
    if (io->last_modified && last_modified &&
        strcmp(io->last_modified, last_modified)) {
        char safe_url[WASM_HTTP_LOG_URL_SIZE];
        av_log(NULL, AV_LOG_ERROR,
               "WASM HTTP Last-Modified changed across ranges for %s; refusing mixed bytes\n",
               safe_url_for_log(io->url, safe_url, sizeof(safe_url)));
        av_free(etag);
        av_free(last_modified);
        return AVERROR(EIO);
    }

    if (!io->length_known) {
        io->length = response_length;
        io->length_known = 1;
    }
    if (!io->etag && etag) {
        io->etag = etag;
        etag = NULL;
    }
    if (!io->last_modified && last_modified) {
        io->last_modified = last_modified;
        last_modified = NULL;
    }
    av_free(etag);
    av_free(last_modified);
    return 0;
}

static void wasm_http_options_consume(AVDictionary **options)
{
    static const char *consumed[] = {
        "headers", "rw_timeout", "seekable", "withCredentials",
        "user_agent", "referer", "cookies", NULL
    };
    int i;

    if (!options || !*options)
        return;
    for (i = 0; consumed[i]; i++)
        av_dict_set(options, consumed[i], NULL, 0);
}

static int install_response(WasmHttpIO *io, int64_t requested_start,
                            FetchRequest *request)
{
    uint64_t range_start = 0, range_end = 0, range_total = 0;
    int has_range = 0, unsatisfied = 0;
    size_t response_size = request->data_size;
    int ret;

    if (request->status == 416) {
        ret = parse_content_range(request->headers, &has_range, &range_start,
                                  &range_end, &range_total, &unsatisfied);
        if (ret >= 0 && has_range && unsatisfied &&
            (uint64_t)requested_start >= range_total) {
            ret = check_response_consistency(io, request, (int64_t)range_total);
            return ret < 0 ? ret : AVERROR_EOF;
        }
        return AVERROR(ERANGE);
    }

    if (request->status == 206) {
        ret = parse_content_range(request->headers, &has_range, &range_start,
                                  &range_end, &range_total, &unsatisfied);
        if (ret < 0 || !has_range || unsatisfied ||
            range_start != (uint64_t)requested_start ||
            range_end < range_start ||
            range_end - range_start + 1 != response_size ||
            (request->has_content_length &&
             request->content_length != response_size) ||
            range_total <= range_end) {
            char safe_url[WASM_HTTP_LOG_URL_SIZE];
            av_log(NULL, AV_LOG_ERROR,
                   "WASM HTTP 206 response has an invalid or hidden Content-Range for %s\n",
                   safe_url_for_log(io->url, safe_url, sizeof(safe_url)));
            return AVERROR_INVALIDDATA;
        }
        ret = check_response_consistency(io, request, (int64_t)range_total);
        if (ret < 0)
            return ret;
        io->range_supported = 1;
    } else if (request->status == 200) {
        if (request->has_content_length &&
            request->content_length != response_size) {
            char safe_url[WASM_HTTP_LOG_URL_SIZE];
            av_log(NULL, AV_LOG_ERROR,
                   "WASM HTTP 200 response was truncated for %s\n",
                   safe_url_for_log(io->url, safe_url, sizeof(safe_url)));
            return AVERROR(EIO);
        }
        ret = check_response_consistency(io, request, (int64_t)response_size);
        if (ret < 0)
            return ret;
        io->range_supported = 0;
        io->full_response_cached = 1;
    } else {
        return map_http_status(request->status);
    }

    if (request->response_url && request->response_url[0]) {
        char *location = av_strdup(request->response_url);
        if (!location)
            return AVERROR(ENOMEM);
        av_freep(&io->location);
        io->location = location;
    }

    cache_clear(io);
    if (response_size) {
        if (!request->pending_reserved ||
            request->pending_size != response_size)
            return AVERROR_INVALIDDATA;
        ret = session_transfer_pending_to_cache(io->session, response_size);
        if (ret < 0)
            return ret;
        request->pending_reserved = 0;
        request->pending_size = 0;
    }
    io->cache = request->data;
    request->data = NULL;
    /* cache_clear resets the old offset; publish the new range only after it. */
    io->cache_start = request->status == 206 ? requested_start : 0;
    io->cache_size = response_size;
    return 0;
}

static int load_range(WasmHttpIO *io, int64_t start, size_t length)
{
    FetchRequest *request = av_mallocz(sizeof(*request));
    int ret;

    if (!request)
        return AVERROR(ENOMEM);
    request->references = 1;
    ret = fetch_range(io, start, length, request);
    if (ret >= 0)
        ret = install_response(io, start, request);
    request_release(request);
    return ret;
}

static int wasm_http_read(void *opaque, uint8_t *buffer, int buffer_size)
{
    WasmHttpIO *io = opaque;
    int64_t cache_end;
    size_t copy_size;
    int ret;

    if (!io || !buffer || buffer_size < 0)
        return AVERROR(EINVAL);
    if (!buffer_size)
        return 0;
    if (interrupt_requested(&io->interrupt_callback))
        return AVERROR_EXIT;
    if (io->length_known && io->position >= io->length)
        return AVERROR_EOF;

    cache_end = io->cache_start + (int64_t)io->cache_size;
    if (!io->cache || io->position < io->cache_start ||
        io->position >= cache_end) {
        if (io->full_response_cached)
            return AVERROR_EOF;
        cache_clear(io);
        ret = load_range(io, io->position, WASM_HTTP_RANGE_SIZE);
        if (ret < 0)
            return ret;
        cache_end = io->cache_start + (int64_t)io->cache_size;
        if (io->position >= cache_end)
            return AVERROR_EOF;
    }

    copy_size = FFMIN((size_t)buffer_size,
                      (size_t)(cache_end - io->position));
    if (io->length_known)
        copy_size = FFMIN(copy_size, (size_t)(io->length - io->position));
    if (!copy_size)
        return AVERROR_EOF;
    memcpy(buffer, io->cache + (size_t)(io->position - io->cache_start),
           copy_size);
    io->position += (int64_t)copy_size;
    return (int)copy_size;
}

static int64_t wasm_http_seek(void *opaque, int64_t offset, int whence)
{
    WasmHttpIO *io = opaque;
    int64_t target;

    if (!io)
        return AVERROR(EINVAL);
    if (!io->allow_seek)
        return AVERROR(ENOSYS);
    if (whence & AVSEEK_SIZE) {
        int64_t size = io->length_known ? io->length : AVERROR(ENOSYS);
        if (!io->size_query_logged) {
            io->size_query_logged = 1;
            av_log(NULL, AV_LOG_DEBUG,
                   "WASM HTTP AVSEEK_SIZE generation=%" PRIu64
                   " session=%ld worker=%" PRIu64 " size=%" PRId64 "\n",
                   io->session->generation, io->session->session_id,
                   (uint64_t)(uintptr_t)pthread_self(), size);
        }
        return size;
    }
    whence &= ~AVSEEK_FORCE;
    switch (whence) {
    case SEEK_SET:
        target = offset;
        break;
    case SEEK_CUR:
        if ((offset > 0 && io->position > INT64_MAX - offset) ||
            (offset < 0 && io->position < INT64_MIN - offset))
            return AVERROR(EOVERFLOW);
        target = io->position + offset;
        break;
    case SEEK_END:
        if (!io->length_known)
            return AVERROR(ENOSYS);
        if ((offset > 0 && io->length > INT64_MAX - offset) ||
            (offset < 0 && io->length < INT64_MIN - offset))
            return AVERROR(EOVERFLOW);
        target = io->length + offset;
        break;
    default:
        return AVERROR(EINVAL);
    }
    if (target < 0)
        return AVERROR(EINVAL);
    if (io->full_response_cached &&
        (uint64_t)target > (uint64_t)io->length)
        return AVERROR(EINVAL);
    io->position = target;
    return target;
}

static void wasm_http_io_free(WasmHttpIO *io)
{
    if (!io)
        return;
    cache_clear(io);
    av_freep(&io->url);
    av_freep(&io->location);
    av_freep(&io->headers);
    av_freep(&io->etag);
    av_freep(&io->last_modified);
    av_dict_free(&io->options);
    session_close_stream(io->session);
    av_free(io);
}

static int wasm_http_io_close(AVFormatContext *context, AVIOContext *pb)
{
    WasmHttpIO *io;
    AVIOContext *closing;
    FFmpegKitWasmHttpSession *session;

    if (!pb)
        return 0;
    session = context ? context->opaque : NULL;
    if (pb->read_packet == wasm_http_read) {
        io = pb->opaque;
        av_freep(&pb->buffer);
        closing = pb;
        avio_context_free(&closing);
        wasm_http_io_free(io);
        return 0;
    }
    if (session && session->magic == WASM_HTTP_MAGIC &&
        session->previous_io_close2)
        return session->previous_io_close2(context, pb);
    closing = pb;
    return avio_closep(&closing);
}

static int wasm_http_io_open(AVFormatContext *context, AVIOContext **pb,
                             const char *url, int flags,
                             AVDictionary **options)
{
    FFmpegKitWasmHttpSession *session;
    WasmHttpIO *io = NULL;
    uint8_t *buffer = NULL;
    int ret;
    char safe_url[WASM_HTTP_LOG_URL_SIZE];

    if (!context || !pb || !url)
        return AVERROR(EINVAL);
    session = context->opaque;
    if (!session || session->magic != WASM_HTTP_MAGIC)
        return AVERROR(EINVAL);

    if (is_crypto_http_url(url)) {
        av_log(context, AV_LOG_ERROR,
               "AES-128 HLS is not supported in the Wasm build\n");
        return AVERROR(ENOSYS);
    }

    if (is_http_url(url) && invalid_http_url_character(url)) {
        av_log(context, AV_LOG_ERROR,
               "WASM browser transport rejected whitespace/control in HTTP URL\n");
        return AVERROR(EINVAL);
    }

    if (!is_http_url(url)) {
        if (!is_local_url(url)) {
            av_log(context, AV_LOG_ERROR,
                   "WASM browser transport does not support URL scheme: %s\n",
                   safe_url_for_log(url, safe_url, sizeof(safe_url)));
            return AVERROR(EPROTONOSUPPORT);
        }
        if (session->previous_io_open &&
            session->previous_io_open != wasm_http_io_open)
            return session->previous_io_open(context, pb, url, flags, options);
        return avio_open2(pb, url, flags, &context->interrupt_callback, options);
    }
    if (!(flags & AVIO_FLAG_READ) || (flags & AVIO_FLAG_WRITE))
        return AVERROR(ENOSYS);
    if (emscripten_is_main_runtime_thread()) {
        av_log(context, AV_LOG_ERROR,
               "WASM HTTP input requires a pthread separate from the Emscripten runtime thread\n");
        return AVERROR(EPERM);
    }
    if (interrupt_requested(&context->interrupt_callback))
        return AVERROR_EXIT;
    ret = session_open_stream(session);
    if (ret < 0)
        return ret;

    io = av_mallocz(sizeof(*io));
    if (!io) {
        session_close_stream(session);
        return AVERROR(ENOMEM);
    }
    io->session = session;
    io->av_class = &wasm_http_io_child_class;
    io->interrupt_callback = context->interrupt_callback;
    io->timeout_ms = WASM_HTTP_TIMEOUT_MS;
    io->url = av_strdup(url);
    io->location = av_strdup(url);
    io->length = -1;
    io->allow_seek = 1;
    if (options && *options && av_dict_copy(&io->options, *options, 0) < 0) {
        wasm_http_io_free(io);
        return AVERROR(ENOMEM);
    }
    {
        const AVDictionaryEntry *timeout = av_dict_get(io->options, "rw_timeout",
                                                       NULL, 0);
        if (timeout && timeout->value) {
            char *end = NULL;
            long long timeout_us = strtoll(timeout->value, &end, 10);
            if (end != timeout->value && !*end && timeout_us > 0) {
                uint64_t timeout_ms = (uint64_t)timeout_us / 1000;
                io->timeout_ms = (unsigned int)FFMIN(timeout_ms, UINT_MAX);
                if (!io->timeout_ms)
                    io->timeout_ms = 1;
            }
        }
        timeout = av_dict_get(io->options, "withCredentials", NULL, 0);
        if (timeout && timeout->value)
            __atomic_store_n(&session->with_credentials,
                !strcasecmp(timeout->value, "1") ||
                !strcasecmp(timeout->value, "true"), __ATOMIC_RELEASE);
        io->with_credentials = __atomic_load_n(&session->with_credentials,
                                                __ATOMIC_ACQUIRE);
        timeout = av_dict_get(io->options, "seekable", NULL, 0);
        if (timeout && timeout->value &&
            (!strcasecmp(timeout->value, "0") ||
             !strcasecmp(timeout->value, "false")))
            io->allow_seek = 0;
    }
    {
        const AVDictionaryEntry *headers = av_dict_get(io->options, "headers",
                                                       NULL, 0);
        if (headers && headers->value) {
            io->headers = av_strdup(headers->value);
            if (!io->headers) {
                wasm_http_io_free(io);
                return AVERROR(ENOMEM);
            }
        }
        io->rw_timeout = (int64_t)io->timeout_ms * 1000;
    }
    if (!io->url || !io->location) {
        wasm_http_io_free(io);
        return AVERROR(ENOMEM);
    }
    wasm_http_options_consume(options);

    ret = load_range(io, 0, WASM_HTTP_RANGE_SIZE);
    if (ret < 0) {
        wasm_http_io_free(io);
        return ret;
    }

    buffer = av_malloc(WASM_HTTP_READ_BUFFER_SIZE);
    if (!buffer) {
        wasm_http_io_free(io);
        return AVERROR(ENOMEM);
    }
    *pb = avio_alloc_context(buffer, WASM_HTTP_READ_BUFFER_SIZE, 0, io,
                             wasm_http_read, NULL, wasm_http_seek);
    if (!*pb) {
        av_free(buffer);
        wasm_http_io_free(io);
        return AVERROR(ENOMEM);
    }
    (*pb)->av_class = &wasm_http_io_av_class;
    (*pb)->seekable = io->allow_seek &&
                      (io->range_supported || io->full_response_cached)
                          ? AVIO_SEEKABLE_NORMAL : 0;
    av_log(context, AV_LOG_DEBUG,
           "WASM HTTP open generation=%" PRIu64 " session=%ld worker=%" PRIu64 " range=%d size=%" PRId64 " url=%s\n",
           session->generation, session->session_id,
           (uint64_t)(uintptr_t)pthread_self(), io->range_supported,
           io->length_known ? io->length : -1,
           safe_url_for_log(io->location, safe_url, sizeof(safe_url)));
    return 0;
}

int ffmpegkit_wasm_http_install(AVFormatContext *context, long session_id,
                                FFmpegKitWasmHttpSession **session_out)
{
    FFmpegKitWasmHttpSession *session;
    int ret;

    if (!context || !session_out)
        return AVERROR(EINVAL);
    *session_out = NULL;
    if (context->opaque) {
        av_log(context, AV_LOG_ERROR,
               "Cannot install WASM HTTP transport: AVFormatContext opaque is already owned\n");
        return AVERROR(EBUSY);
    }
    session = av_mallocz(sizeof(*session));
    if (!session)
        return AVERROR(ENOMEM);
    pthread_mutex_lock(&generation_mutex);
    session->generation = next_generation++;
    pthread_mutex_unlock(&generation_mutex);
    session->references = 1;
    session->magic = WASM_HTTP_MAGIC;
    session->session_id = session_id;
    ret = session_budget_acquire(session);
    if (ret < 0) {
        av_free(session);
        return ret;
    }
    session->previous_io_open = context->io_open;
    session->previous_io_close2 = context->io_close2;
    context->opaque = session;
    context->io_open = wasm_http_io_open;
    context->io_close2 = wasm_http_io_close;
    *session_out = session;
    return 0;
}

void ffmpegkit_wasm_http_session_free(FFmpegKitWasmHttpSession *session)
{
    if (!session || __atomic_sub_fetch(&session->references, 1, __ATOMIC_ACQ_REL))
        return;
    session->magic = 0;
    session_budget_release(session);
    av_free(session);
}

#if defined(FFMPEG_KIT_TEST_HOOKS)
typedef struct WasmHttpWaitProbe {
    char *url;
    unsigned int timeout_ms;
    unsigned int interrupt_after_ms;
    double started_ms;
} WasmHttpWaitProbe;

static int wasm_http_wait_probe_state;
static int wasm_http_wait_probe_result;
static double wasm_http_wait_probe_elapsed;

static int wasm_http_wait_probe_interrupt(void *opaque)
{
    WasmHttpWaitProbe *probe = opaque;
    return probe->interrupt_after_ms &&
           emscripten_get_now() - probe->started_ms >= probe->interrupt_after_ms;
}

static void *wasm_http_wait_probe_worker(void *opaque)
{
    WasmHttpWaitProbe *probe = opaque;
    FFmpegKitWasmHttpSession *session = NULL;
    AVFormatContext *context = avformat_alloc_context();
    AVIOContext *pb = NULL;
    AVDictionary *options = NULL;
    int ret = context ? 0 : AVERROR(ENOMEM);
    int expected = probe->interrupt_after_ms ? AVERROR_EXIT : AVERROR(ETIMEDOUT);
    double elapsed;

    if (!ret) {
        context->interrupt_callback.callback = wasm_http_wait_probe_interrupt;
        context->interrupt_callback.opaque = probe;
        ret = ffmpegkit_wasm_http_install(context, 0, &session);
    }
    if (!ret)
        ret = av_dict_set_int(&options, "rw_timeout", probe->timeout_ms * 1000LL, 0);
    probe->started_ms = emscripten_get_now();
    if (!ret)
        ret = context->io_open(context, &pb, probe->url, AVIO_FLAG_READ, &options);
    if (pb)
        context->io_close2(context, pb);
    av_dict_free(&options);
    if (context) {
        context->opaque = NULL;
        avformat_free_context(context);
    }
    ffmpegkit_wasm_http_session_free(session);
    elapsed = emscripten_get_now() - probe->started_ms;
    av_log(NULL, AV_LOG_WARNING,
           "WASM HTTP TEST wait timeout_ms=%u interrupt_after_ms=%u elapsed_ms=%.3f result=%d expected=%d forced_close_failures=%d\n",
           probe->timeout_ms, probe->interrupt_after_ms, elapsed, ret, expected,
           __atomic_load_n(&wasm_http_wait_probe_forced_close_failures, __ATOMIC_ACQUIRE));
    __atomic_store(&wasm_http_wait_probe_elapsed, &elapsed, __ATOMIC_RELEASE);
    av_freep(&probe->url);
    av_free(probe);
    __atomic_store_n(&wasm_http_wait_probe_result, ret, __ATOMIC_RELEASE);
    __atomic_store_n(&wasm_http_wait_probe_state, 2, __ATOMIC_RELEASE);
    return NULL;
}

int ffmpeg_kit_test_http_io_wait_start(const char *url, int timeout_ms,
                                     int interrupt_after_ms, int fail_close_proxy)
{
    WasmHttpWaitProbe *probe;
    pthread_t thread;
    int state = __atomic_load_n(&wasm_http_wait_probe_state, __ATOMIC_ACQUIRE);
    int ret;

    if (!url || !is_http_url(url) || invalid_http_url_character(url) ||
        timeout_ms < 1 || timeout_ms > 10000 || interrupt_after_ms < 0 ||
        interrupt_after_ms >= timeout_ms ||
        (fail_close_proxy != 0 && fail_close_proxy != 1))
        return AVERROR(EINVAL);
    do {
        if (state == 1)
            return AVERROR(EBUSY);
    } while (!__atomic_compare_exchange_n(&wasm_http_wait_probe_state, &state,
                                          1, 0, __ATOMIC_ACQ_REL,
                                          __ATOMIC_ACQUIRE));
    probe = av_mallocz(sizeof(*probe));
    if (!probe) {
        __atomic_store_n(&wasm_http_wait_probe_state, 0, __ATOMIC_RELEASE);
        return AVERROR(ENOMEM);
    }
    probe->url = av_strdup(url);
    probe->timeout_ms = timeout_ms;
    probe->interrupt_after_ms = interrupt_after_ms;
    __atomic_store_n(&wasm_http_wait_probe_fail_close_proxy, fail_close_proxy, __ATOMIC_RELEASE);
    __atomic_store_n(&wasm_http_wait_probe_forced_close_failures, 0, __ATOMIC_RELEASE);
    if (!probe->url) {
        av_free(probe);
        __atomic_store_n(&wasm_http_wait_probe_state, 0, __ATOMIC_RELEASE);
        return AVERROR(ENOMEM);
    }
    ret = pthread_create(&thread, NULL, wasm_http_wait_probe_worker, probe);
    if (ret) {
        av_freep(&probe->url);
        av_free(probe);
        __atomic_store_n(&wasm_http_wait_probe_state, 0, __ATOMIC_RELEASE);
        return AVERROR(ret);
    }
    pthread_detach(thread);
    return 0;
}

int ffmpeg_kit_test_http_io_wait_status(void)
{
    int state = __atomic_load_n(&wasm_http_wait_probe_state, __ATOMIC_ACQUIRE);
    if (state == 1)
        return 1;
    return state == 2
        ? __atomic_load_n(&wasm_http_wait_probe_result, __ATOMIC_ACQUIRE)
        : AVERROR(EINVAL);
}

double ffmpeg_kit_test_http_io_wait_elapsed(void)
{
    double elapsed;
    __atomic_load(&wasm_http_wait_probe_elapsed, &elapsed, __ATOMIC_ACQUIRE);
    return elapsed;
}

typedef struct WasmHttpStreamProbe {
    char *url;
} WasmHttpStreamProbe;

static int wasm_http_stream_probe_state;
static int wasm_http_stream_probe_result;

static void *wasm_http_stream_probe_worker(void *opaque)
{
    WasmHttpStreamProbe *probe = opaque;
    AVFormatContext *context = avformat_alloc_context();
    FFmpegKitWasmHttpSession *session = NULL;
    AVIOContext *pb = NULL;
    uint8_t buffer[1024];
    int ret = context ? 0 : AVERROR(ENOMEM);

    if (ret >= 0)
        ret = ffmpegkit_wasm_http_install(context, 0, &session);
    if (ret >= 0)
        ret = context->io_open(context, &pb, probe->url, AVIO_FLAG_READ, NULL);
    while (ret >= 0) {
        ret = avio_read(pb, buffer, sizeof(buffer));
        if (ret > 0)
            continue;
        if (ret == AVERROR_EOF)
            ret = 0;
        break;
    }
    if (pb)
        context->io_close2(context, pb);
    if (context) {
        context->opaque = NULL;
        avformat_free_context(context);
    }
    ffmpegkit_wasm_http_session_free(session);
    av_log(NULL, ret == AVERROR(EIO) ? AV_LOG_WARNING : AV_LOG_INFO,
           "WASM HTTP TEST stream result=%d expected_consistency_error=%d\n",
           ret, AVERROR(EIO));
    av_freep(&probe->url);
    av_free(probe);
    __atomic_store_n(&wasm_http_stream_probe_result, ret, __ATOMIC_RELEASE);
    __atomic_store_n(&wasm_http_stream_probe_state, 2, __ATOMIC_RELEASE);
    return NULL;
}

int ffmpeg_kit_test_http_io_stream_start(const char *url)
{
    WasmHttpStreamProbe *probe;
    pthread_t thread;
    int state = __atomic_load_n(&wasm_http_stream_probe_state, __ATOMIC_ACQUIRE);
    int ret;

    if (!url || !is_http_url(url) || invalid_http_url_character(url))
        return AVERROR(EINVAL);
    do {
        if (state == 1)
            return AVERROR(EBUSY);
    } while (!__atomic_compare_exchange_n(&wasm_http_stream_probe_state, &state,
                                          1, 0, __ATOMIC_ACQ_REL,
                                          __ATOMIC_ACQUIRE));
    probe = av_mallocz(sizeof(*probe));
    if (!probe) {
        __atomic_store_n(&wasm_http_stream_probe_state, 0, __ATOMIC_RELEASE);
        return AVERROR(ENOMEM);
    }
    probe->url = av_strdup(url);
    if (!probe->url) {
        av_free(probe);
        __atomic_store_n(&wasm_http_stream_probe_state, 0, __ATOMIC_RELEASE);
        return AVERROR(ENOMEM);
    }
    __atomic_store_n(&wasm_http_stream_probe_result, AVERROR(EAGAIN),
                     __ATOMIC_RELEASE);
    ret = pthread_create(&thread, NULL, wasm_http_stream_probe_worker, probe);
    if (ret) {
        av_freep(&probe->url);
        av_free(probe);
        __atomic_store_n(&wasm_http_stream_probe_state, 0, __ATOMIC_RELEASE);
        return AVERROR(ret);
    }
    pthread_detach(thread);
    return 0;
}

int ffmpeg_kit_test_http_io_stream_status(void)
{
    int state = __atomic_load_n(&wasm_http_stream_probe_state, __ATOMIC_ACQUIRE);
    if (state == 1)
        return 1;
    return state == 2
        ? __atomic_load_n(&wasm_http_stream_probe_result, __ATOMIC_ACQUIRE)
        : AVERROR(EINVAL);
}

int ffmpeg_kit_test_http_io_stream_eio(void)
{
    return AVERROR(EIO);
}

typedef struct WasmHttpHeapTest {
    char *url;
    int warmup_cycles;
    int measured_cycles;
} WasmHttpHeapTest;

static int wasm_http_heap_test_state;
static int wasm_http_heap_test_result;

static int wasm_http_heap_test_cycles(AVFormatContext *context,
                                      const char *url, int cycles)
{
    int i;

    for (i = 0; i < cycles; i++) {
        AVIOContext *pb = NULL;
        int ret = context->io_open(context, &pb, url, AVIO_FLAG_READ, NULL);
        if (ret < 0)
            return ret;
        ret = context->io_close2(context, pb);
        if (ret < 0)
            return ret;
    }
    return 0;
}

static void *wasm_http_heap_test_worker(void *opaque)
{
    WasmHttpHeapTest *test = opaque;
    AVFormatContext *context = avformat_alloc_context();
    FFmpegKitWasmHttpSession *session = NULL;
    size_t heap_before = 0;
    size_t heap_after = 0;
    int64_t heap_delta = 0;
    int ret = context ? 0 : AVERROR(ENOMEM);

    if (ret >= 0)
        ret = ffmpegkit_wasm_http_install(context, 0, &session);
    if (ret >= 0)
        ret = wasm_http_heap_test_cycles(context, test->url,
                                         test->warmup_cycles);
    if (ret >= 0)
        heap_before = mallinfo().uordblks;
    if (ret >= 0)
        ret = wasm_http_heap_test_cycles(context, test->url,
                                         test->measured_cycles);
    if (ret >= 0)
        heap_after = mallinfo().uordblks;
    if (context) {
        context->opaque = NULL;
        avformat_free_context(context);
    }
    ffmpegkit_wasm_http_session_free(session);
    if (ret >= 0) {
        if (heap_after >= heap_before)
            heap_delta = (int64_t)(heap_after - heap_before);
        else
            heap_delta = -(int64_t)(heap_before - heap_after);
        av_log(NULL, AV_LOG_WARNING,
               "WASM HTTP TEST heap cycles=%d warmup=%d before=%zu after=%zu delta=%" PRId64 "\n",
               test->measured_cycles, test->warmup_cycles, heap_before,
               heap_after, heap_delta);
    } else {
        av_log(NULL, AV_LOG_ERROR,
               "WASM HTTP TEST heap cycles failed: %d\n", ret);
    }
    av_freep(&test->url);
    av_free(test);
    __atomic_store_n(&wasm_http_heap_test_result, ret, __ATOMIC_RELEASE);
    __atomic_store_n(&wasm_http_heap_test_state, 2, __ATOMIC_RELEASE);
    return NULL;
}

int ffmpeg_kit_test_http_io_heap_start(const char *url, int warmup_cycles,
                                       int measured_cycles)
{
    WasmHttpHeapTest *test;
    pthread_t thread;
    int state;
    int ret;

    if (!url || !is_http_url(url) || invalid_http_url_character(url) ||
        warmup_cycles < 0 || warmup_cycles > 100 || measured_cycles <= 0 ||
        measured_cycles > 1000)
        return AVERROR(EINVAL);
    state = __atomic_load_n(&wasm_http_heap_test_state, __ATOMIC_ACQUIRE);
    do {
        if (state == 1)
            return AVERROR(EBUSY);
    } while (!__atomic_compare_exchange_n(&wasm_http_heap_test_state, &state,
                                          1, 0, __ATOMIC_ACQ_REL,
                                          __ATOMIC_ACQUIRE));
    test = av_mallocz(sizeof(*test));
    if (!test) {
        __atomic_store_n(&wasm_http_heap_test_state, 0, __ATOMIC_RELEASE);
        return AVERROR(ENOMEM);
    }
    test->url = av_strdup(url);
    test->warmup_cycles = warmup_cycles;
    test->measured_cycles = measured_cycles;
    if (!test->url) {
        av_free(test);
        __atomic_store_n(&wasm_http_heap_test_state, 0, __ATOMIC_RELEASE);
        return AVERROR(ENOMEM);
    }
    __atomic_store_n(&wasm_http_heap_test_result, AVERROR(EAGAIN),
                     __ATOMIC_RELEASE);
    ret = pthread_create(&thread, NULL, wasm_http_heap_test_worker, test);
    if (ret) {
        av_freep(&test->url);
        av_free(test);
        __atomic_store_n(&wasm_http_heap_test_state, 0, __ATOMIC_RELEASE);
        return AVERROR(ret);
    }
    pthread_detach(thread);
    return 0;
}

int ffmpeg_kit_test_http_io_heap_status(void)
{
    int state = __atomic_load_n(&wasm_http_heap_test_state, __ATOMIC_ACQUIRE);
    if (state == 1)
        return 1;
    if (state == 2)
        return __atomic_load_n(&wasm_http_heap_test_result, __ATOMIC_ACQUIRE);
    return AVERROR(EINVAL);
}

double ffmpeg_kit_test_http_io_heap_snapshot(void)
{
    return (double)mallinfo().uordblks;
}
#endif

#endif
