#include "ffmpegkit_wrapper.h"

/* Persistent storage keeps user_data valid through dispatch and observation.
 * Each kind is started once per page so a late callback cannot be reset away. */
typedef struct CompletionObservation {
    void *started_handle;
    void *callback_handle;
    int count;
} CompletionObservation;

static CompletionObservation observations[2];

static void observe_completion(void *handle, void *user_data)
{
    CompletionObservation *observation = user_data;
    __atomic_store_n(&observation->callback_handle, handle, __ATOMIC_RELEASE);
    __atomic_add_fetch(&observation->count, 1, __ATOMIC_RELEASE);
}

void *ffmpeg_kit_test_completion_start(int kind, const char *command)
{
    CompletionObservation *observation;
    if (kind < 0 || kind > 1 || !command)
        return NULL;
    observation = &observations[kind];
    if (observation->started_handle)
        return NULL;
    observation->started_handle = kind == 0
        ? ffprobe_kit_execute_async(command, observe_completion, observation)
        : ffmpeg_kit_execute_async(command, observe_completion, observation);
    return observation->started_handle;
}

int ffmpeg_kit_test_completion_count(int kind, void *expected_handle)
{
    CompletionObservation *observation;
    int count;
    if (kind < 0 || kind > 1 || !expected_handle)
        return -1;
    observation = &observations[kind];
    count = __atomic_load_n(&observation->count, __ATOMIC_ACQUIRE);
    if (count && __atomic_load_n(&observation->callback_handle, __ATOMIC_ACQUIRE)
                     != expected_handle)
        return -1;
    return count;
}
