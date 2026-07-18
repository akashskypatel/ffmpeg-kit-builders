/*
 * Copyright (c) 2025 Akash Patel
 *
 * This file is part of FFmpegKit.
 *
 * FFmpegKit is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * FFmpegKit is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with FFmpegKit.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "ArchDetect.hpp"
extern "C" {
#include <libavutil/avutil.h>
}

extern void *ffmpegKitInitialize();

const void *_archDetectInitializer{ffmpegKitInitialize()};

std::string ffmpegkit::ArchDetect::getArch() {
  std::string buildConfiguration = avutil_configuration();
  std::string key = "--arch=";
  size_t pos = buildConfiguration.find(key);
  if (pos == std::string::npos) {
    return "";
  }
  pos += key.length();
  size_t end = buildConfiguration.find(" ", pos);
  if (end == std::string::npos) {
    return buildConfiguration.substr(pos);
  }
  return buildConfiguration.substr(pos, end - pos);
}
