/*
 * Copyright (c) 2025 Akash Patel
 *
 * This file is part of FFmpegKit.
 *
 * FFmpegKit is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * FFmpegKit is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General License for more details.
 *
 *  You should have received a copy of the GNU Lesser General License
 *  along with FFmpegKit.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef FFMPEG_KIT_PACKAGES_H
#define FFMPEG_KIT_PACKAGES_H

#include <memory>
#include <set>
#include <string>
#include <mutex>

namespace ffmpegkit {

/**
 * <p>Helper class to extract binary package information.
 */
class Packages {
private:
  static std::mutex packages_mutex_;

public:
  /**
   * Returns the FFmpegKit binary package name.
   *
   * @return predicted FFmpegKit binary package name
   */
  static std::string getPackageName();

  /**
   * Returns enabled external libraries by FFmpeg.
   *
   * @return enabled external libraries
   */
  static std::shared_ptr<std::set<std::string>> getExternalLibraries();

  /**
   * Returns if GPL is enabled.
   *
   * @return true if GPL is enabled, false otherwise
   */
  static bool getIsGpl();

  /**
   * Returns if non-free is enabled.
   *
   * @return true if non-free is enabled, false otherwise
   */
  static bool getIsNonFree();

  /**
   * Returns the FFmpegKit bundle type.
   *
   * @return FFmpegKit bundle type
   */
  static std::string getBundleType();

  /**
   * Returns all codecs registered in the linked FFmpeg (both encoders and decoders).
   */
  static std::shared_ptr<std::set<std::string>> getRegisteredCodecs();

  /**
   * Returns all registered encoders.
   */
  static std::shared_ptr<std::set<std::string>> getRegisteredEncoders();

  /**
   * Returns all registered decoders.
   */
  static std::shared_ptr<std::set<std::string>> getRegisteredDecoders();

  /**
   * Returns all registered muxers (output formats).
   */
  static std::shared_ptr<std::set<std::string>> getRegisteredMuxers();

  /**
   * Returns all registered demuxers (input formats).
   */
  static std::shared_ptr<std::set<std::string>> getRegisteredDemuxers();

  /**
   * Returns all registered filters.
   */
  static std::shared_ptr<std::set<std::string>> getRegisteredFilters();

  /**
   * Returns all registered protocols (input and output).
   */
  static std::shared_ptr<std::set<std::string>> getRegisteredProtocols();

  /**
   * Returns all registered bitstream filters.
   */
  static std::shared_ptr<std::set<std::string>> getRegisteredBitStreamFilters();

  /**
   * Returns the FFmpeg build configuration string.
   */
  static std::string getBuildConfiguration();
};

} // namespace ffmpegkit

#endif // FFMPEG_KIT_PACKAGES_H
