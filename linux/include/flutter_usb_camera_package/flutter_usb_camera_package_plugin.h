#ifndef FLUTTER_PLUGIN_FLUTTER_USB_CAMERA_PACKAGE_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_USB_CAMERA_PACKAGE_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _FlutterUsbCameraPackagePlugin FlutterUsbCameraPackagePlugin;
typedef struct {
  GObjectClass parent_class;
} FlutterUsbCameraPackagePluginClass;

FLUTTER_PLUGIN_EXPORT GType flutter_usb_camera_package_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void flutter_usb_camera_package_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_FLUTTER_USB_CAMERA_PACKAGE_PLUGIN_H_
