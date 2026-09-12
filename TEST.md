# Test documentation

This document describes library build and test commands. The examples use the
FFmpegKit builder checkout and the prebuilt Wasm base bundle.

## Build commands for debug builds

### Thread Sanitizer

```bash
# Linux
sudo ./runner.sh --host=linux --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=thread --build-debug --skip -y

# Windows - Windows libtsan libraries are not available by default on Linux.
sudo ./runner.sh --host=windows --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=thread --build-debug --skip -y
```

### Address Sanitizer

```bash
# Linux
sudo ./runner.sh --host=linux --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=address --build-debug --skip -y

# Windows - Windows libasan libraries are not available by default on Linux.
sudo ./runner.sh --host=windows --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=address --build-debug --skip -y
```

### Undefined Behavior Sanitizer

```bash
# Linux
sudo ./runner.sh --host=linux --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=undefined --build-debug --skip -y

# Windows - Windows libubsan libraries are not available by default on Linux.
sudo ./runner.sh --host=windows --arch=x86_64 --enable-base --gpl --kit --build-deps --no-bundle --test=undefined --build-debug --skip -y
```

## Test execution commands

### Thread Sanitizer

```bash
# Disable ASLR temporarily for ThreadSanitizer tests.
setarch $(uname -m) -R ./FFmpegKit/build/tests/ffmpegkit_tests > test_tsan.log 2>&1
```

### Address Sanitizer

```bash
export LSAN_OPTIONS=suppressions=/home/vscode/ffmpeg-kit-builders/FFmpegKit/tests/asan.supp
export ASAN_OPTIONS=detect_odr_violation=0:detect_leaks=1
./FFmpegKit/build/tests/ffmpegkit_tests > test_asan.log 2>&1
```

## Wasm callback tests

The Wasm callback harness is built with Emscripten pthread support and runs
under Node. Each focused command uses a semantic build directory so independent
test runs can coexist.

### Common Wasm configuration

```bash
export FFMPEG_KIT_ROOT=/home/vscode/ffmpeg-kit-builders
export FFMPEG_KIT_SOURCE=$FFMPEG_KIT_ROOT/FFmpegKit
export FFMPEG_KIT_DEPS=$FFMPEG_KIT_ROOT/prebuilt/wasm-wasm32/libraries
export FFMPEG_KIT_BUNDLE=$FFMPEG_KIT_ROOT/prebuilt/wasm-wasm32/ffmpeg-base-wasm-wasm32-static-gpl
export PKG_CONFIG_PATH=$FFMPEG_KIT_DEPS/lib/pkgconfig:$FFMPEG_KIT_BUNDLE/lib/pkgconfig
source /usr/local/emsdk/emsdk_env.sh
```

### Callback thread identity

This focused test verifies that a worker pthread is distinct from the main
runtime thread and that a proxied callback is observed on the main runtime.

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-callback-authority
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-callback-authority
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm_callback_tests -j2
node "$FFMPEG_KIT_BUILD/tests/ffmpegkit_wasm_callback_tests.js" \
  --gtest_filter=WasmCallbackAuthorityTest.*
ctest --test-dir "$FFMPEG_KIT_BUILD" --output-on-failure \
  -R '^ffmpegkit_wasm_callback_tests$'
```

### Callback lock re-entry

This test registers a global log callback that unregisters itself through the
public wrapper API while the callback-state lock is held. A watchdog makes
lock re-entry failures explicit.

#### Native Linux

```bash
cmake --build "$FFMPEG_KIT_SOURCE/build" --target ffmpegkit_tests -j2
ctest --test-dir "$FFMPEG_KIT_SOURCE/build" --output-on-failure -R '^ffmpegkit_tests$'
```

#### Wasm

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-callback-lock
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-callback-lock
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm_callback_tests -j2
node "$FFMPEG_KIT_BUILD/tests/ffmpegkit_wasm_callback_tests.js" \
  --gtest_filter=GlobalCallbackLockTest.*
ctest --test-dir "$FFMPEG_KIT_BUILD" --output-on-failure \
  -R '^ffmpegkit_wasm_callback_tests$'
```

### Pthread startup failure safety

This suite injects an immediate `pthread_create()` failure and checks that
callback redirection and each asynchronous session family reach a deterministic
terminal state. It also exercises successful pthread startup.

#### Native Linux

```bash
cmake --build "$FFMPEG_KIT_SOURCE/build" --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 90s \
  "$FFMPEG_KIT_SOURCE/build/tests/ffmpegkit_tests" \
  --gtest_filter=PthreadFailureTest.*
```

#### Wasm

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-startup-safety
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-startup-safety
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm_callback_tests -j2
node "$FFMPEG_KIT_BUILD/tests/ffmpegkit_wasm_callback_tests.js" \
  --gtest_filter=PthreadFailureTest.*
ctest --test-dir "$FFMPEG_KIT_BUILD" --output-on-failure \
  -R '^ffmpegkit_wasm_callback_tests$'
```

### Synchronized wrapper callback state

This stress test concurrently replaces and clears the global log callback while
another thread emits unattributed logs. Callback and user-data pairs are
snapshotted under one mutex before user code runs.

#### Native Linux with ThreadSanitizer

```bash
cmake --build "$FFMPEG_KIT_SOURCE/build" --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 120s \
  "$FFMPEG_KIT_SOURCE/build/tests/ffmpegkit_tests" \
  --gtest_filter=WrapperCallbackStateTest.*
```

#### Wasm

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-callback-state
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-callback-state
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm_callback_tests -j2
node "$FFMPEG_KIT_BUILD/tests/ffmpegkit_wasm_callback_tests.js" \
  --gtest_filter=WrapperCallbackStateTest.*
ctest --test-dir "$FFMPEG_KIT_BUILD" --output-on-failure \
  -R '^ffmpegkit_wasm_callback_tests$'
```

The Wasm configuration uses a bounded emission count to remain within the
existing fixed test heap; callback registration still performs a larger set of
replacements.

### Stable session-ID callback ABI

This boundary test verifies versioned C callback exports that pass the stable
session ID as an `int64_t`. Legacy opaque-handle exports remain available, and
a synthetic emitter validates IDs beyond the Wasm 32-bit pointer range.

#### Native Linux

```bash
cmake --build "$FFMPEG_KIT_SOURCE/build" --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 120s \
  "$FFMPEG_KIT_SOURCE/build/tests/ffmpegkit_tests" \
  --gtest_filter=VersionedCallbackTest.*
```

#### Wasm

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-session-id
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-session-id
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm_callback_tests -j2
node "$FFMPEG_KIT_BUILD/tests/ffmpegkit_wasm_callback_tests.js" \
  --gtest_filter=VersionedCallbackTest.*
ctest --test-dir "$FFMPEG_KIT_BUILD" --output-on-failure \
  -R '^ffmpegkit_wasm_callback_tests$'
```

### Main-runtime callback dispatcher

The dispatcher owns each payload until delivery. Native callers execute
callbacks directly; Emscripten worker callers proxy to the main runtime.
`process_pending()` lets deterministic hosts and tests explicitly drain the
main-runtime queue.

#### Native Linux

```bash
cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_SOURCE/build"
cmake --build "$FFMPEG_KIT_SOURCE/build" --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 120s \
  "$FFMPEG_KIT_SOURCE/build/tests/ffmpegkit_tests" \
  --gtest_filter=WasmCallbackDispatcherTest.*
```

#### Wasm

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-callback-dispatch
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-callback-dispatch
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm_callback_tests -j2
node "$FFMPEG_KIT_BUILD/tests/ffmpegkit_wasm_callback_tests.js" \
  --gtest_filter=WasmCallbackDispatcherTest.*
ctest --test-dir "$FFMPEG_KIT_BUILD" --output-on-failure \
  -R '^ffmpegkit_wasm_callback_tests$'
```

### Session completion callbacks

This test covers the FFmpeg, FFprobe, FFplay, and MediaInformation completion
families. Events retain the session ID, callback pointer, and user data until
delivery after terminal state is reached.

#### Native Linux

```bash
cmake --build "$FFMPEG_KIT_SOURCE/build" --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 120s \
  "$FFMPEG_KIT_SOURCE/build/tests/ffmpegkit_tests" \
  --gtest_filter=SessionCompletionTest.*
```

#### Wasm

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-session-completion
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-session-completion
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm_callback_tests -j2
node "$FFMPEG_KIT_BUILD/tests/ffmpegkit_wasm_callback_tests.js" \
  --gtest_filter=SessionCompletionTest.*
ctest --test-dir "$FFMPEG_KIT_BUILD" --output-on-failure \
  -R '^ffmpegkit_wasm_callback_tests$'
```

### Log and statistics callbacks

This test verifies owned log payloads, scalar statistics delivery, callback
ordering, and completion after the queue has drained.

#### Native Linux

```bash
cmake --build "$FFMPEG_KIT_SOURCE/build" --target ffmpegkit_tests -j2
setarch $(uname -m) -R timeout 120s \
  "$FFMPEG_KIT_SOURCE/build/tests/ffmpegkit_tests" \
  --gtest_filter=LogStatisticsTest.*
```

#### Wasm

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-log-statistics
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-log-statistics
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm_callback_tests -j2
node "$FFMPEG_KIT_BUILD/tests/ffmpegkit_wasm_callback_tests.js" \
  --gtest_filter=LogStatisticsTest.*
ctest --test-dir "$FFMPEG_KIT_BUILD" --output-on-failure \
  -R '^ffmpegkit_wasm_callback_tests$'
```

### Complete C/C++ Wasm callback harness

The complete harness is independent of Flutter, generated bindings, and
`ffigen_js`. It covers callback thread identity, lock re-entry, startup
failures, synchronized state, stable session IDs, dispatch, completion,
logging, statistics, replacement, and ordering.

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-callback-suite
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-callback-suite
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm_callback_tests -j2
/usr/local/emsdk/node/24.19.0_64bit/bin/node \
  "$FFMPEG_KIT_BUILD/tests/ffmpegkit_wasm_callback_tests.js"
ctest --test-dir "$FFMPEG_KIT_BUILD" --output-on-failure \
  -R '^ffmpegkit_wasm_callback_tests$'
```

### Wasm indirect function-table growth

This build enables Emscripten runtime table growth on the final
`ffmpegkit_wasm` module with `-sALLOW_TABLE_GROWTH=1`.

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-table-growth
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-table-growth
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=OFF -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm -j2
```

The built artifact is:

```text
$FFMPEG_KIT_BUILD/ffmpegkit.wasm
```

Inspect the actual `WebAssembly.Table` export `__indirect_function_table` and
verify that `table.grow(1)` succeeds.

### Wasm table-growth artifact test

This automated Node test instantiates the actual Wasm binary, discovers the
table by runtime type, verifies growth, preserves an existing callable Wasm
function, writes compatible functions into new slots, and repeats growth.

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-table-growth-test
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-table-growth-test
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm -j2
/usr/local/emsdk/node/24.19.0_64bit/bin/node \
  "$FFMPEG_KIT_SOURCE/tests/table_growth_test.mjs" \
  "$FFMPEG_KIT_BUILD/ffmpegkit.wasm"
ctest --test-dir "$FFMPEG_KIT_BUILD" --output-on-failure \
  -R '^ffmpegkit_wasm_table_growth$'
```

Example output:

```text
{"artifact":"FFmpegKit/build-wasm-table-growth-test/ffmpegkit.wasm","tableDiscoveryCount":1,"initialLength":14575,"firstGrowReturn":14575,"finalLength":14602,"oldFunctionIndex":9,"writableIndex":14575,"repeatedGrowth":[3,7,16],"status":"PASS"}
```

### C-to-JS Wasm callback round-trip

This test-only build exports the C++ V2 callback emitters and uses the
generated Emscripten loader to initialize the main runtime before registering
callback pointers. The production environment remains `web,worker`; this
verification build selects `node`.

```bash
export EM_CACHE=$FFMPEG_KIT_ROOT/.emscripten-cache-callback-roundtrip
export FFMPEG_KIT_BUILD=$FFMPEG_KIT_SOURCE/build-wasm-callback-roundtrip
emcmake cmake -S "$FFMPEG_KIT_SOURCE" -B "$FFMPEG_KIT_BUILD" \
  -DBUILD_TESTS=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Debug \
  -DFFMPEG_KIT_WASM_ENVIRONMENT=node \
  -DFFMPEG_BUILD_DIR="$FFMPEG_KIT_BUNDLE" \
  -DDEPENDENCY_BUILD_DIR="$FFMPEG_KIT_DEPS" \
  -DFFMPEG_KIT_BUNDLE_TYPE=base -DFFMPEG_KIT_WASM_PTHREAD_POOL_SIZE=4
cmake --build "$FFMPEG_KIT_BUILD" --target ffmpegkit_wasm -j2
```

From the Windows checkout, run the loader-initialized test with the artifact
and generated loader from the Wasm build:

```bash
wsl.exe -d ManyLinux -- bash -lc "cd /mnt/d/Projects/ffmpeg_kit_extended && /usr/local/emsdk/node/24.19.0_64bit/bin/node flutter/web/ffmpegkit_callback_roundtrip_test.mjs /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-roundtrip/ffmpegkit.wasm /home/vscode/ffmpeg-kit-builders/FFmpegKit/build-wasm-callback-roundtrip/ffmpegkit.mjs"
```

The test should report one completion, the expected log and statistics counts,
the stable session ID, and `"status":"PASS"`.
