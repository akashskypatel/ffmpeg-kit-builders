#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207

# ffmpeg windows cross compile helper extra script, see github repo README
# Copyright (C) 2023 FREE WING,Y.Sakamoto, the script is under the GPLv3, but output FFmpeg's executables aren't
# set -x

echo "This is Patch for Git clone from code.videolan.org"
# fatal: unable to access 'https://code.videolan.org/videolan/x264.git/': server certificate verification failed. CAfile: none CRLfile: none

echo "Disable Git server certificate verification"
git config --global http.sslverify false

