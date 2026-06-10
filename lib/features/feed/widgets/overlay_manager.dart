import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';

class OverlayItem {
  final String id;
  final bool isText;
  String content;

  Offset position;
  double scale;
  double rotation;

  String fontFamily;
  Color color;
  bool hasBackground;

  OverlayItem({
    required this.id,
    required this.isText,
    required this.content,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.fontFamily = 'Inter',
    this.color = Colors.white,
    this.hasBackground = false,
  });
}

class OverlayManager extends StatefulWidget {
  final List<OverlayItem> items;
  final Function(OverlayItem) onItemTap;
  final VoidCallback onItemsChanged;

  const OverlayManager({
    super.key,
    required this.items,
    required this.onItemTap,
    required this.onItemsChanged,
  });

  @override
  State<OverlayManager> createState() => _OverlayManagerState();
}

class _OverlayManagerState extends State<OverlayManager> {
  OverlayItem? _activeItem;
  
  // Gesture tracking
  Offset _initialPosition = Offset.zero;
  double _initialScale = 1.0;
  double _initialRotation = 0.0;
  
  bool _isDragging = false;
  bool _isInTrashZone = false;
  
  // Trash zone bounds (bottom center)
  final double _trashZoneHeight = 100.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Items
        ...widget.items.map(_buildItem),
        
        // Trash Can (only visible when dragging)
        if (_isDragging)
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: AnimatedScale(
              scale: _isInTrashZone ? 1.5 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: AnimatedOpacity(
                opacity: _isInTrashZone ? 1.0 : 0.6,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black45,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: _isInTrashZone ? AppTheme.error : Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItem(OverlayItem item) {
    final isSticker = !item.isText;
    
    // Base widget
    Widget child = isSticker
        ? Text(
            item.content,
            style: const TextStyle(fontSize: 48, decoration: TextDecoration.none),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: item.hasBackground
                ? BoxDecoration(
                    color: item.color == Colors.white || item.color == Colors.transparent 
                        ? Colors.black87 
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: Text(
              item.content,
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(
                item.fontFamily,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: item.hasBackground && item.color == Colors.white
                    ? Colors.black
                    : item.color,
                shadows: item.hasBackground ? null : const [
                  Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))
                ],
                decoration: TextDecoration.none,
              ),
            ),
          );

    return Positioned(
      left: item.position.dx,
      top: item.position.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () {
          // Bring to front
          widget.items.remove(item);
          widget.items.add(item);
          widget.onItemTap(item);
          widget.onItemsChanged();
        },
        onScaleStart: (details) {
          setState(() {
            _activeItem = item;
            _initialPosition = item.position;
            _initialScale = item.scale;
            _initialRotation = item.rotation;
            _isDragging = true;
            _isInTrashZone = false;
            
            // Bring to front
            widget.items.remove(item);
            widget.items.add(item);
          });
        },
        onScaleUpdate: (details) {
          if (_activeItem != item) return;
          
          setState(() {
            item.position += details.focalPointDelta;
            item.scale = _initialScale * details.scale;
            item.rotation = _initialRotation + details.rotation;
            
            // Check trash zone (bottom 100 pixels) using the actual finger position!
            final screenHeight = MediaQuery.of(context).size.height;
            _isInTrashZone = details.focalPoint.dy > screenHeight - _trashZoneHeight;
          });
        },
        onScaleEnd: (details) {
          if (_activeItem != item) return;
          
          setState(() {
            _isDragging = false;
            if (_isInTrashZone) {
              widget.items.remove(item);
            }
            _activeItem = null;
            _isInTrashZone = false;
          });
          widget.onItemsChanged();
        },
        child: Transform.translate(
          // Offset by half size approximately to keep the touch point centered?
          // Since it's Positioned, the x,y is the top-left corner.
          // Transform scales around its center.
          offset: Offset.zero,
          child: Transform.scale(
            scale: item.scale,
            child: Transform.rotate(
              angle: item.rotation,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
