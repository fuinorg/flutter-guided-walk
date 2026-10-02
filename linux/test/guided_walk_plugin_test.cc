#include <flutter_linux/flutter_linux.h>
#include <gtest/gtest.h>

#include "include/guided_walk/guided_walk_plugin.h"
#include "guided_walk_plugin_private.h"

// Once the example is built, from its folder:
// $ build/linux/x64/debug/plugins/guided_walk/guided_walk_test

namespace guided_walk {
namespace test {

TEST(GuidedWalkPlugin, ReadsAWindowSize) {
  int width = 0, height = 0;
  ASSERT_TRUE(guided_walk_parse_size("900x700", &width, &height));
  EXPECT_EQ(width, 900);
  EXPECT_EQ(height, 700);
}

TEST(GuidedWalkPlugin, LeavesTheSizeAsItIsWhereNoneIsGiven) {
  int width = 840, height = 860;
  EXPECT_FALSE(guided_walk_parse_size(nullptr, &width, &height));
  EXPECT_FALSE(guided_walk_parse_size("tall", &width, &height));
  EXPECT_FALSE(guided_walk_parse_size("5x5", &width, &height));
  EXPECT_FALSE(guided_walk_parse_size("900x700px", &width, &height));
  EXPECT_EQ(width, 840);
  EXPECT_EQ(height, 860);
}

}  // namespace test
}  // namespace guided_walk
