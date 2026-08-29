#include "ffmpeg_lib.h"
#include "ffplay_lib.h"
#include "ffprobe_lib.h"

#include <chrono>
#include <filesystem>
#include <gtest/gtest.h>
#include <string>
#include <thread>

#ifndef FFMPEG_KIT_TEST_DIR
#define FFMPEG_KIT_TEST_DIR "."
#endif
#define TEST_VIDEO_FILE FFMPEG_KIT_TEST_DIR "/dummy_video.mp4"

namespace {

std::string quoteCompatibilityArgument(const std::string &value) {
  std::string result = "\"";
  for (const char ch : value) {
    if (ch == '"')
      result += "\\\"";
    else
      result += ch;
  }
  result += "\"";
  return result;
}

int runFFmpegCompatibility(const std::string &input) {
  const std::string command =
      "ffmpeg -v error -i " + quoteCompatibilityArgument(input) +
      " -f null -";
  FFmpegContext *ctx = ffmpeg_init(command.c_str());
  if (!ctx)
    return -1000;
  const int result = ffmpeg_run(ctx);
  ffmpeg_free(ctx);
  return result;
}

int runFFprobeCompatibility(const std::string &input) {
  const std::string command =
      "ffprobe -v error -show_format -show_streams -i " +
      quoteCompatibilityArgument(input);
  FFprobeContext *ctx = ffprobe_init(command.c_str());
  if (!ctx)
    return -1000;
  const int result = ffprobe_run(ctx);
  ffprobe_free(ctx);
  return result;
}

bool initializeAndDrainFFplayCompatibility(const std::string &input) {
  const std::string command =
      "ffplay -v error -autoexit -an " + quoteCompatibilityArgument(input);
  FFplayContext *ctx = ffplay_init(command.c_str(), nullptr);
  if (!ctx)
    return false;

  bool sawMedia = false;
  bool ok = ffplay_start(ctx) == 0;
  if (ok) {
    for (int i = 0; i < 1000; i++) {
      if (ffplay_get_duration(ctx) > 0.0)
        sawMedia = true;
      if (ffplay_step(ctx) != 0)
        break;
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
  }
  ffplay_free(ctx);
  return ok && sawMedia;
}

} // namespace

#ifndef _WIN32
TEST(EmbeddedCliReuseTest, QuotedFilenameDoesNotPoisonSubsequentRuns) {
  const std::filesystem::path source(TEST_VIDEO_FILE);
  const std::filesystem::path quoted =
      source.parent_path() / "runtime reuse - \"quoted\".mp4";
  std::error_code ec;
  std::filesystem::copy_file(source, quoted,
                             std::filesystem::copy_options::overwrite_existing,
                             ec);
  ASSERT_FALSE(ec) << ec.message();

  const std::string quotedPath = quoted.string();
  const std::string normalPath = source.string();

  EXPECT_EQ(runFFmpegCompatibility(quotedPath), 0);
  EXPECT_EQ(runFFmpegCompatibility(normalPath), 0);

  EXPECT_EQ(runFFprobeCompatibility(quotedPath), 0);
  EXPECT_EQ(runFFprobeCompatibility(normalPath), 0);

  EXPECT_TRUE(initializeAndDrainFFplayCompatibility(quotedPath));
  EXPECT_TRUE(initializeAndDrainFFplayCompatibility(normalPath));

  std::filesystem::remove(quoted, ec);
}

TEST(EmbeddedCliReuseTest, FailedInvocationDoesNotPoisonFollowingRuns) {
  const std::string normalPath = std::filesystem::path(TEST_VIDEO_FILE).string();

  {
    const std::string command =
        "ffmpeg -v error -i definitely-missing-runtime-reuse.mp4 -f null -";
    FFmpegContext *ctx = ffmpeg_init(command.c_str());
    ASSERT_NE(ctx, nullptr);
    EXPECT_NE(ffmpeg_run(ctx), 0);
    ffmpeg_free(ctx);
  }
  EXPECT_EQ(runFFmpegCompatibility(normalPath), 0);

  {
    const std::string command =
        "ffprobe -v error -show_format -i " +
        quoteCompatibilityArgument(normalPath) + " second-input.mp4";
    FFprobeContext *ctx = ffprobe_init(command.c_str());
    ASSERT_NE(ctx, nullptr);
    EXPECT_NE(ffprobe_run(ctx), 0);
    ffprobe_free(ctx);
  }
  EXPECT_EQ(runFFmpegCompatibility(normalPath), 0);
  EXPECT_EQ(runFFprobeCompatibility(normalPath), 0);

  {
    const std::string command =
        "ffplay -v error -autoexit -an " +
        quoteCompatibilityArgument(normalPath) + " second-input.mp4";
    FFplayContext *ctx = ffplay_init(command.c_str(), nullptr);
    EXPECT_EQ(ctx, nullptr);
    if (ctx)
      ffplay_free(ctx);
  }

  EXPECT_EQ(runFFmpegCompatibility(normalPath), 0);
  EXPECT_EQ(runFFprobeCompatibility(normalPath), 0);
  EXPECT_TRUE(initializeAndDrainFFplayCompatibility(normalPath));
}
#endif
