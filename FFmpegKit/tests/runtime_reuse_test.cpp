#include "ffmpeg_lib.h"
#include "ffplay_lib.h"
#include "ffprobe_lib.h"

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>
#include <thread>

namespace {

void writeLittleEndian16(std::ofstream &stream, std::uint16_t value) {
  const char bytes[] = {static_cast<char>(value & 0xff),
                        static_cast<char>((value >> 8) & 0xff)};
  stream.write(bytes, sizeof(bytes));
}

void writeLittleEndian32(std::ofstream &stream, std::uint32_t value) {
  const char bytes[] = {
      static_cast<char>(value & 0xff),
      static_cast<char>((value >> 8) & 0xff),
      static_cast<char>((value >> 16) & 0xff),
      static_cast<char>((value >> 24) & 0xff),
  };
  stream.write(bytes, sizeof(bytes));
}

bool createRuntimeReuseFixture(const std::filesystem::path &path) {
  constexpr std::uint32_t sampleRate = 8000;
  constexpr std::uint16_t channels = 1;
  constexpr std::uint16_t bitsPerSample = 16;
  constexpr std::uint32_t sampleCount = 1600; // 200 ms of silence.
  constexpr std::uint32_t bytesPerSample = bitsPerSample / 8;
  constexpr std::uint32_t dataSize = sampleCount * channels * bytesPerSample;
  constexpr std::uint32_t byteRate = sampleRate * channels * bytesPerSample;
  constexpr std::uint16_t blockAlign = channels * bytesPerSample;

  std::ofstream stream(path, std::ios::binary | std::ios::trunc);
  if (!stream)
    return false;

  stream.write("RIFF", 4);
  writeLittleEndian32(stream, 36 + dataSize);
  stream.write("WAVE", 4);
  stream.write("fmt ", 4);
  writeLittleEndian32(stream, 16);
  writeLittleEndian16(stream, 1); // PCM
  writeLittleEndian16(stream, channels);
  writeLittleEndian32(stream, sampleRate);
  writeLittleEndian32(stream, byteRate);
  writeLittleEndian16(stream, blockAlign);
  writeLittleEndian16(stream, bitsPerSample);
  stream.write("data", 4);
  writeLittleEndian32(stream, dataSize);

  for (std::uint32_t i = 0; i < sampleCount; i++)
    writeLittleEndian16(stream, 0);

  return stream.good();
}

std::filesystem::path runtimeReuseFixturePath() {
  return std::filesystem::temp_directory_path() /
         "ffmpegkit-runtime-reuse-fixture.wav";
}

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
      "ffplay -v error -autoexit -nodisp " + quoteCompatibilityArgument(input);
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
  const std::filesystem::path source = runtimeReuseFixturePath();
  ASSERT_TRUE(createRuntimeReuseFixture(source));

  const std::filesystem::path quoted =
      source.parent_path() / "runtime reuse - \"quoted\".wav";
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
  std::filesystem::remove(source, ec);
}

TEST(EmbeddedCliReuseTest, FFmpegOverwriteFlagsResetAfterFailure) {
  const std::filesystem::path source = runtimeReuseFixturePath();
  ASSERT_TRUE(createRuntimeReuseFixture(source));

  const std::filesystem::path output =
      source.parent_path() / "runtime-reuse-overwrite-output.wav";
  std::error_code ec;

  std::filesystem::copy_file(
      source, output, std::filesystem::copy_options::overwrite_existing, ec);
  ASSERT_FALSE(ec) << ec.message();

  {
    const std::string command =
        "ffmpeg -v error -n -i definitely-missing-runtime-reuse.wav -f null -";
    FFmpegContext *ctx = ffmpeg_init(command.c_str());
    ASSERT_NE(ctx, nullptr);
    EXPECT_NE(ffmpeg_run(ctx), 0);
    ffmpeg_free(ctx);
  }

  {
    const std::string command =
        "ffmpeg -v error -y -i " +
        quoteCompatibilityArgument(source.string()) +
        " -map 0 -c copy " + quoteCompatibilityArgument(output.string());
    FFmpegContext *ctx = ffmpeg_init(command.c_str());
    ASSERT_NE(ctx, nullptr);
    EXPECT_EQ(ffmpeg_run(ctx), 0);
    ffmpeg_free(ctx);
  }

  std::filesystem::remove(output, ec);
  std::filesystem::remove(source, ec);
}

TEST(EmbeddedCliReuseTest, FailedInvocationDoesNotPoisonFollowingRuns) {
  const std::filesystem::path source = runtimeReuseFixturePath();
  ASSERT_TRUE(createRuntimeReuseFixture(source));
  const std::string normalPath = source.string();

  {
    const std::string command =
        "ffmpeg -v error -i " + quoteCompatibilityArgument(normalPath) +
        " -i definitely-missing-runtime-reuse.wav -f null -";
    FFmpegContext *ctx = ffmpeg_init(command.c_str());
    ASSERT_NE(ctx, nullptr);
    EXPECT_NE(ffmpeg_run(ctx), 0);
    ffmpeg_free(ctx);
  }
  EXPECT_EQ(runFFmpegCompatibility(normalPath), 0);

  {
    const std::string command =
        "ffprobe -v error -show_format -i " +
        quoteCompatibilityArgument(normalPath) + " second-input.wav";
    FFprobeContext *ctx = ffprobe_init(command.c_str());
    ASSERT_NE(ctx, nullptr);
    EXPECT_NE(ffprobe_run(ctx), 0);
    ffprobe_free(ctx);
  }
  EXPECT_EQ(runFFmpegCompatibility(normalPath), 0);
  EXPECT_EQ(runFFprobeCompatibility(normalPath), 0);

  {
    const std::string command =
        "ffplay -v error -autoexit -nodisp " +
        quoteCompatibilityArgument(normalPath) + " second-input.wav";
    FFplayContext *ctx = ffplay_init(command.c_str(), nullptr);
    EXPECT_EQ(ctx, nullptr);
    if (ctx)
      ffplay_free(ctx);
  }

  EXPECT_EQ(runFFmpegCompatibility(normalPath), 0);
  EXPECT_EQ(runFFprobeCompatibility(normalPath), 0);
  EXPECT_TRUE(initializeAndDrainFFplayCompatibility(normalPath));

  std::error_code ec;
  std::filesystem::remove(source, ec);
}
#endif
