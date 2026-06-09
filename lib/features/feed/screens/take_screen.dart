// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'package:universal_html/html.dart' as html;
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../utils/ui_web_shim.dart' as ui_web;
import 'package:js/js.dart';
import '../utils/ar_interop.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';

// ─── Draggable Overlay Item ───────────────────────────────────────────────────
class DraggableItem {
  final String content;
  final bool isText;
  Offset position;
  double scale;

  DraggableItem({
    required this.content,
    required this.isText,
    this.position = const Offset(100, 100),
    this.scale = 1.0,
  });
}

// ─── Instagram-style Color Filter Matrices ────────────────────────────────────
class AppColorFilters {
  static const Map<String, List<double>> _matrices = {
    'Normal': [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ],
    'Clarendon': [
      1.1,  0,    0,    0, -20,
      0,    1.05, 0,    0, -10,
      0,    0,    1.15, 0, -20,
      0,    0,    0,    1,   0,
    ],
    'Gingham': [
      0.98, 0.02, 0,    0, 10,
      0.02, 0.98, 0,    0, 10,
      0,    0,    0.92, 0, 20,
      0,    0,    0,    1,  0,
    ],
    'Moon': [
      0.37, 0.34, 0.29, 0, 15,
      0.37, 0.34, 0.29, 0, 15,
      0.37, 0.34, 0.29, 0, 15,
      0,    0,    0,    1,  0,
    ],
    'Lark': [
      1.0,  0,    0,    0,  5,
      0,    1.12, 0,    0,  5,
      0,    0,    1.08, 0,  0,
      0,    0,    0,    1,  0,
    ],
    'Valencia': [
      1.08, 0,    0,    0, 12,
      0,    0.95, 0,    0,  8,
      0,    0,    0.85, 0,  5,
      0,    0,    0,    1,  0,
    ],
  };

  static List<double> get(String name) => _matrices[name] ?? _matrices['Normal']!;
  static List<String> get names => _matrices.keys.toList();
}

// ─── Filter Calibration Config ───────────────────────────────────────────────
class FilterConfig {
  double scale;
  double offsetX;
  double offsetY;

  FilterConfig({
    this.scale   = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
  });
}

// ─── Firestore instance ───────────────────────────────────────────────────────
final _db = FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: 'default',
);

// ─── TakeScreen ───────────────────────────────────────────────────────────────
class TakeScreen extends ConsumerStatefulWidget {
  const TakeScreen({super.key});

  @override
  ConsumerState<TakeScreen> createState() => _TakeScreenState();
}

class _TakeScreenState extends ConsumerState<TakeScreen>
    with SingleTickerProviderStateMixin {
  // ── Mode state ──
  String _mode = 'PHOTO'; // PHOTO | VIDEO
  String _tab = 'FILTER'; // FILTER | TEXT | STICKERS
  String _filter = 'Normal';

  // ── Camera / Media state ──
  html.VideoElement? _videoElement;
  html.MediaStream? _stream;
  bool _cameraReady = false;
  String? _cameraError;
  String? _viewType;
  
  // ── Video Recording ──
  html.MediaRecorder? _mediaRecorder;
  final List<html.Blob> _videoChunks = [];
  Uint8List? _capturedVideoBytes;
  String? _previewVideoUrl;
  String? _previewViewType;

  // ── AR Tracking ──
  html.CanvasElement? _arCanvasElement;
  String? _arViewType;
  String _arFilter = 'NONE';
  static const _arFilters = [
    'NONE',
    'Thug Life',
    'Dog',
    'Cat',
    'Bunny',
    'Flower Crown',
    'Devil',
    'Angel',
    'Crown',
    'Heart Eyes',
    'Clown',
    'Rainbow',
    'Fire',
    'Cyberpunk',
    'Stars',
    'Tears',
    'Beard',
    'Sunglasses',
    'Neon',
    'Glitter',
    'Alien',
  ];

  // ── Live Filter Calibration ──
  bool _showCalibrator = false;
  double _calScale   = 1.0;
  double _calOffsetX = 0.0;
  double _calOffsetY = 0.0;

  void _updateFilterConfig() {
    if (_arFilter == 'NONE') return;
    try {
      updateARFilterConfig(_arFilter, _calScale, _calOffsetX, _calOffsetY);
    } catch (_) {}
  }

  // ── Capture state ──
  Uint8List? _capturedImageBytes;
  bool _isRecording = false;
  Timer? _recordTimer;
  int _recordSeconds = 0;

  // ── Overlay items ──
  final List<DraggableItem> _overlays = [];
  final GlobalKey _previewKey = GlobalKey();

  // ── Upload / Post state ──
  bool _isSaving = false;

  // ── Animation ──
  late AnimationController _shutterAnim;
  late Animation<double> _shutterScale;

  // ── Filter thumbnails cache ──
  final String _filterColors = '';

  @override
  void initState() {
    super.initState();
    _shutterAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _shutterScale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _shutterAnim, curve: Curves.easeInOut),
    );
    if (kIsWeb) _initWebCamera();
  }

  @override
  void dispose() {
    _stopCamera();
    _shutterAnim.dispose();
    _recordTimer?.cancel();
    super.dispose();
  }

  // ─── Camera Lifecycle ───────────────────────────────────────────────────────

  Future<void> _initWebCamera() async {
    final viewType = 'camera-view-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _viewType = viewType;
      _cameraError = null;
      _cameraReady = false;
    });

    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception('MediaDevices API not supported in this browser.');
      }

      final stream = await mediaDevices.getUserMedia({
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
        'audio': false,
      });

      _stream = stream;

      final video = html.VideoElement()
        ..srcObject = stream
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true');
        // We don't style or mirror the video element itself anymore because it's hidden and processed by JS.

      _stream = stream;
      _videoElement = video;

      // Initialize AR Tracker
      final canvas = initializeARTracker(video);
      canvas.style.width = '100%';
      canvas.style.height = '100%';
      canvas.style.objectFit = 'cover';
      _arCanvasElement = canvas;

      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        viewType,
        (int id) => canvas,
      );

      _arViewType = viewType;

      // Wait for camera to actually be playing
      video.onPlaying.first.then((_) {
        if (mounted) setState(() => _cameraReady = true);
      });

      // Timeout fallback
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_cameraReady && _stream != null) {
          setState(() => _cameraReady = true);
        }
      });
    } on html.DomException catch (e) {
      debugPrint('Camera DomException: ${e.name}: ${e.message}');
      String msg;
      if (e.name == 'NotAllowedError' || e.name == 'PermissionDeniedError') {
        msg = '📷 Camera permission denied.\n\nClick the camera icon in your browser address bar to allow access, then press "Retry".';
      } else if (e.name == 'NotFoundError') {
        msg = '📷 No camera found on this device.\n\nUse the UPLOAD button to select a photo.';
      } else if (e.name == 'NotReadableError') {
        msg = '📷 Camera is in use by another application.\n\nClose other apps using your camera and press "Retry".';
      } else {
        msg = '📷 Camera error: ${e.name}\n\nTry using the UPLOAD button.';
      }
      if (mounted) setState(() => _cameraError = msg);
    } catch (e) {
      debugPrint('Camera error: $e');
      if (mounted) {
        setState(() => _cameraError = '📷 Camera unavailable.\n\nUse the UPLOAD button to select a photo.');
      }
    }
  }

  void _stopCamera() {
    _stream?.getTracks().forEach((track) => track.stop());
    stopARTracker();
    _stream = null;
    _videoElement = null;
    _arCanvasElement = null;
  }

  // ─── Photo Capture ──────────────────────────────────────────────────────────

  Future<void> _takePhoto() async {
    if (_arCanvasElement == null) return;

    _shutterAnim.forward().then((_) => _shutterAnim.reverse());

    // Capture directly from the AR Canvas, which already includes the mirrored image and AR filters
    final blob = await _arCanvasElement!.toBlob('image/jpeg', 0.70);
    final reader = html.FileReader();
    reader.readAsArrayBuffer(blob);
    await reader.onLoad.first;
    final bytes = Uint8List.fromList(reader.result as List<int>);

    setState(() {
      _capturedImageBytes = bytes;
    });
  }

  Future<void> _uploadFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1280,
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() => _capturedImageBytes = bytes);
    }
  }

  void _retake() {
    setState(() {
      _capturedImageBytes = null;
      _capturedVideoBytes = null;
      if (_previewVideoUrl != null) {
        html.Url.revokeObjectUrl(_previewVideoUrl!);
        _previewVideoUrl = null;
      }
      _previewViewType = null;
      _overlays.clear();
    });
  }

  // ─── Post / Upload ──────────────────────────────────────────────────────────

  Future<void> _post() async {
    if (_capturedImageBytes == null) {
      _snack('Take a photo or upload one first! 📸');
      return;
    }
    setState(() => _isSaving = true);

    try {
      // If there are overlays, capture the composed view via RepaintBoundary
      Uint8List? uploadBytes;
      if (_overlays.isEmpty) {
        uploadBytes = _capturedImageBytes!;
      } else {
        try {
          final boundary = _previewKey.currentContext
              ?.findRenderObject() as RenderRepaintBoundary?;
          if (boundary != null) {
            final image = await boundary.toImage(pixelRatio: 2.0);
            final byteData =
                await image.toByteData(format: ui.ImageByteFormat.png);
            uploadBytes = byteData?.buffer.asUint8List() ?? _capturedImageBytes!;
          } else {
            uploadBytes = _capturedImageBytes!;
          }
        } catch (_) {
          uploadBytes = _capturedImageBytes!;
        }
      }

      final currentUser = ref.read(currentUserProvider);
      final storyId = DateTime.now().millisecondsSinceEpoch.toString();
      final ext = _overlays.isEmpty ? 'jpg' : 'png';
      final storageRef =
          FirebaseStorage.instance.ref('stories/$storyId.$ext');
      await storageRef.putData(
        uploadBytes!,
        SettableMetadata(contentType: 'image/$ext'),
      );
      final imageUrl = await storageRef.getDownloadURL();

      String? videoUrl;
      if (_capturedVideoBytes != null) {
        final videoRef = FirebaseStorage.instance.ref('stories/$storyId.webm');
        await videoRef.putData(
          _capturedVideoBytes!,
          SettableMetadata(contentType: 'video/webm'),
        );
        videoUrl = await videoRef.getDownloadURL();
      }

      final Map<String, dynamic> overlayDataList = {};
      for (var i = 0; i < _overlays.length; i++) {
        final o = _overlays[i];
        overlayDataList[i.toString()] = {
          'content': o.content,
          'isText': o.isText,
          'dx': o.position.dx,
          'dy': o.position.dy,
          'scale': o.scale,
        };
      }

      await _db.collection('stories').doc(storyId).set({
        'id': storyId,
        'userId': currentUser.id,
        'userName': currentUser.name,
        'userAvatar': currentUser.avatarUrl,
        'imageUrl': imageUrl,
        if (videoUrl != null) 'videoUrl': videoUrl,
        'filter': _filter,
        'caption': '',
        'overlays': overlayDataList,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'expiresAt':
            DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
        'viewers': [],
      });

      if (mounted) {
        _snack('Take shared! ✨ +5 aura applied', isSuccess: true);
        _stopCamera();
        context.pop();
      }
    } catch (e) {
      debugPrint('Post error: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        _snack('Failed to share: $e', isError: true);
      }
    }
  }

  void _snack(String msg, {bool isError = false, bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError
          ? AppTheme.error
          : isSuccess
              ? AppTheme.success
              : AppTheme.primaryBlue,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─── Text & Sticker Overlays ────────────────────────────────────────────────

  void _addText() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Text',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(
            hintText: 'Type something...',
            hintStyle: const TextStyle(color: Colors.white38),
            counterStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: AppTheme.darkBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() => _overlays.add(
                    DraggableItem(content: ctrl.text.trim(), isText: true)));
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _addSticker() {
    const stickers = [
      '🔥', '✨', '💜', '😍', '😂', '❤️', '💯', '🎉',
      '👑', '🌟', '🥂', '💫', '🎶', '🦋', '🌸', '💅',
      '😈', '🤍', '🌙', '🫀', '🥵', '🫶', '💌', '🎯',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Text('Choose a Sticker',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: stickers
                  .map((e) => GestureDetector(
                        onTap: () {
                          setState(() => _overlays.add(
                              DraggableItem(content: e, isText: false)));
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.darkBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(e, style: const TextStyle(fontSize: 28)),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildPreviewArea()),
            _buildBottomControls(),
            _buildTabBar(),
            _buildTabContent(),
            _buildPostBar(),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ─────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              _stopCamera();
              context.pop();
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                _modeBtn('PHOTO'),
                _modeBtn('VIDEO'),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _uploadFromGallery,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white24),
              ),
              child: const Row(
                children: [
                  Icon(Icons.upload_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('UPLOAD',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeBtn(String m) {
    final sel = _mode == m;
    return GestureDetector(
      onTap: () => setState(() => _mode = m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          m,
          style: TextStyle(
            color: sel ? Colors.black : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ── Preview Area ─────────────────────────────────────────────────────────────
  Widget _buildPreviewArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: RepaintBoundary(
          key: _previewKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Base layer: camera or captured image
              _buildBaseLayer(),
              // Filter overlay (for captured image)
              if (_capturedImageBytes != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColorFiltered(
                      colorFilter: ColorFilter.matrix(
                          AppColorFilters.get(_filter)),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                ),
              // Text/Sticker overlays
              ..._overlays.map((item) => _buildOverlayItem(item)),
              // Recording indicator
              if (_isRecording)
                Positioned(
                  top: 16,
                  left: 16,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppTheme.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatDuration(_recordSeconds),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              // Live filter calibrator (appears when long-pressing a filter)
              _buildFilterCalibrator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBaseLayer() {
    // Live looping video preview
    if (_previewVideoUrl != null && _previewViewType != null) {
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(AppColorFilters.get(_filter)),
        child: HtmlElementView(viewType: _previewViewType!),
      );
    }

    // Captured photo from camera or gallery
    if (_capturedImageBytes != null) {
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(AppColorFilters.get(_filter)),
        child: Image.memory(_capturedImageBytes!, fit: BoxFit.cover),
      );
    }

    // Live camera feed
    if (_cameraError != null) {
      return Container(
        color: AppTheme.darkCard,
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_rounded,
                  color: Colors.white24, size: 64),
              const SizedBox(height: 16),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _cameraError = null;
                    _cameraReady = false;
                    _viewType = null;
                    _arViewType = null;
                  });
                  _initWebCamera();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _uploadFromGallery,
                icon: const Icon(Icons.upload_file_rounded,
                    color: Colors.white54),
                label: const Text('Upload from Gallery',
                    style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
      );
    }

    if (!_cameraReady || _arViewType == null) {
      return Container(
        color: AppTheme.darkCard,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.accentPurple),
              SizedBox(height: 12),
              Text('Starting AR camera...',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    // Render the live HTML AR Canvas element
    return HtmlElementView(viewType: _arViewType!);
  }

  Widget _buildOverlayItem(DraggableItem item) {
    return Positioned(
      left: item.position.dx,
      top: item.position.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() => item.position += d.delta);
        },
        onScaleUpdate: (d) {
          setState(() => item.scale = (item.scale * d.scale).clamp(0.5, 5.0));
        },
        onDoubleTap: () {
          setState(() => _overlays.remove(item));
        },
        child: Transform.scale(
          scale: item.scale,
          child: item.isText
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.black, blurRadius: 6),
                      ],
                    ),
                  ),
                )
              : Text(item.content, style: const TextStyle(fontSize: 52)),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Bottom Shutter Controls ───────────────────────────────────────────────────
  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: retake if captured, else flip camera placeholder
          GestureDetector(
            onTap: _capturedImageBytes != null ? _retake : null,
            child: AnimatedOpacity(
              opacity: _capturedImageBytes != null ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.refresh_rounded,
                        color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('Retake',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),

          // Center: Shutter button
          if (_capturedImageBytes == null)
            ScaleTransition(
              scale: _shutterScale,
              child: GestureDetector(
                onTap: () {
                  if (_mode == 'PHOTO') {
                    _handlePhotoShutter();
                  } else if (_mode == 'VIDEO') {
                    if (_isRecording) {
                      _stopVideoRecord();
                    } else {
                      _startVideoRecord();
                    }
                  }
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _mode == 'VIDEO'
                          ? AppTheme.error
                          : Colors.white,
                      shape: _isRecording
                          ? BoxShape.rectangle
                          : BoxShape.circle,
                      borderRadius:
                          _isRecording ? BorderRadius.circular(8) : null,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 80),

          // Right: empty spacer (balance)
          const SizedBox(width: 80),
        ],
      ),
    );
  }

  Future<void> _handlePhotoShutter() async {
    if (!_cameraReady) return;
    await _takePhoto();
  }

  Future<void> _startVideoRecord() async {
    if (_stream == null) return;
    _videoChunks.clear();
    
    try {
      // Use MediaRecorder to record the AR Canvas stream
      final options = {
        'mimeType': 'video/webm;codecs=vp8,opus',
        'videoBitsPerSecond': 800000,
      };
      
      // Capture stream from the Canvas to bake in AR filters!
      final canvasStream = _arCanvasElement!.captureStream(30);
      _mediaRecorder = html.MediaRecorder(canvasStream, options);
      
      _mediaRecorder!.addEventListener('dataavailable', (event) {
        final e = event as html.BlobEvent;
        if (e.data != null && e.data!.size > 0) {
          _videoChunks.add(e.data!);
        }
      });
      
      _mediaRecorder!.start(1000); // collect data every second
      
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordSeconds++);
      });
    } catch (e) {
      debugPrint('MediaRecorder error: $e');
      _snack('Video recording not supported in this browser. Use Photo mode.');
    }
  }

  Future<void> _stopVideoRecord() async {
    _recordTimer?.cancel();
    if (_mediaRecorder == null) {
      setState(() => _isRecording = false);
      return;
    }
    
    final completer = Completer<void>();
    _mediaRecorder!.addEventListener('stop', (_) => completer.complete());
    _mediaRecorder!.stop();
    
    await completer.future;
    
    if (_videoChunks.isEmpty) {
      setState(() => _isRecording = false);
      _snack('No video data recorded. Try again.');
      return;
    }
    
    // Combine all chunks into one blob
    final videoBlob = html.Blob(_videoChunks, 'video/webm');
    
    // Create instant preview video element
    final videoUrl = html.Url.createObjectUrlFromBlob(videoBlob);
    final previewType = 'preview-video-${DateTime.now().millisecondsSinceEpoch}';
    final videoEl = html.VideoElement()
      ..src = videoUrl
      ..autoplay = true
      ..loop = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.transform = 'scaleX(-1)';
      
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      previewType,
      (int id) => videoEl,
    );

    final reader = html.FileReader();
    reader.readAsArrayBuffer(videoBlob);
    await reader.onLoad.first;
    final videoBytes = Uint8List.fromList(reader.result as List<int>);
    
    setState(() {
      _isRecording = false;
      _capturedVideoBytes = videoBytes;
      _previewVideoUrl = videoUrl;
      _previewViewType = previewType;
      // Use a thumbnail from current camera frame
    });
    
    // Take a photo as thumbnail for the video
    await _takePhoto();
    
    _snack('Video recorded! (${_recordSeconds}s) Tap Post to share.');
  }

  // ── Tab Bar ──────────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: ['FILTER', 'TEXT', 'STICKERS']
          .map((t) => _tabBtn(t))
          .toList(),
    );
  }

  Widget _tabBtn(String t) {
    final sel = _tab == t;
    return GestureDetector(
      onTap: () {
        setState(() => _tab = t);
        if (t == 'TEXT') _addText();
        if (t == 'STICKERS') _addSticker();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: sel
              ? AppTheme.accentPurple.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: sel
              ? Border.all(color: AppTheme.accentPurple.withOpacity(0.4))
              : null,
        ),
        child: Text(
          t,
          style: TextStyle(
            color: sel ? AppTheme.accentPurple : Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  // ── Tab Content (Filters) ────────────────────────────────────────────────────
  Widget _buildTabContent() {
    if (_tab == 'FILTER') return _buildARFilterBar();
    return const SizedBox(height: 16);
  }

  // ── Post Bar ─────────────────────────────────────────────────────────────────
  Widget _buildPostBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '✨ +5 aura on first post today',
            style:
                TextStyle(color: Colors.white38, fontSize: 12),
          ),
          AnimatedOpacity(
            opacity: _capturedImageBytes != null ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 200),
            child: ElevatedButton(
              onPressed:
                  _isSaving || _capturedImageBytes == null ? null : _post,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Post',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildARFilterBar() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _arFilters.length,
        itemBuilder: (ctx, i) {
          final f = _arFilters[i];
          final sel = _arFilter == f;
          return GestureDetector(
            onTap: () {
              setState(() {
                _arFilter = f;
                _calScale   = 1.0;
                _calOffsetX = 0.0;
                _calOffsetY = 0.0;
                _showCalibrator = false;
              });
              setARFilter(f);
            },
            onLongPress: () {
              if (f == 'NONE') return;
              setState(() {
                _arFilter = f;
                _showCalibrator = !_showCalibrator;
              });
              setARFilter(f);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: sel
                    ? AppTheme.accentPurple.withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: sel
                      ? AppTheme.accentPurple
                      : Colors.white.withOpacity(0.15),
                ),
              ),
              child: Center(
                child: Text(
                  f,
                  style: TextStyle(
                    color: sel ? AppTheme.accentPurple : Colors.white60,
                    fontSize: 12,
                    fontWeight:
                        sel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Live Filter Calibrator Panel ─────────────────────────────────────────────
  Widget _buildFilterCalibrator() {
    if (!_showCalibrator || _arFilter == 'NONE') return const SizedBox();
    return Positioned(
      bottom: 130,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.82),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.accentPurple.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentPurple.withOpacity(0.3),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Calibrate: $_arFilter',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showCalibrator = false),
                  child: const Icon(Icons.close, color: Colors.white54, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _calibSlider(
              label: 'Scale',
              value: _calScale,
              min: 0.3,
              max: 3.5,
              onChanged: (v) {
                setState(() => _calScale = v);
                _updateFilterConfig();
              },
            ),
            _calibSlider(
              label: 'X Offset',
              value: _calOffsetX,
              min: -1.5,
              max: 1.5,
              onChanged: (v) {
                setState(() => _calOffsetX = v);
                _updateFilterConfig();
              },
            ),
            _calibSlider(
              label: 'Y Offset',
              value: _calOffsetY,
              min: -1.5,
              max: 1.5,
              onChanged: (v) {
                setState(() => _calOffsetY = v);
                _updateFilterConfig();
              },
            ),
            const SizedBox(height: 4),
            Text(
              'S:${_calScale.toStringAsFixed(2)}  X:${_calOffsetX.toStringAsFixed(2)}  Y:${_calOffsetY.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calibSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppTheme.accentPurple,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: AppTheme.accentPurple.withOpacity(0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
