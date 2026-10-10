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
std::string sanitizeUtf8(const char *message) {
  std::string result;
  if (!message) {
    return result;
  }
  const auto *bytes = reinterpret_cast<const unsigned char *>(message);
  while (*bytes) {
    const unsigned char first = *bytes;
    if (first < 0x80) {
      result.push_back(static_cast<char>(first));
      ++bytes;
      continue;
    }
    const int length = first >= 0xC2 && first <= 0xDF ? 2 :
                       first >= 0xE0 && first <= 0xEF ? 3 :
                       first >= 0xF0 && first <= 0xF4 ? 4 : 0;
    bool valid = length != 0;
    for (int index = 1; valid && index < length; ++index) {
      if (!bytes[index] || (bytes[index] & 0xC0) != 0x80) valid = false;
    }
    if (valid && length == 3) {
      valid = !(first == 0xE0 && bytes[1] < 0xA0) &&
              !(first == 0xED && bytes[1] >= 0xA0);
    }
    if (valid && length == 4) {
      valid = !(first == 0xF0 && bytes[1] < 0x90) &&
              !(first == 0xF4 && bytes[1] > 0x8F);
    }
    if (valid) {
      result.append(reinterpret_cast<const char *>(bytes), length);
      bytes += length;
    } else {
      result.append("\xEF\xBF\xBD", 3);
      ++bytes;
    }
  }
  return result;
}
} // namespace

ffmpegkit::Log::Log(const long sessionId, const ffmpegkit::Level level,
                    const char *message)
    : _sessionId{sessionId}, _level{level},
      _message{sanitizeUtf8(message)} {
  if (!_message.empty() && _message.back() != '\n') {
    _message.push_back('\n');
  }
}

long ffmpegkit::Log::getSessionId() const { return _sessionId; }

ffmpegkit::Level ffmpegkit::Log::getLevel() const { return _level; }

const std::string& ffmpegkit::Log::getMessage() const { return _message; }

int64_t ffmpegkit::Log::getSequence() const { return _sequence; }

void ffmpegkit::Log::setSequence(const int64_t sequence) {
  _sequence = sequence;
}
