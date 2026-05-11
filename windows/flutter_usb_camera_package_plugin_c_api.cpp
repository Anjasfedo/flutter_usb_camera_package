#include "include/flutter_usb_camera_package/flutter_usb_camera_package_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_usb_camera_package_plugin.h"

void FlutterUsbCameraPackagePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_usb_camera_package::FlutterUsbCameraPackagePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
