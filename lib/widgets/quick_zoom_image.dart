import 'package:flutter/material.dart';

class QuickZoomImage extends StatefulWidget {
  final String imageUrl;
  final Widget? placeholder;
  final String? heroTag;
  final BoxFit fit;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const QuickZoomImage({
    super.key,
    required this.imageUrl,
    this.placeholder,
    this.heroTag,
    this.fit = BoxFit.cover,
    this.onTap,
    this.onDoubleTap,
  });

  @override
  State<QuickZoomImage> createState() => _QuickZoomImageState();
}

class _QuickZoomImageState extends State<QuickZoomImage> with SingleTickerProviderStateMixin {
  late TransformationController _transformationController;
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  OverlayEntry? _overlayEntry;
  bool _isZooming = false;
  int _pointerCount = 0;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        _transformationController.value = _animation?.value ?? Matrix4.identity();
      });
  }

  @override
  void dispose() {
    _animationController.stop();
    _animationController.dispose();
    _transformationController.dispose();
    if (_overlayEntry != null && _overlayEntry!.mounted) {
      _overlayEntry!.remove();
    }
    _overlayEntry = null;
    super.dispose();
  }

  void _showOverlay(BuildContext context) {
    if (_overlayEntry != null) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<Matrix4>(
                  valueListenable: _transformationController,
                  builder: (context, matrix, _) {
                    final double scale = matrix.getMaxScaleOnAxis();
                    final double opacity = ((scale - 1) * 0.4).clamp(0.0, 0.7);
                    return Container(color: Colors.black.withOpacity(opacity));
                  },
                ),
              ),
              Positioned(
                left: offset.dx,
                top: offset.dy,
                width: size.width,
                height: size.height,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  panEnabled: true,
                  scaleEnabled: true,
                  minScale: 0.8,
                  maxScale: 8.0,
                  onInteractionEnd: (_) => _resetAnimation(),
                  clipBehavior: Clip.none,
                  child: Image.network(
                    widget.imageUrl,
                    fit: widget.fit,
                    errorBuilder: (context, error, stackTrace) => widget.placeholder ?? const SizedBox(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isZooming = true);
  }

  void _removeOverlay() {
    if (_overlayEntry != null && _overlayEntry!.mounted) {
      _overlayEntry!.remove();
    }
    _overlayEntry = null;
    if (mounted) setState(() => _isZooming = false);
  }

  void _resetAnimation() {
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward(from: 0).then((_) {
      _removeOverlay();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _pointerCount++,
      onPointerUp: (e) => _pointerCount--,
      onPointerCancel: (e) => _pointerCount = 0,
      behavior: HitTestBehavior.translucent,
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onScaleStart: (details) {
          if (_pointerCount >= 2) {
            _showOverlay(context);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: _isZooming ? 0 : 1,
          child: Hero(
            tag: widget.heroTag ?? widget.imageUrl,
            child: Image.network(
              widget.imageUrl,
              fit: widget.fit,
              width: double.infinity,
              errorBuilder: (context, error, stackTrace) =>
                  widget.placeholder ??
                  Container(
                    color: Colors.black12,
                    child: const Center(child: Icon(Icons.broken_image)),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
