# #!/bin/bash

#echo -e "${SCRIPTDIR}/variable.sh"
#echo -e "${SCRIPTDIR}/function.sh"
#echo -e "${SCRIPTDIR}/function-windows.sh"

source "${SCRIPTDIR}/function.sh"
source "${SCRIPTDIR}/function-windows.sh"

if [ -z "$(get_cpu_count)" ]; then
  cpu_count=$(sysctl -n hw.ncpu | tr -d '\n') # OS X cpu count
  if [ -z "$(get_cpu_count)" ]; then
    echo -e "warning, unable to determine cpu count, defaulting to 1"
    cpu_count=1 # else default to just 1, instead of blank, which means infinite
  fi
fi

set_box_memory_size_bytes
if [[ $box_memory_size_bytes -lt 600000000 ]]; then
  echo -e "your box only has $box_memory_size_bytes, 512MB (only) boxes crash when building cross compiler gcc, please add some swap" # 1G worked OK however...
  exit 1
fi

if [[ $box_memory_size_bytes -gt 2000000000 ]]; then
  gcc_cpu_count=$(get_cpu_count) # they can handle it seemingly...
else
  echo -e "low RAM detected so using only one cpu for gcc compilation"
  gcc_cpu_count=1 # compatible low RAM...
fi

yes_no_sel () {
  unset user_input
  local question="$1"
  shift
  local default_answer="$1"
  while [[ "$user_input" != [YyNn] ]]; do
    echo -e -n "$question"
    read -r user_input
    if [[ -z "$user_input" ]]; then
      echo -e "using default $default_answer"
      user_input=$default_answer
    fi
    if [[ "$user_input" != [YyNn] ]]; then
      clear; echo -e 'Your selection was not vaild, please try again.'; echo
    fi
  done
  # downcase it
  user_input=$(echo -e "$user_input" | tr "[:upper:]" "[:lower:]")
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
  echo -e "$(date)" # for timestamping super long builds LOL
  if [[ $sandbox_ok != 'y' && ! -d prebuilt ]]; then
    echo -e
    echo -e "Building in $PWD/$sandbox, will use ~ 285GB space!"
    echo -e
  fi
  create_dir "$WORKDIR"
  change_dir "$WORKDIR" || exit
  echo -e "sit back, this may take awhile..."
}

pick_compiler_flavors() {
  while [[ "$compiler_flavors" != [1-5] ]]; do
    if [[ -n "${unknown_opts[@]}" ]]; then
      echo -e -n 'Unknown option(s)'
      for unknown_opt in "${unknown_opts[@]}"; do
        echo -e -n " '$unknown_opt'"
      done
      echo -e ', ignored.'; echo
    fi
    cat <<'EOF'
What version of MinGW-w64 would you like to build or update?
  1. Both Win32 and Win64
  2. Win32 (32-bit only)
  3. Win64 (64-bit only)
  4. Local native
  5. Exit
EOF
    echo -e -n 'Input your choice [1-5]: '
    read -r compiler_flavors
  done
  case "$compiler_flavors" in
  1 ) compiler_flavors=multi ;;
  2 ) compiler_flavors=win32 ;;
  3 ) compiler_flavors=win64 ;;
  4 ) compiler_flavors=native ;;
  5 ) echo -e "exiting"; exit 0 ;;
  * ) clear;  echo -e 'Your choice was not valid, please try again.'; echo ;;
  esac
}

reset_cflags # also overrides any "native" CFLAGS, which we may need if there are some 'linux only' settings in there
reset_cppflags # Ensure CPPFLAGS are cleared and set to what is configured
check_missing_packages # do this first since it's annoying to go through prompts then be rejected
intro # remember to always run the intro, since it adjust pwd
install_cross_compiler 1>>$LOG_FILE 2>&1

if [[ -n "$build_only_index" ]]; then
  # Setup the environment based on the globally set compiler_flavors
  
  # Now, call the single requested build function by its index
  step_name="${BUILD_STEPS[$build_only_index]}"
  echo -e "--- Executing single build step: $step_name ---"
  build_ffmpeg_dependency_only "$step_name" 1>>$LOG_FILE 2>&1
  echo -e "--- Done building single build step: $step_name ---"
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
      echo -e "INFO: Building dependencies only..."
      build_all_ffmpeg_dependencies #1>>$LOG_FILE 2>&1
      exit 0
    elif [[ $build_ffmpeg_only == "y"|| $build_ffmpeg_only == "yes" || $build_ffmpeg_only == "1" ]]; then
      echo -e "INFO: Building ffmpeg only..."
      download_ffmpeg #1>>$LOG_FILE 2>&1
      install_ffmpeg #1>>$LOG_FILE 2>&1
      exit 0
    elif [[ $build_ffmpeg_kit_only == "y" || $build_ffmpeg_kit_only == "yes" || $build_ffmpeg_kit_only == "1" ]]; then
      echo -e "INFO: Building ffmpeg-kit only..."
      configure_ffmpeg_kit #1>>$LOG_FILE 2>&1
      install_ffmpeg_kit
      create_windows_bundle
      exit 0
    else
      echo -e "INFO: Building all..."
      #build_all_ffmpeg_dependencies #1>>$LOG_FILE 2>&1
      #download_ffmpeg #1>>$LOG_FILE 2>&1
      install_ffmpeg #1>>$LOG_FILE 2>&1
      #configure_ffmpeg_kit #1>>$LOG_FILE 2>&1
      #install_ffmpeg_kit
      #create_windows_bundle
      exit 0
    fi

  # if [[ $build_dependencies_only == "n" || $build_dependencies_only == "no" || $build_dependencies_only == "0" ]]; then
  #   echo -e "searching for all local exe's (some may not have been built this round, NB)..."
  #   for file in $(find_all_build_exes); do
  #     echo -e "built $file"
  #   done
  # fi
fi