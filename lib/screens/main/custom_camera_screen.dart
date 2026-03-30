import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:ui';
import '../../theme/app_theme.dart';

class CustomCameraScreen extends StatefulWidget {
  const CustomCameraScreen({super.key});

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  int _selectedCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  bool _showGrid = false;
  Color _selectedFilterColor = Colors.transparent;

  final List<Map<String, dynamic>> _filters = [
    {'name': 'Natural', 'color': Colors.transparent},
    {'name': 'Vintage', 'color': const Color(0xFF704214).withOpacity(0.2)},
    {'name': 'Warm', 'color': Colors.orange.withOpacity(0.15)},
    {'name': 'Cool', 'color': Colors.blue.withOpacity(0.1)},
    {'name': 'Pink', 'color': Colors.pink.withOpacity(0.1)},
    {'name': 'Golden', 'color': Colors.amber.withOpacity(0.2)},
  ];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _onNewCameraSelected(_cameras![_selectedCameraIndex]);
      } else {
        debugPrint('No cameras found');
      }
    } catch (e) {
      debugPrint('Error getting cameras: $e');
    }
  }

  void _onNewCameraSelected(CameraDescription description) async {
    if (_controller != null) {
      await _controller!.dispose();
    }
    _controller = CameraController(
      description,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();
      await _controller!.setFlashMode(_flashMode);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  void _toggleCamera() {
    if (_cameras == null || _cameras!.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    _onNewCameraSelected(_cameras![_selectedCameraIndex]);
  }

  void _toggleFlash() async {
    if (_flashMode == FlashMode.off) {
      _flashMode = FlashMode.always;
    } else if (_flashMode == FlashMode.always) {
      _flashMode = FlashMode.auto;
    } else {
      _flashMode = FlashMode.off;
    }
    await _controller?.setFlashMode(_flashMode);
    setState(() {});
  }

  bool _isFlashing = false;

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      setState(() => _isFlashing = true);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _isFlashing = false);
      });

      final image = await _controller!.takePicture();
      if (mounted) Navigator.pop(context, image);
    } catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: context.primary)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. FULL SCREEN CAMERA PREVIEW
          LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              var scale = size.aspectRatio * _controller!.value.aspectRatio;
              if (scale < 1) scale = 1 / scale;

              return Transform.scale(
                scale: scale,
                child: Center(child: CameraPreview(_controller!)),
              );
            },
          ),

          // 2. FILTER OVERLAY
          if (_selectedFilterColor != Colors.transparent)
            IgnorePointer(child: Container(color: _selectedFilterColor)),

          // 3. GRID LINES
          if (_showGrid)
            IgnorePointer(child: CustomPaint(painter: GridPainter())),

          // 3.5 SHUTTER FLASH EFFECT
          if (_isFlashing) IgnorePointer(child: Container(color: Colors.white)),
          // 4. TOP CONTROLS (Glassmorphism)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 10,
                    bottom: 15,
                    left: 20,
                    right: 20,
                  ),
                  color: Colors.black26,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildRoundButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                      Row(
                        children: [
                          _buildRoundButton(
                            icon: _flashMode == FlashMode.always
                                ? Icons.flash_on_rounded
                                : _flashMode == FlashMode.auto
                                ? Icons.flash_auto_rounded
                                : Icons.flash_off_rounded,
                            isActive: _flashMode != FlashMode.off,
                            onTap: _toggleFlash,
                          ),
                          const SizedBox(width: 15),
                          _buildRoundButton(
                            icon: Icons.grid_on_rounded,
                            isActive: _showGrid,
                            onTap: () => setState(() => _showGrid = !_showGrid),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 5. BOTTOM CONTROLS (Glassmorphism)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.only(top: 20, bottom: 40),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Filter Selection
                      SizedBox(
                        height: 90,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _filters.length,
                          itemBuilder: (context, index) {
                            final f = _filters[index];
                            final isSelected =
                                _selectedFilterColor == f['color'];
                            return GestureDetector(
                              onTap: () => setState(
                                () => _selectedFilterColor = f['color'],
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(right: 18),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected
                                              ? context.primary
                                              : Colors.white24,
                                          width: isSelected ? 3.0 : 1.5,
                                        ),
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: context.primary
                                                      .withOpacity(0.3),
                                                  blurRadius: 10,
                                                  spreadRadius: 2,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: ClipOval(
                                        child: f['color'] == Colors.transparent
                                            ? const Icon(
                                                Icons.block,
                                                color: Colors.white30,
                                                size: 20,
                                              )
                                            : Container(
                                                color: f['color'].withOpacity(1.0),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Flexible(
                                      child: Text(
                                        f['name'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.white60,
                                          fontSize: 10,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 30),
                      // Main Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildRoundButton(
                            icon: Icons.photo_library_rounded,
                            size: 50,
                            onTap: () {
                              // Gallery action handled by outer screen
                              Navigator.pop(context);
                            },
                          ),
                          // Capture Button
                          GestureDetector(
                            onTap: _takePicture,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  height: 85,
                                  width: 85,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                  ),
                                ),
                                Container(
                                  height: 70,
                                  width: 70,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                if (_flashMode != FlashMode.off)
                                  const Icon(
                                    Icons.flash_on,
                                    color: Colors.black26,
                                    size: 30,
                                  ),
                              ],
                            ),
                          ),
                          _buildRoundButton(
                            icon: Icons.flip_camera_android_rounded,
                            size: 50,
                            onTap: _toggleCamera,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundButton({
    required IconData icon,
    VoidCallback? onTap,
    bool isActive = false,
    double size = 44,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? context.primary.withOpacity(0.3) : Colors.white10,
          border: Border.all(
            color: isActive ? context.primary : Colors.white24,
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? context.primary : Colors.white,
          size: size * 0.55,
        ),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0;

    // Vertical lines
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(2 * size.width / 3, 0),
      Offset(2 * size.width / 3, size.height),
      paint,
    );

    // Horizontal lines
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, 2 * size.height / 3),
      Offset(size.width, 2 * size.height / 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
