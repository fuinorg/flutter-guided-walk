#include "include/guided_walk/guided_walk_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstdio>

#include "guided_walk_plugin_private.h"

// The walk's panel in a window of its own is the app started a second time with
// GUIDED_WALK_WINDOW set. Dart cannot name or size the window it is drawn in, so this part does,
// when the plugin is registered: before the window is first shown.

#define GUIDED_WALK_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), guided_walk_plugin_get_type(), \
                              GuidedWalkPlugin))

struct _GuidedWalkPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(GuidedWalkPlugin, guided_walk_plugin, g_object_get_type())

static void guided_walk_plugin_class_init(GuidedWalkPluginClass* klass) {}

static void guided_walk_plugin_init(GuidedWalkPlugin* self) {}

gboolean guided_walk_parse_size(const gchar* text, int* width, int* height) {
  int w = 0, h = 0;
  char rest = '\0';
  if (text == nullptr || sscanf(text, "%dx%d%c", &w, &h, &rest) != 2) {
    return FALSE;
  }
  if (w < 200 || w > 8000 || h < 200 || h > 8000) {
    return FALSE;
  }
  *width = w;
  *height = h;
  return TRUE;
}

void guided_walk_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  const gchar* walk_window = g_getenv("GUIDED_WALK_WINDOW");
  if (walk_window == nullptr || walk_window[0] == '\0') {
    return;
  }
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view == nullptr) {
    return;
  }
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (!GTK_IS_WINDOW(toplevel)) {
    return;
  }
  GtkWindow* window = GTK_WINDOW(toplevel);

  // Named as a panel beside the app, not as a second app.
  GtkWidget* titlebar = gtk_window_get_titlebar(window);
  if (titlebar != nullptr && GTK_IS_HEADER_BAR(titlebar)) {
    gtk_header_bar_set_title(GTK_HEADER_BAR(titlebar), "Guided walk");
  }
  gtk_window_set_title(window, "Guided walk");

  // As large as it was last made, or a panel's size.
  int width = 840, height = 860;
  guided_walk_parse_size(g_getenv("GUIDED_WALK_WINDOW_SIZE"), &width, &height);
  gtk_window_set_default_size(window, width, height);
  gtk_window_resize(window, width, height);
}
