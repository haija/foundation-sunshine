#pragma once

#include <Limelight.h>

namespace platf {
  // Only controller-arrival metadata is used: never guesses game support.
  constexpr bool promote_automatic_to_dualsense(int selected_mode, int reported_type,
                                               unsigned int capabilities, bool component_available) {
    return selected_mode == 1 && reported_type == LI_CTYPE_PS &&
           (capabilities & LI_CCAP_DS5_HAPTICS_PCM) != 0 && component_available;
  }
}
