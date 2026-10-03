import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/utils/image_url_helper.dart';
import '../../core/theme/app_theme.dart';

class PhotoItem {
  final String? url;
  final XFile? file;
  final Uint8List? bytes;
  final String id;

  PhotoItem({
    this.url,
    this.file,
    this.bytes,
    required this.id,
  });
}

class MultiPhotoManager extends StatefulWidget {
  final List<PhotoItem> photos;
  final ValueChanged<List<PhotoItem>> onPhotosChanged;
  final bool isDark;
  final int maxPhotos;

  const MultiPhotoManager({
    super.key,
    required this.photos,
    required this.onPhotosChanged,
    required this.isDark,
    this.maxPhotos = 4,
  });

  @override
  State<MultiPhotoManager> createState() => _MultiPhotoManagerState();
}

class _MultiPhotoManagerState extends State<MultiPhotoManager> {
  final ImagePicker _picker = ImagePicker();

  Future<PhotoItem> _createPhotoItem(XFile file) async {
    final bytes = await file.readAsBytes();
    return PhotoItem(
      file: file,
      bytes: bytes,
      id: 'file_${DateTime.now().microsecondsSinceEpoch}_${file.name}',
    );
  }

  Future<void> _pickPhotos() async {
    final remaining = widget.maxPhotos - widget.photos.length;
    if (remaining <= 0) return;

    try {
      if (remaining > 1) {
        final List<XFile> pickedList = await _picker.pickMultiImage(
          imageQuality: 85,
          maxWidth: 1080,
        );
        if (pickedList.isNotEmpty) {
          final newItems = await Future.wait(
            pickedList.take(remaining).map((f) => _createPhotoItem(f)),
          );
          final updated = List<PhotoItem>.from(widget.photos)..addAll(newItems);
          widget.onPhotosChanged(updated);
        }
      } else {
        final XFile? picked = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 1080,
        );
        if (picked != null) {
          final newItem = await _createPhotoItem(picked);
          final updated = List<PhotoItem>.from(widget.photos)..add(newItem);
          widget.onPhotosChanged(updated);
        }
      }
    } catch (e) {
      debugPrint('Error picking images: $e');
    }
  }

  Future<void> _replacePhoto(int index) async {
    HapticFeedback.selectionClick();
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1080,
      );
      if (picked != null) {
        final newItem = await _createPhotoItem(picked);
        final updated = List<PhotoItem>.from(widget.photos);
        if (index < updated.length) {
          updated[index] = newItem;
        } else {
          updated.add(newItem);
        }
        widget.onPhotosChanged(updated);
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint('Error replacing photo: $e');
    }
  }

  void _removePhoto(int index) {
    HapticFeedback.mediumImpact();
    final updated = List<PhotoItem>.from(widget.photos)..removeAt(index);
    widget.onPhotosChanged(updated);
  }

  void _movePhoto(int fromIndex, int toIndex) {
    if (toIndex < 0 || toIndex >= widget.photos.length || fromIndex == toIndex) return;
    HapticFeedback.selectionClick();
    final updated = List<PhotoItem>.from(widget.photos);
    final item = updated.removeAt(fromIndex);
    updated.insert(toIndex, item);
    widget.onPhotosChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Profile Photos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${widget.photos.length}/${widget.maxPhotos}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.photos.length < widget.maxPhotos)
              TextButton.icon(
                onPressed: _pickPhotos,
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                label: const Text('Add Photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Tap any photo to change it. Drag or tap arrows to reorder. 1st is your main avatar ⭐',
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? Colors.white54 : AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),

        // 2x2 Photo Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.maxPhotos,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (context, index) {
            if (index < widget.photos.length) {
              return _buildPhotoTile(index, widget.photos[index], isDark);
            } else {
              return _buildEmptySlot(index, isDark);
            }
          },
        ),
      ],
    );
  }

  Widget _buildPhotoTile(int index, PhotoItem item, bool isDark) {
    final isPrimary = index == 0;

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) {
        _movePhoto(details.data, index);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;

        final tile = _buildTileContainer(index, item, isPrimary, isDark, isHovered);

        final feedback = Material(
          elevation: 16,
          borderRadius: BorderRadius.circular(20),
          color: Colors.transparent,
          child: SizedBox(
            width: 140,
            height: 170,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildImageContent(item),
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Icon(Icons.drag_indicator_rounded, color: Colors.white, size: 32),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        // Use LongPressDraggable with a short 200ms delay on both web and mobile
        // so that simple taps/clicks immediately trigger buttons & image replacement,
        // while holding for a brief moment initiates drag reordering.
        return LongPressDraggable<int>(
          delay: const Duration(milliseconds: 200),
          data: index,
          feedback: feedback,
          childWhenDragging: Opacity(opacity: 0.35, child: tile),
          child: tile,
        );
      },
    );
  }

  Widget _buildTileContainer(
    int index,
    PhotoItem item,
    bool isPrimary,
    bool isDark,
    bool isHovered,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHovered
              ? AppTheme.accentPink
              : isPrimary
                  ? AppTheme.primaryBlue
                  : (isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1)),
          width: isPrimary ? 2.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isPrimary
                ? AppTheme.primaryBlue.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: isPrimary ? 12 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Image (tap anywhere on photo to change it!)
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _replacePhoto(index),
                  behavior: HitTestBehavior.opaque,
                  child: _buildImageContent(item, index),
                ),
              ),
            ),

            // Top gradient scrim
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 52,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.65),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom gradient scrim
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 52,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Slot badge (Top Left)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isPrimary ? AppTheme.primaryBlue : Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPrimary) ...[
                      const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                      const SizedBox(width: 3),
                      const Text(
                        'MAIN',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ] else ...[
                      Text(
                        '#${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Action Buttons (Top Right: Change + Delete)
            Positioned(
              top: 6,
              right: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Change / Replace button
                  Tooltip(
                    message: 'Change photo',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _replacePhoto(index),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1),
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Delete button
                  Tooltip(
                    message: 'Remove photo',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _removePhoto(index),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Reorder Controls: Move Left, Change button, Move Right
            Positioned(
              bottom: 6,
              left: 6,
              right: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (index > 0)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _movePhoto(index, index - 1),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.8),
                          ),
                          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 14),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 26),
                  
                  // Center "Change" pill
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _replacePhoto(index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_camera_rounded, size: 12, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'Change',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  if (index < widget.photos.length - 1)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _movePhoto(index, index + 1),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.8),
                          ),
                          child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 14),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 26),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySlot(int index, bool isDark) {
    final isFirstEmpty = index == widget.photos.length;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _pickPhotos,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isFirstEmpty
                  ? AppTheme.primaryBlue.withValues(alpha: 0.4)
                  : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isFirstEmpty
                      ? AppTheme.primaryBlue.withValues(alpha: 0.12)
                      : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFirstEmpty ? Icons.add_rounded : Icons.photo_outlined,
                  color: isFirstEmpty
                      ? AppTheme.primaryBlue
                      : (isDark ? Colors.white30 : Colors.black26),
                  size: 26,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isFirstEmpty ? 'Add Photo' : 'Slot #${index + 1}',
                style: TextStyle(
                  color: isFirstEmpty
                      ? AppTheme.primaryBlue
                      : (isDark ? Colors.white38 : Colors.black38),
                  fontWeight: isFirstEmpty ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageContent(PhotoItem item, [int? index]) {
    // 1. Direct In-Memory Bytes (Instant, zero network, zero CORS issues)
    if (item.bytes != null && item.bytes!.isNotEmpty) {
      return Image.memory(
        item.bytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackTile(index),
      );
    }

    // 2. Local File (if bytes not cached yet, read asynchronously)
    if (item.file != null) {
      return FutureBuilder<Uint8List>(
        future: item.file!.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            return Image.memory(snapshot.data!, fit: BoxFit.cover);
          }
          return Container(
            color: widget.isDark ? const Color(0xFF1E1B4B) : const Color(0xFFFDE8F0),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      );
    }

    // 3. Network URL
    if (item.url != null && item.url!.trim().isNotEmpty) {
      final trimmedUrl = item.url!.trim();
      final proxied = ImageUrlHelper.proxy(trimmedUrl);
      return Image.network(
        proxied,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: widget.isDark ? const Color(0xFF1E1B4B) : const Color(0xFFFDE8F0),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
              ),
            ),
          );
        },
        errorBuilder: (_, error, ___) {
          debugPrint('[MultiPhotoManager] Image failed: $proxied, error: $error');
          if (proxied != trimmedUrl) {
            return Image.network(
              trimmedUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallbackTile(index),
            );
          }
          return _buildFallbackTile(index);
        },
      );
    }

    return _buildFallbackTile(index);
  }

  Widget _buildFallbackTile([int? index]) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: index != null ? () => _replacePhoto(index) : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: widget.isDark ? const Color(0xFF1E1B4B) : const Color(0xFFFDE8F0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.photo_rounded, size: 32, color: Colors.white60),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Tap to change',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
