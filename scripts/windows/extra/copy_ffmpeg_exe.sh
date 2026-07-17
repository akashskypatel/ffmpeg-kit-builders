#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207

# ffmpeg windows cross compile helper extra script, see github repo README
# Copyright (C) 2023 FREE WING,Y.Sakamoto, the script is under the GPLv3, but output FFmpeg's executables aren't
# set -x

FFMPEG_VER="n4.4.4"
if [ -n "$1" ]; then
  FFMPEG_VER="$1"
fi

WIN_FFMPEG_DIR=/mnt/c/ffmpeg_tmp_$FFMPEG_VER

echo "FFmpeg $FFMPEG_VER for Windows"

echo "Copy FFmpeg execute files to Windows C:\ffmpeg_tmp_$FFMPEG_VER directory"

ls -l ./prebuilt/win64/ffmpeg_git_with_fdk_aac_$FFMPEG_VER/ff*.exe
ls -l ./prebuilt/win64/x264/x*.exe
ls -l ./prebuilt/win64/x265/8bit/x*.exe

mkdir ${WIN_FFMPEG_DIR}/
cp ./prebuilt/win64/ffmpeg_git_with_fdk_aac_$FFMPEG_VER/ff*.exe ${WIN_FFMPEG_DIR}/
cp ./prebuilt/win64/x264/x*.exe ${WIN_FFMPEG_DIR}/
cp ./prebuilt/win64/x265/8bit/x*.exe ${WIN_FFMPEG_DIR}/
rm ${WIN_FFMPEG_DIR}/ff*_g.exe

ls -l ${WIN_FFMPEG_DIR}/

