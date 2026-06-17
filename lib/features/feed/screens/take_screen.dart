// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import '../utils/ui_web_shim.dart' as ui_web;
import '../utils/ar_interop.dart';
import '../utils/ar_webview_camera.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
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
import '../../../core/utils/color_filters.dart';

import '../widgets/overlay_manager.dart';
import '../widgets/text_editor_overlay.dart';

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
  String _tab = 'NONE'; // NONE | AR | FILTERS | STICKERS
  String _filter = 'Normal';
  bool _isDraggingItem = false;

  // ── Camera / Media state (Web) ──
  bool _isFrontCamera = true;
  web.HTMLVideoElement? _videoElement;
  web.MediaStream? _stream;
  bool _cameraReady = false;
  String? _cameraError;
  String? _viewType;

  // ── Native Camera (Android / iOS via WebView AR) ──
  CameraController? _cameraController;   // kept for backward compat but unused on Android
  bool _nativeCameraReady = false;
  bool _nativeCameraPermissionDenied = false;
  bool _nativeCameraPermissionPermanentlyDenied = false;
  // WebView AR key — used to call captureFrame / setFilter on the WebView
  final GlobalKey<ARWebViewCameraState> _arWebViewKey = GlobalKey<ARWebViewCameraState>();
  bool _arWebViewReady = false;
  bool _arWebViewRecording = false;

  // ── Video Recording ──
  web.MediaRecorder? _mediaRecorder;
  final List<web.Blob> _videoChunks = [];
  Uint8List? _capturedVideoBytes;
  String? _previewVideoUrl;
  String? _previewViewType;

  // ── AR Tracking ──
  web.HTMLCanvasElement? _arCanvasElement;
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
  final List<OverlayItem> _overlays = [];
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
    if (kIsWeb) {
      _initWebCamera();
    } else {
      _initNativeCamera();
    }
  }

  @override
  void dispose() {
    _stopCamera();
    _cameraController?.dispose();
    _shutterAnim.dispose();
    _recordTimer?.cancel();
    super.dispose();
  }

  // ─── Native Camera Init (Android / iOS) ─────────────────────────────────────
  Future<void> _initNativeCamera() async {
    // Request camera permission first
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied) {
      if (mounted) setState(() => _nativeCameraPermissionPermanentlyDenied = true);
      return;
    }
    if (!status.isGranted) {
      if (mounted) setState(() => _nativeCameraPermissionDenied = true);
      return;
    }
    // Permission granted — show the AR WebView (it handles getUserMedia internally)
    if (mounted) setState(() => _nativeCameraReady = true);
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
      final mediaDevices = web.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception('MediaDevices API not supported in this browser.');
      }

      final constraints = {
        'video': {
          'facingMode': _isFrontCamera ? 'user' : 'environment',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
        'audio': false,
      }.jsify() as web.MediaStreamConstraints;
      final stream = await mediaDevices.getUserMedia(constraints).toDart;

      _stream = stream;

      final video = web.HTMLVideoElement()
        ..srcObject = stream
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true');
        // We don't style or mirror the video element itself anymore because it's hidden and processed by JS.

      _stream = stream;
      _videoElement = video;

      // Initialize AR Tracker
      final canvas = initializeARTracker(video, _isFrontCamera ? 'user' : 'environment');
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
    } on web.DOMException catch (e) {
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
    if (kIsWeb) {
      if (_videoElement != null) {
        _videoElement!.pause();
        _videoElement!.removeAttribute('src');
        _videoElement!.load();
        _videoElement!.srcObject = null;
      }
      _stream?.getTracks().toDart.forEach((track) {
        track.stop();
      });
      stopARTracker();
      _stream = null;
      _videoElement = null;
      _arCanvasElement = null;
    } else {
      _arWebViewKey.currentState?.stopCamera();
    }
  }

  // ─── Photo Capture ──────────────────────────────────────────────────────────

  Future<void> _takePhoto() async {
    _shutterAnim.forward().then((_) => _shutterAnim.reverse());

    if (!kIsWeb) {
      // Android: trigger frame capture from the AR WebView
      await _arWebViewKey.currentState?.captureFrame();
      // The result comes back via onCapture callback — nothing else needed here
      return;
    }

    // ── Web: capture from the AR Canvas ──
    if (_arCanvasElement == null) return;
    
    // Grab the image synchronously as a high-quality base64 string
    // This is significantly faster and higher quality than toBlob + FileReader
    final dataUrl = _arCanvasElement!.toDataUrl('image/jpeg', 1.0);
    final parts = dataUrl.split(',');
    if (parts.length < 2) {
      _snack('Camera is still loading. Please wait a moment.');
      return;
    }
    
    final base64Str = parts.last;
    if (base64Str.isEmpty || base64Str.length < 100) {
      _snack('Camera is still initializing. Please wait a moment.');
      return;
    }
    
    final bytes = base64Decode(base64Str);
    setState(() => _capturedImageBytes = bytes);
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
        web.URL.revokeObjectURL(_previewVideoUrl!);
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
      // If there are overlays or a filter, capture the composed view via RepaintBoundary
      Uint8List? uploadBytes;
      if (_overlays.isEmpty && _filter == 'Normal') {
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
          'id': o.id,
          'content': o.content,
          'isText': o.isText,
          'dx': o.position.dx,
          'dy': o.position.dy,
          'scale': o.scale,
          'rotation': o.rotation,
          'fontFamily': o.fontFamily,
          'color': o.color.value,
          'hasBackground': o.hasBackground,
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
    final result = await Navigator.push<OverlayItem>(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, _, __) => const TextEditorOverlay(),
      ),
    );
    if (result != null) {
      setState(() => _overlays.add(result));
    }
  }

  void _editOverlayItem(OverlayItem item) async {
    final result = await Navigator.push<OverlayItem>(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, _, __) => TextEditorOverlay(initialItem: item),
      ),
    );
    if (result != null) {
      setState(() {
        final idx = _overlays.indexWhere((e) => e.id == item.id);
        if (idx != -1) _overlays[idx] = result;
      });
    }
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
                            OverlayItem(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              content: e, 
                              isText: false,
                              position: const Offset(150, 250),
                            )
                          ));
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
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _stopCamera();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen camera preview
          _buildPreviewArea(),
          
          // Floating Controls Overlay
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isDraggingItem ? 0.0 : 1.0,
            child: IgnorePointer(
              ignoring: _isDraggingItem,
              child: SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(),
                    const Spacer(),
                    _buildTabContent(),
                    _buildTabBar(),
                    _buildBottomControls(),
                    _buildPostBar(),
                  ],
                ),
              ),
            ),
          ),
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
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
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
            onTap: () {
              setState(() => _isFrontCamera = !_isFrontCamera);
              if (kIsWeb) {
                _stopCamera();
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) _initWebCamera();
                });
              } else {
                _arWebViewKey.currentState?.flipCamera(_isFrontCamera);
              }
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 20),
            ),
          ),
          GestureDetector(
            onTap: () {
              if (_tab != 'NONE') {
                setState(() => _tab = 'NONE');
              }
              _addText();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, spreadRadius: 2),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.text_fields_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text('Text',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
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
    return RepaintBoundary(
      key: _previewKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base layer: camera or captured image
          _buildBaseLayer(),
          
          // Gradients to make UI text visible over bright camera feeds
          const Positioned(
            top: 0, left: 0, right: 0, height: 160,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 0, left: 0, right: 0, height: 240,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),
          
              // Filter overlay (for captured image)
              if (_capturedImageBytes != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColorFiltered(
                      colorFilter: ColorFilter.matrix(AppColorFilters.get(_filter)),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                ),
              // Text/Sticker overlays
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_tab != 'NONE') {
                    setState(() => _tab = 'NONE');
                  } else {
                    _addText();
                  }
                },
                child: OverlayManager(
                  items: _overlays,
                  onDragStateChanged: (dragging) {
                    setState(() => _isDraggingItem = dragging);
                  },
                  onItemTap: (item) {
                    if (item.isText) {
                      _editOverlayItem(item);
                    }
                  },
                  onItemsChanged: () => setState(() {}),
                ),
              ),
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
    );
  }

  Widget _buildBaseLayer() {
    // ── ANDROID / iOS path ──────────────────────────────────────────────────
    if (!kIsWeb) {
      // Permission permanently denied → open settings
      if (_nativeCameraPermissionPermanentlyDenied) {
        return _buildPermissionScreen(
          message: '📷 Camera permission was permanently denied.\n\nOpen Settings to allow camera access.',
          actionLabel: 'Open Settings',
          onAction: () => openAppSettings(),
        );
      }
      // Permission denied (not permanent)
      if (_nativeCameraPermissionDenied) {
        return _buildPermissionScreen(
          message: '📷 Camera permission is required to take photos.',
          actionLabel: 'Grant Permission',
          onAction: () {
            setState(() => _nativeCameraPermissionDenied = false);
            _initNativeCamera();
          },
        );
      }
      // Error (e.g. no cameras)
      if (_cameraError != null) {
        return _buildPermissionScreen(
          message: _cameraError!,
          actionLabel: 'Upload from Gallery',
          onAction: _uploadFromGallery,
        );
      }
      // Loading (waiting for permission request to complete)
      if (!_nativeCameraReady) {
        return Container(
          color: AppTheme.darkCard,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppTheme.accentPurple),
                SizedBox(height: 12),
                Text('Starting camera...', style: TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ),
          ),
        );
      }

      // Keep the Live AR WebView always active in the background to avoid 
      // expensive reloads when hitting "Retake".
      return Stack(
        fit: StackFit.expand,
        children: [
          // Live AR WebView (fills frame, handles face mesh internally)
          ARWebViewCamera(
            key: _arWebViewKey,
            onReady: () => setState(() => _arWebViewReady = true),
            onCapture: (bytes) {
              setState(() => _capturedImageBytes = bytes);
            },
            onVideoCapture: (bytes) {
              setState(() {
                _capturedVideoBytes = bytes;
                _isRecording = false;
              });
              // Also trigger a still capture for thumbnail
              _arWebViewKey.currentState?.captureFrame();
              _snack('Video recorded! Tap Post to share.');
            },
          ),
          
          // Captured photo preview overlaid on top
          if (_capturedImageBytes != null)
            ColorFiltered(
              colorFilter: ColorFilter.matrix(AppColorFilters.get(_filter)),
              child: Image.memory(_capturedImageBytes!, fit: BoxFit.cover),
            ),
        ],
      );
    }

    // ── WEB path ────────────────────────────────────────────────────────────

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

    // Web camera error
    if (_cameraError != null) {
      return Container(
        color: AppTheme.darkCard,
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_rounded, color: Colors.white24, size: 64),
              const SizedBox(height: 16),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _uploadFromGallery,
                icon: const Icon(Icons.upload_file_rounded, color: Colors.white54),
                label: const Text('Upload from Gallery', style: TextStyle(color: Colors.white54)),
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
              Text('Starting AR camera...', style: TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    // Render the live HTML AR Canvas element
    // Note: Color matrix is applied via JS SVG filter
    return HtmlElementView(
      key: ValueKey(_arViewType!),
      viewType: _arViewType!,
    );
  }

  // ── Permission denied screen helper ──────────────────────────────────────────
  Widget _buildPermissionScreen({
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      color: AppTheme.darkCard,
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_rounded, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(actionLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _uploadFromGallery,
              icon: const Icon(Icons.upload_file_rounded, color: Colors.white54),
              label: const Text('Upload from Gallery', style: TextStyle(color: Colors.white54)),
            ),
          ],
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
          // Left: Empty space (if no image) or Retake (if image)
          _capturedImageBytes == null
              ? const SizedBox(width: 56)
              : GestureDetector(
                  onTap: _retake,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, spreadRadius: 2),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Retake', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
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
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 2),
                    ],
                  ),
                  padding: const EdgeInsets.all(6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _mode == 'VIDEO' ? AppTheme.error : Colors.white,
                      shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: _isRecording ? BorderRadius.circular(8) : null,
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
    if (kIsWeb && !_cameraReady) return;
    if (!kIsWeb && !_nativeCameraReady) return;
    await _takePhoto();
  }

  Future<void> _startVideoRecord() async {
    if (!kIsWeb) {
      // Android: start recording in the AR WebView
      await _arWebViewKey.currentState?.startRecording();
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordSeconds++);
      });
      return;
    }

    // ── Web path ──
    if (_stream == null || _arCanvasElement == null) return;
    _videoChunks.clear();
    
    try {
      // Capture stream from the Canvas to bake in AR filters!
      final canvasStream = _arCanvasElement!.captureStream(30);
      
      // Use MediaRecorder without forcing mimeType for broader browser support
      _mediaRecorder = web.MediaRecorder(canvasStream, web.MediaRecorderOptions(videoBitsPerSecond: 800000));
      
      _mediaRecorder!.addEventListener('dataavailable', (web.Event event) {
        final e = event as web.BlobEvent;
        if (e.data.size > 0) {
          _videoChunks.add(e.data);
        }
      }.toJS);
      
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

    if (!kIsWeb) {
      // Android: stop recording in the AR WebView
      // The result (video bytes) comes back via onVideoCapture callback
      await _arWebViewKey.currentState?.stopRecording();
      // _isRecording will be set to false in the onVideoCapture callback
      return;
    }

    // ── Web path ──
    if (_mediaRecorder == null) {
      setState(() => _isRecording = false);
      return;
    }
    
    final completer = Completer<void>();
    _mediaRecorder!.addEventListener('stop', ((web.Event _) => completer.complete()).toJS);
    _mediaRecorder!.stop();
    
    await completer.future;
    
    if (_videoChunks.isEmpty) {
      setState(() => _isRecording = false);
      _snack('No video data recorded. Try again.');
      return;
    }
    
    // Combine all chunks into one blob
    final videoBlob = web.Blob(_videoChunks.toJS, web.BlobPropertyBag(type: 'video/webm'));
    
    // Revoke previous URL if exists
    if (_previewVideoUrl != null) web.URL.revokeObjectURL(_previewVideoUrl!);
    
    final videoUrl = web.URL.createObjectURL(videoBlob);
    
    // Create instant preview video element
    final previewType = 'preview-video-${DateTime.now().millisecondsSinceEpoch}';
    final videoEl = web.HTMLVideoElement()
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

    final reader = web.FileReader();
    reader.readAsArrayBuffer(videoBlob);
    
    final loadCompleter = Completer<void>();
    reader.addEventListener('load', ((web.Event _) => loadCompleter.complete()).toJS);
    await loadCompleter.future;
    
    final result = reader.result as JSArrayBuffer;
    final videoBytes = result.toDart.asUint8List();
    
    setState(() {
      _isRecording = false;
      _capturedVideoBytes = videoBytes;
      _previewVideoUrl = videoUrl;
      _previewViewType = previewType;
    });
    
    // Take a photo as thumbnail for the video
    await _takePhoto();
    
    _snack('Video recorded! (${_recordSeconds}s) Tap Post to share.');
  }

  // ── Tab Bar ──────────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['AR', 'FILTERS', 'STICKERS']
              .map((t) => _tabBtn(t))
              .toList(),
        ),
      ),
    );
  }

  Widget _tabBtn(String t) {
    final sel = _tab == t;
    return GestureDetector(
      onTap: () {
        if (t == 'STICKERS') {
          _addSticker();
          setState(() => _tab = 'NONE');
        } else {
          setState(() => _tab = (_tab == t) ? 'NONE' : t);
        }
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

  // ── Tab Content ──────────────────────────────────────────────────────────────
  Widget _buildTabContent() {
    if (_tab == 'AR') {
      return _buildARFilterBar();
    } else if (_tab == 'FILTERS') {
      return _buildColorFilterBar();
    }
    return const SizedBox(height: 16);
  }

  // ── Color Filter Bar (Android / iOS / Web) ─────────────────────────────────
  Widget _buildColorFilterBar() {
    final filters = AppColorFilters.names;
    return SizedBox(
      height: 80,
      child: ListView.builder(
        key: const PageStorageKey('color_filters_list'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (ctx, i) {
          final f = filters[i];
          final sel = _filter == f;
          return GestureDetector(
            onTap: () {
              setState(() => _filter = f);
              final matrix = AppColorFilters.get(f);
              final blurRadius = AppColorFilters.getBlur(f);
              if (kIsWeb) {
                applyColorMatrixJS(matrix, blurRadius);
                applyBeautyFilterJS(blurRadius);
              } else {
                _arWebViewKey.currentState?.applyColorMatrix(matrix, blurRadius);
                _arWebViewKey.currentState?.applyBeautyFilter(blurRadius);
              }
            },
            child: RepaintBoundary(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                width: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel ? AppTheme.accentPurple : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColorFiltered(
                      colorFilter: ColorFilter.matrix(AppColorFilters.get(f)),
                      child: Image.asset(
                        'assets/images/filter_person.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black87, Colors.transparent],
                          begin: Alignment.bottomCenter,
                          end: Alignment.center,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          f,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
          );
        },
      ),
    );
  }


  // ── Post Bar ─────────────────────────────────────────────────────────────────
  Widget _buildPostBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Align(
        alignment: Alignment.centerRight,
        child: AnimatedOpacity(
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
              elevation: 4,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Post',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      SizedBox(width: 6),
                      Icon(Icons.send_rounded, size: 16),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildARFilterBar() {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        key: const PageStorageKey('ar_filters_list'),
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
              if (kIsWeb) {
                setARFilter(f);
              } else {
                _arWebViewKey.currentState?.setFilter(f);
              }
            },
            onLongPress: () {
              if (f == 'NONE') return;
              setState(() {
                _arFilter = f;
                _showCalibrator = !_showCalibrator;
              });
              if (kIsWeb) {
                setARFilter(f);
              } else {
                _arWebViewKey.currentState?.setFilter(f);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              width: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: sel ? AppTheme.accentPurple : Colors.transparent,
                  width: 3,
                ),
              ),
              child: ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      switch (f) {
                        'Thug Life' => 'assets/images/ar_thug_life.png',
                        'Dog' => 'assets/images/ar_dog.png',
                        'Cat' => 'assets/images/ar_cat.png',
                        'Bunny' => 'assets/images/ar_bunny.png',
                        'Flower Crown' => 'assets/images/ar_flower_crown.png',
                        'Devil' => 'assets/images/ar_devil.png',
                        'Angel' => 'assets/images/ar_angel.png',
                        'Crown' => 'assets/images/ar_crown.png',
                        _ => 'assets/images/filter_person.png',
                      },
                      fit: BoxFit.cover,
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black87, Colors.transparent],
                          begin: Alignment.bottomCenter,
                          end: Alignment.center,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          f,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                          ),
                        ),
                      ),
                    ),
                  ],
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
