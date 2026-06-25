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

#include "AbstractSession.hpp"
#include "FFmpegKit.hpp"
#include "FFmpegKitConfig.hpp"
#include "Log.hpp"
#include "LogCallback.hpp"
#include "ReturnCode.hpp"
#include <atomic>
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <stdarg.h>
#include <sys/time.h>

static std::atomic<long> sessionIdGenerator(1);

extern void
addSessionToSessionHistory(const std::shared_ptr<ffmpegkit::Session> session);

ffmpegkit::AbstractSession::AbstractSession(
    const std::list<std::string> &arguments,
    const ffmpegkit::LogCallback logCallback,
    const LogRedirectionStrategy logRedirectionStrategy)
    : _sessionId{sessionIdGenerator++}, _logCallback{logCallback},
      _debuggingEnabled{false}, _debugLog{""},
      _createTime{std::chrono::system_clock::now()},
      _arguments{std::make_shared<std::list<std::string>>(arguments)},
      _logs{std::make_shared<std::list<std::shared_ptr<ffmpegkit::Log>>>()},
      _state{SessionStateCreated}, _returnCode{nullptr},
      _logRedirectionStrategy{logRedirectionStrategy} {}


ffmpegkit::AbstractSession::~AbstractSession() {
  // Synchronize destruction with any final operations in other threads.
  // This helps ThreadSanitizer understand the happens-before relationship
  // between session completion and its eventual cleanup.
  std::lock_guard<std::mutex> lock(_stateMutex);
}

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

void ffmpegkit::AbstractSession::waitForAsynchronousMessagesInTransmit(
    const int timeout) const {
  FFmpegKitConfig::waitForSessionMessagesInTransmit(_sessionId, timeout);
}

ffmpegkit::LogCallback ffmpegkit::AbstractSession::getLogCallback() const {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _logCallback;
}

long ffmpegkit::AbstractSession::getSessionId() const { return _sessionId; }

std::chrono::time_point<std::chrono::system_clock>
ffmpegkit::AbstractSession::getCreateTime() const {
  return _createTime;
}

std::chrono::time_point<std::chrono::system_clock>
ffmpegkit::AbstractSession::getStartTime() const {
    std::lock_guard<std::mutex> lock(_stateMutex);
    return _startTime;
}

std::chrono::time_point<std::chrono::system_clock>
ffmpegkit::AbstractSession::getEndTime() const {
    std::lock_guard<std::mutex> lock(_stateMutex);
    return _endTime;
}

long ffmpegkit::AbstractSession::getDuration() const {
    std::lock_guard<std::mutex> lock(_stateMutex);
    const auto startTime = _startTime;
    const auto endTime = _endTime;
    // now compute outside lock if you prefer, but snapshot under it
    if (startTime.time_since_epoch() != std::chrono::microseconds(0) &&
        endTime.time_since_epoch() != std::chrono::microseconds(0)) {
        return std::chrono::duration_cast<std::chrono::milliseconds>(
                   endTime - startTime).count();
    }
    return 0;
}

std::shared_ptr<std::list<std::string>>
ffmpegkit::AbstractSession::getArguments() const {
  return _arguments;
}

std::string ffmpegkit::AbstractSession::getCommand() const {
  return ffmpegkit::FFmpegKitConfig::argumentsToString(_arguments);
}

std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Log>>>
ffmpegkit::AbstractSession::getAllLogsWithTimeout(const int waitTimeout) const {
  this->waitForAsynchronousMessagesInTransmit(waitTimeout);

  if (this->thereAreAsynchronousMessagesInTransmit()) {
    std::cout << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [WARNING] getAllLogsWithTimeout was called to return all logs but "
                 "there are still logs being transmitted for session id "
              << _sessionId << "." << std::endl;
  }

  return this->getLogs();
}
std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Log>>>
ffmpegkit::AbstractSession::getAllLogs() const {
  return this->getAllLogsWithTimeout(
      ffmpegkit::AbstractSession::
          DefaultTimeoutForAsynchronousMessagesInTransmit);
}

std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Log>>>
ffmpegkit::AbstractSession::getLogs() const {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return std::make_shared<std::list<std::shared_ptr<ffmpegkit::Log>>>(*_logs);
}

int64_t ffmpegkit::AbstractSession::getLogsCount() const {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _logs->size();
}

std::shared_ptr<ffmpegkit::Log> ffmpegkit::AbstractSession::getLogAt(int64_t index) const {
  std::lock_guard<std::mutex> lock(_stateMutex);
  if (index >= 0 && index < _logs->size()) {
      auto it = _logs->begin();
      std::advance(it, index);
      return *it;
  }
  return nullptr;
}

std::string ffmpegkit::AbstractSession::getAllLogsAsStringWithTimeout(
    const int waitTimeout) const {
  this->waitForAsynchronousMessagesInTransmit(waitTimeout);

  if (this->thereAreAsynchronousMessagesInTransmit()) {
    std::cout << "[" << getCurrentTimeStamp() << "] [ffmpeg-kit] [WARNING] getAllLogsAsStringWithTimeout was called to return all logs "
                 "but there are still logs being transmitted for session id "
              << _sessionId << "." << std::endl;
  }

  return this->getLogsAsString();
}

std::string ffmpegkit::AbstractSession::getAllLogsAsString() const {
  return this->getAllLogsAsStringWithTimeout(
      ffmpegkit::AbstractSession::
          DefaultTimeoutForAsynchronousMessagesInTransmit);
}

std::string ffmpegkit::AbstractSession::getLogsAsString() const {
  std::lock_guard<std::mutex> lock(_stateMutex);
  std::string concatenatedString;

  if (_logs) {
      for (const auto& log : *_logs) {
          concatenatedString.append(log->getMessage());
      }
  }

  return concatenatedString;
}

std::string ffmpegkit::AbstractSession::getOutput() const {
  return this->getAllLogsAsString();
}

ffmpegkit::SessionState ffmpegkit::AbstractSession::getState() const {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _state;
}

std::shared_ptr<ffmpegkit::ReturnCode>
ffmpegkit::AbstractSession::getReturnCode() const {
    std::lock_guard<std::mutex> lock(_stateMutex);
    return _returnCode;
}

std::string ffmpegkit::AbstractSession::getFailStackTrace() const {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _failStackTrace;
}

ffmpegkit::LogRedirectionStrategy
ffmpegkit::AbstractSession::getLogRedirectionStrategy() const {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _logRedirectionStrategy;
}

bool ffmpegkit::AbstractSession::thereAreAsynchronousMessagesInTransmit()
    const {
  return (FFmpegKitConfig::messagesInTransmit(_sessionId) != 0);
}

void ffmpegkit::AbstractSession::addLog(
    const std::shared_ptr<ffmpegkit::Log> log) {
  std::lock_guard<std::mutex> lock(_stateMutex);
  _logs->push_back(log);
}

void ffmpegkit::AbstractSession::startRunning() {
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    _state = SessionStateRunning;
    _startTime = std::chrono::system_clock::now();
  }
  this->debugLog("AbstractSession::startRunning session=%ld state=RUNNING", _sessionId);
}

void ffmpegkit::AbstractSession::complete(
    const std::shared_ptr<ffmpegkit::ReturnCode> returnCode) {
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    _returnCode = returnCode;
    _state = SessionStateCompleted;
    _endTime = std::chrono::system_clock::now();
    _stateConditionVariable.notify_all();
  }
  this->debugLog("AbstractSession::complete session=%ld state=COMPLETED return=%d", _sessionId, returnCode ? returnCode->getValue() : 0);
}

void ffmpegkit::AbstractSession::fail(const char *error) {
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    _failStackTrace = error;
    _state = SessionStateFailed;
    _endTime = std::chrono::system_clock::now();
    _stateConditionVariable.notify_all();
  }
  this->debugLog("AbstractSession::fail session=%ld state=FAILED error=%s", _sessionId, error ? error : "");
}

bool ffmpegkit::AbstractSession::isFFmpeg() const {
  // IMPLEMENTED IN SUBCLASSES
  return false;
}

bool ffmpegkit::AbstractSession::isFFprobe() const {
  // IMPLEMENTED IN SUBCLASSES
  return false;
}

bool ffmpegkit::AbstractSession::isMediaInformation() const {
  // IMPLEMENTED IN SUBCLASSES
  return false;
}

bool ffmpegkit::AbstractSession::isFFplay() const {
  // IMPLEMENTED IN SUBCLASSES
  return false;
}

void ffmpegkit::AbstractSession::cancel() {
  this->debugLog("AbstractSession::cancel session=%ld", _sessionId);
  SessionState currentState;
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    currentState = _state;
  }
  if (currentState == SessionStateRunning) {
    this->debugLog("AbstractSession::cancel dispatch session=%ld", _sessionId);
    FFmpegKit::cancel(_sessionId);
  }
}

void ffmpegkit::AbstractSession::wait() {
  std::unique_lock<std::mutex> lock(_stateMutex);
  _stateConditionVariable.wait(lock, [this] {
    return _state == SessionStateCompleted || _state == SessionStateFailed;
  });
}

bool ffmpegkit::AbstractSession::waitFor(int timeout) {
  std::unique_lock<std::mutex> lock(_stateMutex);
  return _stateConditionVariable.wait_for(lock, std::chrono::milliseconds(timeout), [this] {
    return _state == SessionStateCompleted || _state == SessionStateFailed;
  });
}

void ffmpegkit::AbstractSession::debugLog(const char *fmt, ...) {
    if (!_debuggingEnabled.load(std::memory_order_relaxed)) return;

    // 1. Properly format the variadic arguments (evaluate %ld, %s, etc.)
    va_list args1;
    va_start(args1, fmt);
    va_list args2;
    va_copy(args2, args1);

    // Calculate required buffer size
    int len = std::vsnprintf(nullptr, 0, fmt, args1);
    va_end(args1);
    if (len < 0) {
        va_end(args2);
        return;
    }
    
    // Write formatted string to buffer
    std::vector<char> buffer(len + 1);
    std::vsnprintf(buffer.data(), buffer.size(), fmt, args2);
    va_end(args2);
    std::string logMessage = std::string("[") + getCurrentTimeStamp() + "] " +
                             "[ffmpeg-kit] [DEBUG] " + buffer.data() + "\n";

    {
        std::lock_guard<std::mutex> lock(_debugLogMutex);
        // Optional: Prevent unbounded memory growth (Cap log at ~1MB)
        if (_debugLog.size() > 1024 * 1024) {
             // Erase the oldest half of the logs to free memory
             _debugLog.erase(0, 512 * 1024);
             _debugLog += "\n[... PREVIOUS LOGS TRUNCATED FOR MEMORY ...]\n";
        }

        _debugLog += logMessage;
    }

    std::shared_ptr<ffmpegkit::Log> log = std::make_shared<ffmpegkit::Log>(
        _sessionId, ffmpegkit::LevelAVLogDebug, logMessage.c_str());

    ffmpegkit::LogCallback sessionLogCallback = this->getLogCallback();
    if (sessionLogCallback != nullptr) {
        sessionLogCallback(log);
    }

    ffmpegkit::LogCallback globalLogCallback =
        ffmpegkit::FFmpegKitConfig::getLogCallback();
    if (globalLogCallback != nullptr) {
        globalLogCallback(log);
    }
}

void ffmpegkit::AbstractSession::clearDebugLog() {
    std::lock_guard<std::mutex> lock(_debugLogMutex);
    _debugLog = "";
}

std::string ffmpegkit::AbstractSession::getDebugLog() const {
    std::lock_guard<std::mutex> lock(_debugLogMutex);
    return _debugLog;
}

void ffmpegkit::AbstractSession::enableDebugLog() {
    _debuggingEnabled.store(true, std::memory_order_relaxed);
}

void ffmpegkit::AbstractSession::disableDebugLog() {
    _debuggingEnabled.store(false, std::memory_order_relaxed);
}

bool ffmpegkit::AbstractSession::isDebugLogEnabled() const {
    return _debuggingEnabled.load(std::memory_order_relaxed);
}

void ffmpegkit::AbstractSession::setLogCallback(const LogCallback logCallback) {
    std::lock_guard<std::mutex> lock(_stateMutex);
    _logCallback = logCallback;
}
