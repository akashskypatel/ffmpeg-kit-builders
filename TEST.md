# Test documentation

## Build commands to build debug builds

### Thread Sanitizer

```bash
# Linux
sudo ./runner.sh --host=linux --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=thread --build-debug --skip -y

# Windows - note that windows build will need windows libtsan libraries which are not available by defauly on linux
sudo ./runner.sh --host=windows --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=thread --build-debug --skip -y
```

### Address Sanitizer

```bash
# Linux
sudo ./runner.sh --host=linux --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=address --build-debug --skip -y

# Windows - note that windows build will need windows libasan libraries which are not available by defauly on linux
sudo ./runner.sh --host=windows --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=address --build-debug --skip -y
```

### Undefined Behavior Sanitizer

```bash
# Linux
sudo ./runner.sh --host=linux --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=undefined --build-debug --skip -y

# Windows - note that windows build will need windows libubsan libraries which are not available by defauly on linux
sudo ./runner.sh --host=windows --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=undefined --build-debug --skip -y
```

## Test execution Commands

### Thread Sanitizer

```bash
# disbale ASLR temporarily for thread sanitizer tests
setarch $(uname -m) -R ./FFmpegKit/build/tests/ffmpegkit_tests > test_tsan.log 2>&1
```

### Address Sanitizer

```bash
export LSAN_OPTIONS=suppressions=/home/vscode/ffmpeg-kit-builders/FFmpegKit/tests/asan.supp && export ASAN_OPTIONS=detect_odr_violation=0:detect_leaks=1 && ./FFmpegKit/build/tests/ffmpegkit_tests > test_asan.log 2>&1
```


### Wasm pthread callback authority

The G0 callback authority test must be configured and executed with Emscripten
pthread support. The isolated build below uses the existing Wasm base bundle
and runs the test executable under Node:

```bash
source /usr/local/emsdk/emsdk_env.sh
export EM_CACHE=/home/vscode/ffmpeg-kit-builders/.emscripten-cache-g0
export PKG_CONFIG_PATH=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries/lib/pkgconfig:/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl/lib/pkgconfig

emcmake cmake \
  -S /home/vscode/ffmpeg-kit-builders/FFmpegKit \
  -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g0 \
  -DBUILD_TESTS=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl \
  -DDEPENDENCY_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries \
  -DFFMPEG_KIT_BUNDLE_TYPE=base \
  -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4

cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g0 \
  --target ffmpegkit_wasm_callback_tests -j2

node /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g0/tests/ffmpegkit_wasm_callback_tests.js \
  --gtest_filter=WasmCallbackAuthorityTest.*

ctest --test-dir /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g0 \
  --output-on-failure -R '^ffmpegkit_wasm_callback_tests$'
```

The test is valid only when it passes under Emscripten and proves that the
worker pthread is distinct from the main runtime thread, with the proxied
callback observed on the main runtime thread.

### G1 callback lock re-entry

The G1 regression test registers a real FFmpegKit global log callback. The
callback unregisters itself through the public wrapper API, which acquires the
same global callback-state lock. A five-second watchdog makes lock re-entry
failure explicit.

#### Native Linux

```bash
cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build --target ffmpegkit_tests -j2
ctest --test-dir /home/vscode/ffmpeg-kit-builders/FFmpegKit/build --output-on-failure -R '^ffmpegkit_tests$'
```

#### Wasm pthread build

```bash
source /usr/local/emsdk/emsdk_env.sh
export EM_CACHE=/home/vscode/ffmpeg-kit-builders/.emscripten-cache-g1
export PKG_CONFIG_PATH=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries/lib/pkgconfig:/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl/lib/pkgconfig

emcmake cmake \
  -S /home/vscode/ffmpeg-kit-builders/FFmpegKit \
  -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g1 \
  -DBUILD_TESTS=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl \
  -DDEPENDENCY_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries \
  -DFFMPEG_KIT_BUNDLE_TYPE=base \
  -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4

cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g1 \
  --target ffmpegkit_wasm_callback_tests -j2

node /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g1/tests/ffmpegkit_wasm_callback_tests.js \
  --gtest_filter=GlobalCallbackLockTest.*

ctest --test-dir /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g1 \
  --output-on-failure -R '^ffmpegkit_wasm_callback_tests$'
```

### G2 pthread startup failure safety

The G2 regression suite injects an immediate `pthread_create()` failure and
checks that callback redirection and every asynchronous session family reach a
deterministic terminal state. It also exercises successful pthread startup for
each family.

#### Native Linux

```bash
sudo cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build \
  --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 90s \
  /home/vscode/ffmpeg-kit-builders/FFmpegKit/build/tests/ffmpegkit_tests \
  --gtest_filter=PthreadFailureTest.*
```

#### Wasm pthread build

### G3 synchronized C wrapper callback state

The G3 stress test concurrently replaces and clears the global log callback
while another thread emits unattributed logs. Callback and user-data pairs are
snapshotted under one mutex, and user callbacks run after the snapshot.

#### Native Linux with ThreadSanitizer

```bash
sudo cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build \
  --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 120s \
  /home/vscode/ffmpeg-kit-builders/FFmpegKit/build/tests/ffmpegkit_tests \
  --gtest_filter=WrapperCallbackStateTest.*
```

#### Wasm pthread build and registered harness

```bash
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && export EM_CACHE=/home/vscode/ffmpeg-kit-builders/.emscripten-cache-g3 && export PKG_CONFIG_PATH=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries/lib/pkgconfig:/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl/lib/pkgconfig && emcmake cmake -S /home/vscode/ffmpeg-kit-builders/FFmpegKit -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g3 -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug -DFFMPEG_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl -DDEPENDENCY_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4 && cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g3 --target ffmpegkit_wasm_callback_tests -j2'
/usr/local/emsdk/node/24.19.0_64bit/bin/node \
  /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g3/tests/ffmpegkit_wasm_callback_tests.js \
  --gtest_filter=WrapperCallbackStateTest.*
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && ctest --test-dir /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g3 --output-on-failure -R ^ffmpegkit_wasm_callback_tests$'
```

The Wasm build uses 1,000 emissions to remain within the existing fixed
16 MiB test heap after the preceding startup-failure suite; the registration
side still performs 3,000 replacements.

### G4 versioned session-ID callback ABI

G4 adds versioned C callback exports that pass the stable session ID as an
`int64_t` value. The legacy opaque-handle callback exports remain available;
their compatibility pointer transport and handle heuristics are unchanged.
The boundary test uses a test-only synthetic emitter so IDs beyond the Wasm
32-bit pointer range are validated without constructing an impossible Wasm
`long` session ID.

#### Native Linux

```bash
sudo cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build \
  --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 120s \
  /home/vscode/ffmpeg-kit-builders/FFmpegKit/build/tests/ffmpegkit_tests \
  --gtest_filter=VersionedCallbackTest.*
```

#### Wasm pthread build and registered harness

```bash
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && export EM_CACHE=/home/vscode/ffmpeg-kit-builders/.emscripten-cache-g4 && export PKG_CONFIG_PATH=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries/lib/pkgconfig:/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl/lib/pkgconfig && emcmake cmake -S /home/vscode/ffmpeg-kit-builders/FFmpegKit -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g4 -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug -DFFMPEG_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl -DDEPENDENCY_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4 && cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g4 --target ffmpegkit_wasm_callback_tests -j2'
/usr/local/emsdk/node/24.19.0_64bit/bin/node \
  /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g4/tests/ffmpegkit_wasm_callback_tests.js \
  --gtest_filter=VersionedCallbackTest.*
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && ctest --test-dir /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g4 --output-on-failure -R ^ffmpegkit_wasm_callback_tests$'
```

Results for the G4 verification run:

- Native build succeeded; the focused test passed 1/1.
- Wasm pthread configure/build succeeded; the focused Node test passed 1/1.
- The registered Wasm CTest harness passed 1/1 entries, including the full
  13-test G0-G4 callback suite.

### G5 main-runtime callback dispatcher

The G5 dispatcher owns each payload until delivery. Native callers execute
callbacks directly; Emscripten worker callers use `emscripten_proxy_async()`
to target `emscripten_main_runtime_thread_id()`. `process_pending()` lets
deterministic hosts and tests explicitly drain the main-runtime queue.

#### Native Linux

```bash
sudo cmake -S /home/vscode/ffmpeg-kit-builders/FFmpegKit \
  -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build
sudo cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build \
  --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 120s \
  /home/vscode/ffmpeg-kit-builders/FFmpegKit/build/tests/ffmpegkit_tests \
  --gtest_filter=WasmCallbackDispatcherTest.*
```

#### Wasm pthread build and registered harness

```bash
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && export EM_CACHE=/home/vscode/ffmpeg-kit-builders/.emscripten-cache-g5 && export PKG_CONFIG_PATH=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries/lib/pkgconfig:/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl/lib/pkgconfig && emcmake cmake -S /home/vscode/ffmpeg-kit-builders/FFmpegKit -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g5 -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug -DFFMPEG_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl -DDEPENDENCY_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4 && cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g5 --target ffmpegkit_wasm_callback_tests -j2'
/usr/local/emsdk/node/24.19.0_64bit/bin/node \
  /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g5/tests/ffmpegkit_wasm_callback_tests.js \
  --gtest_filter=WasmCallbackDispatcherTest.*
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && ctest --test-dir /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g5 --output-on-failure -R ^ffmpegkit_wasm_callback_tests$'
```

Results for the G5 verification run:

- Native direct-dispatch test: 1/1 passed.
- Wasm pthread dispatcher test: 10,000/10,000 callbacks passed exactly once
  with intact payloads on the main runtime thread.
- Registered Wasm CTest harness: 1/1 entry passed, including the full
  14-test G0-G5 callback suite.

```bash
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && export EM_CACHE=/home/vscode/ffmpeg-kit-builders/.emscripten-cache-g2 && export PKG_CONFIG_PATH=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries/lib/pkgconfig:/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl/lib/pkgconfig && emcmake cmake -S /home/vscode/ffmpeg-kit-builders/FFmpegKit -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g2 -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug -DFFMPEG_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl -DDEPENDENCY_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4 && cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g2 --target ffmpegkit_wasm_callback_tests -j2'
/usr/local/emsdk/node/24.19.0_64bit/bin/node \
  /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g2/tests/ffmpegkit_wasm_callback_tests.js \
  --gtest_filter=PthreadFailureTest.*
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && ctest --test-dir /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g2 --output-on-failure -R ^ffmpegkit_wasm_callback_tests$'
```

### G6 session completion callbacks

G6 routes the four global V2 session-completion callback families through
WasmCallbackDispatcher. The callback event retains only the session ID,
callback function pointer, and user data. The callback is scheduled after the
session has reached its terminal state, and Wasm delivery is drained on the
main runtime thread by the test host.

#### Native Linux

```bash
sudo cmake -S /home/vscode/ffmpeg-kit-builders/FFmpegKit -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build
sudo cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 120s /home/vscode/ffmpeg-kit-builders/FFmpegKit/build/tests/ffmpegkit_tests --gtest_filter=G6SessionCompletionTest.*
```

#### Wasm pthread build, direct Node, and registered CTest

```bash
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && export EM_CACHE=/home/vscode/ffmpeg-kit-builders/.emscripten-cache-g6 && export PKG_CONFIG_PATH=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries/lib/pkgconfig:/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl/lib/pkgconfig && emcmake cmake -S /home/vscode/ffmpeg-kit-builders/FFmpegKit -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g6 -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug -DFFMPEG_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl -DDEPENDENCY_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4 && cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g6 --target ffmpegkit_wasm_callback_tests -j2'
/usr/local/emsdk/node/24.19.0_64bit/bin/node /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g6/tests/ffmpegkit_wasm_callback_tests.js --gtest_filter=G6SessionCompletionTest.*
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && ctest --test-dir /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g6 --output-on-failure -R ^ffmpegkit_wasm_callback_tests$'
```

Results for the G6 verification run:

- Native target rebuilt successfully; the focused test passed 1/1.
- Wasm pthread target configured and built successfully; the focused Node test
  passed 1/1.
- The registered Wasm CTest entry passed 1/1, including the full 15-test G0-G6
  callback harness.
- The focused test delivered exactly once for each of the four session
  families, observed terminal state and the expected session ID, verified
  main-runtime delivery under Emscripten, and covered disabled, reconfigured,
  and unregistered callbacks.

### G7 log and statistics callbacks

G7 routes global V2 log and statistics callbacks through the shared
WasmCallbackDispatcher. Log messages are copied into owned event storage before
the producer callback returns; statistics are captured as scalar values. The
same queue also carries FFmpeg completion callbacks, so the ordering test
defines and verifies a drain-before-completion contract.

#### Native Linux

```bash
sudo cmake -S /home/vscode/ffmpeg-kit-builders/FFmpegKit -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build
sudo cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 120s /home/vscode/ffmpeg-kit-builders/FFmpegKit/build/tests/ffmpegkit_tests --gtest_filter=G7LogStatisticsTest.*
```

#### Wasm pthread build, direct Node, and registered CTest

```bash
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && export EM_CACHE=/home/vscode/ffmpeg-kit-builders/.emscripten-cache-g7 && export PKG_CONFIG_PATH=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries/lib/pkgconfig:/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl/lib/pkgconfig && emcmake cmake -S /home/vscode/ffmpeg-kit-builders/FFmpegKit -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g7 -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug -DFFMPEG_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl -DDEPENDENCY_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4 && cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g7 --target ffmpegkit_wasm_callback_tests -j2'
/usr/local/emsdk/node/24.19.0_64bit/bin/node /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g7/tests/ffmpegkit_wasm_callback_tests.js --gtest_filter=G7LogStatisticsTest.*
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && export EM_CACHE=/home/vscode/ffmpeg-kit-builders/.emscripten-cache-g7 && ctest --test-dir /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g7 --output-on-failure -R ^ffmpegkit_wasm_callback_tests$'
```

Results for the G7 verification run:

- Native target rebuilt successfully; the focused test passed 1/1.
- Wasm pthread target configured and built successfully; the focused Node test
  passed 1/1.
- The registered Wasm CTest entry passed 1/1, including the full 16-test G0-G7
  callback harness.
- The focused test generated 2,048 worker log events and 2,048 worker
  statistics events, verified exact-once delivery, preserved log contents
  after the producer buffer was overwritten, preserved every scalar statistic,
  preserved session IDs and ordering, delivered all events on the Emscripten
  main runtime thread, and delivered the completion callback last.
- The direct Node run emitted the known post-exit callback cleanup warning
  after a successful exit.

### G8 independent C/C++ Wasm callback gate

G8 is satisfied by the complete Wasm-only callback harness. No Flutter,
generated bindings, or `ffigen_js` code is involved.

#### Full pinned Node harness and registered CTest

```bash
/usr/local/emsdk/node/24.19.0_64bit/bin/node /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g7/tests/ffmpegkit_wasm_callback_tests.js
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && export EM_CACHE=/home/vscode/ffmpeg-kit-builders/.emscripten-cache-g7 && ctest --test-dir /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-g7 --output-on-failure -R ^ffmpegkit_wasm_callback_tests$'
```

Coverage matrix:

- FFmpeg, FFprobe, FFplay, and MediaInformation completion: G6.
- Log payload lifetime and statistics scalar delivery: G7.
- Callback re-entry and callback-state stress: G1/G3.
- Callback unregister and replacement: G6 lifecycle assertions.
- Pthread producer to main-runtime consumer: G0/G5/G7.
- High session IDs: G4.
- Concurrent sessions: G6.
- Pthread creation and redirection startup failures: G2.
- Callback ordering and drain-before-completion: G7.

Results for the G8 verification run:

- The complete pinned Node harness ran 16 tests from 8 suites and passed
  16/16.
- The registered Wasm CTest entry passed 1/1 and covers the same 16-test
  harness.
- The hard gate is satisfied: the native C/C++ callback layer is proven under
  pthread-enabled Wasm independently of Dart and `ffigen_js`.

### G9 Wasm indirect function-table growth

G9 enables Emscripten runtime table growth on the final `ffmpegkit_wasm`
module with `-sALLOW_TABLE_GROWTH=1`.

#### Build

```bash
sudo bash -lc 'source /usr/local/emsdk/emsdk_env.sh && export EM_CACHE=/home/vscode/ffmpeg-kit-builders/.emscripten-cache-g9 && export PKG_CONFIG_PATH=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries/lib/pkgconfig:/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl/lib/pkgconfig && emcmake cmake -S /home/vscode/ffmpeg-kit-builders/FFmpegKit -B /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-table-g9 -DBUILD_TESTS=OFF -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug -DFFMPEG_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl -DDEPENDENCY_BUILD_DIR=/home/vscode/ffmpeg-kit-builders/prebuilt/wasm-wasm32/libraries -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4 && cmake --build /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-table-g9 --target ffmpegkit_wasm -j2'
```

#### Artifact inspection

The built artifact is:

```text
/home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-table-g9/ffmpegkit.wasm
```

An inspection of the actual `WebAssembly.Table` export
`__indirect_function_table` recorded:

- initial table size: 14,575
- maximum table size: no explicit maximum declared; runtime growth is enabled
- occupied slots before growth: 14,574
- `table.grow(1)`: returned old length 14,575 and succeeded
- element count after growth: 14,576

Results for the G9 verification run:

- The final `ffmpegkit_wasm` target configured and built successfully.
- The link command contains `-sALLOW_TABLE_GROWTH=1`.
- Instantiating the actual built module and calling `table.grow(1)`
  succeeded, satisfying the G9 gate.
