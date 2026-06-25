# FFmpegKit for Desktop (Linux & Windows)

### 1. Features
- Provides a `C++` API with `c++17` (Required for modern GoogleTest support)
- Provides a `C` API wrapper for easy integration
- Supports `x86_64` and `i686` architectures
- Builds shared and static native libraries (.so, .dll, .a)
- Supports native Linux builds and cross-compilation for Windows
- Includes advanced `FFplay` playback controls (Seek, Pause, Resume, Speed, Volume)
- Prebuilt binaries published to [GitHub Releases](https://github.com/akashskypatel/ffmpeg-kit-builders/releases)
- Deploy custom builds for specialized requirements

### 1.1 Limitations

- **Single FFplay Session**: Only one FFplay session can be active at a time. Starting a new FFplay session automatically stops any previous session.
- **MSVC Not Supported**: Windows builds require MinGW-w64 toolchain. Native MSVC compilation is not supported.

---

### 1.5 Documentation Wiki

For detailed technical guides, please refer to the following documentation:
- [C API Reference](docs/C_API.md) - Detailed guide for the C API wrapper.
- [Build System & Patching](docs/BUILD_SYSTEM.md) - Technical overview of how the desktop build works.
- [Architecture & Workflow](DEVELOPMENT.md) - Development workflow and file structure roles.

---

### 2. Building

Building FFmpegKit for Desktop is performed using the unified `runner.sh` script located in the project root directory.

#### 2.1 Pragmatic Guide

1.  **Environment Setup**: Follow the prerequisites and toolchain installation steps outlined in the [Main Repository README](../README.md#quick-start).
2.  **Basic Build**: Execute the runner script to build a bare bones ffmpeg build with built-in functionality only. This build will not have any external libraries.

    ```bash
    # Minimal build for Linux x86_64
    sudo ./runner.sh --host=linux --arch=x86_64 --enable-base --gpl --kit --skip --skip-pkg-check --release=local -y

    # Minimal build for Windows x86_64 (Cross-compile)
    sudo ./runner.sh --host=windows --arch=x86_64 --enable-base --gpl --kit --skip --skip-pkg-check --release=local -y
    ```

3.  **Advanced Options**: Use `--enable-gpl` or `--enable-full` to include additional external libraries. Run `./runner.sh --help` to see all available options or refer to [Main Repository README](../README.md).

#### 2.2 Build Output

All libraries and headers created by the build process can be found under the `prebuilt` directory in the project root.
- Headers and libraries for the consolidated bundle are typically located under `prebuilt/{platform}-{arch}/bundle-.../`.

### 3. Usage

Prebuilt desktop libraries are published to [GitHub Releases](https://github.com/akashskypatel/ffmpeg-kit-builders/releases). Alternatively, you can build them manually following the [Building](#2-building) section.

**Note:** FFmpeg, FFprobe, and FFplay binaries are built as part of the dependency chain and statically merged into the final FFmpegKit library. The resulting library is a self-contained bundle that includes all selected codecs and libraries.

#### 3.1 C API Wrapper (Recommended for FFI)

The C API wrapper is designed for high performance and easy integration with C/C++ projects or FFIs (like Flutter, Dart, or Python).

##### Execute FFmpeg
```C
#include <ffmpegkit_wrapper.h>

// Synchronous execution
FFmpegSessionHandle session = ffmpeg_kit_execute("-i input.mp4 output.mov");

// Check state
FFmpegKitSessionState state = ffmpeg_kit_session_get_state(session);
if (state == FFMPEG_KIT_SESSION_STATE_COMPLETED) {
    int rc = ffmpeg_kit_session_get_return_code(session);
    printf("Execution successful with return code: %d\n", rc);
}

// Memory Management: Always release handles
ffmpeg_kit_handle_release(session);
```

##### Concurrent Execution
FFmpegKit for Desktop supports **parallel execution**. You can run multiple FFmpeg or FFprobe commands simultaneously in separate threads.

```C
// Start multiple asynchronous sessions
FFmpegSessionHandle s1 = ffmpeg_kit_execute_async("-i in1.mp4 out1.mp4", NULL, NULL);
FFmpegSessionHandle s2 = ffmpeg_kit_execute_async("-i in2.mp4 out2.mp4", NULL, NULL);

// ... perform other tasks ...

// Release handles (will also cancel if still running)
ffmpeg_kit_handle_release(s1);
ffmpeg_kit_handle_release(s2);
```

##### Media Information (FFprobe)
```C
MediaInformationSessionHandle media_session = ffprobe_kit_get_media_information("video.mp4");
if (ffmpeg_kit_session_get_state(media_session) == FFMPEG_KIT_SESSION_STATE_COMPLETED) {
    MediaInformationHandle info = media_information_session_get_media_information(media_session);
    char* format = media_information_get_format(info);
    printf("Format: %s\n", format);
    
    // Cleanup
    ffmpeg_kit_free(format);
    ffmpeg_kit_handle_release(info);
}
ffmpeg_kit_handle_release(media_session);
```

##### FFplay Playback Control
FFmpegKit provides advanced playback controls. Note that only one FFplay session can be active at a time; starting a new one automatically stops the previous one.

```C
// Start playback asynchronously
FFplaySessionHandle play_session = ffplay_kit_execute_async("-i video.mp4", NULL, NULL, 1000);

// Interactive Controls
ffplay_kit_session_pause(play_session);
ffplay_kit_session_seek(play_session, 10.5); // Seek to 10.5 seconds
ffplay_kit_session_resume(play_session);

double pos = ffplay_kit_session_get_position(play_session);
printf("Current Position: %f\n", pos);

ffmpeg_kit_handle_release(play_session);
```

#### 3.2 C++ API

For native C++ projects, you can use the object-oriented API:

```C++
#include <FFmpegKit.h>
#include <FFmpegKitConfig.h>

using namespace ffmpegkit;

// Async execution with callbacks
FFmpegKit::executeAsync("-i file1.mp4 file2.mp4", [](auto session) {
    std::cout << "Finished with state: " << (int)session->getState() << std::endl;
}, [](auto log) {
    std::cout << log->getMessage();
}, [](auto stats) {
    std::cout << "Speed: " << stats->getSpeed() << "x" << std::endl;
});
```

---

### 4. Testing

A comprehensive suite of tests is available in the `desktop/tests` directory. These serve as a blueprint for advanced usage:

- **[wrapper_test.cpp](tests/wrapper_test.cpp)**: Demonstrates C API usage, media information extraction, and concurrency.
- **[callback_test.cpp](tests/callback_test.cpp)**: Examples of using log and statistics callbacks.
- **[stress_test.cpp](tests/stress_test.cpp)**: Verifies stability under heavy concurrent load.

To run the tests, refer to the [Build System documentation](docs/BUILD_SYSTEM.md#running-tests).
