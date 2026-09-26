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

#include "Log.hpp"

namespace {

constexpr char kReplacementCharacter[] = "\xEF\xBF\xBD";

// FFmpeg occasionally truncates a formatted log fragment at a byte limit. If
// that limit lands inside a multibyte character, passing the raw bytes through
// the C wrapper makes Dart's Utf8 decoder throw. Preserve valid UTF-8 exactly
// and replace each malformed sequence before it reaches any language binding.
std::string sanitizeUtf8(const char *message) {
  if (message == nullptr) return {};

  const auto *bytes = reinterpret_cast<const unsigned char *>(message);
  std::string result;
  result.reserve(std::char_traits<char>::length(message));

  while (*bytes != 0) {
    const unsigned char lead = *bytes;
    if (lead <= 0x7f) {
      result.push_back(static_cast<char>(lead));
      ++bytes;
      continue;
    }

    int continuationCount = 0;
    unsigned int codePoint = 0;
    unsigned int minimumCodePoint = 0;
    if (lead >= 0xc2 && lead <= 0xdf) {
      continuationCount = 1;
      codePoint = lead & 0x1f;
      minimumCodePoint = 0x80;
    } else if (lead >= 0xe0 && lead <= 0xef) {
      continuationCount = 2;
      codePoint = lead & 0x0f;
      minimumCodePoint = 0x800;
    } else if (lead >= 0xf0 && lead <= 0xf4) {
      continuationCount = 3;
      codePoint = lead & 0x07;
      minimumCodePoint = 0x10000;
    } else {
      result.append(kReplacementCharacter);
      ++bytes;
      continue;
    }

    bool valid = true;
    int availableContinuations = 0;
    for (int i = 1; i <= continuationCount; ++i) {
      const unsigned char next = bytes[i];
      if (next == 0 || (next & 0xc0) != 0x80) {
        valid = false;
        break;
      }
      ++availableContinuations;
      codePoint = (codePoint << 6) | (next & 0x3f);
    }

    if (!valid || codePoint < minimumCodePoint || codePoint > 0x10ffff ||
        (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
      result.append(kReplacementCharacter);
      bytes += 1 + availableContinuations;
      continue;
    }

    result.append(reinterpret_cast<const char *>(bytes),
                  static_cast<size_t>(continuationCount + 1));
    bytes += continuationCount + 1;
  }

  return result;
}

} // namespace

ffmpegkit::Log::Log(const long sessionId, const ffmpegkit::Level level,
                    const char *message)
    : _sessionId{sessionId}, _level{level}, _message{sanitizeUtf8(message)} {}

long ffmpegkit::Log::getSessionId() const { return _sessionId; }

ffmpegkit::Level ffmpegkit::Log::getLevel() const { return _level; }

const std::string& ffmpegkit::Log::getMessage() const { return _message; }
