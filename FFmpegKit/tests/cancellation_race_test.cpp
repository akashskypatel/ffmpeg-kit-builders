#include "FFmpegSession.hpp"
#include "FFmpegKitConfig.hpp"
#include "ffmpeg_lib.h"
#include <gtest/gtest.h>
#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <thread>

extern "C" int ffmpeg_kit_test_cancel_unready_graph(void);
extern "C" int ffmpeg_kit_test_cancel_ready_graph(void);

TEST(CancellationRaceTest, CancellationBeforeContextPublicationIsRemembered) {
  auto session = ffmpegkit::FFmpegSession::create({"-version"});
  session->requestCancel();
  const char *arguments[] = {"ffmpeg", "-version"};
  auto *context = ffmpeg_init_argv(2, arguments);
  ASSERT_NE(context, nullptr);
  ffmpeg_set_session_id(context, session->getSessionId());
  session->setContext(context);
  EXPECT_EQ(ffmpeg_cancel_requested(context), 1);
  EXPECT_EQ(session->detachContext(), context);
  EXPECT_EQ(session->detachContext(), nullptr);
  ffmpeg_free(context);
  session->requestCancel();
}

TEST(CancellationRaceTest, CancellationBeforeGraphReadinessSkipsIncompleteGraph) {
  EXPECT_EQ(ffmpeg_kit_test_cancel_unready_graph(), 0);
}

TEST(CancellationRaceTest, CancellationBeforeExecutionCompletesSafely) {
  auto session = ffmpegkit::FFmpegSession::create(
      {"-hide_banner", "-loglevel", "fatal", "-f", "lavfi", "-i",
       "testsrc=duration=10:size=16x16:rate=30", "-f", "null", "-"});
  session->requestCancel();
  ffmpegkit::FFmpegKitConfig::ffmpegExecute(session);
  ASSERT_NE(session->getReturnCode(), nullptr);
  EXPECT_TRUE(session->getState() == ffmpegkit::SessionStateCompleted ||
              session->getState() == ffmpegkit::SessionStateFailed);
  EXPECT_EQ(session->detachContext(), nullptr);
  session->requestCancel();
}

TEST(CancellationRaceTest, CancellationAfterGraphReadinessStillWakesTasks) {
  EXPECT_EQ(ffmpeg_kit_test_cancel_ready_graph(), 0);
}

TEST(CancellationRaceTest, ConcurrentCancellationAndContextDetach) {
  int iterations = 100;
  if (const char *value = std::getenv("FFMPEG_KIT_CANCEL_RACE_ITERATIONS")) {
    iterations = std::max(1, std::atoi(value));
  }
  for (int iteration = 0; iteration < iterations; ++iteration) {
    SCOPED_TRACE(iteration);
    auto session = ffmpegkit::FFmpegSession::create({"-version"});
    const char *arguments[] = {"ffmpeg", "-version"};
    auto *context = ffmpeg_init_argv(2, arguments);
    ASSERT_NE(context, nullptr);
    ffmpeg_set_session_id(context, session->getSessionId());
    session->setContext(context);
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    auto cancel = [&] {
      ready.fetch_add(1);
      while (!go.load()) std::this_thread::yield();
      session->requestCancel();
    };
    std::thread first(cancel);
    std::thread second(cancel);
    while (ready.load() != 2) std::this_thread::yield();
    go.store(true);
    auto *detached = session->detachContext();
    EXPECT_EQ(detached, context);
    ffmpeg_free(detached);
    first.join();
    second.join();
    EXPECT_EQ(session->detachContext(), nullptr);
    session->requestCancel();
  }
}

TEST(CancellationRaceTest, ConcurrentCancellationDuringExecution) {
  int iterations = 100;
  if (const char *value = std::getenv("FFMPEG_KIT_CANCEL_RACE_ITERATIONS")) {
    iterations = std::max(1, std::atoi(value));
  }
  for (int iteration = 0; iteration < iterations; ++iteration) {
    SCOPED_TRACE(iteration);
    auto session = ffmpegkit::FFmpegSession::create(
        {"-hide_banner", "-loglevel", "fatal", "-f", "lavfi", "-i",
         "testsrc=duration=1:size=16x16:rate=30", "-filter_complex",
         "[0:v]null[filtered]", "-map", "[filtered]", "-f", "null", "-"});
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    auto start = [&] {
      ready.fetch_add(1);
      while (!go.load()) std::this_thread::yield();
    };
    std::thread worker([&] {
      start();
      ffmpegkit::FFmpegKitConfig::ffmpegExecute(session);
    });
    std::thread first([&] { start(); session->requestCancel(); });
    std::thread second([&] { start(); session->requestCancel(); });
    while (ready.load() != 3) std::this_thread::yield();
    go.store(true);
    worker.join();
    first.join();
    second.join();
    EXPECT_NE(session->getReturnCode(), nullptr);
    EXPECT_EQ(session->detachContext(), nullptr);
    session->requestCancel();
  }
}

TEST(CancellationRaceTest, CancellationDoesNotLeakToSequentialIndependentSession) {
  auto cancelledSession = ffmpegkit::FFmpegSession::create(
      {"-hide_banner", "-loglevel", "fatal", "-f", "lavfi", "-i",
       "testsrc=duration=2:size=16x16:rate=30", "-f", "null", "-"});
  cancelledSession->requestCancel();
  ffmpegkit::FFmpegKitConfig::ffmpegExecute(cancelledSession);
  ASSERT_NE(cancelledSession->getReturnCode(), nullptr);

  auto independentSession = ffmpegkit::FFmpegSession::create(
      {"-hide_banner", "-loglevel", "fatal", "-f", "lavfi", "-i",
       "testsrc=duration=1:size=16x16:rate=1", "-f", "null", "-"});
  ffmpegkit::FFmpegKitConfig::ffmpegExecute(independentSession);

  ASSERT_NE(independentSession->getReturnCode(), nullptr);
  EXPECT_EQ(independentSession->getReturnCode()->getValue(), 0);
  EXPECT_EQ(independentSession->getState(), ffmpegkit::SessionStateCompleted);
}

TEST(CancellationRaceTest, SuccessfulTranscodeUnchangedByGraphReadinessGuard) {
  auto session = ffmpegkit::FFmpegSession::create(
      {"-hide_banner", "-loglevel", "fatal", "-f", "lavfi", "-i",
       "testsrc=duration=1:size=16x16:rate=1", "-filter_complex",
       "[0:v]null[filtered]", "-map", "[filtered]", "-f", "null", "-"});
  ffmpegkit::FFmpegKitConfig::ffmpegExecute(session);

  ASSERT_NE(session->getReturnCode(), nullptr);
  EXPECT_EQ(session->getReturnCode()->getValue(), 0);
  EXPECT_EQ(session->getState(), ffmpegkit::SessionStateCompleted);
}
