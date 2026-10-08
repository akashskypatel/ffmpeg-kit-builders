#include "FFmpegSession.hpp"
#include "ffmpeg_lib.h"

#include <atomic>
#include <cstdlib>
#include <gtest/gtest.h>
#include <thread>

namespace {

int raceIterations() {
  const char *configured = std::getenv("FFMPEG_KIT_CANCEL_RACE_ITERATIONS");
  if (!configured)
    return 10000;
  const int parsed = std::atoi(configured);
  return parsed > 0 ? parsed : 10000;
}

FFmpegContext *newContext(long id) {
  FFmpegContext *ctx = ffmpeg_init(
      "ffmpeg -v quiet -f lavfi -i anullsrc=r=8000:cl=mono "
      "-t 0.001 -f null -");
  if (ctx)
    ffmpeg_set_session_id(ctx, id);
  return ctx;
}

} // namespace

TEST(CancellationRaceTest, BeforeStartAndAfterCompletionAreIdempotent) {
  FFmpegContext *before = newContext(700001);
  ASSERT_NE(before, nullptr);
  ffmpeg_cancel(before);
  EXPECT_NE(ffmpeg_cancel_requested(before), 0);
  EXPECT_EQ(ffmpeg_run(before), 0);
  ffmpeg_cancel(before);
  ffmpeg_free(before);

  FFmpegContext *after = newContext(700002);
  ASSERT_NE(after, nullptr);
  EXPECT_EQ(ffmpeg_run(after), 0);
  ffmpeg_cancel(after);
  ffmpeg_cancel(after);
  ffmpeg_free(after);
}

TEST(CancellationRaceTest, SchedulerPublicationAndTeardown) {
  for (int i = 0; i < raceIterations(); ++i) {
    FFmpegContext *ctx = newContext(710000 + i);
    ASSERT_NE(ctx, nullptr) << "iteration " << i;

    std::thread runner([&] { EXPECT_EQ(ffmpeg_run(ctx), 0); });
    std::thread first([&] {
      for (int duplicate = 0; duplicate < 4; ++duplicate)
        ffmpeg_cancel(ctx);
    });
    std::thread second([&] {
      for (int duplicate = 0; duplicate < 4; ++duplicate)
        ffmpeg_cancel(ctx);
    });

    first.join();
    second.join();
    runner.join();
    ffmpeg_free(ctx);
  }
}

TEST(CancellationRaceTest, SessionContextDetachAndFree) {
  auto session = ffmpegkit::FFmpegSession::create({"-version"});
  ASSERT_NE(session, nullptr);

  for (int i = 0; i < raceIterations(); ++i) {
    FFmpegContext *ctx = newContext(session->getSessionId());
    ASSERT_NE(ctx, nullptr) << "iteration " << i;
    session->setContext(ctx);

    std::atomic<bool> go{false};
    std::thread canceller([&] {
      while (!go.load(std::memory_order_acquire)) {
      }
      session->requestCancel();
      session->requestCancel();
    });
    std::thread teardown([&] {
      go.store(true, std::memory_order_release);
      FFmpegContext *detached = session->detachContext();
      if (detached)
        ffmpeg_free(detached);
    });

    canceller.join();
    teardown.join();
    FFmpegContext *left = session->detachContext();
    if (left)
      ffmpeg_free(left);
  }
}
