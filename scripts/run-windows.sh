#!/bin/bash

source "$(pwd)/scripts/variable.sh"
source "$(pwd)/scripts/function.sh"

reset_cflags # also overrides any "native" CFLAGS, which we may need if there are some 'linux only' settings in there
reset_cppflags # Ensure CPPFLAGS are cleared and set to what is configured
check_missing_packages # do this first since it's annoying to go through prompts then be rejected
intro # remember to always run the intro, since it adjust pwd
install_cross_compiler

if [[ -n "$build_only_index" ]]; then
  # Setup the environment based on the globally set compiler_flavors
  setup_build_environment "$compiler_flavors"
  
  # Now, call the single requested build function by its index
  step_name="${BUILD_STEPS[$build_only_index]}"
  echo "--- Executing single build step: $step_name ---"
  build_ffmpeg_dependencies_only "$step_name"

else

  if [[ $OSTYPE == darwin* ]]; then
    # mac add some helper scripts
    mkdir -p mac_helper_scripts
    cd mac_helper_scripts || exit
      if [[ ! -x readlink ]]; then
        # make some scripts behave like linux...
        curl -4 file://"$patch_dir"/md5sum.mac --fail > md5sum  || exit 1
        chmod u+x ./md5sum
        curl -4 file://"$patch_dir"/readlink.mac --fail > readlink  || exit 1
        chmod u+x ./readlink
      fi
      export PATH=$(pwd):$PATH
    cd ..
  fi

  if [[ $compiler_flavors == "native" ]]; then
    echo "starting native build..."
    # realpath so if you run it from a different symlink path it doesn't rebuild the world...
    # mkdir required for realpath first time
    mkdir -p "$cur_dir"/cross_compilers/native
    mkdir -p "$cur_dir"/cross_compilers/native/bin
    mingw_w64_x86_64_prefix="$(realpath "$cur_dir"/cross_compilers/native)"
    mingw_bin_path="$(realpath "$cur_dir"/cross_compilers/native/bin)" # sdl needs somewhere to drop "binaries"??
    export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
    export PATH="$mingw_bin_path:$original_path"
    make_prefix_options="PREFIX=$mingw_w64_x86_64_prefix"
    if [[ $(uname -m) =~ 'i686' ]]; then
      bits_target=32
    else
      bits_target=64
    fi
    #  bs2b doesn't use pkg-config, sndfile needed Carbon :|
    export CPATH=$cur_dir/cross_compilers/native/include:/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Headers # C_INCLUDE_PATH
    export LIBRARY_PATH=$cur_dir/cross_compilers/native/lib
    work_dir="$(realpath "$cur_dir"/native)"
    mkdir -p "$work_dir"
    cd "$work_dir" || exit
      if [[ $build_dependencies_only == "y" ]]; then
        build_ffmpeg_dependencies
      else
        build_ffmpeg_dependencies
        build_ffmpeg
      fi
    cd ..
  fi

  if [[ $compiler_flavors == "multi" || $compiler_flavors == "win32" ]]; then
    echo
    echo "Starting 32-bit builds..."
    host_target='i686-w64-mingw32'
    mkdir -p "$cur_dir"/cross_compilers/mingw-w64-i686/$host_target
    mingw_w64_x86_64_prefix="$(realpath "$cur_dir"/cross_compilers/mingw-w64-i686/$host_target)"
    mkdir -p "$cur_dir"/cross_compilers/mingw-w64-i686/bin
    mingw_bin_path="$(realpath "$cur_dir"/cross_compilers/mingw-w64-i686/bin)"
    export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
    export PATH="$mingw_bin_path:$original_path"
    bits_target=32
    cross_prefix="$mingw_bin_path/i686-w64-mingw32-"
    make_prefix_options="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$mingw_w64_x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++"
    work_dir="$(realpath "$cur_dir"/win32)"
    mkdir -p "$work_dir"
    cd "$work_dir" || exit
      if [[ $build_dependencies_only == "y" ]]; then
        build_ffmpeg_dependencies
      else
        build_ffmpeg_dependencies
        build_ffmpeg
      fi
    cd ..
  fi

  if [[ $compiler_flavors == "multi" || $compiler_flavors == "win64" ]]; then
    echo
    echo "**************Starting 64-bit builds..." # make it have a bit easier to you can see when 32 bit is done
    host_target='x86_64-w64-mingw32'
    mkdir -p "$cur_dir"/cross_compilers/mingw-w64-x86_64/$host_target
    mingw_w64_x86_64_prefix="$(realpath "$cur_dir"/cross_compilers/mingw-w64-x86_64/$host_target)"
    mkdir -p "$cur_dir"/cross_compilers/mingw-w64-x86_64/bin
    mingw_bin_path="$(realpath "$cur_dir"/cross_compilers/mingw-w64-x86_64/bin)"
    export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
    export PATH="$mingw_bin_path:$original_path"
    bits_target=64
    cross_prefix="$mingw_bin_path/x86_64-w64-mingw32-"
    make_prefix_options="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$mingw_w64_x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++"
    work_dir="$(realpath "$cur_dir"/win64)"
    mkdir -p "$work_dir"
    cd "$work_dir" || exit
      if [[ $build_dependencies_only == "y" ]]; then
        build_ffmpeg_dependencies
      else
        build_ffmpeg_dependencies
        build_ffmpeg
      fi
    cd ..
  fi

  if [[ $build_dependencies_only == "n" ]]; then
    echo "searching for all local exe's (some may not have been built this round, NB)..."
    for file in $(find_all_build_exes); do
      echo "built $file"
    done
  fi
fi