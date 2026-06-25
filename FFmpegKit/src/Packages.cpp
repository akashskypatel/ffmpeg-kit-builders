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

#include "Packages.hpp"
extern "C" {
#include <libavutil/avutil.h>
#include <libavcodec/avcodec.h>
#include <libavcodec/codec.h>
#include <libavformat/avformat.h>
#include <libavfilter/avfilter.h>
#include <libavdevice/avdevice.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavcodec/bsf.h>
}
#include <memory>
#include <mutex>

// Static mutex definition
std::mutex ffmpegkit::Packages::packages_mutex_;

std::string ffmpegkit::Packages::getPackageName() {
  std::string bundleType = getBundleType();
  return bundleType;
}

bool ffmpegkit::Packages::getIsGpl() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  std::string cfg = avutil_configuration();
  // Match "--enable-gpl" as a complete flag (not "--enable-gpl3" etc.)
  std::string flag = "--enable-gpl";
  size_t pos = cfg.find(flag);
  while (pos != std::string::npos) {
    size_t end = pos + flag.length();
    if (end >= cfg.length() || cfg[end] == ' ' || cfg[end] == '\t') {
      return true;
    }
    pos = cfg.find(flag, end);
  }
  return false;
}

bool ffmpegkit::Packages::getIsNonFree() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  std::string cfg = avutil_configuration();
  // Match "--enable-nonfree" as a complete flag
  std::string flag = "--enable-nonfree";
  size_t pos = cfg.find(flag);
  while (pos != std::string::npos) {
    size_t end = pos + flag.length();
    if (end >= cfg.length() || cfg[end] == ' ' || cfg[end] == '\t') {
      return true;
    }
    pos = cfg.find(flag, end);
  }
  return false;
}

std::string ffmpegkit::Packages::getBundleType() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  std::string bundleType = FFMPEG_KIT_BUNDLE_TYPE;
  return bundleType;
}

std::shared_ptr<std::set<std::string>>
ffmpegkit::Packages::getExternalLibraries() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  auto enabledLibrarySet = std::make_shared<std::set<std::string>>();
  std::string buildConfiguration(avutil_configuration());
  
  // Parse all --enable-lib* flags dynamically instead of checking a hardcoded list
  std::string searchToken = "--enable-lib";
  size_t pos = 0;
  while ((pos = buildConfiguration.find(searchToken, pos)) != std::string::npos) {
    pos += searchToken.length();
    size_t end = buildConfiguration.find_first_of(" \t", pos);
    std::string libName = (end != std::string::npos) 
        ? buildConfiguration.substr(pos, end - pos) 
        : buildConfiguration.substr(pos);
    if (!libName.empty()) {
      enabledLibrarySet->insert(libName);
    }
  }
  
  // Also parse non-lib --enable-* flags that are known external libraries
  // (e.g., --enable-openssl, --enable-opencl, --enable-vulkan, etc.)
  const std::set<std::string> nonLibPrefixed = {
    "alsa", "amf", "appkit", "audiotoolbox", "avfoundation", "avisynth",
    "coreimage", "cuda-llvm", "cuda-nvcc", "cuvid", "d3d11va", "d3d12va",
    "drm", "dxva2", "ffnvcodec", "iconv", "jni", "ladspa", "lv2",
    "mediacodec", "mediafoundation", "metal", "nvdec", "nvenc",
    "opencl", "opengl", "openssl", "rkmpp", "schannel", "securetransport",
    "v4l2", "v4l2-m2m", "vaapi", "vdpau", "videotoolbox", "vulkan",
    "xlib", "mbedtls", "gnutls"
  };
  for (const auto& lib : nonLibPrefixed) {
    std::string flag = "--enable-" + lib;
    if (buildConfiguration.find(flag) != std::string::npos) {
      enabledLibrarySet->insert(lib);
    }
  }
  
  return enabledLibrarySet;
}

std::shared_ptr<std::set<std::string>> ffmpegkit::Packages::getRegisteredCodecs() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  auto codecs = std::make_shared<std::set<std::string>>();
  const AVCodec *codec = nullptr;
  void *iter = nullptr;
  while ((codec = av_codec_iterate(&iter))) {
    codecs->insert(codec->name);
  }
  return codecs;
}

std::shared_ptr<std::set<std::string>> ffmpegkit::Packages::getRegisteredEncoders() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  auto encoders = std::make_shared<std::set<std::string>>();
  const AVCodec *codec = nullptr;
  void *iter = nullptr;
  while ((codec = av_codec_iterate(&iter))) {
    if (av_codec_is_encoder(codec)) {
      encoders->insert(codec->name);
    }
  }
  return encoders;
}

std::shared_ptr<std::set<std::string>> ffmpegkit::Packages::getRegisteredDecoders() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  auto decoders = std::make_shared<std::set<std::string>>();
  const AVCodec *codec = nullptr;
  void *iter = nullptr;
  while ((codec = av_codec_iterate(&iter))) {
    if (av_codec_is_decoder(codec)) {
      decoders->insert(codec->name);
    }
  }
  return decoders;
}

std::shared_ptr<std::set<std::string>> ffmpegkit::Packages::getRegisteredMuxers() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  auto muxers = std::make_shared<std::set<std::string>>();
  const AVOutputFormat *ofmt = nullptr;
  void *iter = nullptr;
  while ((ofmt = av_muxer_iterate(&iter))) {
    muxers->insert(ofmt->name);
  }
  return muxers;
}

std::shared_ptr<std::set<std::string>> ffmpegkit::Packages::getRegisteredDemuxers() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  auto demuxers = std::make_shared<std::set<std::string>>();
  const AVInputFormat *ifmt = nullptr;
  void *iter = nullptr;
  while ((ifmt = av_demuxer_iterate(&iter))) {
    demuxers->insert(ifmt->name);
  }
  return demuxers;
}

std::shared_ptr<std::set<std::string>> ffmpegkit::Packages::getRegisteredFilters() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  auto filters = std::make_shared<std::set<std::string>>();
  const AVFilter *filter = nullptr;
  void *iter = nullptr;
  while ((filter = av_filter_iterate(&iter))) {
    filters->insert(filter->name);
  }
  return filters;
}

std::shared_ptr<std::set<std::string>> ffmpegkit::Packages::getRegisteredProtocols() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  auto protocols = std::make_shared<std::set<std::string>>();
  void *opaque = nullptr;
  const char *name;
  // Input protocols
  while ((name = avio_enum_protocols(&opaque, 0))) {
    protocols->insert(name);
  }
  // Output protocols
  opaque = nullptr;
  while ((name = avio_enum_protocols(&opaque, 1))) {
    protocols->insert(name);
  }
  return protocols;
}

std::shared_ptr<std::set<std::string>> ffmpegkit::Packages::getRegisteredBitStreamFilters() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  auto bsfs = std::make_shared<std::set<std::string>>();
  const AVBitStreamFilter *bsf = nullptr;
  void *iter = nullptr;
  while ((bsf = av_bsf_iterate(&iter))) {
    bsfs->insert(bsf->name);
  }
  return bsfs;
}

std::string ffmpegkit::Packages::getBuildConfiguration() {
  std::lock_guard<std::mutex> lock(packages_mutex_);
  return std::string(avutil_configuration());
}