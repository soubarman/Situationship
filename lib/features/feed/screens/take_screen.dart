import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../core/utils/web_stub.dart' if (dart.library.html) 'package:web/web.dart' as web;
import '../../../core/utils/js_interop_stub.dart' if (dart.library.html) 'dart:js_interop';
import 'dart:ui' as ui;
import '../utils/ui_web_shim.dart' as ui_web;
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/utils/color_filters.dart';
import '../../wallet/widgets/coin_gate_sheet.dart';

import '../widgets/overlay_manager.dart';
import '../widgets/text_editor_overlay.dart';

// ─── Firestore instance ───────────────────────────────────────────────────────
final _db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');

// ─── TakeScreen ───────────────────────────────────────────────────────────────
class TakeScreen extends ConsumerStatefulWidget {
  const TakeScreen({super.key});

  @override
  ConsumerState<TakeScreen> createState() => _TakeScreenState();
}

class _TakeScreenState extends ConsumerState<TakeScreen>
    with TickerProviderStateMixin {
  // ── Mode ──
  String _mode = 'PHOTO'; // PHOTO | VIDEO
  String _tab  = 'NONE';  // NONE | FILTERS | STICKERS | CROP | TRIM
  String _filter = 'Normal';
  bool _isDraggingItem = false;
  bool _showGrid = false;
  bool _flashOn = false;
  bool _isFrontScreenFlashing = false;

  // ── Tap to Focus ──
  Offset? _focusPoint;
  late AnimationController _focusCtrl;
  late Animation<double> _focusScale;
  late Animation<double> _focusOpacity;

  // ── Shutter & Ambient animations ──
  late AnimationController _shutterAnim;
  late Animation<double> _shutterScale;
  late AnimationController _pulseCtrl;
  late Animation<double> _glowPulse;
  late AnimationController _flipCtrl;

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

  // ── Native video preview player ──
  VideoPlayerController? _nativePreviewCtrl;

  @override
  void initState() {
    super.initState();
    _shutterAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _shutterScale = Tween<double>(begin: 1.0, end: 0.86).animate(
      CurvedAnimation(parent: _shutterAnim, curve: Curves.easeInOut),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _glowPulse = Tween<double>(begin: 0.35, end: 0.95).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutSine),
    );

    _focusCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _focusScale = Tween<double>(begin: 1.45, end: 1.0).animate(
      CurvedAnimation(parent: _focusCtrl, curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack)),
    );
    _focusOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _focusCtrl, curve: const Interval(0.70, 1.0, curve: Curves.easeIn)),
    );

    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
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
    _pulseCtrl.dispose();
    _focusCtrl.dispose();
    _flipCtrl.dispose();
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
      if (_flashOn && !_isFrontCamera) {
        try {
          await ctrl.setFlashMode(FlashMode.torch);
        } catch (_) {}
      }
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
        if (mounted) {
          setState(() => _webCameraReady = true);
          if (_flashOn && !_isFrontCamera) {
            _applyWebTorch(true);
          }
        }
      });

      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_webCameraReady && _webStream != null) {
          setState(() => _webCameraReady = true);
          if (_flashOn && !_isFrontCamera) {
            _applyWebTorch(true);
          }
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
      if (_flashOn && !_isFrontCamera) {
        _applyWebTorch(false);
      }
      _webVideoElement?.pause();
      _webVideoElement?.removeAttribute('src');
      _webVideoElement?.load();
      _webVideoElement?.srcObject = null;
      _webStream?.getTracks().toDart.forEach((t) => t.stop());
      _webStream = null;
      _webVideoElement = null;
    } else {
      if (_camCtrl != null && _camCtrl!.value.isInitialized) {
        try {
          _camCtrl!.setFlashMode(FlashMode.off);
        } catch (_) {}
      }
      _camCtrl?.dispose();
      _camCtrl = null;
    }
  }

  // ─── Photo Capture ───────────────────────────────────────────────────────────
  Future<void> _takePhoto() async {
    final bool useFrontFlash = _flashOn && _isFrontCamera;

    if (useFrontFlash) {
      // Step 1: Turn screen bright white FIRST so light hits the face
      HapticFeedback.selectionClick();
      if (mounted) setState(() => _isFrontScreenFlashing = true);
      // Wait 450ms for the bright screen to physically illuminate the face and
      // allow the camera hardware auto-exposure to adjust.
      await Future.delayed(const Duration(milliseconds: 450));
    }

    // Step 2: Subject is now fully illuminated — trigger the shutter snap & feedback!
    HapticFeedback.heavyImpact();
    _shutterAnim.forward().then((_) => _shutterAnim.reverse());

    if (!kIsWeb) {
      if (_camCtrl == null || !_camCtrl!.value.isInitialized) {
        if (useFrontFlash && mounted) setState(() => _isFrontScreenFlashing = false);
        return;
      }
      try {
        final xFile = await _camCtrl!.takePicture();
        final bytes = await xFile.readAsBytes();
        if (useFrontFlash) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        if (mounted) {
          setState(() {
            _capturedImageBytes = bytes;
            _isFrontScreenFlashing = false;
          });
        }
        if (_flashOn && !_isFrontCamera) {
          try {
            await _camCtrl!.setFlashMode(FlashMode.off);
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('takePhoto error: $e');
        if (mounted) setState(() => _isFrontScreenFlashing = false);
      }
      return;
    }

    // Web: capture from the live video element via canvas
    if (_webVideoElement == null) {
      if (useFrontFlash && mounted) setState(() => _isFrontScreenFlashing = false);
      return;
    }
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

      // If front flash was active, apply exposure & luminosity enhancement
      if (useFrontFlash) {
        try {
          (ctx as dynamic).filter = 'brightness(1.22) contrast(1.04) saturate(1.04)';
        } catch (_) {}
      }

      ctx.drawImage(_webVideoElement!, 0, 0);

      if (useFrontFlash) {
        try {
          (ctx as dynamic).filter = 'none';
        } catch (_) {}
      }

      final dataUrl = canvas.toDataUrl('image/jpeg', 0.92);
      final base64Str = dataUrl.split(',').last;
      if (base64Str.length < 100) {
        if (mounted) setState(() => _isFrontScreenFlashing = false);
        return;
      }

      // Keep screen bright briefly after snap so user sees the photo was taken while lit
      if (useFrontFlash) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (mounted) {
        setState(() {
          _capturedImageBytes = base64Decode(base64Str);
          _isFrontScreenFlashing = false;
        });
      }
      if (_flashOn && !_isFrontCamera) {
        _applyWebTorch(false);
      }
    } catch (e) {
      debugPrint('web takePhoto error: $e');
      if (mounted) setState(() => _isFrontScreenFlashing = false);
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
    if (_flashOn && !_isFrontCamera) {
      if (kIsWeb) {
        _applyWebTorch(true);
      } else if (_camCtrl != null && _camCtrl!.value.isInitialized) {
        try {
          _camCtrl!.setFlashMode(FlashMode.torch);
        } catch (_) {}
      }
    }
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
        _videoDuration      = previewEl.duration.toDouble();
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
          'color': o.color.toARGB32(),
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

  void _triggerFocus(Offset pos) {
    HapticFeedback.selectionClick();
    setState(() => _focusPoint = pos);
    _focusCtrl.forward(from: 0.0);
  }

  Future<void> _applyWebTorch(bool enable) async {
    if (!kIsWeb || _webStream == null) return;
    try {
      final tracks = _webStream!.getVideoTracks().toDart;
      if (tracks.isNotEmpty) {
        final track = tracks.first;
        final constraints = {
          'advanced': [
            {'torch': enable}.jsify()
          ].jsify()
        }.jsify() as web.MediaTrackConstraints;
        await track.applyConstraints(constraints).toDart;
      }
    } catch (e) {
      debugPrint('Web torch error: $e');
    }
  }

  Future<void> _flipCameraWithAnimation() async {
    HapticFeedback.lightImpact();
    _flipCtrl.forward(from: 0.0);
    // If torch was active on back camera, turn it off before switching
    if (!_isFrontCamera) {
      if (kIsWeb) {
        await _applyWebTorch(false);
      } else if (_camCtrl != null && _camCtrl!.value.isInitialized) {
        try {
          await _camCtrl!.setFlashMode(FlashMode.off);
        } catch (_) {}
      }
    }
    setState(() => _isFrontCamera = !_isFrontCamera);
    if (kIsWeb) {
      _stopCamera();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _initWebCamera();
      });
    } else {
      await _flipNativeCamera();
    }
  }

  Future<void> _toggleFlash() async {
    HapticFeedback.selectionClick();
    if (_isFrontCamera) {
      // Front camera uses softbox / ring light screen illumination
      setState(() => _flashOn = !_flashOn);
      return;
    }

    // Back camera: physically control hardware torch / flash LED
    final nextFlash = !_flashOn;
    if (kIsWeb) {
      await _applyWebTorch(nextFlash);
      if (mounted) setState(() => _flashOn = nextFlash);
    } else {
      if (_camCtrl != null && _camCtrl!.value.isInitialized) {
        try {
          final mode = nextFlash ? FlashMode.torch : FlashMode.off;
          await _camCtrl!.setFlashMode(mode);
          if (mounted) setState(() => _flashOn = nextFlash);
        } catch (e) {
          debugPrint('Native setFlashMode error: $e');
          if (mounted) setState(() => _flashOn = nextFlash);
        }
      } else {
        setState(() => _flashOn = nextFlash);
      }
    }
  }

  void _addSticker() {
    final categories = <String, List<String>>{
      '🔥 Trending': ['🔥', '✨', '💜', '😍', '😂', '❤️', '💯', '🎉'],
      '💌 Romance': ['🥰', '😘', '🌹', '💍', '💌', '🫀', '🫶', '💋'],
      '🌙 Aesthetic': ['🦋', '🌸', '👑', '🌟', '💫', '💅', '🤍', '🌙'],
      '😈 Mood': ['😈', '🥵', '🍸', '🥂', '🎶', '🎯', '🚀', '🕶️'],
    };

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        String activeCat = '🔥 Trending';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final activeStickers = categories[activeCat] ?? [];
            return Container(
              height: 380,
              decoration: BoxDecoration(
                color: const Color(0xFF100D22),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 36,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, color: Color(0xFFFF2E93), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Aesthetic Stickers',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Category Pill Selector
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: categories.keys.map((cat) {
                        final isSel = activeCat == cat;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setSheetState(() => activeCat = cat);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? const Color(0xFFFF2E93).withValues(alpha: 0.22)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSel
                                    ? const Color(0xFFFF2E93).withValues(alpha: 0.7)
                                    : Colors.white.withValues(alpha: 0.08),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: isSel ? Colors.white : Colors.white60,
                                fontSize: 12,
                                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Grid
                  Expanded(
                    child: GridView.builder(
                      itemCount: activeStickers.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 1.05,
                      ),
                      itemBuilder: (_, i) {
                        final emoji = activeStickers[i];
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _overlays.add(OverlayItem(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              content: emoji,
                              isText: false,
                              position: const Offset(150, 250),
                            )));
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Text(emoji, style: const TextStyle(fontSize: 34)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
                      _buildBottomConsole(),
                    ],
                  ),
                ),
              ),
            ),

            // Front screen flash burst: illuminates the user's face while clicking the photo
            if (_isFrontScreenFlashing)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Luxury Floating Top Bar HUD ──────────────────────────────────────────────
  Widget _buildTopBar() {
    final palette = ref.watch(appPaletteProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.48),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Close / Back button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _stopCamera();
                    context.pop();
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 19),
                  ),
                ),
                const Spacer(),

                // PHOTO / VIDEO Segmented Luxury Pill
                Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _modePill('PHOTO', Icons.camera_alt_rounded, palette),
                      _modePill('VIDEO', Icons.videocam_rounded, palette),
                    ],
                  ),
                ),
                const Spacer(),

                // Utilities: Flash / Front Screen Flash
                Tooltip(
                  message: _isFrontCamera
                      ? (_flashOn ? 'Turn off Screen Flash' : 'Turn on Screen Flash')
                      : (_flashOn ? 'Turn off Camera Flash' : 'Turn on Camera Flash'),
                  child: GestureDetector(
                    onTap: _toggleFlash,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _flashOn
                            ? const Color(0xFFFFD600).withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _flashOn
                              ? const Color(0xFFFFD600).withValues(alpha: 0.8)
                              : Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        color: _flashOn ? const Color(0xFFFFD600) : Colors.white70,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Cinema Grid toggle
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showGrid = !_showGrid);
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _showGrid
                          ? palette.primary.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _showGrid
                            ? palette.primary.withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.grid_3x3_rounded,
                      color: _showGrid ? Colors.white : Colors.white70,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Quick Flip Camera
                GestureDetector(
                  onTap: _flipCameraWithAnimation,
                  child: RotationTransition(
                    turns: Tween<double>(begin: 0.0, end: 0.5).animate(
                      CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOutCubic),
                    ),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 18),
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

  Widget _modePill(String m, IconData icon, AppPalette palette) {
    final sel = _mode == m;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _mode = m);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: sel ? palette.primaryGradient : null,
          color: sel ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: sel
              ? [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: sel ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 5),
            Text(
              m,
              style: TextStyle(
                color: sel ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
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

  // ── Preview Area with Viewfinder Overlay ──────────────────────────────────────
  Widget _buildPreviewArea() {
    final palette = ref.watch(appPaletteProvider);

    Widget content = RepaintBoundary(
      key: _previewKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildBaseLayer(),

          // Optical top vignette (viewfinder live camera only)
          if (_capturedImageBytes == null && _capturedVideoBytes == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 140,
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

          // Optical bottom vignette (viewfinder live camera only)
          if (_capturedImageBytes == null && _capturedVideoBytes == null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 220,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Viewfinder Cinema Rule-of-Thirds Grid (viewfinder live camera only)
          if (_showGrid && _capturedImageBytes == null && _capturedVideoBytes == null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CinemaGridPainter(),
                ),
              ),
            ),

          // Viewfinder Corner Cinema Reticles (viewfinder live camera only)
          if (_capturedImageBytes == null && _capturedVideoBytes == null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CinemaReticlePainter(),
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

          // Interactive Gestures & Overlays (Tap to focus, swipe for filter)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (details) {
              if (_tab != 'NONE') {
                setState(() => _tab = 'NONE');
              } else {
                _triggerFocus(details.localPosition);
              }
            },
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;
              final filters = AppColorFilters.names;
              final currentIndex = filters.indexOf(_filter);
              if (details.primaryVelocity! < -250) {
                HapticFeedback.selectionClick();
                setState(() {
                  _filter = filters[(currentIndex + 1) % filters.length];
                });
              } else if (details.primaryVelocity! > 250) {
                HapticFeedback.selectionClick();
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

          // Interactive Tap-to-Focus Reticle
          if (_focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 30,
              top: _focusPoint!.dy - 30,
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _focusOpacity,
                  child: ScaleTransition(
                    scale: _focusScale,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFFFD600).withValues(alpha: 0.9),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD600).withValues(alpha: 0.4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFFFD600),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Active Filter Floating Chip
          if (_filter != 'Normal')
            Positioned(
              top: 72,
              left: 0,
              right: 0,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: palette.primary.withValues(alpha: 0.45),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: palette.primary.withValues(alpha: 0.3),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (b) => palette.primaryGradient.createShader(b),
                            child: const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            _filter,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() => _filter = 'Normal');
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.16),
                              ),
                              child: const Icon(Icons.close_rounded, size: 11, color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Live Recording Status HUD
          if (_isRecording)
            Positioned(
              top: 72,
              left: 0,
              right: 0,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFFFF2D55).withValues(alpha: 0.65),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF2D55).withValues(alpha: 0.45),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseCtrl,
                            builder: (_, __) => Container(
                              width: 8.5,
                              height: 8.5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFF2D55),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF2D55).withValues(
                                      alpha: 0.5 + 0.5 * _glowPulse.value,
                                    ),
                                    blurRadius: 8 * _glowPulse.value,
                                    spreadRadius: 2 * _glowPulse.value,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Text(
                            'REC',
                            style: TextStyle(
                              color: Color(0xFFFF2D55),
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            _formatDuration(_recordSeconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              fontFamily: 'monospace',
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '/ 00:30',
                            style: TextStyle(
                              color: Colors.white38,
                              fontWeight: FontWeight.w600,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
          child: Center(
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
        child: Center(
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

  // ── Floating Creative Studio Dock ───────────────────────────────────────────
  Widget _buildTabBar() {
    final palette = ref.watch(appPaletteProvider);
    final hasCapturedVideo = _capturedVideoBytes != null;

    final items = <_StudioDockItem>[
      const _StudioDockItem(
        key: 'FILTERS',
        icon: Icons.auto_awesome_rounded,
        label: 'Filters',
      ),
      const _StudioDockItem(
        key: 'STICKERS',
        icon: Icons.sentiment_satisfied_alt_rounded,
        label: 'Stickers',
      ),
      const _StudioDockItem(
        key: 'CROP',
        icon: Icons.aspect_ratio_rounded,
        label: 'Format',
      ),
      const _StudioDockItem(
        key: 'TEXT',
        icon: Icons.text_fields_rounded,
        label: 'Text',
      ),
      if (hasCapturedVideo)
        const _StudioDockItem(
          key: 'TRIM',
          icon: Icons.content_cut_rounded,
          label: 'Trim',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: items.map((it) {
                final isSel = _tab == it.key;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (it.key == 'STICKERS') {
                      setState(() => _tab = 'NONE');
                      _addSticker();
                    } else if (it.key == 'TEXT') {
                      setState(() => _tab = 'NONE');
                      _addText();
                    } else {
                      setState(() => _tab = isSel ? 'NONE' : it.key);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      gradient: isSel ? palette.primaryGradient : null,
                      color: isSel ? null : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: isSel
                          ? [
                              BoxShadow(
                                color: palette.primary.withValues(alpha: 0.45),
                                blurRadius: 12,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          it.icon,
                          size: 15,
                          color: isSel ? Colors.white : Colors.white70,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          it.label,
                          style: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
                            fontSize: 11.5,
                            fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
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
    return const SizedBox(height: 12);
  }

  // ── Luxury Lens Filter Studio Carousel ───────────────────────────────────────
  Widget _buildColorFilterBar() {
    final filters = AppColorFilters.names;
    final currentUser = ref.watch(currentUserProvider);
    final isPremium = currentUser.hasActiveSubscription;
    final palette = ref.watch(appPaletteProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 94,
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
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _filter = f);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: sel ? 60 : 52,
                    height: sel ? 60 : 52,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: sel ? palette.primaryGradient : null,
                      border: sel
                          ? null
                          : Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 1.2,
                            ),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                color: palette.primary.withValues(alpha: 0.55),
                                blurRadius: 14,
                                spreadRadius: 1.5,
                              ),
                            ]
                          : null,
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF141022),
                      ),
                      clipBehavior: Clip.antiAlias,
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
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.55),
                                ],
                              ),
                            ),
                          ),
                          if (isPremiumFilter && !isPremium)
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.65),
                                ),
                                child: const Icon(
                                  Icons.lock_rounded,
                                  color: Colors.amberAccent,
                                  size: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        f,
                        style: TextStyle(
                          color: sel ? Colors.white : Colors.white60,
                          fontSize: 10,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (isPremiumFilter) ...[
                        const SizedBox(width: 2.5),
                        const Icon(Icons.auto_awesome, size: 8.5, color: Colors.amberAccent),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Luxury Format & Framing Studio ───────────────────────────────────────────
  Widget _buildCropTab() {
    final palette = ref.watch(appPaletteProvider);
    const aspects = <_AspectItem>[
      _AspectItem('Original', 'Free', Icons.crop_free_rounded),
      _AspectItem('1:1', 'Square', Icons.crop_square_rounded),
      _AspectItem('4:5', 'Portrait', Icons.crop_portrait_rounded),
      _AspectItem('9:16', 'Story', Icons.stay_current_portrait_rounded),
      _AspectItem('16:9', 'Cinema', Icons.crop_16_9_rounded),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF100D22).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 4),
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
              const Row(
                children: [
                  Icon(Icons.crop_rotate_rounded, color: Colors.white70, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Frame & Proportions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _cropAspect = 'Original';
                    _cropZoom = 1.0;
                    _cropX = 0.0;
                    _cropY = 0.0;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Reset',
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Aspect Ratio Horizontal Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: aspects.map((a) {
                final isSelected = _cropAspect == a.key;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _cropAspect = a.key);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: isSelected ? palette.primaryGradient : null,
                      color: isSelected ? null : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? Colors.transparent
                            : Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: palette.primary.withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(a.icon, size: 14, color: isSelected ? Colors.white : Colors.white60),
                        const SizedBox(width: 6),
                        Text(
                          a.label,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // Zoom Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Optical Zoom', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text(
                '${_cropZoom.toStringAsFixed(2)}x',
                style: TextStyle(color: palette.primary, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: palette.primary,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: palette.primary.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
            ),
            child: Slider(
              value: _cropZoom,
              min: 1.0,
              max: 3.0,
              onChanged: (val) => setState(() => _cropZoom = val),
            ),
          ),
        ],
      ),
    );
  }

  // ── Luxury Video Trim Studio ─────────────────────────────────────────────────
  Widget _buildTrimTab() {
    final palette = ref.watch(appPaletteProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF100D22).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 4),
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
              const Row(
                children: [
                  Icon(Icons.content_cut_rounded, color: Colors.white70, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Trim Video',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Text(
                '${_trimStart.toStringAsFixed(1)}s → ${_trimEnd.toStringAsFixed(1)}s (${(_trimEnd - _trimStart).toStringAsFixed(1)}s)',
                style: TextStyle(
                  color: palette.primary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Visual Timeline Wave
          Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: palette.primaryGradient,
            ),
          ),
          const SizedBox(height: 14),

          // Start Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Start Point', style: TextStyle(color: Colors.white60, fontSize: 11)),
              Text('${_trimStart.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: palette.primary,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
              const Text('End Point', style: TextStyle(color: Colors.white60, fontSize: 11)),
              Text('${_trimEnd.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: palette.primary,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
        ],
      ),
    );
  }

  // ── Unified Master Shutter & Post Console ────────────────────────────────────
  Widget _buildBottomConsole() {
    final hasCaptured = _capturedImageBytes != null || _capturedVideoBytes != null;
    final palette = ref.watch(appPaletteProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: hasCaptured
          // ── POST-CAPTURE CONSOLE ──
          ? Row(
              children: [
                // Retake Button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _retake();
                  },
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.replay_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Retake',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Hero Post Moment Button
                Expanded(
                  child: GestureDetector(
                    onTap: (_isSaving || _isRecording) ? null : _post,
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: palette.primaryGradient,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: palette.primary.withValues(alpha: 0.55),
                            blurRadius: 20,
                            spreadRadius: 1,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _isSaving
                          ? const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Row(
                              children: [
                                // Current user avatar with ring
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                    image: currentUser.avatarUrl != null && currentUser.avatarUrl!.isNotEmpty
                                        ? DecorationImage(
                                            image: CachedNetworkImageProvider(currentUser.avatarUrl!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: currentUser.avatarUrl == null || currentUser.avatarUrl!.isEmpty
                                      ? Center(
                                          child: Text(
                                            currentUser.name.isNotEmpty ? currentUser.name[0].toUpperCase() : 'U',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 10),

                                // Title and audience
                                const Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Drop Moment ✨',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      Text(
                                        'Your Story • 24 Hours',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Send icon bubble
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    color: palette.primary,
                                    size: 19,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            )
          // ── PRE-CAPTURE CONSOLE ──
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Gallery Squircle
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _uploadFromGallery();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.photo_library_rounded,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Gallery',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),

                // Master Shutter Button
                ScaleTransition(
                  scale: _shutterScale,
                  child: GestureDetector(
                    onTap: () {
                      if (_mode == 'PHOTO') {
                        _takePhoto();
                      } else {
                        HapticFeedback.mediumImpact();
                        if (_isRecording) {
                          _stopVideoRecord();
                        } else {
                          _startVideoRecord();
                        }
                      }
                    },
                    child: SizedBox(
                      width: 86,
                      height: 86,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer progress ring for video recording
                          if (_isRecording)
                            SizedBox(
                              width: 84,
                              height: 84,
                              child: CircularProgressIndicator(
                                value: (_recordSeconds / 30.0).clamp(0.0, 1.0),
                                strokeWidth: 4.5,
                                color: const Color(0xFFFF2D55),
                                backgroundColor: Colors.white.withValues(alpha: 0.2),
                              ),
                            )
                          else
                            // Concentric ambient halo ring
                            AnimatedBuilder(
                              animation: _pulseCtrl,
                              builder: (_, __) => Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _mode == 'VIDEO'
                                        ? const Color(0xFFFF2D55).withValues(alpha: 0.7)
                                        : Colors.white.withValues(alpha: 0.6 + 0.3 * _glowPulse.value),
                                    width: 3.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_mode == 'VIDEO' ? const Color(0xFFFF2D55) : palette.primary)
                                          .withValues(alpha: 0.35 + 0.25 * _glowPulse.value),
                                      blurRadius: 16,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Inner Liquid Core
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            width: _isRecording ? 34 : 66,
                            height: _isRecording ? 34 : 66,
                            decoration: BoxDecoration(
                              color: _mode == 'VIDEO' ? const Color(0xFFFF2D55) : Colors.white,
                              shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                              borderRadius: _isRecording ? BorderRadius.circular(10) : null,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Quick Flip Camera Squircle
                GestureDetector(
                  onTap: _flipCameraWithAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: RotationTransition(
                          turns: Tween<double>(begin: 0.0, end: 0.5).animate(
                            CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOutCubic),
                          ),
                          child: const Icon(
                            Icons.flip_camera_ios_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Flip',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Models & Custom Viewfinder Painters ───────────────────────────────────────

class _StudioDockItem {
  final String key;
  final IconData icon;
  final String label;

  const _StudioDockItem({
    required this.key,
    required this.icon,
    required this.label,
  });
}

class _AspectItem {
  final String key;
  final String label;
  final IconData icon;

  const _AspectItem(this.key, this.label, this.icon);
}

// ── 3x3 Cinema Rule-of-Thirds Grid Painter ─────────────────────────────────────
class _CinemaGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final x1 = size.width / 3.0;
    final x2 = size.width * 2.0 / 3.0;
    final y1 = size.height / 3.0;
    final y2 = size.height * 2.0 / 3.0;

    canvas.drawLine(Offset(x1, 0), Offset(x1, size.height), paint);
    canvas.drawLine(Offset(x2, 0), Offset(x2, size.height), paint);
    canvas.drawLine(Offset(0, y1), Offset(size.width, y1), paint);
    canvas.drawLine(Offset(0, y2), Offset(size.width, y2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Cinema Viewfinder L-Corner Reticles Painter ────────────────────────────────
class _CinemaReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const pad = 24.0;
    const len = 14.0;

    // Top Left
    canvas.drawLine(const Offset(pad, pad + len), const Offset(pad, pad), paint);
    canvas.drawLine(const Offset(pad, pad), const Offset(pad + len, pad), paint);

    // Top Right
    canvas.drawLine(Offset(size.width - pad - len, pad), Offset(size.width - pad, pad), paint);
    canvas.drawLine(Offset(size.width - pad, pad), Offset(size.width - pad, pad + len), paint);

    // Bottom Left
    canvas.drawLine(Offset(pad, size.height - pad - len), Offset(pad, size.height - pad), paint);
    canvas.drawLine(Offset(pad, size.height - pad), Offset(pad + len, size.height - pad), paint);

    // Bottom Right
    canvas.drawLine(Offset(size.width - pad - len, size.height - pad), Offset(size.width - pad, size.height - pad), paint);
    canvas.drawLine(Offset(size.width - pad, size.height - pad - len), Offset(size.width - pad, size.height - pad), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

