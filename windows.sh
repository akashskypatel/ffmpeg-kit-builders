#!/usr/bin/env bash
# ffmpeg windows cross compile helper/download script, see github repo README
# Copyright (C) 2012 Roger Pack, the script is under the GPLv3, but output FFmpeg's executables aren't
# set -x

source "$(pwd)/scripts/variable.sh"

# If --get-total-steps is passed, just print the size of the array and exit.
if [[ "$1" == "--get-total-steps" ]]; then
  echo ${#BUILD_STEPS[@]}
  exit 0
fi

# If --get-step-name is passed, print the name at that index and exit.
if [[ "$1" == --get-step-name=* ]]; then
  index="${1#*=}"
  echo "${BUILD_STEPS[$index]}"
  exit 0
fi

# parse command line parameters, if any
while true; do
  case $1 in
    -h | --help ) echo "available option=default_value:
      --build-ffmpeg-static=y  (ffmpeg.exe, ffplay.exe and ffprobe.exe)
      --build-ffmpeg-shared=n  (ffmpeg.exe (with libavformat-x.dll, etc., ffplay.exe, ffprobe.exe and dll-files)
      --ffmpeg-git-checkout-version=[master] if you want to build a particular version of FFmpeg, ex: n3.1.1 or a specific git hash
      --ffmpeg-git-checkout=[https://github.com/FFmpeg/FFmpeg.git] if you want to clone FFmpeg from other repositories
      --ffmpeg-source-dir=[default empty] specifiy the directory of ffmpeg source code. When specified, git will not be used.
      --x265-git-checkout-version=[master] if you want to build a particular version of x265, ex: --x265-git-checkout-version=Release_3.2 or a specific git hash
      --fdk-aac-git-checkout-version= if you want to build a particular version of fdk-aac, ex: --fdk-aac-git-checkout-version=v2.0.1 or another tag
      --gcc-cpu-count=[cpu_cores_on_box if RAM > 1GB else 1] number of cpu cores this speeds up initial cross compiler build.
      --build-cpu-count=[cpu_cores_on_box] set to lower than your cpu cores if the background processes eating all your cpu bugs your desktop usage
      --disable-nonfree=y (set to n to include nonfree like libfdk-aac,decklink)
      --build-intel-qsv=y (set to y to include the [non windows xp compat.] qsv library and ffmpeg module. NB this not not hevc_qsv...
      --sandbox-ok=n [skip sandbox prompt if y]
      -d [meaning \"defaults\" skip all prompts, just build ffmpeg static 64 bit with some defaults for speed like no git updates]
      --build-libmxf=n [builds libMXF, libMXF++, writeavidmxfi.exe and writeaviddv50.exe from the BBC-Ingex project]
      --build-mp4box=n [builds MP4Box.exe from the gpac project]
      --build-mplayer=n [builds mplayer.exe and mencoder.exe]
      --build-vlc=n [builds a [rather bloated] vlc.exe]
      --build-lsw=n [builds L-Smash Works VapourSynth and AviUtl plugins]
      --build-ismindex=n [builds ffmpeg utility ismindex.exe]
      -a 'build all' builds ffmpeg, mplayer, vlc, etc. with all fixings turned on [many disabled from disuse these days]
      --build-svt-hevc=n [builds libsvt-hevc modules within ffmpeg etc.]
      --build-svt-vp9=n [builds libsvt-hevc modules within ffmpeg etc.]
      --build-dvbtee=n [build dvbtee.exe a DVB profiler]
      --compiler-flavors=[multi,win32,win64,native] [default prompt, or skip if you already have one built, multi is both win32 and win64]
      --cflags=[default is $original_cflags, which works on any cpu, see README for options]
      --git-get-latest=y [do a git pull for latest code from repositories like FFmpeg--can force a rebuild if changes are detected]
      --build-x264-with-libav=n build x264.exe with bundled/included "libav" ffmpeg libraries within it
      --prefer-stable=y build a few libraries from releases instead of git master
      --debug Make this script  print out each line as it executes
      --enable-gpl=[y] set to n to do an lgpl build
      --build-dependencies=y [builds the ffmpeg dependencies. Disable it when the dependencies was built once and can greatly reduce build time. ]
      --build-dependencies-only=n Only build dependency binaries. Will not build app binaries.
       "; exit 0 ;;
    --sandbox-ok=* ) sandbox_ok="${1#*=}"; shift ;;
    --gcc-cpu-count=* ) gcc_cpu_count="${1#*=}"; shift ;;
    --build-cpu-count=* ) cpu_count="${1#*=}"; shift ;;
    --ffmpeg-git-checkout-version=* ) ffmpeg_git_checkout_version="${1#*=}"; shift ;;
    --ffmpeg-git-checkout=* ) ffmpeg_git_checkout="${1#*=}"; shift ;;
    --ffmpeg-source-dir=* ) ffmpeg_source_dir="${1#*=}"; shift ;;
    --x265-git-checkout-version=* ) x265_git_checkout_version="${1#*=}"; shift ;;
    --fdk-aac-git-checkout-version=* ) fdk_aac_git_checkout_version="${1#*=}"; shift ;;
    --build-libmxf=* ) build_libmxf="${1#*=}"; shift ;;
    --build-mp4box=* ) build_mp4box="${1#*=}"; shift ;;
    --build-ismindex=* ) build_ismindex="${1#*=}"; shift ;;
    --git-get-latest=* ) git_get_latest="${1#*=}"; shift ;;
    --build-amd-amf=* ) build_amd_amf="${1#*=}"; shift ;;
    --build-intel-qsv=* ) build_intel_qsv="${1#*=}"; shift ;;
    --build-x264-with-libav=* ) build_x264_with_libav="${1#*=}"; shift ;;
    --build-mplayer=* ) build_mplayer="${1#*=}"; shift ;;
    --cflags=* )
       original_cflags="${1#*=}"; echo "setting cflags as $original_cflags"; shift ;;
    --build-vlc=* ) build_vlc="${1#*=}"; shift ;;
    --build-lsw=* ) build_lsw="${1#*=}"; shift ;;
    --build-dvbtee=* ) build_dvbtee="${1#*=}"; shift ;;
    --disable-nonfree=* ) disable_nonfree="${1#*=}"; shift ;;
    # this doesn't actually "build all", like doesn't build 10 high-bit LGPL ffmpeg, but it does exercise the "non default" type build options...
    -a | --a        ) compiler_flavors="multi"; build_mplayer=n; build_libmxf=y; build_mp4box=n; build_vlc=y; build_lsw=n;
                 build_ffmpeg_static=y; build_ffmpeg_shared=y; disable_nonfree=n; git_get_latest=y;
                 sandbox_ok=y; build_amd_amf=y; build_intel_qsv=y; build_dvbtee=y; build_x264_with_libav=y; shift ;;
    --build-svt-hevc=* ) build_svt_hevc="${1#*=}"; shift ;;
    --build-svt-vp9=* ) build_svt_vp9="${1#*=}"; shift ;;
    -d | --d        ) echo "defaults: doing 64 bit only, fast"; gcc_cpu_count=$cpu_count; disable_nonfree="y"; sandbox_ok="y"; compiler_flavors="win64"; git_get_latest="n"; shift ;;
    --compiler-flavors=* )
         compiler_flavors="${1#*=}";
         if [[ $compiler_flavors == "native" && $OSTYPE == darwin* ]]; then
           build_intel_qsv=n
           echo "disabling qsv since os x"
         fi
         shift ;;
    --build-ffmpeg-static=* ) build_ffmpeg_static="${1#*=}"; shift ;;
    --build-ffmpeg-shared=* ) build_ffmpeg_shared="${1#*=}"; shift ;;
    --prefer-stable=* ) prefer_stable="${1#*=}"; shift ;;
    --enable-gpl=* ) enable_gpl="${1#*=}"; shift ;;
    --build-dependencies=* ) build_dependencies="${1#*=}"; shift ;;
    --build-only-index=*) build_only_index="${1#*=}"; shift ;;
    --get-total-steps|--get-step-name=*) shift ;; # Handled above, just consume and ignore here
    --build-dependencies-only=*) build_dependencies_only="${1#*=}"; shift ;;
    --debug ) set -x; shift ;;
    -- ) shift; break ;;
    -* ) echo "Error, unknown option: '$1'."; exit 1 ;;
    * ) break ;;
  esac
done

source "$(pwd)/scripts/main-windows.sh"