import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'flutter_usb_camera_package_platform_interface.dart';

class MethodChannelFlutterUsbCameraPackage
    extends FlutterUsbCameraPackagePlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_usb_camera_package');

  @override
  Future<String?> getPlatformVersion() async {
    return await methodChannel.invokeMethod<String>('getPlatformVersion');
  }

  @override
  Future<List<dynamic>> listDevices() async {
    return await methodChannel.invokeMethod<List<dynamic>>('listDevices') ?? [];
  }

  @override
  Future<List<dynamic>> getCameraMetadata(dynamic device) async {
    return await methodChannel.invokeMethod<List<dynamic>>(
          'getCameraMetadata',
          {'device': device},
        ) ??
        [];
  }

  @override
  Future<int> startStream({
    required dynamic device,
    required String format,
    required int width,
    required int height,
    required double fps,
  }) async {
    return await methodChannel.invokeMethod<int>('startStream', {
          'device': device,
          'format': format,
          'width': width,
          'height': height,
          'fps': fps,
        }) ??
        -1;
  }

  @override
  Future<Map<dynamic, dynamic>> getPerformanceMetrics() async {
    return await methodChannel.invokeMethod<Map<dynamic, dynamic>>(
          'getPerformanceMetrics',
        ) ??
        {};
  }

  @override
  Future<void> stopStream() async {
    await methodChannel.invokeMethod<void>('stopStream');
  }
}
