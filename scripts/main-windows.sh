# #!/bin/bash

#echo "${SCRIPTDIR}/variable.sh"
#echo "${SCRIPTDIR}/function.sh"
#echo "${SCRIPTDIR}/function-windows.sh"

source "${SCRIPTDIR}/variable.sh"
source "${SCRIPTDIR}/function.sh"
source "${SCRIPTDIR}/function-windows.sh"

if [ -z "$(get_cpu_count)" ]; then
  cpu_count=$(sysctl -n hw.ncpu | tr -d '\n') # OS X cpu count
  if [ -z "$(get_cpu_count)" ]; then
    echo "warning, unable to determine cpu count, defaulting to 1"
    cpu_count=1 # else default to just 1, instead of blank, which means infinite
  fi
fi

set_box_memory_size_bytes
if [[ $box_memory_size_bytes -lt 600000000 ]]; then
  echo "your box only has $box_memory_size_bytes, 512MB (only) boxes crash when building cross compiler gcc, please add some swap" # 1G worked OK however...
  exit 1
fi

if [[ $box_memory_size_bytes -gt 2000000000 ]]; then
  gcc_cpu_count=$(get_cpu_count) # they can handle it seemingly...
else
  echo "low RAM detected so using only one cpu for gcc compilation"
  gcc_cpu_count=1 # compatible low RAM...
fi

yes_no_sel () {
  unset user_input
  local question="$1"
  shift
  local default_answer="$1"
  while [[ "$user_input" != [YyNn] ]]; do
    echo -n "$question"
    read -r user_input
    if [[ -z "$user_input" ]]; then
      echo "using default $default_answer"
      user_input=$default_answer
    fi
    if [[ "$user_input" != [YyNn] ]]; then
      clear; echo 'Your selection was not vaild, please try again.'; echo
    fi
  done
  # downcase it
  user_input=$(echo "$user_input" | tr "[:upper:]" "[:lower:]")
}


intro() {
  cat <<EOL
     ##################### Welcome ######################
  Welcome to the ffmpeg cross-compile builder-helper script.
  Downloads and builds will be installed to directories within $WORKDIR
  If this is not ok, then exit now, and cd to the directory where you'd
  like them installed, then run this script again from there.
  NB that once you build your compilers, you can no longer rename/move
  the $sandbox directory, since it will have some hard coded paths in there.
  You can, of course, rebuild ffmpeg from within it, etc.
EOL
  echo "$(date)" # for timestamping super long builds LOL
  if [[ $sandbox_ok != 'y' && ! -d prebuilt ]]; then
    echo
    echo "Building in $PWD/$sandbox, will use ~ 285GB space!"
    echo
  fi
  create_dir "$WORKDIR"
  change_dir "$WORKDIR" || exit
  echo "sit back, this may take awhile..."
}

pick_compiler_flavors() {
  while [[ "$compiler_flavors" != [1-5] ]]; do
    if [[ -n "${unknown_opts[@]}" ]]; then
      echo -n 'Unknown option(s)'
      for unknown_opt in "${unknown_opts[@]}"; do
        echo -n " '$unknown_opt'"
      done
      echo ', ignored.'; echo
    fi
    cat <<'EOF'
What version of MinGW-w64 would you like to build or update?
  1. Both Win32 and Win64
  2. Win32 (32-bit only)
  3. Win64 (64-bit only)
  4. Local native
  5. Exit
EOF
    echo -n 'Input your choice [1-5]: '
    read -r compiler_flavors
  done
  case "$compiler_flavors" in
  1 ) compiler_flavors=multi ;;
  2 ) compiler_flavors=win32 ;;
  3 ) compiler_flavors=win64 ;;
  4 ) compiler_flavors=native ;;
  5 ) echo "exiting"; exit 0 ;;
  * ) clear;  echo 'Your choice was not valid, please try again.'; echo ;;
  esac
}

reset_cflags # also overrides any "native" CFLAGS, which we may need if there are some 'linux only' settings in there
reset_cppflags # Ensure CPPFLAGS are cleared and set to what is configured
check_missing_packages # do this first since it's annoying to go through prompts then be rejected
intro # remember to always run the intro, since it adjust pwd
install_cross_compiler

if [[ -n "$build_only_index" ]]; then
  # Setup the environment based on the globally set compiler_flavors
  
  # Now, call the single requested build function by its index
  step_name="${BUILD_STEPS[$build_only_index]}"
  echo "--- Executing single build step: $step_name ---"
  build_ffmpeg_dependencies_only "$step_name"

else

  if [[ $OSTYPE == darwin* ]]; then
    # mac add some helper scripts
    create_dir mac_helper_scripts
    change_dir mac_helper_scripts || exit
      if [[ ! -x readlink ]]; then
        # make some scripts behave like linux...
        curl -4 file://"$WINPATCHDIR"/md5sum.mac --fail > md5sum  || exit 1
        chmod u+x ./md5sum
        curl -4 file://"$WINPATCHDIR"/readlink.mac --fail > readlink  || exit 1
        chmod u+x ./readlink
      fi
      export PATH=$(pwd):$PATH
    change_dir ..
  fi

  change_dir "$work_dir" || exit
    if [[ $build_dependencies_only == "y" || $build_dependencies_only == "yes" || $build_dependencies_only == "1" ]]; then
      build_ffmpeg_dependencies      
    elif [[ $build_ffmpeg_only == "y"|| $build_ffmpeg_only == "yes" || $build_ffmpeg_only == "1" ]]; then
      download_ffmpeg
      configure_ffmpeg
      install_ffmpeg
    elif [[ $build_ffmpeg_kit_only == "y" || $build_ffmpeg_kit_only == "yes" || $build_ffmpeg_kit_only == "1" ]]; then
      download_ffmpeg
      configure_ffmpeg
      install_ffmpeg
    else
      build_ffmpeg_dependencies
      download_ffmpeg
      configure_ffmpeg
      install_ffmpeg
      # BUILD FFMPEG-KIT BUNDLE
      echo -e -n "\nCreating the bundle under prebuilt: "

      build_ffmpeg_kit

      echo -e "\nINFO: Completed build for ${ARCH} at $(date)\n" 1>>$LOG_FILE 2>&1

      echo -e "DEBUG: Creating the bundle directory\n" 1>>$LOG_FILE 2>&1

      create_windows_bundle

      echo -e "ok\n"
      
      echo -e "\nINFO: Completed bundle at ${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit/lib\n" 1>>$LOG_FILE 2>&1
      
    fi
  change_dir ..

  # if [[ $build_dependencies_only == "n" || $build_dependencies_only == "no" || $build_dependencies_only == "0" ]]; then
  #   echo "searching for all local exe's (some may not have been built this round, NB)..."
  #   for file in $(find_all_build_exes); do
  #     echo "built $file"
  #   done
  # fi
fi