import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_usb_camera_package/flutter_usb_camera_package.dart';
import 'package:flutter_usb_camera_package/flutter_usb_camera_package_platform_interface.dart';
import 'package:flutter_usb_camera_package/flutter_usb_camera_package_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterUsbCameraPackagePlatform
    with MockPlatformInterfaceMixin
    implements FlutterUsbCameraPackagePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterUsbCameraPackagePlatform initialPlatform = FlutterUsbCameraPackagePlatform.instance;

  test('$MethodChannelFlutterUsbCameraPackage is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterUsbCameraPackage>());
  });

  test('getPlatformVersion', () async {
    FlutterUsbCameraPackage flutterUsbCameraPackagePlugin = FlutterUsbCameraPackage();
    MockFlutterUsbCameraPackagePlatform fakePlatform = MockFlutterUsbCameraPackagePlatform();
    FlutterUsbCameraPackagePlatform.instance = fakePlatform;

    expect(await flutterUsbCameraPackagePlugin.getPlatformVersion(), '42');
  });
}
