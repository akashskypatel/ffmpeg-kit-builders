#include <gtest/gtest.h>
#include "ffmpegkit_wrapper.h"
#include <cstdlib>

TEST(FFmpegKitConfigTest, Redirection) {
    // Verify methods can be called without crashing
    ffmpeg_kit_config_enable_redirection();
    ffmpeg_kit_config_disable_redirection();
    SUCCEED();
}

TEST(FFmpegKitConfigTest, EnvironmentVariable) {
    // Set a dummy env var
    int result = ffmpeg_kit_config_set_environment_variable("FFMPEG_KIT_TEST_VAR", "1234");
    EXPECT_EQ(result, 0); // ffmpeg_kit_config_set_environment_variable uses setenv and returns 0 on success
}

TEST(FFmpegKitConfigTest, IgnoreSignal) {
    ffmpeg_kit_config_ignore_signal(FFMPEG_KIT_SIGNAL_SIGPIPE);
    SUCCEED();
}

TEST(FFmpegKitConfigTest, FontDirectory) {
    ffmpeg_kit_config_set_font_directory("/tmp/fonts", nullptr);
    
    const char *fonts[] = {"/tmp/fonts1", "/tmp/fonts2"};
    ffmpeg_kit_config_set_font_directory_list((const char**)fonts, 2, nullptr);
    SUCCEED();
}

TEST(FFmpegKitConfigTest, LogLevelToString) {
    char* str = ffmpeg_kit_config_log_level_to_string(FFMPEG_KIT_LOG_LEVEL_DEBUG);
    ASSERT_NE(str, nullptr);
    EXPECT_STRNE(str, ""); 
    free(str);
}

TEST(FFmpegKitConfigTest, SessionStateToString) {
    char* str = ffmpeg_kit_config_session_state_to_string(FFMPEG_KIT_SESSION_STATE_COMPLETED);
    ASSERT_NE(str, nullptr);
    EXPECT_STRNE(str, ""); 
    free(str);
}

TEST(FFmpegKitConfigTest, ArgumentsToString) {
    const char* args[] = { "ffmpeg", "-i", "test.mp4", "-vcodec", "copy" };
    char* str = ffmpeg_kit_config_arguments_to_string((char**)args, 5);
    ASSERT_NE(str, nullptr);
    EXPECT_STREQ(str, "ffmpeg -i test.mp4 -vcodec copy");
    free(str);
}

TEST(FFmpegKitConfigTest, ArgumentsToStringPreservesSpecialValues) {
    const char* args[] = {
        "-i",
        "C:\\Program Files\\Media\\clip \"quoted\"\\",
        "",
        "single'value"
    };
    char* str = ffmpeg_kit_config_arguments_to_string((char**)args, 4);
    ASSERT_NE(str, nullptr);
    EXPECT_STREQ(
        str,
        "-i 'C:\\Program Files\\Media\\clip \"quoted\"\\' '' 'single'\\''value'");
    free(str);
}
