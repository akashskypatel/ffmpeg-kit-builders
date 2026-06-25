# FFmpegKit Changelog

## Version 0.10.4

- Updated FFmpeg to v8.1.2
  - Fixes critical FFmpeg vulnerability CVE-2026-8461

## Version 0.10.3

- Fixed FFmpeg statistics callbacks only firing at session completion during transcoding.
- Moved the output-header progress counter from thread-local FFmpeg state into the shared FFmpegContext.
- Updated muxer worker threads to increment the shared context counter so the transcode control thread can detect when output initialization has completed.
- Restored periodic print_report() execution after muxer header write, allowing statistics callbacks to fire continuously during long-running transcodes.

## Version 0.10.2

- Added null pointer checks to wrapper functions for robustness.
- Extended Statistics class with dupFrames and dropFrames fields, and added corresponding getters to wrapper.
- Changed `ffmpeg_kit_statistics_get_time` functions to return time instead of time elapsed and added separate `ffmpeg_kit_statistics_get_time_elapsed` functions to get time elapsed.
- Redesigned log attribution to resolve session ownership through native root objects before falling back to session `0`, improving correctness for concurrent FFmpeg and FFprobe runs.
- Reworked log attribution and callback transmission paths so concurrent FFmpeg, FFprobe, and FFplay sessions preserve session ownership more reliably under cancellation and parallel execution.
- Fixed media information parsing to use raw ffprobe JSON output directly instead of reconstructing it from session logs.
- Improved cancellation handoff so stalled and mid-stream sessions unwind correctly and `onComplete` callbacks fire after cancellation.
- Fixed Windows build portability issues in logging/debug helpers and test support code, including MinGW-safe time/thread handling and test-suite compatibility fixes.
- Added regression coverage for parallel log attribution, mixed FFmpeg/FFprobe cancellation, mid-stream termination, and unattributed callback handling.
- **Android**: Fixed binder threadpool crash.
- **Windows**: Fixed crashes due to:
  - Hardened session/input/output access paths and cancellation-related state checks to reduce crashes during parallel execution, repeated cancellation, and teardown races.
  - Fixed MinGW/Windows thread-local storage handling for FFmpeg option state by switching the shared DLL build to a safer TLS path for concurrent sessions.

## Version 0.10.0
 
- **FFmpeg 8.1 Upgrade**: Upgraded FFmpeg from 8.0 to 8.1 with updated build patches and synchronized source files.
- **Apple Platform Support**: Added full XCFramework build pipeline for iOS (device), iOS Simulator, and macOS (arm64, x86_64).
- **FFplay Video Playback**: Transitioned to direct video playback on frame callback instead of using SDL.
 
## Version 0.9.1

- **Android FFplay Video Output**: Implemented full video rendering on Android using SDL `dummy` video driver + `software` render driver. Each decoded frame is read from SDL's in-memory back-buffer via `SDL_RenderReadPixels` and blitted row-by-row to the registered `ANativeWindow` via `ANativeWindow_lock/post`. A `SDL_CreateWindow` interceptor in `ffplay_lib.c` logs dimensions and forwards to SDL without requiring `SDLActivity`. New `ffmpeg_kit_android.c` provides JNI glue that retains the `ANativeWindow` for the playback session.
- **Android FFplay Audio Output**: Set `SDL_AUDIODRIVER=openslES` on Android to use the fully-native OpenSL ES backend (no `JavaVM`/`JNI_OnLoad` required). AAudio is also compiled in for API 26+ devices.
- **New Android Java API**: Added `FFplayKitAndroid.java` (`com.akashskypatel.ffmpegkit`) exposing `setAndroidSurface(Surface)` for binding a `SurfaceView` or `TextureView` surface before playback. Added `getNativeWindowPtr(Surface)` → `long` and `releaseNativeWindowPtr(long)` for acquiring and releasing `ANativeWindow*` references directly from Dart FFI.
- **New C/C++ API**: Exposed `ffplay_set_android_window(ANativeWindow*)` in `ffplay_lib.h` for native-layer surface control. Added C wrapper functions `ffplay_kit_set_android_surface_ptr(int64_t)` and `ffplay_kit_clear_android_surface()` for direct Android surface management from Dart FFI. Added `ffplay_kit_register_frame_callback()` / `ffplay_kit_unregister_frame_callback()` and `FFplayKitFrameCallback` typedef for desktop (Linux/Windows) pixel delivery. Added `ffmpeg_kit_get_build_stamp()` for DLL version verification.
- **SDL2 Android Build Fix**: Replaced the broken autotools `configure` path (dropped in SDL2 2.x) with a CMake build using the Android NDK toolchain. Enables `SDL_OPENSL`, `SDL_AAUDIO`, `SDL_VIDEO`, and `SDL_RENDER` backends.
- **Android AAR Orchestration**: Reworked the build pipeline to collect all per-architecture targets first, then invoke `android-aar.sh` once after all arch builds complete. Added `--no-bundle` and conditional `--clean` flags for Android build steps.
- **Android Build Fixes**: Fixed AAR creation guard (`create_bundle` flag), corrected `jniLibs` output path to use `WORKDIR/host_platform`, fixed Maven Central namespace to `io.github.akashskypatel.ffmpegkit`, and corrected package status check return value.
- **Symbol Conflict Resolution**: Fixed LLVM symbol collisions by explicitly linking system LLVM-17 before libtorch. Added proper RPATH configuration for shared library discovery on Linux/Android.
- **Stats Callback Fix**: Corrected stats time unit passed to the C callback — now reported in milliseconds (was fractional seconds).
- **Video Stream Probe API**: Added `ffplay_has_video_stream(path)` to `ffplay_lib.h` and `ffplay_kit_has_video_stream(path)` to the C ABI wrapper. Probes a file or URL for a video stream using `avformat_open_input` + `avformat_find_stream_info` without decoding. Returns 1 (video present), 0 (audio-only), or -1 (error). Thread-safe.
- **Live Video Dimension API**: Added `FFplaySession::getVideoWidth()` and `FFplaySession::getVideoHeight()` to the C++ session API. Returns the current decoded frame dimensions from an active FFplay session, or 0 if no video stream is open.
- **Audio-only Size Guard**: `ffplay_get_video_size()` now returns `0×0` when no video stream is present (`video_st == NULL`), preventing FFplay's audio-visualization window dimensions from being mistaken for video dimensions.
- **`ffplay_get_video_size` Thread Safety**: Added `ffplay_api_mutex` lock and `active_ffplay_ctx == ctx` validation to `ffplay_get_video_size()`, matching the pattern used by all other getters. Prevents use-after-free if `ffplay_free()` races with a concurrent `getVideoWidth()`/`getVideoHeight()` call.
- **ANativeWindow Reference Leak Fix**: Removed redundant `ANativeWindow_acquire()` in `getNativeWindowPtr()` — `ANativeWindow_fromSurface()` already transfers ownership. `releaseNativeWindowPtr()` now correctly balances the single reference.
- **`FFplayKit::setAndroidSurface` Reference Leak Fix**: Added a static retained `ANativeWindow*` in the C++ path so the reference from `ANativeWindow_fromSurface()` is properly released on the next call, mirroring the `g_retained_window` lifecycle in `ffmpeg_kit_android.c`.
- **Pixel Buffer Performance**: Replaced per-frame `av_malloc`/`av_free` in `ffplay_step()` (both Android blit and desktop callback paths) with a static reusable buffer that is only reallocated when frame dimensions increase. Eliminates ~240 MB/s of allocation churn at 1080p/30fps.
- **Android AAR Build Script Fix**: `ANDROID_PLATFORM_ARCHS` array is now populated only when `platform == android`, preventing spurious non-Android arch entries (e.g. `android-x86_64` from a Linux build pass) from being passed to `android-aar.sh` in mixed-platform builds.
- **GitHub Templates**: Updated issue and PR templates to reflect supported platforms (Android, Linux, Windows) and correct branch names, replacing stale upstream ffmpeg-kit references.

## Version 0.9.0

- **Critical Thread Safety Fixes**: Resolved heap-buffer-overflow in ffplay texture upload by copying renderer_info into VideoState and adding swscale fallback for unsupported pixel formats.
- **TLS Architecture Overhaul**: Replaced shared mutable options[] with read-only options_template + per-thread FFMPEG_THREAD_LOCAL options[] copies, eliminating data races between concurrent sessions.
- **Atomic Operations**: Converted redirectionEnabled, _debuggingEnabled, and FFplaySession._context to atomic types with proper memory ordering for thread-safe access.
- **Assert Recovery System**: Implemented thread-local jmp_buf-based crash recovery to prevent application crashes on assertion failures.
- **Build System Refactoring**: Major CMakeLists.txt overhaul with configure_library_linking() function, optional TensorFlow/OpenVINO/libtorch support, and improved MinGW handling.
- **Session Cleanup Improvements**: Enhanced session lifecycle management with proper network initialization/deinitialization and reordered cleanup steps.
- **Windows TLS Compatibility**: Fixed FFMPEG_THREAD_LOCAL declaration for MinGW using __declspec(thread) instead of __thread for correct DLL TLS semantics.
- **Enhanced Patching System**: Added per-file and global TLS exclusion lists to prevent patching of intentionally non-TLS symbols.

## Version 0.8.3

- **MinGW Build Support**: Comprehensive improvements for Windows/MinGW builds including proper CMAKE_BUILD_TYPE handling, static linking configuration, and Windows-specific compiler/linker flags.
- **Threading Fixes**: Replaced `std::recursive_mutex` with custom `KitMutex` for Windows compatibility and updated pthread handling for cross-platform builds.
- **CMake Configuration**: Fixed CMAKE_BUILD_TYPE to use `set()` instead of `option()` to prevent silent conversion to boolean, and improved library linking order for MinGW.
- **Header Organization**: Cleaned up duplicate includes and reorganized headers for better compilation compatibility across platforms.
- **Static Linking**: Enhanced static library resolution with `replace_dll_a_with_static()` function and improved dependency management for Windows builds.

## Version 0.8.2

- **MediaInformation Improvements**: Refactored `ffprobe_kit_get_media_information_async` in the C wrapper to use the specialized `FFprobeKit::getMediaInformationAsync` helper, improving implementation clarity and consistency.
- **Enhanced Test Coverage**: Added comprehensive verification for `media_information_get_all_properties_json` in both `CallbackTest` and `FFmpegKitTest`, ensuring the full metadata retrieval pipeline is functional.
- **Bug Fix**: Corrected `media_information_create_session_with_callbacks` test case to properly provide a full `ffprobe` command string instead of just a file path, fixing an initialization failure in the test environment.

## Version 0.8.1

- **Race Condition Fixes**: Added `std::lock_guard<std::mutex>` protection to `getLogCallback()`, `getStatisticsCallback()`, and `getCompleteCallback()` across all session types (`AbstractSession`, `FFmpegSession`, `FFprobeSession`, `FFplaySession`, `MediaInformationSession`) to eliminate data races on callback accessor reads.
- **Callback Ordering Fix**: Moved `std::atomic_fetch_add` for `sessionInTransitMessageCountMap` to occur *before* enqueuing `CallbackData` in both `logCallbackDataAdd` and `statisticsCallbackDataAdd`, ensuring the in-transit counter is always incremented before the data is visible to the consumer thread.
- **MediaInformation Drain**: Added a `waitForAsynchronousMessagesInTransmit` call after `executeFFprobe` in `getMediaInformationExecute`, guaranteeing all pending log messages are processed before the session is marked complete.
- **New Setter APIs**: Exposed per-session callback setters for FFmpeg, FFprobe, FFplay, and MediaInformation sessions in the C API:
  - `ffmpeg_kit_set_log_callback`, `ffmpeg_kit_set_statistics_callback`, `ffmpeg_kit_set_complete_callback`, `ffmpeg_kit_set_callbacks`
  - `ffprobe_kit_set_log_callback`, `ffprobe_kit_set_complete_callback`, `ffprobe_kit_set_callbacks`
  - `ffplay_kit_set_log_callback`, `ffplay_kit_set_complete_callback`, `ffplay_kit_set_callbacks`
  - `media_information_kit_set_log_callback`, `media_information_kit_set_complete_callback`, `media_information_kit_set_callbacks`
- **Log Message Lifetime**: Changed log message capture in all lambda callbacks from `const std::string&` (dangling reference risk) to `std::string` by value, ensuring message lifetime is safe across async C callback boundaries.
- **Test Hardening**: Moved `CallbackTest` fixture definition after `CallbackCapturer` to fix declaration order; promoted `CallbackCapturer` to a `shared_ptr` member in the fixture to prevent use-after-free in async tests; added a `logs_mutex` to `CallbackCapturer` to protect concurrent `logs` vector writes; added `SessionCallbackStressTest` to verify concurrent callback swapping during active execution.

## Version 0.8.0

- **Memory Leak Fixes**: Pair `strdup_cpp` allocations with `malloc` instead of `new char[]` to ensure compatibility with C-style `free()` used in the wrapper and tests, resolving significant memory leaks detected by ASAN/LSAN.
- **Robust Handle Management**: Enhanced the C wrapper with handle recycling and validity checks. Asynchronous sessions now reuse their initial handles in callbacks, preventing handle leaks and ensuring safe cleanup.
- **Session API Enhancements**: Implemented missing `setCompleteCallback`, `setLogCallback`, and `setStatisticsCallback` methods across all session types (`FFmpegSession`, `FFprobeSession`, `FFplaySession`, `MediaInformationSession`) to support manual lifecycle configuration.
- **Null Safety**: Added comprehensive `nullptr` guards to all session utility functions in the C wrapper, preventing crashes when invalid or released handles are passed.
- **Handle Validation**: Improved `get_ptr_internal` to validate handles against an active handle registry and added support for using session IDs as "temporary" handles in global callbacks.
- **Improved Test Stability**: Updated the test suite to correctly manage the lifecycles of recycled handles and relaxed state checks for environmental failures, ensuring reliable CI runs under AddressSanitizer and ThreadSanitizer.
- **Extended Test Coverage**: Added new test suites for session creation with manual callback registration (`create_session_with_callbacks`) to verify the split creation-execution flow.

## Version 0.7.0

- **Thread Safety**: Fixed a critical data race issue by resolving shadowed mutex synchronization between `AbstractSession` and its subclasses. All session operations now share a unified, protected `_stateMutex`.
- **Statistics Callback**: Ensured statistics reporting is correctly initialized across worker threads by explicitly registering the thread-local `report_callback` during `executeFFmpeg`, `executeFFprobe`, and `executeFFplay`.
- **Snapshot Accessors**: Introduced `getLogsCount()`, `getLogAt()`, `getStatisticsCount()`, and `getStatisticsAt()` to the Session API. Updated the C wrapper to use these indexed accessors for more efficient and thread-safe data retrieval.
- **Improved Synchronization**: Refactored `getLogs()` and `getStatistics()` to return snapshot-style copies of internal data, preventing race conditions during concurrent iteration and modification.
- **Robust Shutdown**: Updated `FFmpegKitConfig::disableRedirection()` to perform a full `pthread_join()` on the background redirection thread, ensuring a clean shutdown and preventing use-after-free races during process termination.
- **Diagnostic Enhancements**: Added comprehensive `try/catch` handlers and a cross-platform (Windows bitwise stack trace and Linux backtrace) crash reporting mechanism to the C wrapper.
- **Windows Portability**: Added `dbghelp` linking to handle stack trace generation on Windows systems.

## Version 0.6.0

- **Thread Safety**: Comprehensive refactoring of session management and global configurations to ensure thread-safe operations. Added mutex protection to `FFmpegSession`, `MediaInformationSession`, and global callback handlers to eliminate data races identified by ThreadSanitizer.
- **Memory Barriers**: Implemented explicit memory barriers in `AbstractSession` destructor to synchronize session lifecycle transitions across threads.
- **Singleton Initialization**: Introduced eager initialization of internal static managers in `ffmpegKitInitialize` to prevent lazy-loading race conditions during high-concurrency bursts.
- **FFplay Robustness**: Synchronized internal API access in the `ffplay` engine, ensuring safe interaction between the SDL event loop and external control commands.
- **Concurrency**: Improved handle management in the C wrapper with global synchronization, preventing use-after-free scenarios during rapid session destruction.

## Version 0.5.0

- **API Extensions**: Added new statistics getter functions to the C API (`ffmpeg_kit_statistics_get_video_frame_number`, `ffmpeg_kit_statistics_get_speed`, etc.) and session listing utilities (`ffmpeg_kit_list_sessions`, `ffprobe_kit_list_sessions`).
- **Performance**: Optimized `Log::getMessage()` to return a constant reference, reducing memory allocations and string copies during high-frequency log processing.
- **Bug Fixes**: Fixed `ffplay_get_volume` to correctly return a normalized float value (0.0 to 1.0) instead of raw SDL volume integers.
- **Test Coverage**: Expanded internal test suite with dedicated `config_test.cpp` and comprehensive validations for `MediaInformation`, global callbacks, and debug logging.

## Version 0.4.1

- **Concurrency**: Refactored `ffmpeg` and `ffplay` internal state variables from volatile to atomic types to ensure safer multi-threaded execution.
- **State Encapsulation**: Moved global display/filter contexts into the `VideoState` struct within `ffplay`, allowing for independent parallel session execution.
- **Thread Initialization**: Updated `ffmpeg_sched.c` to properly initialize Thread-Local Storage (TLS) options for spawned worker threads.
- **Documentation**: Updated `DEVELOPMENT.md` to list exactly which source files from `ffmpeg/fftools` fall under the concurrency patching workflow.

## Version 0.4.0

- **Memory Management**: Fixed a memory leak in log callbacks where message copies were not being freed. Log messages are now passed directly using internal pointers.
- **Robustness**: Modified `ffmpeg_kit_handle_release` to block destruction until the native background thread has gracefully exited. This prevents use-after-free crashes caused by asynchronous log callbacks under high load.
- **Diagnostic Coverage**: Updated integration tests to use `-loglevel debug` by default, ensuring better verification of asynchronous log handling logic.

## Version 0.3.0

- **Synchronization**: Added `wait()` and `waitFor(timeout)` methods to the `Session` interface for efficient, event-driven completion tracking.
- **Thread Safety**: Implemented mutex-protected state transitions in `AbstractSession` to ensure robust session lifecycle management.
- **FFplay Optimization**: Refactored `ffplayExecute` to use the new synchronization primitives instead of busy-wait polling for previous session cleanup.

## Version 0.2.0

- **Concurrency & Thread Safety**: Implemented automated AST-based refactoring to convert FFmpeg global state into Thread-Local Storage (TLS), enabling true multi-threaded execution within the same process.
- **Improved Development Workflow**: Renamed source snapshots (`_bak.c`/`_orig.c`) and introduced `DEVELOPMENT.md` detailing the new automated patching pipeline.
- **FFplay Stability**: Refactored `ffplay` to move engine state into `VideoState` and improved graph cleanup to prevent memory leaks during rapid session recycling.
- **Build System**: Added support for dynamic TLS and options patching directly within the CMake build sequence.
- **Architecture Documentation**: Added a comprehensive `ARCHITECTURE.md` at the project root.

## Version 0.1.4

- Added debug logging infrastructure to `FFmpegKitConfig` (`enableDebugLog`, `getDebugLog`, etc.) for troubleshooting session execution.
- Improved session log handling by ensuring all asynchronous messages are processed before session completion.
- Added `tlsSessionId` thread-local storage to better track sessions in concurrent environments.
- Added `opt_common.c.patch` to prevent `av_log_set_callback` from being overwritten during help/version commands.

## Version 0.1.3

- Transferred session handle ownership to completion callbacks in the C API, enabling manual lifecycle management.
- Updated log and statistics callbacks to include session handles for better progress tracking.
- Added detailed documentation for user data ownership and handle management in `ffmpegkit_wrapper.h`.
- Fixed potential null pointer dereference in internal handle creation logic.
- Ensured FFmpeg log callbacks are correctly initialized before execution.

## Version 0.1.2

- Added `session_is_media_information_session()` C API function to check if a session is a MediaInformation session.
- Fixed potential dangling pointer issues in `ffmpegkit_wrapper.cpp` log handling.
- Prevent potential null dereferences in log and statistics callbacks and introduce `ffmpeg_kit_free` utility function for ABI mismatch issues between C++ and C.

## Version 0.1.1

- Added `cmdutils.c.patch` to skip Win32 UTF-8 argument preparation when building as a DLL (`FFMPEG_KIT_BUILDING_DLL`), preventing host application argument corruption.

## Version 0.1.0

- Added support for listing and setting audio output devices in FFplay.
- Added C API functions to check session type (`session_is_ffmpeg_session`, `session_is_ffprobe_session`, `session_is_ffplay_session`).
- Added C API functions for audio device management.

## Version 0.0.1

- Initial release

## Version 0.0.0

- Repository created
