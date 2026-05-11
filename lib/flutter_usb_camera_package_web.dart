import 'dart:async';
import 'dart:js_interop';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

import 'flutter_usb_camera_package_platform_interface.dart';

class FlutterUsbCameraPackageWeb extends FlutterUsbCameraPackagePlatform {
  static void registerWith(Registrar registrar) {
    FlutterUsbCameraPackagePlatform.instance = FlutterUsbCameraPackageWeb();
  }

  final Map<int, web.MediaStream> _streams = {};
  int _viewCounter = 0;

  @override
  Future<List<dynamic>> listDevices() async {
    try {
      final devices = await web.window.navigator.mediaDevices
          .enumerateDevices()
          .toDart;
      return devices.toDart
          .where((device) => device.kind == 'videoinput')
          .map(
            (device) => device.label.isEmpty
                ? "Camera ${device.deviceId}"
                : device.label,
          )
          .toList();
    } catch (e) {
      return ["Default Camera"];
    }
  }

  @override
  Future<List<dynamic>> getCameraMetadata(dynamic deviceLabel) async {
    return [
      {
        'format': 'Browser Native',
        'resolutions': [
          {
            'width': 3840,
            'height': 2160,
            'fps': [30.0, 24.0],
          },
          {
            'width': 1920,
            'height': 1080,
            'fps': [60.0, 30.0],
          },
          {
            'width': 1280,
            'height': 720,
            'fps': [30.0],
          },
        ],
      },
    ];
  }

  @override
  Future<int> startStream({
    required dynamic device,
    required String format,
    required int width,
    required int height,
    required double fps,
  }) async {
    final viewId = _viewCounter++;
    final viewType = 'usb-camera-view-$viewId';

    final constraints =
        {
              'video': {
                'width': {'ideal': width},
                'height': {'ideal': height},
                'frameRate': {'ideal': fps},
              },
            }.jsify()
            as web.MediaStreamConstraints;

    final stream = await web.window.navigator.mediaDevices
        .getUserMedia(constraints)
        .toDart;

    final videoElement =
        web.document.createElement('video') as web.HTMLVideoElement;
    videoElement.srcObject = stream;
    videoElement.autoplay = true;
    videoElement.playsInline = true;
    videoElement.muted = true;
    videoElement.style.width = '100%';
    videoElement.style.height = '100%';
    videoElement.style.objectFit = 'contain';

    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int id) => videoElement,
    );

    _streams[viewId] = stream;

    return viewId;
  }

  @override
  Future<Map<dynamic, dynamic>> getPerformanceMetrics() async {
    return {'fps': 0.0, 'width': 0, 'height': 0};
  }
}
