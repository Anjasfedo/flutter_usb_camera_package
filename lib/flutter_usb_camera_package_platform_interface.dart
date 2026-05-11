import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'flutter_usb_camera_package_method_channel.dart';

abstract class FlutterUsbCameraPackagePlatform extends PlatformInterface {
  FlutterUsbCameraPackagePlatform() : super(token: _token);

  static final Object _token = Object();
  static FlutterUsbCameraPackagePlatform _instance =
      MethodChannelFlutterUsbCameraPackage();

  static FlutterUsbCameraPackagePlatform get instance => _instance;

  static set instance(FlutterUsbCameraPackagePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() => throw UnimplementedError();

  Future<List<dynamic>> listDevices() => throw UnimplementedError();

  Future<List<dynamic>> getCameraMetadata(dynamic device) =>
      throw UnimplementedError();

  Future<int> startStream({
    required dynamic device,
    required String format,
    required int width,
    required int height,
    required double fps,
  }) => throw UnimplementedError();

  Future<Map<dynamic, dynamic>> getPerformanceMetrics() =>
      throw UnimplementedError();

  Future<void> stopStream() {
    throw UnimplementedError();
  }
}
