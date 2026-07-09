// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../core/utils/web_stub.dart' if (dart.library.html) 'package:web/web.dart' as web;
import '../../../core/utils/js_interop_stub.dart' if (dart.library.html) 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../utils/ui_web_shim.dart' as ui_web;
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
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/utils/color_filters.dart';
import '../../wallet/widgets/coin_gate_sheet.dart';
import '../../../core/providers/access_provider.dart';

import '../widgets/overlay_manager.dart';
import '../widgets/text_editor_overlay.dart';

// ─── Firestore instance ───────────────────────────────────────────────────────
final _db = FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: '(default)',
);

// ─── TakeScreen ───────────────────────────────────────────────────────────────
class TakeScreen extends ConsumerStatefulWidget {
  const TakeScreen({super.key});

  @override
  ConsumerState<TakeScreen> createState() => _TakeScreenState();
}

class _TakeScreenState extends ConsumerState<TakeScreen>
    with SingleTickerProviderStateMixin {
  // ── Mode ──
  String _mode = 'PHOTO'; // PHOTO | VIDEO
  String _tab  = 'NONE';  // NONE | FILTERS | STICKERS | CROP
  String _filter = 'Normal';
  bool _isDraggingItem = false;

  // ── Crop State ──
  String _cropAspect = 'Original';
  double _cropZoom = 1.0;
  double _cropX = 0.0;
  double _cropY = 0.0;

  // ── Trim State ──
  double _trimStart = 0.0;
  double _trimEnd = 0.0;
  double _videoDuration = 0.0;

  // ── Camera — shared ──
  bool _isFrontCamera = true;

  // ── Camera — Web ──
  web.HTMLVideoElement? _webVideoElement;
  web.MediaStream? _webStream;
  bool _webCameraReady = false;
  String? _webCameraError;
  String? _webViewType;      // live viewfactory key
  web.MediaRecorder? _webMediaRecorder;
  final List<web.Blob> _webVideoChunks = [];
  String? _previewVideoUrl;
  String? _previewViewType;
  web.HTMLVideoElement? _webPreviewElement;

  // ── Camera — Native (Android / iOS) ──
  CameraController? _camCtrl;
  bool _nativeCameraReady = false;
  bool _nativeCameraPermDenied = false;
  bool _nativeCameraPermPermanent = false;

  // ── Capture state ──
  Uint8List? _capturedImageBytes;
  Uint8List? _capturedVideoBytes;
  bool _isRecording = false;
  Timer? _recordTimer;
  int _recordSeconds = 0;

  // ── Overlays ──
  final List<OverlayItem> _overlays = [];
  final GlobalKey _previewKey = GlobalKey();

  // ── Upload / Post ──
  bool _isSaving = false;

  // ── Shutter animation ──
  late AnimationController _shutterAnim;
  late Animation<double> _shutterScale;

  // ── Native video preview player ──
  VideoPlayerController? _nativePreviewCtrl;

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
    _shutterAnim.dispose();
    _recordTimer?.cancel();
    _nativePreviewCtrl?.dispose();
    super.dispose();
  }

  // ─── Native Camera Init ──────────────────────────────────────────────────────
  Future<void> _initNativeCamera() async {
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied) {
      if (mounted) setState(() => _nativeCameraPermPermanent = true);
      return;
    }
    if (!status.isGranted) {
      if (mounted) setState(() => _nativeCameraPermDenied = true);
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (mounted) setState(() => _nativeCameraPermDenied = true);
      return;
    }

    final CameraDescription cam = _pickCamera(cameras);
    await _startNativeCam(cam);
  }

  CameraDescription _pickCamera(List<CameraDescription> cameras) {
    final wantedDir = _isFrontCamera
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    return cameras.firstWhere(
      (c) => c.lensDirection == wantedDir,
      orElse: () => cameras.first,
    );
  }

  Future<void> _startNativeCam(CameraDescription cam) async {
    try {
      final ctrl = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }
      setState(() {
        _camCtrl = ctrl;
        _nativeCameraReady = true;
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) setState(() => _nativeCameraPermDenied = true);
    }
  }

  Future<void> _flipNativeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    final cam = _pickCamera(cameras);
    await _camCtrl?.dispose();
    setState(() {
      _camCtrl = null;
      _nativeCameraReady = false;
    });
    await _startNativeCam(cam);
  }

  // ─── Web Camera Init ─────────────────────────────────────────────────────────
  Future<void> _initWebCamera() async {
    final viewType = 'cam-view-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _webViewType = viewType;
      _webCameraError = null;
      _webCameraReady = false;
    });

    try {
      final mediaDevices = web.window.navigator.mediaDevices;
      if (mediaDevices == null) throw Exception('MediaDevices not supported.');

      final constraints = {
        'video': {
          'facingMode': _isFrontCamera ? 'user' : 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
        'audio': true,
      }.jsify() as web.MediaStreamConstraints;

      final stream = await mediaDevices.getUserMedia(constraints).toDart;
      _webStream = stream;

      final video = web.HTMLVideoElement()
        ..srcObject = stream
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true')
        ..style.width  = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.transform = _isFrontCamera ? 'scaleX(-1)' : 'none';

      _webVideoElement = video;

      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        viewType,
        (int id) => video,
      );

      video.onPlaying.first.then((_) {
        if (mounted) setState(() => _webCameraReady = true);
      });

      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_webCameraReady && _webStream != null) {
          setState(() => _webCameraReady = true);
        }
      });
    } on web.DOMException catch (e) {
      String msg;
      if (e.name == 'NotAllowedError' || e.name == 'PermissionDeniedError') {
        msg = '📷 Camera permission denied.\n\nAllow camera access in your browser, then press Retry.';
      } else if (e.name == 'NotFoundError') {
        msg = '📷 No camera found.\n\nUse UPLOAD to select a photo.';
      } else {
        msg = '📷 Camera error: ${e.name}';
      }
      if (mounted) setState(() => _webCameraError = msg);
    } catch (e) {
      if (mounted) setState(() => _webCameraError = '📷 Camera unavailable.');
    }
  }

  void _stopCamera() {
    if (kIsWeb) {
      _webVideoElement?.pause();
      _webVideoElement?.removeAttribute('src');
      _webVideoElement?.load();
      _webVideoElement?.srcObject = null;
      _webStream?.getTracks().toDart.forEach((t) => t.stop());
      _webStream = null;
      _webVideoElement = null;
    } else {
      _camCtrl?.dispose();
      _camCtrl = null;
    }
  }

  // ─── Photo Capture ───────────────────────────────────────────────────────────
  Future<void> _takePhoto() async {
    _shutterAnim.forward().then((_) => _shutterAnim.reverse());

    if (!kIsWeb) {
      if (_camCtrl == null || !_camCtrl!.value.isInitialized) return;
      try {
        final xFile = await _camCtrl!.takePicture();
        final bytes = await xFile.readAsBytes();
        if (mounted) setState(() => _capturedImageBytes = bytes);
      } catch (e) {
        debugPrint('takePhoto error: $e');
      }
      return;
    }

    // Web: capture from the live video element via canvas
    if (_webVideoElement == null) return;
    try {
      final canvas = web.HTMLCanvasElement()
        ..width  = _webVideoElement!.videoWidth
        ..height = _webVideoElement!.videoHeight;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      // Mirror front camera
      if (_isFrontCamera) {
        ctx.translate(_webVideoElement!.videoWidth.toDouble(), 0);
        ctx.scale(-1, 1);
      }
      ctx.drawImage(_webVideoElement!, 0, 0);
      final dataUrl = canvas.toDataUrl('image/jpeg', 0.92);
      final base64Str = dataUrl.split(',').last;
      if (base64Str.length < 100) return;
      if (mounted) setState(() => _capturedImageBytes = base64Decode(base64Str));
    } catch (e) {
      debugPrint('web takePhoto error: $e');
    }
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
      if (mounted) setState(() => _capturedImageBytes = bytes);
    }
  }

  void _retake() {
    _nativePreviewCtrl?.dispose();
    _nativePreviewCtrl = null;
    if (_previewVideoUrl != null) {
      web.URL.revokeObjectURL(_previewVideoUrl!);
    }
    setState(() {
      _capturedImageBytes = null;
      _capturedVideoBytes = null;
      _previewVideoUrl    = null;
      _previewViewType    = null;
      _overlays.clear();
    });
  }

  // ─── Video Recording ─────────────────────────────────────────────────────────
  Future<void> _startVideoRecord() async {
    if (_isRecording) return;

    if (!kIsWeb) {
      // Native
      if (_camCtrl == null || !_camCtrl!.value.isInitialized) return;
      try {
        await _camCtrl!.startVideoRecording();
        setState(() { _isRecording = true; _recordSeconds = 0; });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          setState(() => _recordSeconds++);
        });
      } catch (e) {
        debugPrint('startVideoRecording error: $e');
      }
      return;
    }

    // Web
    if (_webStream == null) return;
    _webVideoChunks.clear();
    try {
      _webMediaRecorder = web.MediaRecorder(_webStream!, web.MediaRecorderOptions(videoBitsPerSecond: 2500000));
      _webMediaRecorder!.addEventListener('dataavailable', (web.Event event) {
        final e = event as web.BlobEvent;
        if (e.data.size > 0) _webVideoChunks.add(e.data);
      }.toJS);
      _webMediaRecorder!.start(1000);
      setState(() { _isRecording = true; _recordSeconds = 0; });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordSeconds++);
      });
    } catch (e) {
      debugPrint('web startVideoRecord error: $e');
      _snack('Video recording not supported in this browser.');
    }
  }

  Future<void> _stopVideoRecord() async {
    _recordTimer?.cancel();

    if (!kIsWeb) {
      // Native
      if (_camCtrl == null) { setState(() => _isRecording = false); return; }
      try {
        final xFile = await _camCtrl!.stopVideoRecording();
        // Read bytes for upload
        final bytes = await xFile.readAsBytes();
        // Build a looping preview player — use file() on native platforms
        final ctrl = VideoPlayerController.file(File(xFile.path));
        await ctrl.initialize();
        ctrl.setLooping(true);
        ctrl.setVolume(1.0); // audible preview
        ctrl.play();
        ctrl.addListener(_onPreviewPlayerTick);
        if (mounted) {
          setState(() {
            _capturedVideoBytes = bytes;
            _isRecording = false;
            _nativePreviewCtrl = ctrl;
            _videoDuration = ctrl.value.duration.inMilliseconds / 1000.0;
            _trimStart = 0.0;
            _trimEnd = _videoDuration;
          });
          _snack('🎬 Video ready! Tap Post to share.');
        }
      } catch (e) {
        debugPrint('stopVideoRecording error: $e');
        if (mounted) setState(() => _isRecording = false);
      }
      return;
    }

    // Web
    if (_webMediaRecorder == null) { setState(() => _isRecording = false); return; }

    final completer = Completer<void>();
    _webMediaRecorder!.addEventListener('stop', ((web.Event _) => completer.complete()).toJS);
    _webMediaRecorder!.stop();
    await completer.future;

    if (_webVideoChunks.isEmpty) {
      setState(() => _isRecording = false);
      _snack('No video data. Try again.');
      return;
    }

    final mimeType = (_webMediaRecorder as dynamic).mimeType as String? ?? '';
    final blobType = mimeType.isNotEmpty ? mimeType : 'video/webm';
    final blob = web.Blob(_webVideoChunks.toJS, web.BlobPropertyBag(type: blobType));
    if (_previewVideoUrl != null) web.URL.revokeObjectURL(_previewVideoUrl!);
    final videoUrl = web.URL.createObjectURL(blob);

    // Register preview video element (mirrored for front cam)
    final previewType = 'preview-${DateTime.now().millisecondsSinceEpoch}';
    final previewEl = web.HTMLVideoElement()
      ..src = videoUrl
      ..autoplay = true
      ..loop = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.transform = _isFrontCamera ? 'scaleX(-1)' : 'none';

    _webPreviewElement = previewEl;

    previewEl.addEventListener('timeupdate', ((web.Event _) {
      if (_trimEnd > 0 && _trimEnd < _videoDuration) {
        if (previewEl.currentTime >= _trimEnd) {
          previewEl.currentTime = _trimStart;
          previewEl.play();
        }
      } else if (_trimStart > 0 && previewEl.currentTime < _trimStart - 0.1) {
        previewEl.currentTime = _trimStart;
      }
    }).toJS);

    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(previewType, (int id) => previewEl);

    // Read bytes
    final reader = web.FileReader();
    reader.readAsArrayBuffer(blob);
    final loadCompleter = Completer<void>();
    reader.addEventListener('load', ((web.Event _) => loadCompleter.complete()).toJS);
    await loadCompleter.future;
    final result = reader.result as JSArrayBuffer;
    final videoBytes = result.toDart.asUint8List();

    // Capture a still from the preview for thumbnail
    try {
      final canvas = web.HTMLCanvasElement()
        ..width  = previewEl.videoWidth  > 0 ? previewEl.videoWidth  : 640
        ..height = previewEl.videoHeight > 0 ? previewEl.videoHeight : 480;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      if (_isFrontCamera) {
        ctx.translate(canvas.width.toDouble(), 0);
        ctx.scale(-1, 1);
      }
      ctx.drawImage(previewEl, 0, 0);
      final dataUrl = canvas.toDataUrl('image/jpeg', 0.85);
      final b64 = dataUrl.split(',').last;
      if (b64.length > 100) {
        _capturedImageBytes = base64Decode(b64);
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isRecording        = false;
        _capturedVideoBytes = videoBytes;
        _previewVideoUrl    = videoUrl;
        _previewViewType    = previewType;
        _videoDuration      = previewEl.duration?.toDouble() ?? _recordSeconds.toDouble();
        if (_videoDuration.isNaN || _videoDuration == 0) _videoDuration = _recordSeconds.toDouble();
        _trimStart          = 0.0;
        _trimEnd            = _videoDuration;
      });
      _snack('🎬 Video recorded! (${_recordSeconds}s) Tap Post to share.');
    }
  }

  void _onPreviewPlayerTick() {
    if (_nativePreviewCtrl == null) return;
    final pos = _nativePreviewCtrl!.value.position.inMilliseconds;
    final endMs = (_trimEnd * 1000).toInt();
    final startMs = (_trimStart * 1000).toInt();
    
    if (pos >= endMs && endMs > 0 && endMs < (_videoDuration * 1000).toInt()) {
      _nativePreviewCtrl!.seekTo(Duration(milliseconds: startMs));
      if (!_nativePreviewCtrl!.value.isPlaying) _nativePreviewCtrl!.play();
    } else if (pos < startMs - 100 && startMs > 0) { // allow small margin
      _nativePreviewCtrl!.seekTo(Duration(milliseconds: startMs));
    }
  }

  Future<void> _post() async {
    final hasContent = _capturedImageBytes != null || _capturedVideoBytes != null;
    if (!hasContent) {
      _snack('Take a photo or record a video first! 📸');
      return;
    }

    final isPremiumFilter = _filter != 'Normal';
    if (isPremiumFilter) {
      final allowed = await showCoinGate(context, ref, 'extra_filters');
      if (!allowed) {
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      Uint8List? uploadBytes;
      if (_capturedImageBytes != null) {
        final hasCrop = _cropAspect != 'Original' || _cropZoom != 1.0 || _cropX != 0.0 || _cropY != 0.0;
        if (_overlays.isEmpty && _filter == 'Normal' && !hasCrop) {
          uploadBytes = _capturedImageBytes!;
        } else {
          try {
            final boundary = _previewKey.currentContext
                ?.findRenderObject() as RenderRepaintBoundary?;
            if (boundary != null) {
              final img = await boundary.toImage(pixelRatio: 2.0);
              final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
              uploadBytes = byteData?.buffer.asUint8List() ?? _capturedImageBytes!;
            } else {
              uploadBytes = _capturedImageBytes!;
            }
          } catch (_) {
            uploadBytes = _capturedImageBytes!;
          }
        }
      }

      final currentUser = ref.read(currentUserProvider);
      final storyId = DateTime.now().millisecondsSinceEpoch.toString();

      final List<Future<String?>> uploadFutures = [];

      // Image / thumbnail
      if (uploadBytes != null) {
        final ext = _overlays.isEmpty ? 'jpg' : 'png';
        final ref = FirebaseStorage.instance.ref('stories/$storyId.$ext');
        uploadFutures.add(
          ref.putData(uploadBytes, SettableMetadata(contentType: 'image/$ext'))
              .then((_) => ref.getDownloadURL()),
        );
      } else {
        uploadFutures.add(Future.value(null));
      }

      // Video (webm/mp4 for web, mp4 for native)
      if (_capturedVideoBytes != null) {
        final isNativeVid = !kIsWeb;
        String ext = isNativeVid ? 'mp4' : 'webm';
        String mime = isNativeVid ? 'video/mp4' : 'video/webm';
        
        if (kIsWeb && _webMediaRecorder != null) {
          final rMime = ((_webMediaRecorder as dynamic).mimeType as String? ?? '').toLowerCase();
          if (rMime.contains('mp4')) {
            ext = 'mp4';
            mime = 'video/mp4';
          }
        }
        
        final vRef = FirebaseStorage.instance.ref('stories/$storyId.$ext');
        uploadFutures.add(
          vRef.putData(_capturedVideoBytes!, SettableMetadata(contentType: mime))
              .then((_) => vRef.getDownloadURL()),
        );
      } else {
        uploadFutures.add(Future.value(null));
      }

      final results = await Future.wait(uploadFutures);
      final imageUrl = results[0];
      final videoUrl = results[1];

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
        'id':         storyId,
        'userId':     currentUser.id,
        'userName':   currentUser.name,
        'userAvatar': currentUser.avatarUrl,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (videoUrl != null) 'videoUrl': videoUrl,
        // tell viewer whether to mirror (front camera videos)
        'mirrored': _isFrontCamera && _capturedVideoBytes != null,
        'filter':    _filter,
        'cropAspect': _cropAspect,
        'cropZoom': _cropZoom,
        'cropX': _cropX,
        'cropY': _cropY,
        'trimStart': _trimStart,
        'trimEnd': _trimEnd,
        'caption':   '',
        'overlays':  overlayDataList,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'expiresAt': DateTime.now()
            .add(const Duration(hours: 24))
            .millisecondsSinceEpoch,
        'viewers': [],
      });

      if (mounted) {
        _snack('Take shared! ✨', isSuccess: true);
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

  // ─── Text & Sticker Overlays ─────────────────────────────────────────────────
  void _addText() async {
    final result = await Navigator.push<OverlayItem>(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, _, __) => const TextEditorOverlay(),
      ),
    );
    if (result != null) setState(() => _overlays.add(result));
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
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(4)),
            ),
            const Text('Choose a Sticker',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: stickers
                  .map((e) => GestureDetector(
                        onTap: () {
                          setState(() => _overlays.add(OverlayItem(
                            id: DateTime.now().millisecondsSinceEpoch.toString(),
                            content: e,
                            isText: false,
                            position: const Offset(150, 250),
                          )));
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

  // ─── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) => _stopCamera(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildPreviewArea(),
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

  // ── Top Bar ──────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () { _stopCamera(); context.pop(); },
            child: Container(
              width: 36, height: 36,
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
          const Spacer(),
          // PHOTO / VIDEO toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [_modeBtn('PHOTO'), _modeBtn('VIDEO')],
            ),
          ),
          const Spacer(),
          // Flip camera
          GestureDetector(
            onTap: () {
              setState(() => _isFrontCamera = !_isFrontCamera);
              if (kIsWeb) {
                _stopCamera();
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) _initWebCamera();
                });
              } else {
                _flipNativeCamera();
              }
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              width: 36, height: 36,
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 20),
            ),
          ),
          // Add text
          GestureDetector(
            onTap: () {
              setState(() => _tab = 'NONE');
              _addText();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
              ),
              child: const Row(
                children: [
                  Icon(Icons.text_fields_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text('Text', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
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

  double? get _cropRatioValue {
    switch (_cropAspect) {
      case '1:1': return 1.0;
      case '4:5': return 4.0 / 5.0;
      case '9:16': return 9.0 / 16.0;
      case '16:9': return 16.0 / 9.0;
      default: return null;
    }
  }

  // ── Preview Area ─────────────────────────────────────────────────────────────
  Widget _buildPreviewArea() {
    Widget content = RepaintBoundary(
      key: _previewKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildBaseLayer(),
          // Top gradient
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
          // Bottom gradient
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
          // Filter overlay on captured image
          if (_capturedImageBytes != null && _filter != 'Normal')
            Positioned.fill(
              child: IgnorePointer(
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(AppColorFilters.get(_filter)),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          // Text / Sticker overlays
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_tab != 'NONE') {
                setState(() => _tab = 'NONE');
              } else {
                _addText();
              }
            },
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;
              final filters = AppColorFilters.names;
              final currentIndex = filters.indexOf(_filter);
              if (details.primaryVelocity! < -300) {
                // Swipe left, next filter
                setState(() {
                  _filter = filters[(currentIndex + 1) % filters.length];
                });
              } else if (details.primaryVelocity! > 300) {
                // Swipe right, prev filter
                setState(() {
                  _filter = filters[(currentIndex - 1 + filters.length) % filters.length];
                });
              }
            },
            child: OverlayManager(
              items: _overlays,
              onDragStateChanged: (d) => setState(() => _isDraggingItem = d),
              onItemTap: (item) { if (item.isText) _editOverlayItem(item); },
              onItemsChanged: () => setState(() {}),
            ),
          ),
          
          // Filter Name / Premium Badge
          if (_filter != 'Normal')
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _filter,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (_filter != 'Normal') ...[
                        const SizedBox(width: 8),
                        const Text('✨', style: TextStyle(fontSize: 14)),
                      ]
                    ],
                  ),
                ),
              ),
            ),
            
          // Recording badge
          if (_isRecording)
            Positioned(
              top: 16, left: 16,
              child: Row(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: const BoxDecoration(
                      color: AppTheme.error, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatDuration(_recordSeconds),
                    style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (_cropRatioValue != null) {
      content = Center(
        child: AspectRatio(
          aspectRatio: _cropRatioValue!,
          child: ClipRect(child: content),
        ),
      );
    }

    return content;
  }

  Widget _buildBaseLayer() {
    if (kIsWeb) {
      final cssFilter = AppColorFilters.getCssFilter(_filter);
      _webVideoElement?.style.filter = cssFilter;
      _webPreviewElement?.style.filter = cssFilter;
    }

    Widget baseLayer = _buildRawBaseLayer();
    
    if (_cropZoom != 1.0 || _cropX != 0.0 || _cropY != 0.0) {
      baseLayer = ClipRect(
        child: FractionalTranslation(
          translation: Offset(_cropX, _cropY),
          child: Transform.scale(
            scale: _cropZoom,
            child: baseLayer,
          ),
        ),
      );
    }
    
    // 2. apply filter
    if (_filter != 'Normal') {
      baseLayer = ColorFiltered(
        colorFilter: ColorFilter.matrix(AppColorFilters.get(_filter)),
        child: baseLayer,
      );
    }
    
    return baseLayer;
  }

  Widget _buildRawBaseLayer() {
    // ── ANDROID / iOS ──────────────────────────────────────────────────────────
    if (!kIsWeb) {
      if (_nativeCameraPermPermanent) {
        return _buildPermScreen(
          '📷 Camera permission permanently denied.\nOpen Settings to allow access.',
          'Open Settings',
          () => openAppSettings(),
        );
      }
      if (_nativeCameraPermDenied) {
        return _buildPermScreen(
          '📷 Camera permission required.',
          'Grant Permission',
          () {
            setState(() => _nativeCameraPermDenied = false);
            _initNativeCamera();
          },
        );
      }
      if (!_nativeCameraReady || _camCtrl == null) {
        return Container(
          color: AppTheme.darkCard,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppTheme.accentPurple),
                SizedBox(height: 12),
                Text('Starting camera…', style: TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ),
          ),
        );
      }

      // Native camera preview or captured content
      if (_nativePreviewCtrl != null && _nativePreviewCtrl!.value.isInitialized) {
        // Video preview (looping, muted, mirrored for front cam)
        return Transform(
          alignment: Alignment.center,
          transform: _isFrontCamera
              ? (Matrix4.identity()..scale(-1.0, 1.0))
              : Matrix4.identity(),
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width:  _nativePreviewCtrl!.value.size.width,
              height: _nativePreviewCtrl!.value.size.height,
              child: VideoPlayer(_nativePreviewCtrl!),
            ),
          ),
        );
      }

      if (_capturedImageBytes != null) {
        return Transform(
          alignment: Alignment.center,
          transform: _isFrontCamera
              ? (Matrix4.identity()..scale(-1.0, 1.0))
              : Matrix4.identity(),
          child: Image.memory(_capturedImageBytes!, fit: BoxFit.cover),
        );
      }

      // Live camera preview (native) — fill the screen edge-to-edge without extreme zoom
      return LayoutBuilder(
        builder: (context, constraints) {
          final cameraAspect = 1.0 / _camCtrl!.value.aspectRatio;
          final containerAspect = constraints.maxWidth / constraints.maxHeight;
          final scale = containerAspect > cameraAspect 
              ? containerAspect / cameraAspect 
              : cameraAspect / containerAspect;

          return ClipRect(
            child: Transform.scale(
              scale: scale,
              child: Center(
                child: AspectRatio(
                  aspectRatio: cameraAspect,
                  child: CameraPreview(_camCtrl!),
                ),
              ),
            ),
          );
        },
      );
    }

    // ── WEB ────────────────────────────────────────────────────────────────────

    // Web: video preview after recording
    if (_previewVideoUrl != null && _previewViewType != null) {
      return HtmlElementView(viewType: _previewViewType!);
    }

    // Web: photo preview
    if (_capturedImageBytes != null) {
      return Image.memory(_capturedImageBytes!, fit: BoxFit.cover);
    }

    // Web: camera error
    if (_webCameraError != null) {
      return Container(
        color: AppTheme.darkCard,
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_rounded, color: Colors.white24, size: 64),
              const SizedBox(height: 16),
              Text(_webCameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.5)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _webCameraError = null;
                    _webCameraReady = false;
                    _webViewType    = null;
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

    // Web: loading
    if (!_webCameraReady || _webViewType == null) {
      return Container(
        color: AppTheme.darkCard,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.accentPurple),
              SizedBox(height: 12),
              Text('Starting camera…', style: TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    // Web: live camera feed (mirror applied via CSS in the video element)
    return HtmlElementView(key: ValueKey(_webViewType!), viewType: _webViewType!);
  }

  Widget _buildPermScreen(String msg, String label, VoidCallback onAction) {
    return Container(
      color: AppTheme.darkCard,
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_rounded, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.6)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(label),
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

  // ── Tab Bar ──────────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    final tabs = ['FILTERS', 'STICKERS', 'CROP'];
    if (_capturedVideoBytes != null) {
      tabs.add('TRIM');
    }
    
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
          children: tabs.map(_tabBtn).toList(),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: sel ? AppTheme.accentPurple.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: sel ? Border.all(color: AppTheme.accentPurple.withOpacity(0.4)) : null,
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
    if (_tab == 'FILTERS') return _buildColorFilterBar();
    if (_tab == 'CROP') return _buildCropTab();
    if (_tab == 'TRIM') return _buildTrimTab();
    return const SizedBox(height: 16);
  }

  Widget _buildTrimTab() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Trim', style: TextStyle(color: Colors.white, fontSize: 13)),
              Text('${_trimStart.toStringAsFixed(1)}s → ${_trimEnd.toStringAsFixed(1)}s · ${(_trimEnd - _trimStart).toStringAsFixed(1)}s', 
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          
          // Visual timeline bar (inactive)
          Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(colors: [AppTheme.primaryBlue, AppTheme.accentPurple]),
            ),
          ),
          const SizedBox(height: 24),
          
          // Start Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Start', style: TextStyle(color: Colors.white, fontSize: 13)),
              Text('${_trimStart.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.white38,
              inactiveTrackColor: Colors.white12,
              thumbColor: AppTheme.primaryBlue,
              trackHeight: 4,
            ),
            child: Slider(
              value: _trimStart,
              min: 0.0,
              max: _trimEnd > 0 ? _trimEnd : 0.0,
              onChanged: (val) {
                setState(() => _trimStart = val);
                _nativePreviewCtrl?.seekTo(Duration(milliseconds: (val * 1000).toInt()));
                if (kIsWeb) _webPreviewElement?.currentTime = val;
              },
            ),
          ),
          
          // End Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('End', style: TextStyle(color: Colors.white, fontSize: 13)),
              Text('${_trimEnd.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.white38,
              inactiveTrackColor: Colors.white12,
              thumbColor: AppTheme.primaryBlue,
              trackHeight: 4,
            ),
            child: Slider(
              value: _trimEnd,
              min: _trimStart,
              max: _videoDuration > 0 ? _videoDuration : 0.0,
              onChanged: (val) {
                setState(() => _trimEnd = val);
                _nativePreviewCtrl?.seekTo(Duration(milliseconds: (val * 1000).toInt()));
                if (kIsWeb) _webPreviewElement?.currentTime = val;
              },
            ),
          ),
          const SizedBox(height: 16),
          
          // Reset Button
          GestureDetector(
            onTap: () => setState(() {
              _trimStart = 0.0;
              _trimEnd = _videoDuration;
              _nativePreviewCtrl?.seekTo(Duration.zero);
            }),
            child: const Text('Reset trim', style: TextStyle(color: Colors.white70, decoration: TextDecoration.underline, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildCropTab() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Aspect Ratio Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Original', '1:1', '4:5', '9:16', '16:9'].map((aspect) {
                final isSelected = _cropAspect == aspect;
                return GestureDetector(
                  onTap: () => setState(() => _cropAspect = aspect),
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.accentPurple : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? AppTheme.accentPurple : Colors.white24),
                    ),
                    child: Text(
                      aspect,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white60,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
          
          // Zoom Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Zoom', style: TextStyle(color: Colors.white, fontSize: 13)),
              Text('${_cropZoom.toStringAsFixed(2)}x', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.white38,
              inactiveTrackColor: Colors.white12,
              thumbColor: AppTheme.primaryBlue,
              overlayColor: AppTheme.primaryBlue.withOpacity(0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: _cropZoom,
              min: 1.0,
              max: 3.0,
              onChanged: (val) => setState(() => _cropZoom = val),
            ),
          ),
          
          // X and Y Sliders
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('X', style: TextStyle(color: Colors.white, fontSize: 13)),
                        Text('${(_cropX * 100).toInt()}%', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: Colors.white38,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: AppTheme.primaryBlue,
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _cropX,
                        min: -1.0,
                        max: 1.0,
                        onChanged: (val) => setState(() => _cropX = val),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Y', style: TextStyle(color: Colors.white, fontSize: 13)),
                        Text('${(_cropY * 100).toInt()}%', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: Colors.white38,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: AppTheme.primaryBlue,
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _cropY,
                        min: -1.0,
                        max: 1.0,
                        onChanged: (val) => setState(() => _cropY = val),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Reset Button
          GestureDetector(
            onTap: () => setState(() {
              _cropAspect = 'Original';
              _cropZoom = 1.0;
              _cropX = 0.0;
              _cropY = 0.0;
            }),
            child: const Text('Reset crop', style: TextStyle(color: Colors.white70, decoration: TextDecoration.underline, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildColorFilterBar() {
    final filters = AppColorFilters.names;
    final currentUser = ref.watch(currentUserProvider);
    final isPremium = currentUser.hasActiveSubscription;

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
          final isPremiumFilter = f != 'Normal' && f != 'Arabica 12' && f != 'Ava 614';

          return GestureDetector(
            onTap: () => setState(() => _filter = f),
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
                        child: Image.asset('assets/images/filter_person.png', fit: BoxFit.cover),
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
                      if (isPremiumFilter && !isPremium)
                        const Positioned(
                          top: 4,
                          right: 4,
                          child: Icon(Icons.lock_rounded, color: Colors.white70, size: 12),
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
                              color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold,
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

  // ── Bottom Controls ──────────────────────────────────────────────────────────
  Widget _buildBottomControls() {
    final hasCaptured = _capturedImageBytes != null || _capturedVideoBytes != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Retake or gallery
          hasCaptured
              ? GestureDetector(
                  onTap: _retake,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Retake', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: _uploadFromGallery,
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                    ),
                    child: const Icon(Icons.photo_library_rounded, color: Colors.white, size: 22),
                  ),
                ),

          // Center: Shutter / Record button
          if (!hasCaptured)
            ScaleTransition(
              scale: _shutterScale,
              child: GestureDetector(
                onTap: () {
                  if (_mode == 'PHOTO') {
                    _takePhoto();
                  } else {
                    if (_isRecording) _stopVideoRecord(); else _startVideoRecord();
                  }
                },
                child: Container(
                  width: 80, height: 80,
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

          // Right: spacer / placeholder
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── Post Bar ─────────────────────────────────────────────────────────────────
  Widget _buildPostBar() {
    final bool hasContent = _capturedImageBytes != null || _capturedVideoBytes != null;
    // For native video: wait until bytes are ready (nativePreviewCtrl or capturedVideoBytes set)
    final bool isProcessing = _isRecording;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Align(
        alignment: Alignment.centerRight,
        child: AnimatedOpacity(
          opacity: hasContent ? 1.0 : 0.3,
          duration: const Duration(milliseconds: 200),
          child: ElevatedButton(
            onPressed: (hasContent && !_isSaving && !isProcessing) ? _post : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              elevation: 4,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Post', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      SizedBox(width: 6),
                      Icon(Icons.send_rounded, size: 16),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
