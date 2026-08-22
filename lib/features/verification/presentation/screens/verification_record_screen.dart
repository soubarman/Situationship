// lib/features/verification/presentation/screens/verification_record_screen.dart
//
// Step 2: Camera recording screen with challenge overlay.
// Uses browser MediaRecorder API via dart:js_interop for Flutter Web.

import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/verification_provider.dart';
import '../widgets/challenge_display_widget.dart';

class VerificationRecordScreen extends ConsumerStatefulWidget {
  const VerificationRecordScreen({super.key});

  @override
  ConsumerState<VerificationRecordScreen> createState() =>
      _VerificationRecordScreenState();
}

class _VerificationRecordScreenState
    extends ConsumerState<VerificationRecordScreen> {
  // Recording state
  bool _isLoading = true;
  bool _isRecording = false;
  bool _isDone = false;
  Uint8List? _recordedBytes;
  String? _errorMessage;

  // MediaRecorder state (web)
  web.MediaRecorder? _mediaRecorder;
  web.MediaStream? _mediaStream;
  final List<web.Blob> _chunks = [];

  // Live camera preview video element
  web.HTMLVideoElement? _previewElement;
  String? _previewElementId;

  // Playback video element (shows after recording stops)
  web.HTMLVideoElement? _playbackElement;
  String? _playbackElementId;

  @override
  void initState() {
    super.initState();
    final ts = DateTime.now().millisecondsSinceEpoch;
    _previewElementId = 'preview-$ts';
    _playbackElementId = 'playback-$ts';

    // ── Live preview video element (mirrored) ──────────────────────────────
    _previewElement = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.transform = 'scaleX(-1)'; // Mirror for front camera
    _previewElement!.setAttribute('playsinline', 'true');

    ui_web.platformViewRegistry.registerViewFactory(
      _previewElementId!,
      (int viewId) => _previewElement!,
    );

    // ── Playback video element (also mirrored to match what user saw) ──────
    _playbackElement = web.HTMLVideoElement()
      ..autoplay = false
      ..muted = false
      ..controls = false
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.transform = 'scaleX(-1)'; // Mirror to match preview
    _playbackElement!.setAttribute('playsinline', 'true');
    _playbackElement!.setAttribute('loop', 'true');

    ui_web.platformViewRegistry.registerViewFactory(
      _playbackElementId!,
      (int viewId) => _playbackElement!,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchChallengeAndInitCamera();
    });
  }

  Future<void> _fetchChallengeAndInitCamera() async {
    await ref.read(challengeProvider.notifier).fetchChallenge();

    if (!mounted) return;
    final challengeState = ref.read(challengeProvider);
    if (challengeState.hasError) {
      setState(() {
        _errorMessage = challengeState.error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
      return;
    }

    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final constraints = web.MediaStreamConstraints(
        video: (web.MediaTrackConstraints(
          width: web.ConstrainULongRange(ideal: 1280),
          height: web.ConstrainULongRange(ideal: 720),
          facingMode: 'user'.toJS,
        ).jsify() as JSAny),
        audio: true.toJS,
      );

      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;

      _mediaStream = stream;

      if (_previewElement != null) {
        _previewElement!.srcObject = stream;
        await _previewElement!.play().toDart;
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Camera access denied. Please allow camera permission and retry.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startRecording() async {
    if (_mediaStream == null) return;
    _chunks.clear();

    final mimeType = _getSupportedMimeType();
    final options = web.MediaRecorderOptions(
      mimeType: mimeType,
      videoBitsPerSecond: 800000,
    );

    _mediaRecorder = web.MediaRecorder(_mediaStream!, options);

    _mediaRecorder!.ondataavailable = (web.BlobEvent event) {
      if (event.data.size > 0) {
        _chunks.add(event.data);
      }
    }.toJS;

    _mediaRecorder!.onstop = (web.Event _) {
      _onRecordingStop();
    }.toJS;

    _mediaRecorder!.start(1000);
    setState(() => _isRecording = true);

    // Auto-stop after 15 seconds
    Timer(const Duration(seconds: 15), () {
      if (_isRecording && mounted) _stopRecording();
    });
  }

  void _stopRecording() {
    _mediaRecorder?.stop();
    setState(() {
      _isRecording = false;
      _isDone = true;
    });
  }

  Future<void> _onRecordingStop() async {
    if (_chunks.isEmpty) {
      setState(() => _errorMessage = 'No video data captured. Please try again.');
      return;
    }

    // Combine chunks into a single Blob
    final jsArray = _chunks.toJS;
    final blob = web.Blob(jsArray);

    // Convert to bytes for upload
    final arrayBuffer = await blob.arrayBuffer().toDart;
    final bytes = arrayBuffer.toDart.asUint8List();

    // Build an object URL for local playback in the review step
    final blobUrl = web.URL.createObjectURL(blob);
    if (_playbackElement != null) {
      _playbackElement!.src = blobUrl;
      _playbackElement!.load();
      _playbackElement!.play(); // ignore: unawaited_futures — fire & forget
    }

    setState(() => _recordedBytes = bytes);
  }

  String _getSupportedMimeType() {
    const mimeTypes = [
      'video/webm;codecs=vp9,opus',
      'video/webm;codecs=vp8,opus',
      'video/webm',
      'video/mp4',
    ];
    for (final mime in mimeTypes) {
      if (web.MediaRecorder.isTypeSupported(mime)) return mime;
    }
    return 'video/webm';
  }

  Future<void> _submitVideo() async {
    if (_recordedBytes == null) return;

    final challenge = ref.read(challengeProvider).value;
    if (challenge == null) return;

    if (challenge.isExpired) {
      _showError('Challenge has expired. Please go back and start again.');
      return;
    }

    // Reset state before starting
    ref.read(verificationSubmissionProvider.notifier).reset();

    // Show upload progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Consumer(
          builder: (dialogCtx, ref, child) {
            final submissionState = ref.watch(verificationSubmissionProvider);
            final progressPercent = (submissionState.uploadProgress * 100).toInt();

            return Dialog(
              backgroundColor: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFAB47BC)),
                    const SizedBox(height: 20),
                    const Text(
                      'Uploading video…',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$progressPercent%',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // Trigger video upload & verification submission in the background
    ref.read(verificationSubmissionProvider.notifier).submitVideo(
          videoBytes: _recordedBytes!,
          challenge: challenge,
        );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFFF5252),
      ),
    );
  }

  void _retake() {
    // Stop playback and go back to live camera
    if (_playbackElement != null) {
      _playbackElement!.pause();
      _playbackElement!.src = '';
    }
    setState(() {
      _isDone = false;
      _recordedBytes = null;
      _chunks.clear();
    });
  }

  @override
  void dispose() {
    final tracks = _mediaStream?.getTracks().toDart;
    if (tracks != null) {
      for (final track in tracks) {
        (track as web.MediaStreamTrack).stop();
      }
    }
    _playbackElement?.pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to submission state changes for clean, single-trigger side-effects
    ref.listen<SubmissionState>(verificationSubmissionProvider, (previous, next) {
      if (next.step == SubmissionStep.failed) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // Close upload dialog
        }
        _showError(next.error ?? 'Upload failed');
      } else if (next.step == SubmissionStep.processing || next.step == SubmissionStep.completed) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // Close upload dialog
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Video uploaded! We are verifying your profile in the background. '
              'Feel free to use the app in the meantime.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Color(0xFFAB47BC),
            duration: Duration(seconds: 5),
          ),
        );
        context.go('/feed'); // Redirect user to home screen immediately
      }
    });

    final challengeAsync = ref.watch(challengeProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _isRecording
              ? '🔴  Recording…'
              : _isDone
                  ? 'Review'
                  : 'Record Video',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _RecordingTimer(),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFAB47BC)),
            )
          : _errorMessage != null
              ? _ErrorView(
                  message: _errorMessage!,
                  onRetry: () {
                    setState(() {
                      _errorMessage = null;
                      _isLoading = true;
                    });
                    _fetchChallengeAndInitCamera();
                  },
                )
              : Stack(
                  children: [
                    // ── Video layer: live camera or recorded playback ──────
                    Positioned.fill(
                      child: _isDone
                          // Review mode: show recorded clip
                          ? HtmlElementView(viewType: _playbackElementId!)
                          // Live mode: show camera preview (mirrored)
                          : HtmlElementView(viewType: _previewElementId!),
                    ),

                    // ── Challenge overlay (only while not reviewing) ───────
                    if (!_isDone)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: challengeAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (e, _) => _ErrorBanner(message: e.toString()),
                          data: (challenge) => challenge == null
                              ? const SizedBox.shrink()
                              : ChallengeDisplayWidget(
                                  code: challenge.code,
                                  phrase: challenge.phrase,
                                  action: challenge.action,
                                  movement: challenge.movement,
                                  ttlSeconds: challenge.ttlSeconds,
                                  onExpired: () =>
                                      _showError('Challenge expired. Going back.'),
                                ),
                        ),
                      ),

                    // ── Bottom controls ────────────────────────────────────
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _buildControls(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
        ),
      ),
      child: _isDone
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _retake,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Retake',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _recordedBytes != null ? _submitVideo : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFAB47BC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Submit Video',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: GestureDetector(
                onTap: _isRecording ? _stopRecording : _startRecording,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording
                        ? const Color(0xFFFF5252)
                        : const Color(0xFFAB47BC),
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording
                                ? const Color(0xFFFF5252)
                                : const Color(0xFFAB47BC))
                            .withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.fiber_manual_record,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
    );
  }
}

class _RecordingTimer extends StatefulWidget {
  @override
  State<_RecordingTimer> createState() => _RecordingTimerState();
}

class _RecordingTimerState extends State<_RecordingTimer> {
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mins = _seconds ~/ 60;
    final secs = _seconds % 60;
    return Text(
      '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
      style: const TextStyle(
        color: Color(0xFFFF5252),
        fontSize: 16,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, color: Color(0xFFFF5252), size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFAB47BC)),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5252).withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}
