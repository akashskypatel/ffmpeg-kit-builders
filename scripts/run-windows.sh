#!/bin/bash

#echo "${SCRIPTDIR}/variable.sh"
#echo "${SCRIPTDIR}/function.sh"

source "${SCRIPTDIR}/variable.sh"
source "${SCRIPTDIR}/function.sh"

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
    mkdir -p mac_helper_scripts
    cd mac_helper_scripts || exit
      if [[ ! -x readlink ]]; then
        # make some scripts behave like linux...
        curl -4 file://"$WINPATCHDIR"/md5sum.mac --fail > md5sum  || exit 1
        chmod u+x ./md5sum
        curl -4 file://"$WINPATCHDIR"/readlink.mac --fail > readlink  || exit 1
        chmod u+x ./readlink
      fi
      export PATH=$(pwd):$PATH
    cd ..
  fi

  cd "$work_dir" || exit
    if [[ $build_dependencies_only == "y" ]]; then
      build_ffmpeg_dependencies
    else
      build_ffmpeg_dependencies
      build_ffmpeg
    fi
  cd ..

  if [[ $build_dependencies_only == "n" ]]; then
    echo "searching for all local exe's (some may not have been built this round, NB)..."
    for file in $(find_all_build_exes); do
      echo "built $file"
    done
  fi
fi