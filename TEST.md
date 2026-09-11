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
