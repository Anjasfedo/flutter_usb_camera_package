import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter_usb_camera_package/flutter_usb_camera_package.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyanAccent,
          brightness: Brightness.dark,
          surface: const Color(0xFF121212),
        ),
      ),
      home: const CameraOnboardingPage(),
    );
  }
}

class CameraOnboardingPage extends StatefulWidget {
  const CameraOnboardingPage({super.key});

  @override
  State<CameraOnboardingPage> createState() => _CameraOnboardingPageState();
}

class _CameraOnboardingPageState extends State<CameraOnboardingPage>
    with SingleTickerProviderStateMixin {
  final _cameraPlugin = FlutterUsbCameraPackage();
  final PageController _pageController = PageController();

  int _currentStep = 0;

  List<dynamic> _devices = [];
  dynamic _selectedDevice;
  List<dynamic> _formats = [];
  Map<dynamic, dynamic>? _selectedFormat;
  Map<dynamic, dynamic>? _selectedResolution;
  double? _selectedFps;

  int? _textureId;
  bool _isStreaming = false;
  double _currentFps = 0.0;
  int _width = 0;
  int _height = 0;
  Timer? _metricsTimer;

  FragmentProgram? _shaderProgram;
  late final AnimationController _shaderClock;
  bool _shaderEnabled = true;

  @override
  void initState() {
    super.initState();

    _shaderClock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();

    _loadShader();
    _refreshDevices();
  }

  Future<void> _loadShader() async {
    try {
      final program = await FragmentProgram.fromAsset(
        'shaders/camera_overlay.frag',
      );

      if (!mounted) return;

      setState(() {
        _shaderProgram = program;
      });
    } catch (e) {
      debugPrint("Shader Load Error: $e");
    }
  }

  Future<void> _refreshDevices() async {
    try {
      final devices = await _cameraPlugin.listDevices();

      if (!mounted) return;

      setState(() {
        _devices = devices.toSet().toList();
      });
    } catch (e) {
      debugPrint("Device Scan Error: $e");
    }
  }

  Future<void> _fetchMetadata(dynamic device) async {
    try {
      final List<dynamic> metadata = await _cameraPlugin.getCameraMetadata(
        device,
      );

      if (!mounted) return;

      setState(() {
        final seen = <String>{};
        _formats = metadata
            .where((item) => seen.add(item['format'].toString()))
            .toList();
        _selectedDevice = device;
      });

      _nextPage();
    } catch (e) {
      debugPrint("Metadata Error: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to probe camera capabilities")),
      );
    }
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _prevPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _reset() async {
    try {
      await _cameraPlugin.stopStream();
    } catch (e) {
      debugPrint("Error stopping stream: $e");
    }

    _metricsTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _isStreaming = false;
      _textureId = null;
      _currentStep = 0;
      _selectedDevice = null;
      _selectedFormat = null;
      _selectedResolution = null;
      _selectedFps = null;
      _currentFps = 0.0;
      _width = 0;
      _height = 0;
      _shaderEnabled = true;
    });

    _pageController.jumpToPage(0);
    _refreshDevices();
  }

  Future<void> _startStreaming() async {
    try {
      final id = await _cameraPlugin.startStream(
        device: _selectedDevice,
        format: _selectedFormat!['format'],
        width: _selectedResolution!['width'],
        height: _selectedResolution!['height'],
        fps: _selectedFps!,
      );

      if (!mounted) return;

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
      try {
        final m = await _cameraPlugin.getPerformanceMetrics();

        if (!mounted) return;

        setState(() {
          _currentFps = (m['fps'] as num).toDouble();
          _width = m['width'] as int;
          _height = m['height'] as int;
        });
      } catch (e) {
        debugPrint("Metrics Error: $e");
      }
    });
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    _pageController.dispose();
    _shaderClock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.8, -0.6),
                  radius: 1.2,
                  colors: [Color(0xFF1A2A2D), Color(0xFF0F1213)],
                ),
              ),
            ),
          ),

          // Video Texture
          if (_isStreaming && _textureId != null)
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _width > 0 && _height > 0
                      ? _width / _height
                      : 16 / 9,
                  child: kIsWeb
                      ? HtmlElementView(viewType: 'usb-camera-view-$_textureId')
                      : Texture(textureId: _textureId!),
                ),
              ),
            ),

          // Shader Overlay Layer
          if (_isStreaming && _shaderEnabled && _shaderProgram != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CameraShaderPainter(
                    program: _shaderProgram!,
                    clock: _shaderClock,
                    fps: _currentFps,
                    cameraSize: Size(_width.toDouble(), _height.toDouble()),
                  ),
                ),
              ),
            ),

          // UI Layer
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              layoutBuilder:
                  (Widget? currentChild, List<Widget> previousChildren) {
                    return Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
              child: !_isStreaming ? _buildOnboardingWizard() : _buildHUD(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingWizard() {
    return Container(
      key: const ValueKey('onboarding'),
      color: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildHeader(),
            const SizedBox(height: 10),
            _buildStepIndicator(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) {
                  setState(() => _currentStep = i);
                },
                children: [
                  _buildSelectionPage(
                    title: "Hardware",
                    subtitle: "Select your active USB device",
                    items: _devices,
                    onSelect: (val) => _fetchMetadata(val),
                  ),
                  _buildSelectionPage(
                    title: "Encoding",
                    subtitle: "Choose compression format",
                    items: _formats,
                    label: (i) => i['format'],
                    onSelect: (val) {
                      setState(() => _selectedFormat = val);
                      _nextPage();
                    },
                  ),
                  _buildSelectionPage(
                    title: "Resolution",
                    subtitle: "Set native sensor dimensions",
                    items: _selectedFormat?['resolutions'],
                    label: (i) => "${i['width']}x${i['height']}",
                    onSelect: (val) {
                      setState(() => _selectedResolution = val);
                      _nextPage();
                    },
                  ),
                  _buildSelectionPage(
                    title: "Framerate",
                    subtitle: "Finalize temporal resolution",
                    items: _selectedResolution?['fps'],
                    label: (i) => "${(i as num).toStringAsFixed(0)} FPS",
                    onSelect: (val) {
                      _selectedFps = (val as num).toDouble();
                      _startStreaming();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _currentStep > 0
              ? IconButton(
                  onPressed: _prevPage,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  style: IconButton.styleFrom(backgroundColor: Colors.white10),
                )
              : const SizedBox(width: 40),
          const Text(
            "WIZARD",
            style: TextStyle(
              letterSpacing: 4,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.cyanAccent,
            ),
          ),
          _currentStep == 0
              ? IconButton(
                  onPressed: _refreshDevices,
                  icon: const Icon(
                    Icons.refresh,
                    size: 20,
                    color: Colors.cyanAccent,
                  ),
                  style: IconButton.styleFrom(backgroundColor: Colors.white10),
                )
              : const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final active = index == _currentStep;
        final completed = index < _currentStep;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 4,
          width: active ? 30 : 6,
          decoration: BoxDecoration(
            color: active
                ? Colors.cyanAccent
                : completed
                ? Colors.cyanAccent.withOpacity(0.3)
                : Colors.white10,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildSelectionPage({
    required String title,
    required String subtitle,
    required List<dynamic>? items,
    required Function(dynamic) onSelect,
    String Function(dynamic)? label,
  }) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 30),
          Expanded(
            child: ListView.separated(
              itemCount: items?.length ?? 0,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items![index];

                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: ListTile(
                      tileColor: Colors.white.withOpacity(0.05),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      title: Text(
                        label != null ? label(item) : item.toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.cyanAccent.withOpacity(0.5),
                      ),
                      onTap: () => onSelect(item),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHUD() {
    return SizedBox.expand(
      key: const ValueKey('hud'),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    color: Colors.black26,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _metricChip(
                          "FPS",
                          _currentFps.toStringAsFixed(1),
                          Colors.greenAccent,
                        ),
                        const SizedBox(width: 8),
                        _metricChip(
                          "RES",
                          "${_width}x$_height",
                          Colors.cyanAccent,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _shaderEnabled = !_shaderEnabled;
                            });
                          },
                          icon: Icon(
                            _shaderEnabled
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 18,
                          ),
                          tooltip: _shaderEnabled
                              ? "Disable shader"
                              : "Enable shader",
                          style: IconButton.styleFrom(
                            backgroundColor: _shaderEnabled
                                ? Colors.cyanAccent.withOpacity(0.2)
                                : Colors.white10,
                            foregroundColor: _shaderEnabled
                                ? Colors.cyanAccent
                                : Colors.white54,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _reset,
                          icon: const Icon(Icons.power_settings_new, size: 18),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.redAccent.withOpacity(0.2),
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "CORE SOURCE: $_selectedDevice | ${_selectedFormat?['format']}",
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      fontFamily: 'monospace',
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class CameraShaderPainter extends CustomPainter {
  CameraShaderPainter({
    required this.program,
    required this.clock,
    required this.fps,
    required this.cameraSize,
  }) : super(repaint: clock);

  final FragmentProgram program;
  final AnimationController clock;
  final double fps;
  final Size cameraSize;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();

    final elapsedSeconds =
        (clock.lastElapsedDuration ?? Duration.zero).inMicroseconds /
        Duration.microsecondsPerSecond;

    // Uniform order must match shaders/camera_overlay.frag:
    //
    // uniform vec2 uSize;        // float 0, 1
    // uniform float uTime;       // float 2
    // uniform float uFps;        // float 3
    // uniform vec2 uCameraSize;  // float 4, 5

    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, elapsedSeconds);
    shader.setFloat(3, fps);
    shader.setFloat(4, cameraSize.width);
    shader.setFloat(5, cameraSize.height);

    final paint = Paint()..shader = shader;

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CameraShaderPainter oldDelegate) {
    return oldDelegate.program != program ||
        oldDelegate.fps != fps ||
        oldDelegate.cameraSize != cameraSize;
  }
}
