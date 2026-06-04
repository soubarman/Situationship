import 'package:flutter/material.dart';

class InstaZoom extends StatefulWidget {
  final Widget child;

  const InstaZoom({super.key, required this.child});

  @override
  State<InstaZoom> createState() => _InstaZoomState();
}

class _InstaZoomState extends State<InstaZoom> with TickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  late Animation<Matrix4> _animation;
  final TransformationController _transformationController = TransformationController();

  Offset _initialFocalPoint = Offset.zero;
  double _initialScale = 1.0;
  bool _isZooming = false;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        _transformationController.value = _animation.value;
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Optional: slight dark background
            Positioned.fill(
              child: ValueListenableBuilder<Matrix4>(
                valueListenable: _transformationController,
                builder: (context, matrix, _) {
                  final scale = matrix.getMaxScaleOnAxis();
                  final opacity = ((scale - 1) / 3).clamp(0.0, 0.6);
                  return Container(
                    color: Colors.black.withOpacity(opacity),
                  );
                },
              ),
            ),
            Positioned(
              left: offset.dx,
              top: offset.dy,
              width: size.width,
              height: size.height,
              child: ValueListenableBuilder<Matrix4>(
                valueListenable: _transformationController,
                builder: (context, matrix, child) {
                  return Transform(
                    transform: matrix,
                    alignment: Alignment.center,
                    child: widget.child,
                  );
                },
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    
    _animationController.forward(from: 0).whenComplete(() {
      _overlayEntry?.remove();
      _overlayEntry = null;
      _isZooming = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: (details) {
        _initialFocalPoint = details.focalPoint;
        _initialScale = 1.0;
        // Don't show overlay immediately on start to prevent one-finger scrolls from triggering it
      },
      onScaleUpdate: (details) {
        // If not zooming yet, check if it's a pinch (scale > 1.0)
        if (!_isZooming) {
          if (details.scale > 1.05) {
            _isZooming = true;
            _animationController.stop();
            _showOverlay();
          } else {
            return;
          }
        }

        final currentScale = details.scale.clamp(1.0, 4.0);
        final delta = details.focalPoint - _initialFocalPoint;

        final matrix = Matrix4.identity()
          ..translate(delta.dx, delta.dy)
          ..scale(currentScale, currentScale);

        _transformationController.value = matrix;
      },
      onScaleEnd: (details) {
        if (!_isZooming) return;
        _hideOverlay();
      },
      child: Opacity(
        opacity: _isZooming ? 0.0 : 1.0, // hide original while zooming
        child: widget.child,
      ),
    );
  }
}
