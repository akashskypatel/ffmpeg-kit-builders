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
 * You should have received a copy of the GNU Lesser General License
 * along with FFmpegKit.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "FFmpegSession.hpp"
#include "FFmpegKitConfig.hpp"
#include "LogCallback.hpp"
#include "StatisticsCallback.hpp"
#include <mutex>
#include <sys/time.h>

extern void
addSessionToSessionHistory(const std::shared_ptr<ffmpegkit::Session> session);

static std::string getCurrentTimeStamp() {
  time_t now = time(0);
  struct tm *timeinfo = localtime(&now);
  char buffer[80];
  strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", timeinfo);
  struct timeval tv;
  gettimeofday(&tv, NULL);
  char milliseconds[4];
  snprintf(milliseconds, sizeof(milliseconds), "%03d", (int)(tv.tv_usec / 1000));
  return std::string(buffer) + "." + std::string(milliseconds);
}

std::shared_ptr<ffmpegkit::FFmpegSession>
ffmpegkit::FFmpegSession::create(const std::list<std::string> &arguments) {
  std::shared_ptr<ffmpegkit::FFmpegSession> session =
      std::static_pointer_cast<ffmpegkit::FFmpegSession>(
          std::make_shared<ffmpegkit::FFmpegSession::PublicFFmpegSession>(
              arguments, nullptr, nullptr, nullptr,
              ffmpegkit::FFmpegKitConfig::getLogRedirectionStrategy()));
  addSessionToSessionHistory(session);
  return session;
}

std::shared_ptr<ffmpegkit::FFmpegSession> ffmpegkit::FFmpegSession::create(
    const std::list<std::string> &arguments,
    FFmpegSessionCompleteCallback completeCallback) {
  std::shared_ptr<ffmpegkit::FFmpegSession> session =
      std::static_pointer_cast<ffmpegkit::FFmpegSession>(
          std::make_shared<ffmpegkit::FFmpegSession::PublicFFmpegSession>(
              arguments, completeCallback, nullptr, nullptr,
              ffmpegkit::FFmpegKitConfig::getLogRedirectionStrategy()));
  addSessionToSessionHistory(session);
  return session;
}

std::shared_ptr<ffmpegkit::FFmpegSession> ffmpegkit::FFmpegSession::create(
    const std::list<std::string> &arguments,
    FFmpegSessionCompleteCallback completeCallback,
    ffmpegkit::LogCallback logCallback,
    ffmpegkit::StatisticsCallback statisticsCallback) {
  std::shared_ptr<ffmpegkit::FFmpegSession> session =
      std::static_pointer_cast<ffmpegkit::FFmpegSession>(
          std::make_shared<ffmpegkit::FFmpegSession::PublicFFmpegSession>(
              arguments, completeCallback, logCallback, statisticsCallback,
              ffmpegkit::FFmpegKitConfig::getLogRedirectionStrategy()));
  addSessionToSessionHistory(session);
  return session;
}

std::shared_ptr<ffmpegkit::FFmpegSession> ffmpegkit::FFmpegSession::create(
    const std::list<std::string> &arguments,
    FFmpegSessionCompleteCallback completeCallback,
    ffmpegkit::LogCallback logCallback,
    ffmpegkit::StatisticsCallback statisticsCallback,
    LogRedirectionStrategy logRedirectionStrategy) {
  std::shared_ptr<ffmpegkit::FFmpegSession> session =
      std::static_pointer_cast<ffmpegkit::FFmpegSession>(
          std::make_shared<ffmpegkit::FFmpegSession::PublicFFmpegSession>(
              arguments, completeCallback, logCallback, statisticsCallback,
              logRedirectionStrategy));
  addSessionToSessionHistory(session);
  return session;
}

struct ffmpegkit::FFmpegSession::PublicFFmpegSession
    : public ffmpegkit::FFmpegSession {
  PublicFFmpegSession(const std::list<std::string> &arguments,
                      FFmpegSessionCompleteCallback completeCallback,
                      ffmpegkit::LogCallback logCallback,
                      ffmpegkit::StatisticsCallback statisticsCallback,
                      LogRedirectionStrategy logRedirectionStrategy)
      : FFmpegSession(arguments, completeCallback, logCallback,
                      statisticsCallback, logRedirectionStrategy) {}
};

ffmpegkit::FFmpegSession::FFmpegSession(
    const std::list<std::string> &arguments,
    FFmpegSessionCompleteCallback completeCallback,
    ffmpegkit::LogCallback logCallback,
    ffmpegkit::StatisticsCallback statisticsCallback,
    LogRedirectionStrategy logRedirectionStrategy)
    : ffmpegkit::AbstractSession(arguments, logCallback,
                                 logRedirectionStrategy),
      _completeCallback{completeCallback},
      _statisticsCallback{statisticsCallback},
      _statistics{std::make_shared<
          std::list<std::shared_ptr<ffmpegkit::Statistics>>>()} {}

ffmpegkit::StatisticsCallback
ffmpegkit::FFmpegSession::getStatisticsCallback() {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _statisticsCallback;
}

ffmpegkit::FFmpegSessionCompleteCallback
ffmpegkit::FFmpegSession::getCompleteCallback() {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _completeCallback;
}

std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Statistics>>>
ffmpegkit::FFmpegSession::getAllStatisticsWithTimeout(const int waitTimeout) {
  this->waitForAsynchronousMessagesInTransmit(waitTimeout);

  if (this->thereAreAsynchronousMessagesInTransmit()) {
    std::cout << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [INFO] "
        << "getAllStatisticsWithTimeout was called to return all statistics "
           "but there are still statistics being transmitted for session id "
        << this->getSessionId() << "." << std::endl;
  }

  return this->getStatistics();
}

std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Statistics>>>
ffmpegkit::FFmpegSession::getAllStatistics() {
  return this->getAllStatisticsWithTimeout(
      ffmpegkit::AbstractSession::
          DefaultTimeoutForAsynchronousMessagesInTransmit);
}

std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Statistics>>>
ffmpegkit::FFmpegSession::getStatistics() {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return std::make_shared<std::list<std::shared_ptr<ffmpegkit::Statistics>>>(
      *_statistics);
}

int64_t ffmpegkit::FFmpegSession::getStatisticsCount() {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _statistics->size();
}

std::shared_ptr<ffmpegkit::Statistics>
ffmpegkit::FFmpegSession::getStatisticsAt(int64_t index) {
  std::lock_guard<std::mutex> lock(_stateMutex);
  if (index >= 0 && index < _statistics->size()) {
    auto it = _statistics->begin();
    std::advance(it, index);
    return *it;
  }
  return nullptr;
}

std::shared_ptr<ffmpegkit::Statistics>
ffmpegkit::FFmpegSession::getLastReceivedStatistics() {
  std::lock_guard<std::mutex> lock(_stateMutex);
  if (_statistics->size() > 0) {
    return _statistics->back();
  } else {
    return nullptr;
  }
}

void ffmpegkit::FFmpegSession::addStatistics(
    const std::shared_ptr<ffmpegkit::Statistics> statistics) {
  std::lock_guard<std::mutex> lock(_stateMutex);
  _statistics->push_back(statistics);
}

FFmpegContext *ffmpegkit::FFmpegSession::getContext() {
  return _context.load(std::memory_order_acquire);
}

void ffmpegkit::FFmpegSession::setContext(FFmpegContext *context) {
  _context.store(context, std::memory_order_release);
}

bool ffmpegkit::FFmpegSession::isFFmpeg() const { return true; }

bool ffmpegkit::FFmpegSession::isFFprobe() const { return false; }

bool ffmpegkit::FFmpegSession::isFFplay() const { return false; }

bool ffmpegkit::FFmpegSession::isMediaInformation() const { return false; }

void ffmpegkit::FFmpegSession::cancel() {
  FFmpegContext *context = getContext();
  if (context != nullptr) {
    ffmpeg_cancel(context);
  }
  ffmpegkit::AbstractSession::cancel();
}

void ffmpegkit::FFmpegSession::setCompleteCallback(
    const FFmpegSessionCompleteCallback completeCallback) {
  std::lock_guard<std::mutex> lock(_stateMutex);
  _completeCallback = completeCallback;
}

void ffmpegkit::FFmpegSession::setStatisticsCallback(
    const StatisticsCallback statisticsCallback) {
  std::lock_guard<std::mutex> lock(_stateMutex);
  _statisticsCallback = statisticsCallback;
}
