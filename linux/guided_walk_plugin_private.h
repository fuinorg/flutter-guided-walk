#include <flutter_linux/flutter_linux.h>

#include "include/guided_walk/guided_walk_plugin.h"

// Reads a window's size given as "<width>x<height>"; false, and nothing written, where it is not one
// or is not a size a window is made.
gboolean guided_walk_parse_size(const gchar* text, int* width, int* height);
