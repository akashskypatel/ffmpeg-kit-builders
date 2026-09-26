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

#ifndef FFMPEG_KIT_FFMPEG_SESSION_H
#define FFMPEG_KIT_FFMPEG_SESSION_H

#include "AbstractSession.hpp"
#include "FFmpegSessionCompleteCallback.hpp"
#include "StatisticsCallback.hpp"
#include "ffmpeg_lib.h"

#include <mutex>

namespace ffmpegkit {

/**
 * <p>An FFmpeg session.
 */
class FFmpegSession : public AbstractSession {
public:
  /**
   * Builds a new FFmpeg session.
   *
   * @param arguments command arguments
   * @return created session
   */
  static std::shared_ptr<ffmpegkit::FFmpegSession>
  create(const std::list<std::string> &arguments);

  /**
   * Builds a new FFmpeg session.
   *
   * @param arguments         command arguments
   * @param completeCallback  session specific complete callback
   * @return created session
   */
  static std::shared_ptr<ffmpegkit::FFmpegSession>
  create(const std::list<std::string> &arguments,
         ffmpegkit::FFmpegSessionCompleteCallback completeCallback);

  /**
   * Builds a new FFmpeg session.
   *
   * @param arguments             command arguments
   * @param completeCallback      session specific complete callback
   * @param logCallback           session specific log callback
   * @param statisticsCallback    session specific statistics callback
   * @return created session
   */
  static std::shared_ptr<ffmpegkit::FFmpegSession>
  create(const std::list<std::string> &arguments,
         ffmpegkit::FFmpegSessionCompleteCallback completeCallback,
         ffmpegkit::LogCallback logCallback,
         ffmpegkit::StatisticsCallback statisticsCallback);

  /**
   * Builds a new FFmpeg session.
   *
   * @param arguments               command arguments
   * @param completeCallback        session specific complete callback
   * @param logCallback             session specific log callback
   * @param statisticsCallback      session specific statistics callback
   * @param logRedirectionStrategy  session specific log redirection strategy
   * @return created session
   */
  static std::shared_ptr<ffmpegkit::FFmpegSession>
  create(const std::list<std::string> &arguments,
         ffmpegkit::FFmpegSessionCompleteCallback completeCallback,
         ffmpegkit::LogCallback logCallback,
         ffmpegkit::StatisticsCallback statisticsCallback,
         ffmpegkit::LogRedirectionStrategy logRedirectionStrategy);

  /**
   * Returns the session specific statistics callback.
   *
   * @return session specific statistics callback
   */
  ffmpegkit::StatisticsCallback getStatisticsCallback();

  /**
   * Returns the session specific complete callback.
   *
   * @return session specific complete callback
   */
  ffmpegkit::FFmpegSessionCompleteCallback getCompleteCallback();

  /**
   * Returns all statistics entries generated for this session. If there are
   * asynchronous messages that are not delivered yet, this method waits for
   * them until the given timeout.
   *
   * @param waitTimeout wait timeout for asynchronous messages in milliseconds
   * @return list of statistics entries generated for this session
   */
  std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Statistics>>>
  getAllStatisticsWithTimeout(const int waitTimeout);

  /**
   * Returns all statistics entries generated for this session. If there are
   * asynchronous messages that are not delivered yet, this method waits for
   * them until AbstractSessionDefaultTimeoutForAsynchronousMessagesInTransmit
   * expires.
   *
   * @return list of statistics entries generated for this session
   */
  std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Statistics>>>
  getAllStatistics();

  /**
   * Returns all statistics entries delivered for this session. Note that if
   * there are asynchronous messages that are not delivered yet, this method
   * will not wait for them and will return immediately.
   *
   * @return list of statistics entries received for this session
   */
  std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Statistics>>>
  getStatistics();

  /**
   * Returns the number of statistics entries received for this session.
   *
   * @return number of statistics entries received
   */
  int64_t getStatisticsCount();

  /**
   * Returns the statistics entry at the given index.
   *
   * @param index statistics index
   * @return statistics entry at the given index or nullptr if it does not exist
   */
  std::shared_ptr<ffmpegkit::Statistics> getStatisticsAt(int64_t index);

  /**
   * Returns the last received statistics entry.
   *
   * @return the last received statistics entry or nullptr if there are not any
   * statistics entries received
   */
  std::shared_ptr<ffmpegkit::Statistics> getLastReceivedStatistics();

  /**
   * Adds a new statistics entry for this session. It is invoked internally by
   * <code>FFmpegKit</code> library methods. Must not be used by user
   * applications.
   *
   * @param statistics statistics entry
   */
  void addStatistics(const std::shared_ptr<ffmpegkit::Statistics> statistics);

  /**
   * Returns whether it is an <code>FFmpeg</code> session or not.
   *
   * @return true if it is an <code>FFmpeg</code> session, false otherwise
   */
  bool isFFmpeg() const override;

  /**
   * Returns whether it is an <code>FFprobe</code> session or not.
   *
   * @return true if it is an <code>FFprobe</code> session, false otherwise
   */
  bool isFFprobe() const override;

  /**
   * Returns whether it is an <code>FFplay</code> session or not.
   *
   * @return true if it is an <code>FFplay</code> session, false otherwise
   */
  bool isFFplay() const override;

  /**
   * Returns whether it is a <code>MediaInformation</code> session or not.
   *
   * @return true if it is a <code>MediaInformation</code> session, false
   * otherwise
   */
  bool isMediaInformation() const override;

  /**
   * Binds the native ffmpeg context for active execution.
   */
  void setContext(FFmpegContext *context);

  /**
   * Atomically detaches and returns the native context. Once this returns,
   * cancellation can no longer acquire the context, so the caller may free it.
   */
  FFmpegContext *detachContext();

  /**
   * Records cancellation and stops the active FFmpeg scheduler, if present.
   * Unlike cancel(), this never dispatches back through FFmpegKit::cancel().
   */
  void requestCancel();

  /**
   * Cancels the ffmpeg session.
   */
  void cancel() override;

  /**
   * Sets the session specific complete callback.
   *
   * @param completeCallback session specific complete callback
   */
  void
  setCompleteCallback(const FFmpegSessionCompleteCallback completeCallback);

  /**
   * Sets the session specific statistics callback.
   *
   * @param statisticsCallback session specific statistics callback
   */
  void setStatisticsCallback(const StatisticsCallback statisticsCallback);

private:
  struct PublicFFmpegSession;

  /**
   * Builds a new FFmpeg session.
   *
   * @param arguments               command arguments
   * @param completeCallback        session specific complete callback
   * @param logCallback             session specific log callback
   * @param statisticsCallback      session specific statistics callback
   * @param logRedirectionStrategy  session specific log redirection strategy
   */
  FFmpegSession(const std::list<std::string> &arguments,
                ffmpegkit::FFmpegSessionCompleteCallback completeCallback,
                ffmpegkit::LogCallback logCallback,
                ffmpegkit::StatisticsCallback statisticsCallback,
                ffmpegkit::LogRedirectionStrategy logRedirectionStrategy);
  
private:
  ffmpegkit::StatisticsCallback _statisticsCallback;
  FFmpegSessionCompleteCallback _completeCallback;
  std::shared_ptr<std::list<std::shared_ptr<ffmpegkit::Statistics>>>
      _statistics;
  std::mutex _contextMutex;
  FFmpegContext *_context{nullptr};
};

} // namespace ffmpegkit

#endif // FFMPEG_KIT_FFMPEG_SESSION_H
