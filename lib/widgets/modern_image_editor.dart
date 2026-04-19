import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../theme/app_theme.dart';

enum EditorMode { profile, story }

class ModernImageEditor extends StatefulWidget {
  final String imagePath;
  final EditorMode mode;
  final Function(Uint8List) onComplete;

  const ModernImageEditor({
    super.key,
    required this.imagePath,
    required this.mode,
    required this.onComplete,
  });

  static Future<void> open(
    BuildContext context, {
    required String imagePath,
    required EditorMode mode,
    required Function(Uint8List) onComplete,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ModernImageEditor(
          imagePath: imagePath,
          mode: mode,
          onComplete: onComplete,
        ),
      ),
    );
  }

  @override
  State<ModernImageEditor> createState() => _ModernImageEditorState();
}

class _ModernImageEditorState extends State<ModernImageEditor> {
  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _transformationController = TransformationController();
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isProfile = widget.mode == EditorMode.profile;
    
    // Calculate aspect ratio for crop area
    final double cropAspectRatio = isProfile ? 1.0 : 9 / 16;
    final double horizontalPadding = isProfile ? 40.0 : 0.0;
    final double cropWidth = size.width - (horizontalPadding * 2);
    final double cropHeight = cropWidth / cropAspectRatio;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background blurry image (Instagram style)
          Positioned.fill(
            child: kIsWeb
                ? Image.network(widget.imagePath, fit: BoxFit.cover)
                : Image.file(File(widget.imagePath), fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ),

          // Main Editor Area
          Center(
            child: RepaintBoundary(
              key: _boundaryKey,
              child: Container(
                width: cropWidth,
                height: cropHeight,
                decoration: BoxDecoration(
                  borderRadius: isProfile ? BorderRadius.circular(cropWidth / 2) : BorderRadius.zero,
                  color: Colors.black,
                ),
                clipBehavior: Clip.hardEdge,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  minScale: 0.1,
                  maxScale: 5.0,
                  child: kIsWeb
                      ? Image.network(
                          widget.imagePath,
                          fit: BoxFit.cover,
                          width: cropWidth,
                          height: cropHeight,
                        )
                      : Image.file(
                          File(widget.imagePath),
                          fit: BoxFit.cover,
                          width: cropWidth,
                          height: cropHeight,
                        ),
                ),
              ),
            ),
          ),

          // Grid & Mask Overlay
          IgnorePointer(
            child: CustomPaint(
              size: size,
              painter: EditorOverlayPainter(
                cropWidth: cropWidth,
                cropHeight: cropHeight,
                isProfile: isProfile,
                borderColor: context.primary,
              ),
            ),
          ),

          // Top Navigation
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCircularButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                Text(
                  isProfile ? 'Edit Profile Photo' : 'Edit Story',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                _isProcessing
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : _buildCircularButton(
                        icon: Icons.check_rounded,
                        color: context.primary,
                        onTap: _handleComplete,
                      ),
              ],
            ),
          ),

          // Bottom Hint
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  'Pinch to zoom • Drag to move',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (isProfile) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Content within the circle will be shown',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color ?? Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  Future<void> _handleComplete() async {
    setState(() => _isProcessing = true);
    
    try {
      // Capture the RepaintBoundary as an image
      RenderRepaintBoundary? boundary = 
          _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      
      if (boundary == null) return;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        Uint8List pngBytes = byteData.buffer.asUint8List();
        widget.onComplete(pngBytes);
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error cropping image: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}

class EditorOverlayPainter extends CustomPainter {
  final double cropWidth;
  final double cropHeight;
  final bool isProfile;
  final Color borderColor;

  EditorOverlayPainter({
    required this.cropWidth,
    required this.cropHeight,
    required this.isProfile,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final rect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: cropWidth,
      height: cropHeight,
    );

    // Dim Background (the area outside the crop)
    final backgroundPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final fullRect = Path()..addRect(Offset.zero & size);
    final cropPath = isProfile 
        ? (Path()..addOval(rect)) 
        : (Path()..addRect(rect));
    
    canvas.drawPath(
      Path.combine(PathOperation.difference, fullRect, cropPath),
      backgroundPaint,
    );

    // Crop Border
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    if (isProfile) {
      canvas.drawOval(rect, borderPaint);
    } else {
      canvas.drawRect(rect, borderPaint);
    }

    // Rule of Thirds Grid
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Vertical Lines
    canvas.drawLine(Offset(rect.left + cropWidth / 3, rect.top), Offset(rect.left + cropWidth / 3, rect.bottom), gridPaint);
    canvas.drawLine(Offset(rect.left + (cropWidth / 3) * 2, rect.top), Offset(rect.left + (cropWidth / 3) * 2, rect.bottom), gridPaint);
    
    // Horizontal Lines
    canvas.drawLine(Offset(rect.left, rect.top + cropHeight / 3), Offset(rect.right, rect.top + cropHeight / 3), gridPaint);
    canvas.drawLine(Offset(rect.left, rect.top + (cropHeight / 3) * 2), Offset(rect.right, rect.top + (cropHeight / 3) * 2), gridPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
