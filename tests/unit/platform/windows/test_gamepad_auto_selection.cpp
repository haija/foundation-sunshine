#include <gtest/gtest.h>
#include <src/platform/windows/gamepad_auto_selection.h>

TEST(GamepadAutoSelection, NativePlayStationCapabilityPromotesOnlyAuto) {
  EXPECT_TRUE(platf::promote_automatic_to_dualsense(1, LI_CTYPE_PS, LI_CCAP_DS5_HAPTICS_PCM, true));
  for (int mode : {0, 2, 3, 4}) {
    EXPECT_FALSE(platf::promote_automatic_to_dualsense(mode, LI_CTYPE_PS, LI_CCAP_DS5_HAPTICS_PCM, true));
  }
}

TEST(GamepadAutoSelection, MissingComponentOrCapabilityPreservesFallback) {
  EXPECT_FALSE(platf::promote_automatic_to_dualsense(1, LI_CTYPE_PS, LI_CCAP_DS5_HAPTICS_PCM, false));
  EXPECT_FALSE(platf::promote_automatic_to_dualsense(1, LI_CTYPE_PS, 0, true));
}

TEST(GamepadAutoSelection, VirtualXboxOrUnknownNeverPromotes) {
  EXPECT_FALSE(platf::promote_automatic_to_dualsense(1, LI_CTYPE_XBOX, LI_CCAP_DS5_HAPTICS_PCM, true));
  EXPECT_FALSE(platf::promote_automatic_to_dualsense(1, LI_CTYPE_UNKNOWN, LI_CCAP_DS5_HAPTICS_PCM, true));
}
