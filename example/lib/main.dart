import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_usb_camera_package/flutter_usb_camera_package.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _cameraPlugin = FlutterUsbCameraPackage();

  // State for Hardware discovery
  List<dynamic> _devices = []; // List of cameras like /dev/video0, /dev/video1
  dynamic _selectedDevice;

  // Metadata for the selected hardware
  List<dynamic> _availableFormats = [];
  Map<dynamic, dynamic>? _selectedFormat;
  Map<dynamic, dynamic>? _selectedResolution;
  double? _selectedFps;

  // Stream State
  int? _textureId;
  bool _isStreaming = false;

  // Performance Metrics
  double _fps = 0.0;
  int _width = 0;
  int _height = 0;
  Timer? _metricsTimer;

  @override
  void initState() {
    super.initState();
    _refreshDevices();
  }

  // 1. Find all physical camera devices
  Future<void> _refreshDevices() async {
    try {
      // Assuming your plugin returns a list of devices
      final devices = await _cameraPlugin.listDevices();
      setState(() {
        _devices = devices;
        if (_devices.isNotEmpty) _selectedDevice = _devices.first;
      });
    } catch (e) {
      debugPrint("Error listing devices: $e");
    }
  }

  // 2. Query metadata for a specific chosen device
  Future<void> _fetchMetadata(dynamic device) async {
    try {
      final List<dynamic> metadata = await _cameraPlugin.getCameraMetadata(
        device,
      );
      setState(() {
        _availableFormats = metadata;
        if (_availableFormats.isNotEmpty) {
          _selectedFormat = _availableFormats.first;
          _selectedResolution = _selectedFormat!['resolutions'].first;
          _selectedFps = (_selectedResolution!['fps'] as List).first;
        }
      });
    } catch (e) {
      debugPrint("Error fetching metadata: $e");
    }
  }

  // 3. Start the actual pipeline
  Future<void> _handleStart() async {
    if (_selectedFormat == null ||
        _selectedResolution == null ||
        _selectedFps == null)
      return;

    try {
      final id = await _cameraPlugin.startStream(
        device: _selectedDevice,
        format: _selectedFormat!['format'],
        width: _selectedResolution!['width'],
        height: _selectedResolution!['height'],
        fps: _selectedFps!,
      );

      setState(() {
        _textureId = id;
        _isStreaming = true;
      });
      _startMetrics();
    } catch (e) {
      debugPrint("Streaming Error: $e");
    }
  }

  void _startMetrics() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      final metrics = await _cameraPlugin.getPerformanceMetrics();
      setState(() {
        _fps = metrics['fps'];
        _width = metrics['width'];
        _height = metrics['height'];
      });
    });
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blueGrey),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('USB Camera Controller'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshDevices,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildControlPanel(),
            Expanded(child: _buildPreviewArea()),
            _buildMetricsFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.camera_alt_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<dynamic>(
                    isExpanded: true,
                    value: _selectedDevice,
                    hint: const Text("Select Camera Device"),
                    items: _devices
                        .map(
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text(d.toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setState(() => _selectedDevice = val);
                      _fetchMetadata(val);
                    },
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDropdown(
                  "Format",
                  _selectedFormat,
                  _availableFormats,
                  (val) {
                    setState(() {
                      _selectedFormat = val;
                      _selectedResolution = val['resolutions'].first;
                      _selectedFps =
                          (_selectedResolution!['fps'] as List).first;
                    });
                  },
                  labelMapper: (val) => val['format'],
                ),

                _buildDropdown(
                  "Resolution",
                  _selectedResolution,
                  _selectedFormat?['resolutions'],
                  (val) {
                    setState(() {
                      _selectedResolution = val;
                      _selectedFps = (val['fps'] as List).first;
                    });
                  },
                  labelMapper: (val) => "${val['width']}x${val['height']}",
                ),

                _buildDropdown(
                  "FPS",
                  _selectedFps,
                  _selectedResolution?['fps'],
                  (val) {
                    setState(() => _selectedFps = val);
                  },
                  labelMapper: (val) => "${val.toStringAsFixed(0)} FPS",
                ),

                ElevatedButton.icon(
                  onPressed: _handleStart,
                  icon: const Icon(Icons.play_circle_fill),
                  label: const Text("Apply Settings"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String hint,
    dynamic value,
    List<dynamic>? items,
    ValueChanged<dynamic> onChanged, {
    String Function(dynamic)? labelMapper,
  }) {
    return DropdownButton<dynamic>(
      value: value,
      hint: Text(hint),
      items:
          items
              ?.map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    labelMapper != null ? labelMapper(item) : item.toString(),
                  ),
                ),
              )
              .toList() ??
          [],
      onChanged: onChanged,
    );
  }

  Widget _buildPreviewArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: _textureId != null
              ? AspectRatio(
                  aspectRatio: _width > 0 && _height > 0
                      ? _width / _height
                      : 16 / 9,
                  child: Texture(textureId: _textureId!),
                )
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.usb, color: Colors.white24, size: 48),
                    SizedBox(height: 8),
                    Text(
                      "Select a device and format to begin stream",
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildMetricsFooter() {
    if (!_isStreaming) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _metricTile("Actual FPS", "${_fps.toStringAsFixed(1)} Hz"),
          _metricTile("Active Res", "${_width}x$_height"),
          _metricTile("Pipeline", "GStreamer (Native)"),
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
        ),
      ],
    );
  }
}
