# Batch build commands

You can use the batch build script to build ffmpeg, ffmpeg-kit, and bundles for multiple platforms and architectures.

## All platforms

### Build All Script Options

```bash
VALID_TYPES=("full" "video_hw" "video" "audio" "base" "debug")
VALID_PLATFORMS=("linux" "windows" "android" "ios" "iphonesimulator" "macos")
VALID_PLATFORM_ARCHS=("linux-x86_64" "windows-x86_64" "android-aarch64" "android-armv7a" "android-x86_64" "ios-aarch64" "iphonesimulator-aarch64" "macos-aarch64" "macos-x86_64")
VALID_BUILDS=("ffmpeg" "kit" "bundle")
VALID_LICENSES=("lgpl" "gpl")
VALID_SMALL_FLAGS=("small" "")
"
Usage: $0 [--platform=<platform>|<platform-arch>,...] [--deps] [--reset] [--bundles=*] [--help]

Options:
  --platform=*  Comma separated (without spaces) list of platforms or platform-arch pairs.
                A plain platform name expands to all valid archs for that platform.
                  e.g. --platform=android              → android-aarch64,android-armv7a,android-x86_64
                  e.g. --platform=android,linux-x86_64 → android (all archs) + linux-x86_64
                Valid platforms (expands to all archs): ${VALID_PLATFORMS[*]}
                Valid platform-arch combinations:       ${VALID_PLATFORM_ARCHS[*]}
  --deps        Build dependencies first
  --reset       Reset build state and start from beginning
  --bundle=*    Comma separated (without spaces) list of bundles to build (e.g. --bundle=debug,full,base,audio,video,video_hw)
                Valid bundles: ${VALID_TYPES[*]}
  --build=*     Comma separated (without spaces) list of builds to build (e.g. --build=ffmpeg,kit,bundle)
                Valid builds: ${VALID_BUILDS[*]}
  --clean=*     Comma separated (without spaces) list of components to clean (e.g. --clean=ffmpeg,kit,bundle)
                Valid components: all OR ${VALID_BUILDS[*]}
  --license=*   Comma separated (without spaces) list of licenses to build
                Valid licenses: ${VALID_LICENSES[*]}
  --remote      Publish release asset to remote repository
  --local       Build locally instead of using remote releases
  --small       Build with small flags (reduces binary size)
  --not-small   Build without small flag
  --both        Build both small and full versions (default)
  --snapshot    Create snapshot version (Android only)
  --help        Show this help message
"
```


### Build FFmpeg Only

Building ffmpeg before building kit or bundle is required. You can combine building ffmpeg with building kit or bundle but each build will take significantly longer. It is recommended to build ffmpeg first, then build kit and bundle together.

```bash
# this will take a very long time
# add --deps if you need ffmpeg deps built first
sudo ./scripts/build_all.sh --build=ffmpeg --platform=<PLATFORMS>
```

### Build Kit and Bundle Only
```bash
# add --reset if you need to start from scratch otherwise the script will resume from where it left off if it was interrupted

# local build only
sudo ./scripts/build_all.sh --build=kit,bundle --local --platform=<PLATFORMS>

# remote build only. final build artifacts will be published to remote repository
sudo ./scripts/build_all.sh --build=kit,bundle --remote --platform=<PLATFORMS>
```

## Android specific

### Build Android Script Options

```bash
VALID_TYPES=("debug" "full" "base" "audio" "video" "video_hw")
VALID_ARCHS=("x86_64" "aarch64" "armv7a")
VALID_PLATFORM_ARCHS=("android-aarch64" "android-armv7a" "android-x86_64")
VALID_PLATFORMS=("android-aarch64" "android-armv7a" "android-x86_64")

"
Usage: $0 [--platform=linux-x86_64|windows-x86_64|android-aarch64|android-armv7a|android-x86_64] [--reset] [--bundles=*) ] [--help]

Options:
  --platform=*      Comma separated (without spaces) list of platforms and architectures (e.g. --platform=linux-x86_64,windows-x86_64,android-aarch64,android-armv7a,android-x86_64)
                    Valid platforms: ${VALID_PLATFORMS[*]}
                    Valid architectures: ${VALID_ARCHS[*]}
                    Valid platform and arch combinations: ${VALID_PLATFORM_ARCHS[*]}
  --reset           Reset build state and start from beginning
  --bundle=*        Comma separated (without spaces) list of bundles to build (e.g. --bundle=debug,full,base,audio,video,video_hw)
                    Valid bundles: ${VALID_TYPES[*]}
                    Note: Not including one of below flags will create all of artifacts: AAR, and release
                    Do not specify if you want to create all artifacts.
  --license=*       Comma separated (without spaces) list of licenses to build
                    Valid licenses: ${VALID_LICENSES[*]}
  --create-aar      Create AAR file. Will not create release.
  --create-release  Create release. Will not create AAR. Requires aar release asset to be present.
  --small           Build with small flags (reduces binary size).
  --not-small       Build without small flag.
  --both            Build both small and full versions (default)
  --local           Create local release.
  --remote          Publish release to remote repository.
  --snapshot        Create snapshot version.
  --help            Show this help message
"
```

### Build Android AAR

```bash
# add optional --platform=<PLATFORM> if you want to build for specific platform otherwise it will build for all platforms
# add --create-aar if you want to build local AAR files only
# add --create-release if you want to publish the local AAR files to remote repository. It will not create local AAR files.
# local build only
sudo ./scripts/android/build_aar.sh --local

# remote build only
sudo ./scripts/android/build_aar.sh --remote
```

## Apple Specific

### Build XCFramework Options

```bash
VALID_TYPES=("debug" "full" "base" "audio" "video" "video_hw")
VALID_PLATFORMS=("ios" "macos")
VALID_PLATFORM_ARCHS=("ios-aarch64" "iphonesimulator-aarch64" "macos-aarch64" "macos-x86_64")
VALID_LICENSES=("lgpl" "gpl")
VALID_SMALL_FLAGS=("small" "")

"
Usage: $0 [--platform=ios-aarch64,iphonesimulator-aarch64,macos-aarch64,macos-x86_64] [--bundle=base,audio,video,video_hw,full,debug] [--license=gpl,lgpl] [--reset] [--help]

Options:
  --platform=*        Comma separated (without spaces) list of platforms or platform-arch pairs.
                      A plain platform name expands to all valid archs for that platform.
                        e.g. --platform=ios              → ios-aarch64,iphonesimulator-aarch64
                        e.g. --platform=ios,macos-x86_64 → ios (all archs) + macos-x86_64
                      Valid platforms (expands to all archs): ${VALID_PLATFORMS[*]}
                      Valid platform-arch combinations:       ${VALID_PLATFORM_ARCHS[*]}
                      Note: iphonesimulator is automatically added when ios is specified
  --bundle=*          Comma separated (without spaces) list of bundles to build
                      Valid bundles: ${VALID_TYPES[*]}
  --license=*         Comma separated (without spaces) list of licenses to build
                      Valid licenses: ${VALID_LICENSES[*]}
  --small             Build with small flags (reduces binary size).
  --not-small         Build without small flag.
  --both              Build both small and full versions (default)
  --reset             Reset build state and start from beginning
  --remote            Publish release asset to remote repository
  --local             Build locally instead of using remote releases
                      Note: Not including one of below flags will create all of artifacts: framework, bundle, and release
                      Do not specify if you want to create all artifacts.
  --create-framework  Create framework from built libraries, excludes creating bundle and release
  --create-bundle     Create bundle from built libraries, excludes creating framework and release
  --create-release    Create release from built libraries, excludes creating bundle and framework
  --help              Show this help message
"
```

### Build Apple XCFramework

```bash
# add optional --platform=<PLATFORM> if you want to build for specific platform otherwise it will build for all platforms
# Build locally instead of using remote releases
sudo ./scripts/apple/build_xcframework.sh --local

# Publish release asset to remote repository
sudo ./scripts/apple/build_xcframework.sh --remote
```
