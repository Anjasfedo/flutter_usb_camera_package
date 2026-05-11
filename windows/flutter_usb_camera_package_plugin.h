#ifndef FLUTTER_PLUGIN_FLUTTER_USB_CAMERA_PACKAGE_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_USB_CAMERA_PACKAGE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_usb_camera_package {

class FlutterUsbCameraPackagePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterUsbCameraPackagePlugin();

  virtual ~FlutterUsbCameraPackagePlugin();

  // Disallow copy and assign.
  FlutterUsbCameraPackagePlugin(const FlutterUsbCameraPackagePlugin&) = delete;
  FlutterUsbCameraPackagePlugin& operator=(const FlutterUsbCameraPackagePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace flutter_usb_camera_package

#endif  // FLUTTER_PLUGIN_FLUTTER_USB_CAMERA_PACKAGE_PLUGIN_H_
