#!/usr/bin/env bash

if (( BASH_VERSINFO[0] < 5 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 5+ is required." >&2
    exit 1
fi

cd FFmpegKit/build
export ASAN_OPTIONS=detect_leaks=1:detect_odr_violation=0
./tests/ffmpegkit_tests > test.log 2>&1
echo "Test log saved to FFmpegKit/build/test.log"