import 'flutter_usb_camera_package_platform_interface.dart';

class FlutterUsbCameraPackage {
  Future<String?> getPlatformVersion() {
    return FlutterUsbCameraPackagePlatform.instance.getPlatformVersion();
  }

  Future<List<dynamic>> listDevices() {
    return FlutterUsbCameraPackagePlatform.instance.listDevices();
  }

  Future<List<dynamic>> getCameraMetadata(dynamic device) {
    return FlutterUsbCameraPackagePlatform.instance.getCameraMetadata(device);
  }

  Future<int> startStream({
    required dynamic device,
    required String format,
    required int width,
    required int height,
    required double fps,
  }) {
    return FlutterUsbCameraPackagePlatform.instance.startStream(
      device: device,
      format: format,
      width: width,
      height: height,
      fps: fps,
    );
  }

  Future<Map<dynamic, dynamic>> getPerformanceMetrics() {
    return FlutterUsbCameraPackagePlatform.instance.getPerformanceMetrics();
  }

  Future<void> stopStream() {
    return FlutterUsbCameraPackagePlatform.instance.stopStream();
  }
}
