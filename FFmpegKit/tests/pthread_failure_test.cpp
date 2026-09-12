#include <gtest/gtest.h>

#include "FFmpegKitConfig.hpp"
#include "FFmpegSession.hpp"
#include "FFplaySession.hpp"
#include "FFprobeSession.hpp"
#include "MediaInformationSession.hpp"
#include "SessionState.hpp"

#include <atomic>
#include <memory>

namespace {

using ffmpegkit::FFmpegKitConfig;

template <typename SessionType>
void expect_failed_startup(const std::shared_ptr<SessionType> &session,
                           const std::atomic<int> &callbackCount) {
  ASSERT_NE(session, nullptr);
  EXPECT_TRUE(session->waitFor(1000));
  EXPECT_EQ(session->getState(), ffmpegkit::SessionStateFailed);
  EXPECT_FALSE(session->getFailStackTrace().empty());
  EXPECT_EQ(callbackCount.load(std::memory_order_acquire), 1);
  FFmpegKitConfig::setPthreadCreateFailuresForTesting(0);
}

template <typename SessionType>
void expect_successful_startup(const std::shared_ptr<SessionType> &session) {
  ASSERT_NE(session, nullptr);
  EXPECT_TRUE(session->waitFor(10000));
  EXPECT_NE(session->getState(), ffmpegkit::SessionStateRunning);
}

}  // namespace

TEST(PthreadFailureTest, RedirectionFailureRestoresStateAndAllowsRetry) {
  FFmpegKitConfig::disableRedirection();
  ASSERT_FALSE(FFmpegKitConfig::isRedirectionEnabledForTesting());
  FFmpegKitConfig::setPthreadCreateFailuresForTesting(1);
  FFmpegKitConfig::enableRedirection();
  EXPECT_FALSE(FFmpegKitConfig::isRedirectionEnabledForTesting());
  FFmpegKitConfig::setPthreadCreateFailuresForTesting(0);
  FFmpegKitConfig::enableRedirection();
  EXPECT_TRUE(FFmpegKitConfig::isRedirectionEnabledForTesting());
  FFmpegKitConfig::disableRedirection();
}

TEST(PthreadFailureTest, FFmpegStartupFailureIsTerminalAndNotifies) {
  std::atomic<int> callbackCount{0};
  auto session = ffmpegkit::FFmpegSession::create(
      FFmpegKitConfig::parseArguments("-version"),
      [&](std::shared_ptr<ffmpegkit::FFmpegSession>) { callbackCount++; });
  FFmpegKitConfig::setPthreadCreateFailuresForTesting(1);
  FFmpegKitConfig::asyncFFmpegExecute(session);
  expect_failed_startup(session, callbackCount);
}

TEST(PthreadFailureTest, FFprobeStartupFailureIsTerminalAndNotifies) {
  std::atomic<int> callbackCount{0};
  auto session = ffmpegkit::FFprobeSession::create(
      FFmpegKitConfig::parseArguments("-version"),
      [&](std::shared_ptr<ffmpegkit::FFprobeSession>) { callbackCount++; });
  FFmpegKitConfig::setPthreadCreateFailuresForTesting(1);
  FFmpegKitConfig::asyncFFprobeExecute(session);
  expect_failed_startup(session, callbackCount);
}

TEST(PthreadFailureTest, FFplayStartupFailureIsTerminalAndNotifies) {
  std::atomic<int> callbackCount{0};
  auto session = ffmpegkit::FFplaySession::create(
      FFmpegKitConfig::parseArguments("-version"),
      [&](std::shared_ptr<ffmpegkit::FFplaySession>) { callbackCount++; });
  FFmpegKitConfig::setPthreadCreateFailuresForTesting(1);
  FFmpegKitConfig::asyncFFplayExecute(session, 100);
  expect_failed_startup(session, callbackCount);
}

TEST(PthreadFailureTest, MediaInformationStartupFailureIsTerminalAndNotifies) {
  std::atomic<int> callbackCount{0};
  auto session = ffmpegkit::MediaInformationSession::create(
      FFmpegKitConfig::parseArguments("-i /definitely/missing/callback-test-input"),
      [&](std::shared_ptr<ffmpegkit::MediaInformationSession>) {
        callbackCount++;
      });
  FFmpegKitConfig::setPthreadCreateFailuresForTesting(1);
  FFmpegKitConfig::asyncGetMediaInformationExecute(session, 100);
  expect_failed_startup(session, callbackCount);
}

TEST(PthreadFailureTest, FFmpegStartupSuccessCreatesAndCompletesThread) {
  std::atomic<int> callbackCount{0};
  auto session = ffmpegkit::FFmpegSession::create(
      FFmpegKitConfig::parseArguments("-version"),
      [&](std::shared_ptr<ffmpegkit::FFmpegSession>) { callbackCount++; });
  FFmpegKitConfig::setPthreadCreateFailuresForTesting(0);
  FFmpegKitConfig::asyncFFmpegExecute(session);
  expect_successful_startup(session);
}

TEST(PthreadFailureTest, FFprobeStartupSuccessCreatesAndCompletesThread) {
  std::atomic<int> callbackCount{0};
  auto session = ffmpegkit::FFprobeSession::create(
      FFmpegKitConfig::parseArguments("-version"),
      [&](std::shared_ptr<ffmpegkit::FFprobeSession>) { callbackCount++; });
  FFmpegKitConfig::setPthreadCreateFailuresForTesting(0);
  FFmpegKitConfig::asyncFFprobeExecute(session);
  expect_successful_startup(session);
}

TEST(PthreadFailureTest, FFplayStartupSuccessCreatesAndCompletesThread) {
  std::atomic<int> callbackCount{0};
  auto session = ffmpegkit::FFplaySession::create(
      FFmpegKitConfig::parseArguments("-version"),
      [&](std::shared_ptr<ffmpegkit::FFplaySession>) { callbackCount++; });
  FFmpegKitConfig::setPthreadCreateFailuresForTesting(0);
  FFmpegKitConfig::asyncFFplayExecute(session, 100);
  expect_successful_startup(session);
  FFmpegKitConfig::joinAsyncFFplayThread();
}

TEST(PthreadFailureTest, MediaInformationStartupSuccessCreatesAndCompletesThread) {
  std::atomic<int> callbackCount{0};
  auto session = ffmpegkit::MediaInformationSession::create(
      FFmpegKitConfig::parseArguments("-i /definitely/missing/callback-test-input"),
      [&](std::shared_ptr<ffmpegkit::MediaInformationSession>) {
        callbackCount++;
      });
  FFmpegKitConfig::setPthreadCreateFailuresForTesting(0);
  FFmpegKitConfig::asyncGetMediaInformationExecute(session, 100);
  expect_successful_startup(session);
}
