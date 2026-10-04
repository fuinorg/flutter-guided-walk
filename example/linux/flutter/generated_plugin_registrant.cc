//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <guided_walk/guided_walk_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) guided_walk_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "GuidedWalkPlugin");
  guided_walk_plugin_register_with_registrar(guided_walk_registrar);
}
