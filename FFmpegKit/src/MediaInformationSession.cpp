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

#include "MediaInformationSession.hpp"
#include "LogCallback.hpp"
#include "MediaInformation.hpp"

extern void
addSessionToSessionHistory(const std::shared_ptr<ffmpegkit::Session> session);

std::shared_ptr<ffmpegkit::MediaInformationSession>
ffmpegkit::MediaInformationSession::create(
    const std::list<std::string> &arguments) {
  auto session = std::static_pointer_cast<ffmpegkit::MediaInformationSession>(
      std::make_shared<
          ffmpegkit::MediaInformationSession::PublicMediaInformationSession>(
          arguments, nullptr, nullptr));
  addSessionToSessionHistory(session);
  return session;
}

std::shared_ptr<ffmpegkit::MediaInformationSession>
ffmpegkit::MediaInformationSession::create(
    const std::list<std::string> &arguments,
    ffmpegkit::MediaInformationSessionCompleteCallback completeCallback) {
  auto session = std::static_pointer_cast<ffmpegkit::MediaInformationSession>(
      std::make_shared<
          ffmpegkit::MediaInformationSession::PublicMediaInformationSession>(
          arguments, completeCallback, nullptr));
  addSessionToSessionHistory(session);
  return session;
}

std::shared_ptr<ffmpegkit::MediaInformationSession>
ffmpegkit::MediaInformationSession::create(
    const std::list<std::string> &arguments,
    ffmpegkit::MediaInformationSessionCompleteCallback completeCallback,
    ffmpegkit::LogCallback logCallback) {
  auto session = std::static_pointer_cast<ffmpegkit::MediaInformationSession>(
      std::make_shared<
          ffmpegkit::MediaInformationSession::PublicMediaInformationSession>(
          arguments, completeCallback, logCallback));
  addSessionToSessionHistory(session);
  return session;
}

struct ffmpegkit::MediaInformationSession::PublicMediaInformationSession
    : public ffmpegkit::MediaInformationSession {
  PublicMediaInformationSession(
      const std::list<std::string> &arguments,
      ffmpegkit::MediaInformationSessionCompleteCallback completeCallback,
      ffmpegkit::LogCallback logCallback)
      : MediaInformationSession(arguments, completeCallback, logCallback) {}
};

ffmpegkit::MediaInformationSession::MediaInformationSession(
    const std::list<std::string> &arguments,
    ffmpegkit::MediaInformationSessionCompleteCallback completeCallback,
    ffmpegkit::LogCallback logCallback)
    : ffmpegkit::AbstractSession(
          arguments, logCallback,
          ffmpegkit::LogRedirectionStrategyNeverPrintLogs),
      _completeCallback{completeCallback}, _mediaInformation{nullptr} {}

std::shared_ptr<ffmpegkit::MediaInformation>
ffmpegkit::MediaInformationSession::getMediaInformation() {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _mediaInformation;
}

void ffmpegkit::MediaInformationSession::setMediaInformation(
    const std::shared_ptr<ffmpegkit::MediaInformation> mediaInformation) {
  std::lock_guard<std::mutex> lock(_stateMutex);
  _mediaInformation = mediaInformation;
}

ffmpegkit::MediaInformationSessionCompleteCallback
ffmpegkit::MediaInformationSession::getCompleteCallback() {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _completeCallback;
}

bool ffmpegkit::MediaInformationSession::isFFmpeg() const { return false; }

bool ffmpegkit::MediaInformationSession::isFFprobe() const { return false; }

bool ffmpegkit::MediaInformationSession::isFFplay() const { return false; }

bool ffmpegkit::MediaInformationSession::isMediaInformation() const {
  return true;
}

void ffmpegkit::MediaInformationSession::setCompleteCallback(
    const MediaInformationSessionCompleteCallback completeCallback) {
  std::lock_guard<std::mutex> lock(_stateMutex);
  _completeCallback = completeCallback;
}

ffmpegkit::MediaInformationSession::~MediaInformationSession() {
  // Synchronize destruction of derived members to prevent TSAN data races
  // with background threads that might be actively setting them.
  std::lock_guard<std::mutex> lock(_stateMutex);
  _mediaInformation.reset();
}
