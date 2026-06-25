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

#ifndef FFMPEG_KIT_STATISTICS_H
#define FFMPEG_KIT_STATISTICS_H

#include "FFmpegKitObject.hpp"
#include <cstdint>

namespace ffmpegkit {

/**
 * Statistics entry class.
 */
class Statistics : public FFmpegKitObject {
public:
  Statistics(const long sessionId, const int videoFrameNumber,
             const float videoFps, const float videoQuality, const int64_t size,
             const double timeElapsed, const double time, const double bitrate,
             const double speed, const int64_t dupFrames,
             const int64_t dropFrames);

  long getSessionId();
  int getVideoFrameNumber();
  float getVideoFps();
  float getVideoQuality();
  int64_t getSize();
  double getTimeElapsed();
  double getTime();
  double getBitrate();
  double getSpeed();
  int64_t getDupFrames();
  int64_t getDropFrames();

private:
  const long _sessionId;
  const int _videoFrameNumber;
  const float _videoFps;
  const float _videoQuality;
  const int64_t _size;
  const double _timeElapsed;
  const double _time;
  const double _bitrate;
  const double _speed;
  const int64_t _dupFrames;
  const int64_t _dropFrames;
};

} // namespace ffmpegkit

#endif // FFMPEG_KIT_STATISTICS_H
