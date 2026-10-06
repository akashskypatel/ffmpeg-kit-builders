#include <gtest/gtest.h>

#include <cctype>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>

namespace {

std::string read_source(const std::filesystem::path &path) {
  std::ifstream input(path);
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

std::string normalize_whitespace(const std::string &source) {
  std::string normalized;
  normalized.reserve(source.size());
  bool pending_space = false;
  for (const unsigned char character : source) {
    if (std::isspace(character)) {
      pending_space = true;
      continue;
    }
    if (pending_space && !normalized.empty()) normalized.push_back(' ');
    pending_space = false;
    normalized.push_back(static_cast<char>(character));
  }
  return normalized;
}

std::filesystem::path source_root() {
  return std::filesystem::path(FFMPEG_KIT_TEST_DIR).parent_path();
}

}  // namespace

TEST(FFplayRendererSourceContractTest,
     KeepsAppleRendererVisibleButSuppressesPresentation) {
  const auto library_source =
      read_source(source_root() / "src" / "ffplay_lib.c");
  ASSERT_FALSE(library_source.empty());
  const auto normalized = normalize_whitespace(library_source);

  EXPECT_NE(normalized.find(
                "#if !defined(__ANDROID__) && !defined(__APPLE__) #define "
                "SDL_ShowWindow(w)"),
            std::string::npos);
  EXPECT_NE(normalized.find(
                "#ifndef __ANDROID__ #define SDL_RenderPresent(r)"),
            std::string::npos);

  const auto apple_driver =
      normalized.find("SDL_SetHintWithPriority(SDL_HINT_VIDEODRIVER, \"dummy\"");
  const auto software_driver =
      normalized.find(
          "SDL_SetHintWithPriority(SDL_HINT_RENDER_DRIVER, \"software\"");
  EXPECT_NE(apple_driver, std::string::npos);
  EXPECT_NE(software_driver, std::string::npos);
}

TEST(FFplayRendererSourceContractTest,
     PreservesShowBeforeCompositionCaptureOrdering) {
  const auto ffplay_source = read_source(source_root() / "src" / "ffplay.c");
  ASSERT_FALSE(ffplay_source.empty());

  const auto video_open = ffplay_source.find("static int video_open");
  const auto show_window =
      ffplay_source.find("SDL_ShowWindow(is->window)", video_open);
  const auto video_display =
      ffplay_source.find("static void video_display", show_window);
  const auto draw_video =
      ffplay_source.find("video_image_display(is);", video_display);
  const auto capture =
      ffplay_source.find("ffplay_lib_capture_renderer(is->renderer);",
                         video_display);
  const auto present =
      ffplay_source.find("SDL_RenderPresent(is->renderer);", video_display);

  ASSERT_NE(video_open, std::string::npos);
  ASSERT_NE(show_window, std::string::npos);
  ASSERT_NE(video_display, std::string::npos);
  ASSERT_NE(draw_video, std::string::npos);
  ASSERT_NE(capture, std::string::npos);
  ASSERT_NE(present, std::string::npos);
  EXPECT_LT(video_open, show_window);
  EXPECT_LT(show_window, video_display);
  EXPECT_LT(draw_video, capture);
  EXPECT_LT(capture, present);
}

TEST(FFplayRendererSourceContractTest,
     KeepsWasmFunctionPointerRegistrationDisabled) {
  const auto wrapper_source =
      read_source(source_root() / "src" / "ffmpegkit_wrapper.cpp");
  ASSERT_FALSE(wrapper_source.empty());

  const auto registration =
      wrapper_source.find("ffplay_kit_register_frame_callback(");
  const auto wasm_branch =
      wrapper_source.find("#if defined(__EMSCRIPTEN__)", registration);
  const auto ignored_callback =
      wrapper_source.find("(void)callback", wasm_branch);
  const auto native_registration =
      wrapper_source.find("ffplay_set_frame_callback(", wasm_branch);

  ASSERT_NE(registration, std::string::npos);
  ASSERT_NE(wasm_branch, std::string::npos);
  ASSERT_NE(ignored_callback, std::string::npos);
  ASSERT_NE(native_registration, std::string::npos);
  EXPECT_LT(registration, wasm_branch);
  EXPECT_LT(wasm_branch, ignored_callback);
  EXPECT_LT(ignored_callback, native_registration);
}
