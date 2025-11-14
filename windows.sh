#!/usr/bin/env bash

# ffmpeg windows cross compile helper/download script, see github repo README
# Copyright (C) 2012 Roger Pack, the script is under the GPLv3, but output FFmpeg's executables aren't
# set -x

export BASEDIR="$(pwd)"
export FFMPEG_KIT_BUILD_TYPE="windows"
export SCRIPTDIR="${BASEDIR}/scripts"
export LOG_FILE="${BASEDIR}/build.log"
source "${SCRIPTDIR}/variable.sh"
source "${SCRIPTDIR}/function.sh"

chown -R "$USER":"$USER" "$LOG_FILE"

remove_path -f "$LOG_FILE"

echo -e "INFO: Build options: $*\n" 1>> $LOG_FILE 2>&1

# If --get-total-steps is passed, just print the size of the array and exit.
if [[ "$1" == "--get-total-steps" ]]; then
  echo -e ${#BUILD_STEPS[@]}
  exit 0
fi

# If --get-step-name is passed, print the name at that index and exit.
if [[ "$1" == --get-step-name=* ]]; then
  index="${1#*=}"
  echo -e "${BUILD_STEPS[$index]}"
  exit 0
fi

# parse command line parameters, if any
#      -v, --version\t\t\tdisplay version information and exit
while true; do
  case $1 in
    -h | --help ) echo -e "available option=default_value:
      Options:
      -h, --help\t\t\tdisplay this help and exit
      -d, --debug\t\t\tbuild with debug information
      -s, --speed\t\t\toptimize for speed instead of size
      -f, --force\t\t\tignore warnings
      Licensing options:
      --enable-gpl\t\t\tallow building GPL libraries, created libs will be licensed under the GPLv3.0 [no]\n
      --ffmpeg-git-checkout-version=[master] if you want to build a particular version of FFmpeg, ex: n3.1.1 or a specific git hash
      --ffmpeg-git-checkout=[https://github.com/FFmpeg/FFmpeg.git] if you want to clone FFmpeg from other repositories
      --ffmpeg-source-dir=[default empty] specifiy the directory of ffmpeg source code. When specified, git will not be used.
      --compiler-flavors=[multi,win32,win64,native] [default prompt, or skip if you already have one built, multi is both win32 and win64]
      --cflags=[default is $original_cflags, which works on any cpu, see README for options]
      --git-get-latest=y [do a git pull for latest code from repositories like FFmpeg--can force a rebuild if changes are detected]
      --prefer-stable=y build a few libraries from releases instead of git master
      --enable-static
      --debug Make this script  print out each line as it executes
      --enable-gpl=[y] set to n to do an lgpl build
      --get-total-steps|--get-step-name= get dependency steps and step name by index
      --build-only-index={0..} build only specific dependency
      --build-dependencies=y [builds the ffmpeg dependencies. Disable it when the dependencies was built once and can greatly reduce build time. ]
      --build-dependencies-only=n Only build dependency binaries. Will not build app binaries.
      --build-ffmpeg-only=n
      --build-ffmpeg-kit-only=n
      --flavor win32, win64 or native
       "; 
      DISPLAY_HELP="1"
       exit 0 ;;
#    -v | --version) display_version; shift ;;
    -d | --debug ) enable_debug; set -x; shift ;;
    -s | --speed) optimize_for_speed; shift ;;
    -l | --lts) shift ;;
    -f | --force) export BUILD_FORCE="1"; shift ;;
    --no-output-redirection) no_output_redirection; shift ;;
    --no-workspace-cleanup-*)
      export NO_WORKSPACE_CLEANUP_LIBRARY=$(echo -e $1 | sed -e 's/^--[A-Za-z]*-[A-Za-z]*-[A-Za-z]*-//g')
      no_workspace_cleanup_library "${NO_WORKSPACE_CLEANUP_LIBRARY}"; shift ;;
    --no-link-time-optimization) no_link_time_optimization; shift ;;
    --ffmpeg-git-checkout-version=* ) export ffmpeg_git_checkout_version="${1#*=}"; shift ;;
    --ffmpeg-git-checkout=* ) export ffmpeg_git_checkout="${1#*=}"; shift ;;
    --ffmpeg-source-dir=* ) export ffmpeg_source_dir="${1#*=}"; shift ;;
    --cflags=* ) export original_cflags="${1#*=}"; echo -e "setting cflags as $original_cflags"; shift ;;
    --git-get-latest=* ) export git_get_latest="${1#*=}"; shift ;;
    --prefer-stable=* ) export prefer_stable="${1#*=}"; shift ;;
    --enable-gpl=*) export GPL_ENABLED="${1#*=}"; shift ;;
    --build-dependencies=* ) export build_dependencies="${1#*=}"; shift ;;
    --build-only-index=*) export build_only_index="${1#*=}"; shift ;;
    --get-total-steps|--get-step-name=*) shift ;; # Handled above, just consume and ignore here
    --build-dependencies-only=*) export build_dependencies_only="${1#*=}"; shift ;;
    --build-ffmpeg-only=*) export build_ffmpeg_only="${1#*=}"; shift ;;
    --build-ffmpeg-kit-only=*) export build_ffmpeg_kit_only="${1#*=}"; shift ;;
    --flavor=*) export compiler_flavors="${1#*=}"; shift ;;
    --enable-static) export build_ffmpeg_static=y; export build_ffmpeg_shared=n; shift ;;
    -- ) shift; break ;;
    -* ) echo -e "Error, unknown option: '$1'."; exit 1 ;;
    * ) break ;;
  esac
done

source "${SCRIPTDIR}/main-windows.sh"