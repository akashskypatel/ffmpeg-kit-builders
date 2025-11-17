#!/bin/bash

#echo -e "${SCRIPTDIR}/variable.sh"
#echo -e "${SCRIPTDIR}/function.sh"

source "${SCRIPTDIR}/function.sh"

find_all_build_exes() {
  local found=""
# NB that we're currently in the prebuilt dir...
  for file in $(find . -name ffmpeg.exe) $(find . -name ffmpeg_g.exe) $(find . -name ffplay.exe) $(find . -name ffmpeg) $(find . -name ffplay) $(find . -name ffprobe) $(find . -name MP4Box.exe) $(find . -name mplayer.exe) $(find . -name mencoder.exe) $(find . -name avconv.exe) $(find . -name avprobe.exe) $(find . -name x264.exe) $(find . -name writeavidmxf.exe) $(find . -name writeaviddv50.exe) $(find . -name rtmpdump.exe) $(find . -name x265.exe) $(find . -name ismindex.exe) $(find . -name dvbtee.exe) $(find . -name boxdumper.exe) $(find . -name muxer.exe ) $(find . -name remuxer.exe) $(find . -name timelineeditor.exe) $(find . -name lwcolor.auc) $(find . -name lwdumper.auf) $(find . -name lwinput.aui) $(find . -name lwmuxer.auf) $(find . -name vslsmashsource.dll); do
    found="$found $(readlink -f "$file")"
  done

  # bash recursive glob fails here again?
  for file in $(find . -name vlc.exe | grep -- -); do
    found="$found $(readlink -f "$file")"
  done
  echo -e "$found" # pseudo return value...
}

check_audiotoolbox() {
  # if [[ "$non_free" = "y" ]]; then
  #   build_fdk-aac # Uses dlfcn.
	# if [[ $OSTYPE != darwin* ]]; then
  #     build_AudioToolboxWrapper # This wrapper library enables FFmpeg to use AudioToolbox codecs on Windows, with DLLs shipped with iTunes.
	# fi
  if [[ $compiler_flavors != "native" ]]; then
    build_libdecklink # Error finding rpc.h in native builds even if it's available
  fi
  #fi
}

build_all_ffmpeg_dependencies() {
  echo -e "INFO: Building dependencies..."
  # Create a clean array without empty elements
  local steps=${#BUILD_STEPS[@]}
  local current_step=0
  
  for step_name in "${BUILD_STEPS[@]}"; do
    if [[ -z "${step_name// }" ]]; then
      continue
    fi
    ((current_step++))
    percent=$(( current_step * 100 / steps ))
    bars=$((percent * 40 / 100))
    
    bar_str=""
    for((j=0;j<bars;j++)); do bar_str="${bar_str}█"; done
    for((j=bars;j<40;j++)); do bar_str="${bar_str} "; done
    
    printf "\r\033[K[%s] %3d%% (%2d/%2d) | %s" "$bar_str" $percent $current_step $steps "$step_name"
    
    build_ffmpeg_dependency_only "$step_name" 1>>"$LOG_FILE" 2>&1
  done
  printf "\r\033[KAll dependencies built successfully!\n"
}

build_ffmpeg_dependency_only() {
  step=$1
  if [[ -n "$step" ]]; then
    if declare -F "$step" > /dev/null; then
      echo -e "Executing step: $step"
      "$step"  # Execute the function
    else
      echo -e "Error: Function '$step' not found."
      return 1  # Indicate an error
    fi
  else
    echo -e "Error: Step argument is missing."
    return 1  # Indicate an error
  fi
}

build_apps() {
  if [[ $build_dvbtee = "y" ]]; then
    build_dvbtee_app
  fi
  # now the things that use the dependencies...
  if [[ $build_libmxf = "y" ]]; then
    build_libMXF
  fi
  if [[ $build_mp4box = "y" ]]; then
    build_mp4box
  fi
  if [[ $build_mplayer = "y" ]]; then
    build_mplayer
  fi
  if [[ $build_ffmpeg_static = "y" ]]; then
    build_ffmpeg static
  fi
  if [[ $build_ffmpeg_shared = "y" ]]; then
    build_ffmpeg shared
  fi
  if [[ $build_vlc = "y" ]]; then
    build_vlc
  fi
  if [[ $build_lsw = "y" ]]; then
    build_lsw
  fi
}

# This new function centralizes the setup for each build target.
setup_build_environment() {
  local flavor="$1"
  echo -e
  echo -e "************** Setting up environment for $flavor build... **************"
  if [[ $flavor == "win32" ]]; then
    export ARCH=$(get_arch_name $(from_arch_name $flavor))
    export FULL_ARCH="i686"
    export work_dir="$(realpath "$WORKDIR"/"$FFMPEG_KIT_BUILD_TYPE"-"$FULL_ARCH")"
    export host_target='i686-w64-mingw32'
    export mingw_w64_x86_64_prefix="$(realpath $work_dir/cross_compilers/mingw-w64-i686/$host_target)"
    export mingw_bin_path="$(realpath $work_dir/cross_compilers/mingw-w64-i686/bin)"
    export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
    export PATH="$mingw_bin_path:$original_path"
    export bits_target=32
    export cross_prefix="$mingw_bin_path/i686-w64-mingw32-"
    export compiler_flags="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$mingw_w64_x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++"
    export make_prefix_options="--cc=${cross_prefix}gcc \
--ar=$(realpath ${cross_prefix}ar) \
--as=$(realpath ${cross_prefix}as) \
--nm=$(realpath ${cross_prefix}nm) \
--ranlib=$(realpath ${cross_prefix}ranlib) \
--ld=$(realpath ${cross_prefix}ld) \
--strip=$(realpath ${cross_prefix}strip) \
--cxx=$(realpath ${cross_prefix}g++)"
  elif [[ $flavor == "win64" ]]; then
    export ARCH=$(get_arch_name $(from_arch_name $flavor))
    export FULL_ARCH="x86_64"
    export work_dir="$(realpath "$WORKDIR"/"$FFMPEG_KIT_BUILD_TYPE"-"$FULL_ARCH")"
    export host_target='x86_64-w64-mingw32'
    export mingw_w64_x86_64_prefix="$(realpath $work_dir/cross_compilers/mingw-w64-x86_64/$host_target)"
    export mingw_bin_path="$(realpath $work_dir/cross_compilers/mingw-w64-x86_64/bin)"
    export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
    export PATH="$mingw_bin_path:$original_path"
    export bits_target=64
    export cross_prefix="$mingw_bin_path/x86_64-w64-mingw32-"
    export compiler_flags="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$mingw_w64_x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++"
    export make_prefix_options="--cc=${cross_prefix}gcc \
--ar=$(realpath ${cross_prefix}ar) \
--as=$(realpath ${cross_prefix}as) \
--nm=$(realpath ${cross_prefix}nm) \
--ranlib=$(realpath ${cross_prefix}ranlib) \
--ld=$(realpath ${cross_prefix}ld) \
--strip=$(realpath ${cross_prefix}strip) \
--cxx=$(realpath ${cross_prefix}g++)"
    export LIB_INSTALL_BASE=$work_dir
  else
    echo -e "Error: Unknown compiler flavor '$flavor'"
    exit 1
  fi
  export src_dir="${work_dir}/src"
  export LIB_INSTALL_BASE="$work_dir"
  export INSTALL_PKG_CONFIG_DIR="${work_dir}/pkgconfig"
  export ffmpeg_source_dir="${work_dir}/ffmpeg"
  export install_prefix="$ffmpeg_source_dir/build_$(get_build_type)" # install them to their a separate dir
  export ffmpeg_kit_install="${work_dir}/ffmpeg-kit_$(get_build_type)"
  export ffmpeg_kit_bundle="${work_dir}/$(get_bundle_directory)"
  create_dir "$work_dir"
  change_dir "$work_dir" || exit
}

get_arch_specific_ldflags() {
  case ${ARCH} in
  x86-64)
    echo -e "-march=x86-64 -Wl,-z,text"
    ;;
  esac
}

get_size_optimization_ldflags() {
  if [[ -z ${NO_LINK_TIME_OPTIMIZATION} ]]; then
    local LINK_TIME_OPTIMIZATION_FLAGS="-flto"
  else
    local LINK_TIME_OPTIMIZATION_FLAGS=""
  fi

  case ${ARCH} in
  x86-64)
    case $1 in
    ffmpeg)
      echo -e "${LINK_TIME_OPTIMIZATION_FLAGS} -O2 -ffunction-sections -fdata-sections -finline-functions"
      ;;
    *)
      echo -e "-Os -ffunction-sections -fdata-sections"
      ;;
    esac
    ;;
  esac
}

get_common_linked_libraries() {
  local COMMON_LIBRARIES=""

  case $1 in
  chromaprint | ffmpeg-kit | kvazaar | srt | zimg)
    echo -e "-stdlib=libstdc++ -lstdc++ -lc -lm ${COMMON_LIBRARIES}"
    ;;
  *)
    echo -e "-lc -lm -ldl ${COMMON_LIBRARIES}"
    ;;
  esac
}

get_ldflags() {
  local ARCH_FLAGS=$(get_arch_specific_ldflags)
  if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
    local OPTIMIZATION_FLAGS="$(get_size_optimization_ldflags "$1")"
  else
    local OPTIMIZATION_FLAGS="${FFMPEG_KIT_DEBUG}"
  fi
  local COMMON_LINKED_LIBS=$(get_common_linked_libraries "$1")

  echo -e "${ARCH_FLAGS} ${OPTIMIZATION_FLAGS} ${COMMON_LINKED_LIBS} ${LLVM_CONFIG_LDFLAGS} -Wl,--hash-style=both -fuse-ld=lld"
}

get_cxxflags() {
  if [[ -z ${NO_LINK_TIME_OPTIMIZATION} ]]; then
    local LINK_TIME_OPTIMIZATION_FLAGS="-flto"
  else
    local LINK_TIME_OPTIMIZATION_FLAGS=""
  fi

  if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
    local OPTIMIZATION_FLAGS="-Os -ffunction-sections -fdata-sections"
  else
    local OPTIMIZATION_FLAGS="${FFMPEG_KIT_DEBUG}"
  fi

  local BUILD_DATE="-DFFMPEG_KIT_BUILD_DATE=$(date +%Y%m%d 2>>$LOG_FILE)"
  local COMMON_FLAGS="-stdlib=libstdc++ -std=c++11 ${OPTIMIZATION_FLAGS} ${BUILD_DATE} $(get_arch_specific_cflags)"

  case $1 in
  ffmpeg)
    if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
      echo -e "${LINK_TIME_OPTIMIZATION_FLAGS} -stdlib=libstdc++ -std=c++11 -O2 -ffunction-sections -fdata-sections"
    else
      echo -e "${FFMPEG_KIT_DEBUG} -stdlib=libstdc++ -std=c++11"
    fi
    ;;
  ffmpeg-kit)
    echo -e "${COMMON_FLAGS}"
    ;;
  srt | tesseract | zimg)
    echo -e "${COMMON_FLAGS} -fcxx-exceptions -fPIC"
    ;;
  *)
    echo -e "${COMMON_FLAGS} -fno-exceptions -fno-rtti"
    ;;
  esac
}

get_common_includes() {
  echo -e "-I${LLVM_CONFIG_INCLUDEDIR:-.}"
}

get_size_optimization_cflags() {
  if [[ -z ${NO_LINK_TIME_OPTIMIZATION} ]]; then
    local LINK_TIME_OPTIMIZATION_FLAGS="-flto"
  else
    local LINK_TIME_OPTIMIZATION_FLAGS=""
  fi

  local ARCH_OPTIMIZATION=""
  case ${ARCH} in
  x86-64 | x86_64)
    case $1 in
    ffmpeg)
      ARCH_OPTIMIZATION="${LINK_TIME_OPTIMIZATION_FLAGS} -Os -ffunction-sections -fdata-sections"
      ;;
    *)
      ARCH_OPTIMIZATION="-Os -ffunction-sections -fdata-sections"
      ;;
    esac
    ;;
  esac

  local LIB_OPTIMIZATION=""

  echo -e "${ARCH_OPTIMIZATION} ${LIB_OPTIMIZATION}"
}

get_common_cflags() {
  if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
    local LTS_BUILD_FLAG="-DFFMPEG_KIT_LTS "
  fi

  echo -e "-fstrict-aliasing -fPIC -DWINDOWS ${LTS_BUILD_FLAG} ${LLVM_CONFIG_CFLAGS}"
}

get_app_specific_cflags() {
  local APP_FLAGS=""
  case $1 in
  ffmpeg)
    APP_FLAGS="-Wno-unused-function"
    ;;
  ffmpeg-kit)
    APP_FLAGS="-Wno-unused-function -Wno-pointer-sign -Wno-switch -Wno-deprecated-declarations"
    ;;
  kvazaar)
    APP_FLAGS="-std=gnu99 -Wno-unused-function"
    ;;
  openh264)
    APP_FLAGS="-std=gnu99 -Wno-unused-function -fstack-protector-all"
    ;;
  srt)
    APP_FLAGS="-Wno-unused-function"
    ;;
  *)
    APP_FLAGS="-std=c99 -Wno-unused-function"
    ;;
  esac

  echo -e "${APP_FLAGS}"
}

get_arch_specific_cflags() {
  case ${ARCH} in
  x86-64 | x86_64)
    echo -e "-target $(get_target) -DFFMPEG_KIT_X86_64"
    ;;
  esac
}

get_cflags() {
  local ARCH_FLAGS=$(get_arch_specific_cflags)
  local APP_FLAGS=$(get_app_specific_cflags "$1")
  local COMMON_FLAGS=$(get_common_cflags)
  if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
    local OPTIMIZATION_FLAGS=$(get_size_optimization_cflags "$1")
  else
    local OPTIMIZATION_FLAGS="${FFMPEG_KIT_DEBUG}"
  fi
  local COMMON_INCLUDES=$(get_common_includes)

  echo -e "${ARCH_FLAGS} ${APP_FLAGS} ${COMMON_FLAGS} ${OPTIMIZATION_FLAGS} ${COMMON_INCLUDES}"
}

get_target_cpu() {
  case ${ARCH} in
  i686 | x86 | win32)
    echo -e "i686" 
    ;;
  x86-64 | x86_64 | win64)
    echo -e "x86_64"
    ;;
  esac
}

get_build_directory() {
  local LTS_POSTFIX=""
  if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
    LTS_POSTFIX="-lts"
  fi

  echo -e "windows-$(get_target_cpu)${LTS_POSTFIX}"
}

detect_clang_version() {
  if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
    for clang_version in 6 .. 10; do
      if [[ $(command_exists "clang-$clang_version") -eq 0 ]]; then
        echo -e "$clang_version"
        return
      elif [[ $(command_exists "clang-$clang_version.0") -eq 0 ]]; then
        echo -e "$clang_version.0"
        return
      fi
    done
    echo -e "none"
  else
    for clang_version in 11 .. 20; do
      if [[ $(command_exists "clang-$clang_version") -eq 0 ]]; then
        echo -e "$clang_version"
        return
      elif [[ $(command_exists "clang-$clang_version.0") -eq 0 ]]; then
        echo -e "$clang_version.0"
        return
      fi
    done
    echo -e "none"
  fi
}

set_toolchain_paths() {
  export PATH="${PATH}:${mingw_bin_path}:${mingw_w64_x86_64_prefix}/bin"
  export CC="${cross_prefix}gcc"
  export AR="$(realpath "${cross_prefix}ar")"
  export AS="$(realpath "${cross_prefix}as")"
  export NM="$(realpath "${cross_prefix}nm")"
  export RANLIB="$(realpath "${cross_prefix}ranlib")"
  export LD="$(realpath "${cross_prefix}ld")"
  export STRIP="$(realpath "${cross_prefix}strip")"
  export CXX="$(realpath "${cross_prefix}g++")"
}

enable_lts_build() {
  export FFMPEG_KIT_LTS_BUILD="1"
}

install_pkg_config_file() {
  local FILE_NAME="$1"
  local SOURCE="${INSTALL_PKG_CONFIG_DIR}/${FILE_NAME}"
  local DESTINATION="${FFMPEG_KIT_BUNDLE_PKG_CONFIG_DIRECTORY}/${FILE_NAME}"

  # DELETE OLD FILE
  remove_path -rf "$DESTINATION" 2>>$LOG_FILE
  if [[ $? -ne 0 ]]; then
    echo -e "failed\n\nSee $LOG_FILE for details\n"
    exit 1
  fi

  # INSTALL THE NEW FILE
  copy_path "$SOURCE" "$DESTINATION" 2>>$LOG_FILE
  if [[ $? -ne 0 ]]; then
    echo -e "failed\n\nSee $LOG_FILE for details\n"
    exit 1
  fi
  prepare_inline_sed
  # UPDATE PATHS
  ${SED_INLINE} "s|${ffmpeg_kit_install}|${ffmpeg_kit_bundle}|g" "$DESTINATION" 1>>$LOG_FILE 2>&1 || return 1
  ${SED_INLINE} "s|${ffmpeg_source_dir}|${ffmpeg_kit_bundle}|g" "$DESTINATION" 1>>$LOG_FILE 2>&1 || return 1
}

get_ffmpeg_kit_version() {
  local FFMPEG_KIT_VERSION=$(grep -Eo 'FFmpegKitVersion = .*' "${BASEDIR}/windows/src/FFmpegKitConfig.h" 2>>$LOG_FILE | grep -Eo ' \".*' | tr -d '"; ')

  echo -e "${FFMPEG_KIT_VERSION}"
}

build_ffmpeg_kit() {
  echo -e "INFO: Building ffmpeg kit\n" 1>>$LOG_FILE 2>&1
  # BUILD FFMPEG KIT
  
  echo -e "INFO: Done building ffmpeg kit\n" 1>>$LOG_FILE 2>&1
}

download_ffmpeg() {
  local output_dir="$work_dir/ffmpeg"
  local desired_version="$ffmpeg_git_checkout_version"

  if [[ -z $desired_version ]]; then
    desired_version="master"
  fi

  do_git_checkout "$ffmpeg_git_checkout" "$output_dir" "$desired_version" || exit 1
  ffmpeg_source_dir=$output_dir
}

install_cross_compiler() {
  echo -e "INFO: Building (or already built) MinGW-w64 cross-compiler(s)..." | tee -a "$LOG_FILE"
  echo -e `date` | tee -a "$LOG_FILE"
  local win32_gcc="cross_compilers/mingw-w64-i686/bin/i686-w64-mingw32-gcc"
  local win64_gcc="cross_compilers/mingw-w64-x86_64/bin/x86_64-w64-mingw32-gcc"
  if [[ -f $win32_gcc && -f $win64_gcc ]]; then
   echo -e "MinGW-w64 compilers both already installed, not re-installing..." | tee -a "$LOG_FILE"
   if [[ -z $compiler_flavors ]]; then
     echo -e "selecting multi build (both win32 and win64)...since both cross compilers are present assuming you want both..." 1>> $LOG_FILE 2>&1
     compiler_flavors=multi
   fi
   return # early exit they've selected at least some kind by this point...
  fi

  if [[ -z $compiler_flavors ]]; then
    pick_compiler_flavors
  fi
  setup_build_environment "$compiler_flavors"
  create_dir cross_compilers
  change_dir cross_compilers

  unset CFLAGS # don't want these "windows target" settings used the compiler itself since it creates executables to run on the local box (we have a parameter allowing them to set them for the script "all builds" basically)
  # pthreads version to avoid having to use cvs for it
  echo -e "Starting to download and build cross compile version of gcc [requires working internet access] with thread count $gcc_cpu_count..." 1>> $LOG_FILE 2>&1
  echo -e "" 1>> $LOG_FILE 2>&1

  # --disable-shared allows c++ to be distributed at all...which seemed necessary for some random dependency which happens to use/require c++...
  local zeranoe_script_name=mingw-w64-build
  local zeranoe_script_options="--gcc-branch=releases/gcc-14 --mingw-w64-branch=master --binutils-branch=binutils-2_44-branch" # --cached-sources"
  if [[ ($compiler_flavors == "win32" || $compiler_flavors == "multi") && ! -f ../$win32_gcc ]]; then
    echo -e "Building win32 cross compiler..." 1>> $LOG_FILE 2>&1
    download_gcc_build_script $zeranoe_script_name
    if [[ `uname` =~ "5.1" ]]; then # Avoid using secure API functions for compatibility with msvcrt.dll on Windows XP.
      sed -i "s/ --enable-secure-api//" $zeranoe_script_name
    fi
    CFLAGS='-O2 -pipe' CXXFLAGS='-O2 -pipe' nice ./$zeranoe_script_name $zeranoe_script_options i686 || exit 1 # i586 option needs work to implement
    if [[ ! -f ../$win32_gcc ]]; then
      echo -e "Failure building 32 bit gcc? Recommend nuke prebuilt (rm -rf prebuilt) and start over..." 1>> $LOG_FILE 2>&1
      exit 1
    fi
    if [[ ! -f  ../cross_compilers/mingw-w64-i686/i686-w64-mingw32/lib/libmingwex.a ]]; then
      echo -e "failure building mingwex? 32 bit" 1>> $LOG_FILE 2>&1
      exit 1
    fi
  fi
  if [[ ($compiler_flavors == "win64" || $compiler_flavors == "multi") && ! -f ../$win64_gcc ]]; then
    echo -e "Building win64 x86_64 cross compiler..." 1>> $LOG_FILE 2>&1
    download_gcc_build_script $zeranoe_script_name
    CFLAGS='-O3 -pipe' CXXFLAGS='-O3 -pipe' nice ./$zeranoe_script_name $zeranoe_script_options x86_64 || exit 1
    if [[ ! -f ../$win64_gcc ]]; then
      echo -e "Failure building 64 bit gcc? Recommend nuke prebuilt (rm -rf prebuilt) and start over..." 1>> $LOG_FILE 2>&1
      exit 1
    fi
    if [[ ! -f  ../cross_compilers/mingw-w64-x86_64/x86_64-w64-mingw32/lib/libmingwex.a ]]; then
      echo -e "failure building mingwex? 64 bit" 1>> $LOG_FILE 2>&1
      exit 1
    fi
  fi

  # rm -f build.log # leave resultant build log...sometimes useful...
  reset_cflags
  change_dir ..
  echo -e "INFO: Done building (or already built) MinGW-w64 cross-compiler(s) successfully..."  | tee -a "$LOG_FILE"
  echo -e `date` | tee -a "$LOG_FILE" # so they can see how long it took :)
}

check_builds() {
  shared_build_exists=0
  static_build_exists=0

  # Check shared build
  echo -e "DEBUG: Checking $ffmpeg_source_dir/build_$(get_build_type)"
  if [[ -d "${ffmpeg_source_dir}/build_$(get_build_type)" && -d "${ffmpeg_source_dir}/build_$(get_build_type)/bin" ]]; then
    echo -e "DEBUG: Checking binaries in $ffmpeg_source_dir/build_$(get_build_type)/bin"
    check_binaries=0
    if find "${ffmpeg_source_dir}/build_$(get_build_type)/bin" -maxdepth 1 -type f \( -name '*.a' -o -name '*.dll' -o -name '*.so' -o -name '*.dylib' -o -name '*.lib' -o -name '*.exe' \) -print -quit | grep -q .; then
      check_binaries=1
    fi
    [[ $check_binaries -eq 1 ]] && shared_build_exists=1
  fi
  echo -e "DEBUG: Checking $ffmpeg_source_dir/build_$(get_build_type)"
  # Check static build  
  if [[ -d "${ffmpeg_source_dir}/build_$(get_build_type)" && -d "${ffmpeg_source_dir}/build_$(get_build_type)/bin" ]]; then
    echo -e "DEBUG: Checking binaries in $ffmpeg_source_dir/build_$(get_build_type)/bin"
    check_binaries=0
    if find "${ffmpeg_source_dir}/build_$(get_build_type)/bin" -maxdepth 1 -type f \( -name '*.a' -o -name '*.dll' -o -name '*.so' -o -name '*.dylib' -o -name '*.lib' -o -name '*.exe' \) -print -quit | grep -q .; then
      check_binaries=1
    fi
    [[ $check_binaries -eq 1 ]] && static_build_exists=1
  fi
  
  echo -e "INFO: Checking if build already exists..." | tee -a "$LOG_FILE"

  if [[ ${build_ffmpeg_static,,} =~ ^(y|yes|1|true|on)$ ]]; then
    echo -e "INFO: Static build requested..." | tee -a "$LOG_FILE"
    if [[ $static_build_exists == 0 || "$BUILD_FORCE" -eq 1 ]]; then
      echo -e "INFO: Static build does not exist or force requested. (Re-)configuring Ffmpeg for static build." | tee -a "$LOG_FILE"
      remove_path -rf "${ffmpeg_source_dir}/build_$(get_build_type)" 1>> $LOG_FILE 2>&1
      remove_path -f ${ffmpeg_source_dir}/already_* 1>> $LOG_FILE 2>&1
      configure_ffmpeg 1>> $LOG_FILE 2>&1
    fi
  elif [[ ${build_ffmpeg_shared,,} =~ ^(y|yes|1|true|on)$ ]]; then
    echo -e "INFO: Shared build requested..." | tee -a "$LOG_FILE"
    if [[ $shared_build_exists == 0 || "$BUILD_FORCE" -eq 1 ]]; then
      echo -e "INFO: Shared build does not exist or force requested. (Re-)configuring Ffmpeg for shared build." | tee -a "$LOG_FILE"
      remove_path -rf "${ffmpeg_source_dir}/build_$(get_build_type)" 1>> $LOG_FILE 2>&1
      remove_path -f ${ffmpeg_source_dir}/already_* 1>> $LOG_FILE 2>&1
      configure_ffmpeg 1>> $LOG_FILE 2>&1
    fi
  fi
}

install_ffmpeg() {
  check_builds
  echo -e "INFO: Installing ffmpeg if not installed\n"  | tee -a "$LOG_FILE"
  change_dir $ffmpeg_source_dir

  echo -e "INFO: Making Ffmpeg $(pwd)" | tee -a "$LOG_FILE"

  create_dir $install_prefix

  do_make_and_make_install "" "" "$(get_build_type)" 1>> $LOG_FILE 2>&1
  
  echo -e "INFO: Moving all binaries" | tee -a "$LOG_FILE"

  mv */*.a "${install_prefix}/bin" 1>> $LOG_FILE 2>&1
  mv */*.dylib "${install_prefix}/bin" 1>> $LOG_FILE 2>&1
  mv */*.lib "${install_prefix}/bin" 1>> $LOG_FILE 2>&1
  mv */*.dll "${install_prefix}/bin" 1>> $LOG_FILE 2>&1
  mv *.exe "${install_prefix}/bin" 1>> $LOG_FILE 2>&1
  mv *.so "${install_prefix}/bin" 1>> $LOG_FILE 2>&1

  echo -e "INFO: Done installing ffmpeg\n" | tee -a "$LOG_FILE"

  install_ffmpeg_pkg
}

install_ffmpeg_pkg() {
  echo -e "INFO: Checking deployment files...\n" | tee -a "$LOG_FILE"

  required_files=(
    "${install_prefix}/lib/pkgconfig/libavformat.pc"
    "${install_prefix}/lib/pkgconfig/libswresample.pc"
    "${install_prefix}/lib/pkgconfig/libswscale.pc"
    "${install_prefix}/lib/pkgconfig/libavdevice.pc"
    "${install_prefix}/lib/pkgconfig/libavfilter.pc"
    "${install_prefix}/lib/pkgconfig/libavcodec.pc"
    "${install_prefix}/lib/pkgconfig/libavutil.pc")

  check_files_exist "false" "${required_files[@]}"

  echo -e "INFO: Done checking deployment files.\n" | tee -a "$LOG_FILE"

  echo -e "INFO: Installing ffmpeg pkg-config\n" | tee -a "$LOG_FILE"

  create_dir "$INSTALL_PKG_CONFIG_DIR"

  # MANUALLY COPY PKG-CONFIG FILES
  overwrite_file "${install_prefix}"/lib/pkgconfig/libavformat.pc "${INSTALL_PKG_CONFIG_DIR}/libavformat.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libswresample.pc "${INSTALL_PKG_CONFIG_DIR}/libswresample.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libswscale.pc "${INSTALL_PKG_CONFIG_DIR}/libswscale.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libavdevice.pc "${INSTALL_PKG_CONFIG_DIR}/libavdevice.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libavfilter.pc "${INSTALL_PKG_CONFIG_DIR}/libavfilter.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libavcodec.pc "${INSTALL_PKG_CONFIG_DIR}/libavcodec.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libavutil.pc "${INSTALL_PKG_CONFIG_DIR}/libavutil.pc" || return 1

  # # MANUALLY ADD REQUIRED HEADERS
  mkdir -p "${install_prefix}"/include/libavutil/x86 1>> $LOG_FILE 2>&1
  mkdir -p "${install_prefix}"/include/libavutil/arm 1>> $LOG_FILE 2>&1
  mkdir -p "${install_prefix}"/include/libavutil/aarch64 1>> $LOG_FILE 2>&1
  mkdir -p "${install_prefix}"/include/libavcodec/x86 1>> $LOG_FILE 2>&1
  mkdir -p "${install_prefix}"/include/libavcodec/arm 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/config.h "${install_prefix}"/include/config.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavcodec/mathops.h "${install_prefix}"/include/libavcodec/mathops.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavcodec/x86/mathops.h "${install_prefix}"/include/libavcodec/x86/mathops.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavcodec/arm/mathops.h "${install_prefix}"/include/libavcodec/arm/mathops.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavformat/network.h "${install_prefix}"/include/libavformat/network.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavformat/os_support.h "${install_prefix}"/include/libavformat/os_support.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavformat/url.h "${install_prefix}"/include/libavformat/url.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/attributes_internal.h "${install_prefix}"/include/libavutil/attributes_internal.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/bprint.h "${install_prefix}"/include/libavutil/bprint.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/getenv_utf8.h "${install_prefix}"/include/libavutil/getenv_utf8.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/internal.h "${install_prefix}"/include/libavutil/internal.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/libm.h "${install_prefix}"/include/libavutil/libm.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/reverse.h "${install_prefix}"/include/libavutil/reverse.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/thread.h "${install_prefix}"/include/libavutil/thread.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/timer.h "${install_prefix}"/include/libavutil/timer.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/x86/asm.h "${install_prefix}"/include/libavutil/x86/asm.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/x86/timer.h "${install_prefix}"/include/libavutil/x86/timer.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/arm/timer.h "${install_prefix}"/include/libavutil/arm/timer.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/aarch64/timer.h "${install_prefix}"/include/libavutil/aarch64/timer.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/compat/w32pthreads.h "${install_prefix}"/include/libavutil/compat/w32pthreads.h 1>> $LOG_FILE 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/wchar_filename.h "${install_prefix}"/include/libavutil/wchar_filename.h 1>> $LOG_FILE 2>&1

  echo -e "INFO: Done installing ffmpeg pkg-config\n" | tee -a "$LOG_FILE"
}

configure_ffmpeg() {
  echo -e "INFO: Configuring ffmpeg\n" | tee -a "$LOG_FILE"
  
  # PREPARE PATHS & DEFINE ${INSTALL_PKG_CONFIG_DIR}
  LIB_NAME="ffmpeg"

  change_dir "$ffmpeg_source_dir" 1>>$LOG_FILE 2>&1 || return 1

  if [[ $BUILD_FORCE == "1" ]]; then
    remove_path -f ${ffmpeg_source_dir}/already_configured_$(get_build_type)*
  fi

  # SET DEBUG OPTIONS
  if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
    # SET LTO FLAGS
    DEBUG_OPTIONS=" --disable-debug"
  else
    DEBUG_OPTIONS=" --enable-debug --disable-stripping"
  fi
  local extra_postpend_configure_options=$2

  local postpend_configure_opts=""

  # can't mix and match --enable-static --enable-shared unfortunately, or the final executable seems to just use shared if the're both present
  if [[ ${build_ffmpeg_shared,,} =~ ^(y|yes|1|true|on)$ ]]; then
    postpend_configure_opts="--enable-shared --disable-static --prefix=${install_prefix}" # I guess this doesn't have to be at the end...
  else
    postpend_configure_opts="--enable-static --disable-shared --prefix=${install_prefix}"
  fi

  if [[ $ffmpeg_git_checkout_version == *"n4.4"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.3"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.2"* ]]; then
    postpend_configure_opts="${postpend_configure_opts} --disable-libdav1d " # dav1d has diverged since so isn't compat with older ffmpegs
  fi

  change_dir "$ffmpeg_source_dir" || exit
    apply_patch file://"$WINPATCHDIR"/frei0r_load-shared-libraries-dynamically.diff
    if [ "$bits_target" = "32" ]; then
      local arch=x86
    else
      local arch=amd64
    fi

    local init_options="--pkg-config=pkg-config"
          init_options+=" --pkg-config-flags=--static"
          init_options+=" --enable-version3"
          init_options+=" --disable-debug"

    if [[ $compiler_flavors != "native" ]]; then
      init_options+=" --arch=$arch"
      init_options+=" --target-os=mingw32"
      init_options+=" --cross-prefix=$cross_prefix"
    else
      if [[ $OSTYPE != darwin* ]]; then
        unset PKG_CONFIG_LIBDIR # just use locally packages for all the xcb stuff for now, you need to install them locally first...
        init_options+=" --enable-libv4l2"
        init_options+=" --enable-libxcb"
        init_options+=" --enable-libxcb-shm"
        init_options+=" --enable-libxcb-xfixes"
        init_options+=" --enable-libxcb-shape "
      else
        config_options+=" --disable-libv4l2"
      fi
    fi
    if [[ $(uname) =~ "5.1" ]]; then
      init_options+=" --disable-schannel"
      # Fix WinXP incompatibility by disabling Microsoft's Secure Channel, because Windows XP doesn't support TLS 1.1 and 1.2, but with GnuTLS or OpenSSL it does.  XP compat!
    fi
    local config_options=" $init_options"
    config_options+=" --disable-alsa"
    config_options+=" --disable-appkit"
    config_options+=" --disable-audiotoolbox"
    config_options+=" --disable-autodetect"
    config_options+=" --disable-doc"
    config_options+=" --disable-gmp"
    config_options+=" --disable-gnutls"
    config_options+=" --disable-htmlpages"
    config_options+=" --disable-iconv"
    config_options+=" --disable-libdav1d"
    config_options+=" --disable-libfribidi"
    config_options+=" --disable-libilbc"
    config_options+=" --disable-libkvazaar"
    config_options+=" --disable-libopencore-amrnb"
    config_options+=" --disable-libopencore-amrwb"
    config_options+=" --disable-libopenh264"
    config_options+=" --disable-librubberband"
    config_options+=" --disable-libshine"
    config_options+=" --disable-libsnappy"
    config_options+=" --disable-libsoxr"
    config_options+=" --disable-libspeex"
    config_options+=" --disable-libsrt"
    config_options+=" --disable-libtesseract"
    config_options+=" --disable-libtheora"
    config_options+=" --disable-libtwolame"
    config_options+=" --disable-libvidstab"
    config_options+=" --disable-libvo-amrwbenc"
    config_options+=" --disable-libxml2"
    config_options+=" --disable-libxvid"
    config_options+=" --disable-libzimg"
    config_options+=" --disable-manpages"
    config_options+=" --disable-neon-clobber-test"
    config_options+=" --disable-openssl"
    config_options+=" --disable-podpages"
    config_options+=" --disable-pthreads"
    config_options+=" --disable-sdl2"
    config_options+=" --disable-securetransport"
    config_options+=" --disable-sndio"
    config_options+=" --disable-txtpages"
    config_options+=" --disable-v4l2-m2m"
    config_options+=" --disable-vaapi"
    config_options+=" --disable-vdpau"
    config_options+=" --disable-videotoolbox"
    config_options+=" --disable-xlib"
    config_options+=" --disable-xmm-clobber-test"
    config_options+=" --enable-bzlib"
    config_options+=" --enable-cross-compile"
    config_options+=" --enable-cuda"
    config_options+=" --enable-cuvid"
    config_options+=" --enable-ffnvcodec"
    config_options+=" --enable-filter=drawtext"
    config_options+=" --enable-libass"
    config_options+=" --enable-libfontconfig"
    config_options+=" --enable-libfreetype"
    config_options+=" --enable-libmp3lame"
    config_options+=" --enable-libopus"
    config_options+=" --enable-libvorbis"
    config_options+=" --enable-libvpx"
    config_options+=" --enable-libwebp"
    config_options+=" --enable-libx264"
    config_options+=" --enable-nvdec"
    config_options+=" --enable-nvenc"
    config_options+=" --enable-optimizations"
    config_options+=" --enable-pic"
    config_options+=" --enable-small"
    config_options+=" --enable-swscale"
    config_options+=" --enable-w32threads"
    config_options+=" --enable-zlib"
    #config_options+=" --disable-indevs"
    #config_options+=" --disable-outdevs"
    config_options+=${SIZE_OPTIONS}
    config_options+=${DEBUG_OPTIONS}

    if [[ $build_svt_hevc = y ]]; then
      # SVT-HEVC patches and enable
      if [[ $ffmpeg_git_checkout_version == *"n4.4"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.3"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.2"* ]]; then
        git apply "$work_dir/SVT-HEVC_git/ffmpeg_plugin/n4.4-0001-lavc-svt_hevc-add-libsvt-hevc-encoder-wrapper.patch"
        git apply "$WINPATCHDIR/SVT-HEVC-0002-doc-Add-libsvt_hevc-encoder-docs.patch"
      elif [[ $ffmpeg_git_checkout_version == *"n4.1"* ]] || [[ $ffmpeg_git_checkout_version == *"n3"* ]] || [[ $ffmpeg_git_checkout_version == *"n2"* ]]; then
        : # too old...
      else
        git apply "$work_dir/SVT-HEVC_git/ffmpeg_plugin/master-0001-lavc-svt_hevc-add-libsvt-hevc-encoder-wrapper.patch"
      fi
      config_options+=" --enable-libsvthevc"
    fi

    if [[ $build_svt_vp9 = y ]]; then
      # SVT-VP9 patches and enable
      if [[ $ffmpeg_git_checkout_version == *"n4.3.1"* ]]; then
        git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/n4.3.1-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
      elif [[ $ffmpeg_git_checkout_version == *"n4.2.3"* ]]; then
        git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/n4.2.3-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
      elif [[ $ffmpeg_git_checkout_version == *"n4.2.2"* ]]; then
        git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
      else 
        git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/master-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
      fi
      config_options+=" --enable-libsvtvp9"
    fi
    local enable_libsvtav1=" --enable-libsvtav1"
    # SVT-AV1
    if [[ $ffmpeg_git_checkout_version != *"n6"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then
      git apply "$work_dir/SVT-AV1_git/.gitlab/workflows/linux/ffmpeg_n7_fix.patch" >/dev/null 2>&1 
      patch_exists=$?
      if [[ $patch_exists != 0 ]]; then
        enable_libsvtav1=" --disable-libsvtav1"
      fi
    fi
    config_options+=$enable_libsvtav1

    config_options+=" --enable-libaom"

    # ==================== ORIGINAL EXTRAS (conditionally kept) ====================
    
    if [[ $build_amd_amf = n ]]; then
      config_options+=" --disable-amf"
    else
      config_options+=" --enable-amf"
    fi

    if [[ $compiler_flavors != "native" ]]; then 
      config_options+=" --enable-libvpl"
    else
      config_options+=" --disable-libvpl"
    fi
    
    if [[ $ffmpeg_git_checkout_version != *"n6.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then
      config_options+=" --enable-libaribcaption"
    fi
    
    if [[ $GPL_ENABLED == 'y' ]] || [[ $GPL_ENABLED == 'yes' ]]; then
      config_options+=" --enable-gpl --enable-frei0r --enable-librubberband --enable-libvidstab --enable-libx265 --enable-avisynth"
      config_options+=" --enable-libxvid --enable-libdavs2"
      if [[ $host_target != 'i686-w64-mingw32' ]]; then
        config_options+=" --enable-libxavs2"
      fi
      if [[ $compiler_flavors != "native" ]]; then
        config_options+=" --enable-libxavs"
      fi
    fi

    # Extra libs and flags
    config_options+=" --extra-libs=-lz"
    config_options+=" --extra-libs=-lpng"
    config_options+=" --extra-libs=-lm"
    config_options+=" --extra-libs=-lfreetype"

    if [[ $compiler_flavors != "native" ]]; then
      config_options+=" --extra-libs=-lshlwapi"
    fi
    config_options+=" --extra-libs=-lmpg123"
    config_options+=" --extra-libs=-lpthread"

    config_options+=" --extra-cflags=-DLIBTWOLAME_STATIC --extra-cflags=-DMODPLUG_STATIC --extra-cflags=-DCACA_STATIC"
    config_options+=" --extra-cflags=-DWIN32_ANSI_API --extra-cflags=-DHAVE_WCHAR_FILENAME_H=0"
    config_options+=" --extra-ldflags=-lole32 --extra-ldflags=-lshlwapi"
    config_options+=" --extra-ldflags=-static-libgcc --extra-ldflags=-static-libstdc++"
    for i in $CFLAGS; do
      config_options+=" --extra-cflags=$i"
    done

    config_options+=" $postpend_configure_opts"

    # if [[ "$non_free" = "y" ]]; then
    #   config_options+=" --enable-nonfree --enable-libfdk-aac"
    #   if [[ $OSTYPE != darwin* ]]; then
    #     config_options+=" --enable-audiotoolbox --disable-outdev=audiotoolbox --extra-libs=-lAudioToolboxWrapper" && apply_patch file://"$WINPATCHDIR"/AudioToolBox.patch -p1
    #   fi
    #   if [[ $compiler_flavors != "native" ]]; then
    #     config_options+=" --enable-decklink"
    #   fi
    # fi

    do_debug_build=n
    if [[ "$do_debug_build" = "y" ]]; then
      config_options+=" --disable-optimizations --extra-cflags=-Og --extra-cflags=-fno-omit-frame-pointer --enable-debug=3 --extra-cflags=-fno-inline $postpend_configure_opts"
      config_options+=" --disable-libgme"
    fi
    config_options+=" $extra_postpend_configure_options"

    do_configure "$config_options" "./configure" "$(get_build_type)" 1>> $LOG_FILE 2>&1

  echo -e "INFO: Done configuering ffmpeg\n" | tee -a "$LOG_FILE"
}

configure_ffmpeg_kit() {
  echo -e "INFO: Configuring ffmpeg kit\n" | tee -a "$LOG_FILE"
  local TYPE_POSTFIX="$(get_build_type)"
  local FFMPEG_KIT_VERSION=$(get_ffmpeg_kit_version)

  if [[ $BUILD_FORCE == "1" ]]; then
    remove_path -rf "${BASEDIR}"/windows/already_configured_*
    remove_path -rf $ffmpeg_kit_install
  fi
  
  create_dir $ffmpeg_kit_install

  export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${install_prefix}/lib/pkgconfig"
  set_toolchain_paths

  reset_cflags
  reset_cppflags    
  local local_cflags="${CFLAGS} -I${install_prefix}/include -L${install_prefix}/bin -L${install_prefix}/lib -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat -DHAVE_W32PTHREADS_H=1"
  local local_cxxfalgs="${CXXFLAGS} -I${install_prefix}/include -L${install_prefix}/bin -L${install_prefix}/lib -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat"
  
  change_dir "${BASEDIR}/windows"
    make distclean 2>/dev/null 1>/dev/null

  local touch_name=$(get_small_touchfile_name already_autoreconf_${TYPE_POSTFIX} "$FFMPEG_KIT_VERSION $local_cflags $local_cxxfalgs")
  if [ ! -f "$touch_name" ]; then
    remove_path -f "${BASEDIR}"/windows/already_autoreconf_${TYPE_POSTFIX}*
    change_dir "${BASEDIR}/windows"
      autoreconf_library "ffmpeg-kit" 1>> $LOG_FILE 2>&1 || return 1
    touch -- "$touch_name"
    local BUILD_DATE="-DFFMPEG_KIT_BUILD_DATE=$(date +%Y%m%d 2>>"${BASEDIR}"/build.log)"
    export CFLAGS="${local_cflags} ${BUILD_DATE}"
    export CXXFLAGS="${local_cxxfalgs} ${BUILD_DATE}"
  fi

  local config_options="--prefix=${ffmpeg_kit_install}"
  
  config_options+=" --host=${host_target}"
  if [[ ${build_ffmpeg_static,,} =~ ^(y|yes|1|true|on)$ ]]; then
    config_options+=" --enable-static" 
    config_options+=" --disable-shared"
  else
    config_options+=" --enable-shared" 
    config_options+=" --disable-static"
  fi
  change_dir "${BASEDIR}/windows"
    do_configure "${config_options}" "./configure" "${TYPE_POSTFIX}" 1>> $LOG_FILE 2>&1 || return 1
  
  echo -e "INFO: Done configuring ffmpeg kit\n" | tee -a "$LOG_FILE"
}


create_ffmpegkit_package_config() {
  local FFMPEGKIT_VERSION="$1"

  cat >"${INSTALL_PKG_CONFIG_DIR}/ffmpeg-kit.pc" <<EOF
prefix=${ffmpeg_kit_install}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: ffmpeg-kit
Description: FFmpeg for applications on Windows
Version: ${FFMPEGKIT_VERSION}

# Public dependencies that have their own .pc files
Requires: libavfilter, libswscale, libavformat, libavcodec, libswresample, libavutil

# Linker flags for the ffmpeg-kit library itself (includes jsoncpp if static)
Libs: -L\${libdir} -lffmpegkit

# Private dependencies needed for linking on Windows
Libs.private: -lstdc++ -lws2_32 -lpsapi -lole32 -lshlwapi -lgdi32 -lbcrypt -luser32 -luuid

# Compiler flags for the ffmpeg-kit headers (includes jsoncpp headers if bundled)
Cflags: -I\${includedir}
EOF
}


install_ffmpeg_kit() {
  echo -e "INFO: Installing ffmpeg kit to ${ffmpeg_kit_install}\n" | tee -a "$LOG_FILE"
  
  change_dir "${BASEDIR}/windows"
    do_make_and_make_install "" "" "$(get_build_type)" 1>>$LOG_FILE 2>&1

  create_ffmpegkit_package_config "$(get_ffmpeg_kit_version)" 1>> $LOG_FILE 2>&1 || return 1

  echo -e "INFO: Done installing ffmpeg kit to ${ffmpeg_kit_install}\n" | tee -a "$LOG_FILE"
}

get_bundle_directory() {
  local LTS_POSTFIX=""
  if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
    LTS_POSTFIX="-lts"
  fi
  local TYPE_POSTFIX="$(get_build_type)"
  echo -e "bundle-windows-${TYPE_POSTFIX}${LTS_POSTFIX}"
}

create_windows_bundle() {
  echo -e "INFO: Creating bundle" 1>>$LOG_FILE 2>&1
  local TYPE_POSTFIX="$(get_build_type)"
  local FFMPEG_KIT_VERSION=$(get_ffmpeg_kit_version)

  if [[ $BUILD_FORCE == "1" ]]; then
    remove_path -rf "${BASEDIR}"/windows/already_bundled_${TYPE_POSTFIX}*
  fi

  local touch_name=$(get_small_touchfile_name already_bundled_${TYPE_POSTFIX} "$FFMPEG_KIT_VERSION $ffmpeg_kit_bundle")
  if [ ! -f "$touch_name" ]; then
    export FFMPEG_KIT_BUNDLE_INCLUDE_DIRECTORY="${ffmpeg_kit_bundle}/include"
    export FFMPEG_KIT_BUNDLE_LIB_DIRECTORY="${ffmpeg_kit_bundle}/lib"
    export FFMPEG_KIT_BUNDLE_BIN_DIRECTORY="${ffmpeg_kit_bundle}/bin"
    export FFMPEG_KIT_BUNDLE_PKG_CONFIG_DIRECTORY="${ffmpeg_kit_bundle}/pkgconfig"
    remove_path "-rf" "${ffmpeg_kit_bundle}"
    create_dir "${ffmpeg_kit_bundle}"
    create_dir "${FFMPEG_KIT_BUNDLE_INCLUDE_DIRECTORY}"
    create_dir "${FFMPEG_KIT_BUNDLE_LIB_DIRECTORY}"
    create_dir "${FFMPEG_KIT_BUNDLE_BIN_DIRECTORY}"
    create_dir "${FFMPEG_KIT_BUNDLE_PKG_CONFIG_DIRECTORY}"
    
    # COPY HEADERS
    copy_path "${ffmpeg_kit_install}"/include/* "${FFMPEG_KIT_BUNDLE_INCLUDE_DIRECTORY}" "-r -P" 2>>"${BASEDIR}"/build.log
    copy_path "${install_prefix}"/include/* "${FFMPEG_KIT_BUNDLE_INCLUDE_DIRECTORY}" "-r -P" 2>>"${BASEDIR}"/build.log

    # COPY LIBS
    copy_path "${ffmpeg_kit_install}"/lib/* "${FFMPEG_KIT_BUNDLE_LIB_DIRECTORY}" "-r -P" 2>>"${BASEDIR}"/build.log
    copy_path "${install_prefix}"/lib/* "${FFMPEG_KIT_BUNDLE_LIB_DIRECTORY}" "-r -P" 2>>"${BASEDIR}"/build.log

    # COPY BINARIES
    copy_path "${ffmpeg_kit_install}"/bin/* "${FFMPEG_KIT_BUNDLE_BIN_DIRECTORY}" "-r -P" 2>>"${BASEDIR}"/build.log
    copy_path "${install_prefix}"/bin/* "${FFMPEG_KIT_BUNDLE_BIN_DIRECTORY}" "-r -P" 2>>"${BASEDIR}"/build.log

    install_pkg_config_file "libavformat.pc"
    install_pkg_config_file "libswresample.pc"
    install_pkg_config_file "libswscale.pc"
    install_pkg_config_file "libavdevice.pc"
    install_pkg_config_file "libavfilter.pc"
    install_pkg_config_file "libavcodec.pc"
    install_pkg_config_file "libavutil.pc"
    install_pkg_config_file "ffmpeg-kit.pc"

    local LICENSE_BASEDIR="${ffmpeg_kit_bundle}/licenses"

    create_dir "${LICENSE_BASEDIR}"

    echo -e "INFO: Copying licenses...\n" | tee -a "$LOG_FILE"
    bash "${SCRIPTDIR}/extract_licenses.sh" "${work_dir}" "${LICENSE_BASEDIR}" 1>>$LOG_FILE 2>&1
    echo -e "INFO: Done copying licenses\n" | tee -a "$LOG_FILE"

    copy_path "${BASEDIR}"/tools/source/SOURCE "${LICENSE_BASEDIR}/source.txt" 1>>$LOG_FILE 2>&1
    copy_path "${BASEDIR}"/tools/license/LICENSE.GPLv3 "${LICENSE_BASEDIR}"/license.txt 1>>"${BASEDIR}"/build.log 2>&1
    touch -- "$touch_name"
  fi
  echo -e "INFO: Done creating bundle\n" | tee -a "$LOG_FILE"
}


pick_clean_type() {
  while [[ ! "$clean_type" =~ ^([1-5]|"all"|"ffmpeg"|"ffmpeg-kit"|"ffmpeg-kit-bundle")$ ]]; do
    if [[ -n "${unknown_opts[@]}" ]]; then
      echo -e -n 'Unknown option(s)'
      for unknown_opt in "${unknown_opts[@]}"; do
        echo -e -n " '$unknown_opt'"
      done
      echo -e ', ignored.'; echo
    fi
    cat <<'EOF'
What would you like to clean?
  1. all
  2. ffmpeg
  3. ffmpeg-kit
  4. ffmpeg-kit-bundle
  5. Exit
EOF
    echo -e -n 'Input your choice [1-5]: '
    read -r clean_type
  done
  case "$clean_type" in
  1 )                 export clean_type="all" ;;
  2 )                 export clean_type="ffmpeg" ;;
  3 )                 export clean_type="ffmpeg-kit" ;;
  4 )                 export clean_type="ffmpeg-kit-bundle" ;;
  all )               export clean_type="all" ;;
  ffmpeg )            export clean_type="ffmpeg" ;;
  ffmpeg-kit )        export clean_type="ffmpeg-kit" ;;
  ffmpeg-kit-bundle ) export clean_type="ffmpeg-kit-bundle" ;;
  5 ) echo -e "exiting"; exit 0 ;;
  * ) echo -e 'Your choice was not valid, please try again.'; echo ;;
  esac
}

clean_ffmpeg_builds() {
  if [[ -z $compiler_flavors ]]; then
    pick_compiler_flavors
  fi
  pick_clean_type
  if [[ ${compiler_flavors,,} =~ ^(multi)$ ]]; then
    clean_builds "win32"
    clean_builds "win64"
  else
    clean_builds "$compiler_flavors"
    exit 0
  fi
}

clean_builds() {
  local build_flavor=$1
  if [[ -z $build_flavor ]]; then
    exit 1;
  fi
  pick_compiler_flavors $build_flavor
  setup_build_environment "$compiler_flavors"
  if [[ ${clean_type,,} =~ ^("all"|"ffmpeg")$ ]]; then
    echo -e "INFO: Deleting ${install_prefix}..."
    remove_path "${install_prefix}"
  fi
  if [[ ${clean_type,,} =~ ^("all"|"ffmpeg-kit")$ ]]; then
    echo -e "INFO: Deleting ${ffmpeg_kit_install}..."
    remove_path "${ffmpeg_kit_install}"
  fi
  if [[ ${clean_type,,} =~ ^("all"|"ffmpeg-kit-bundle")$ ]]; then
    echo -e "INFO: Deleting ${ffmpeg_kit_bundle}..."
    remove_path "${ffmpeg_kit_bundle}"
  fi
}