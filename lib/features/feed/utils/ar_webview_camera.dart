// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// A widget that renders the AR camera inside a WebView.
/// The WebView loads `assets/ar_webview.html` which contains the MediaPipe
/// face-mesh tracker and all filter images from `assets/filters/`.
///
/// Communication with Flutter:
///   Flutter → JS : controller.runJavaScript('setFilter("Dog")');
///   JS → Flutter : ARChannel.postMessage(JSON.stringify({ type, data }));
class ARWebViewCamera extends StatefulWidget {
  /// Called when the WebView signals readiness.
  final VoidCallback? onReady;

  /// Called when a JPEG frame is captured (base64 encoded, no prefix).
  final void Function(Uint8List bytes)? onCapture;

  /// Called when a video blob is captured (base64 data URL).
  final void Function(Uint8List bytes)? onVideoCapture;

  const ARWebViewCamera({
    super.key,
    this.onReady,
    this.onCapture,
    this.onVideoCapture,
  });

  @override
  State<ARWebViewCamera> createState() => ARWebViewCameraState();
}

class ARWebViewCameraState extends State<ARWebViewCamera> {
  WebViewController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          // Once HTML is loaded, the JS will call startAR() automatically
        },
      ))
      ..addJavaScriptChannel(
        'ARChannel',
        onMessageReceived: _handleMessage,
      );

    // Enable camera permission in the Android WebView
    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      await androidController.setMediaPlaybackRequiresUserGesture(false);
      await androidController.setOnPlatformPermissionRequest(
        (PlatformWebViewPermissionRequest request) {
          request.grant(); // grant camera + microphone
        },
      );
    }

    // Load the AR HTML from bundled assets.
    // loadFlutterAsset serves the file via Flutter's asset server, so
    // relative paths like ar_tracker.js and filters/ resolve correctly.
    await controller.loadFlutterAsset('assets/ar_webview.html');

    setState(() => _controller = controller);
  }

  void _handleMessage(JavaScriptMessage msg) {
    try {
      final data = jsonDecode(msg.message) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'ready':
          setState(() => _ready = true);
          widget.onReady?.call();
          break;

        case 'capture':
          final base64Str = (data['data'] as String)
              .replaceFirst(RegExp(r'^data:image/\w+;base64,'), '');
          if (base64Str.isEmpty || base64Str.length < 100) {
            debugPrint('ARWebView: capture ignored (canvas empty/loading)');
            break;
          }
          final bytes = base64Decode(base64Str);
          widget.onCapture?.call(bytes);
          break;

        case 'video':
          final base64Str = (data['data'] as String)
              .replaceFirst(RegExp(r'^data:video/\w+;base64,'), '');
          if (base64Str.isEmpty || base64Str.length < 100) {
            debugPrint('ARWebView: video capture ignored (empty data)');
            break;
          }
          final bytes = base64Decode(base64Str);
          widget.onVideoCapture?.call(bytes);
          break;

        case 'recording_started':
          // optional: tell parent recording began
          break;

        case 'error':
          debugPrint('ARWebView error: ${data['message']}');
          break;
      }
    } catch (e) {
      debugPrint('ARChannel parse error: $e');
    }
  }

  // ── Public API (called by parent) ─────────────────────────────────────────

  Future<void> setFilter(String filterName) async {
    // Determine the asset path and the JS object key based on the filter name
    String? assetPath;
    String? jsKey;
    switch (filterName) {
      case 'Dog': assetPath = 'assets/filters/dog_filter.png'; jsKey = 'dog'; break;
      case 'Thug Life': assetPath = 'assets/filters/thug_life.png'; jsKey = 'thugLife'; break;
      case 'Flower Crown': assetPath = 'assets/filters/flower_crown.png'; jsKey = 'flowerCrown'; break;
      case 'Cat': assetPath = 'assets/filters/cat_filter.png'; jsKey = 'cat'; break;
      case 'Devil': assetPath = 'assets/filters/devil_horns.png'; jsKey = 'devil'; break;
      case 'Bunny': assetPath = 'assets/filters/bunny_filter.png'; jsKey = 'bunny'; break;
      case 'Halo': assetPath = 'assets/filters/angel_halo.png'; jsKey = 'halo'; break;
      case 'Hearts': assetPath = 'assets/filters/heart_eyes.png'; jsKey = 'hearts'; break;
      case 'Clown': assetPath = 'assets/filters/clown_filter.png'; jsKey = 'clown'; break;
      case 'Crown': assetPath = 'assets/filters/crown_filter.png'; jsKey = 'crown'; break;
    }

    // Inject the base64 image into JS to bypass CORS and canvas tainting on Android
    if (assetPath != null && jsKey != null) {
      try {
        final ByteData data = await DefaultAssetBundle.of(context).load(assetPath);
        final base64Str = base64Encode(data.buffer.asUint8List());
        await _controller?.runJavaScript("if (window.arTracker) { "
            "if (!window.arTracker.images['$jsKey']) window.arTracker.images['$jsKey'] = new Image(); "
            "window.arTracker.images['$jsKey'].src = 'data:image/png;base64,$base64Str'; "
            "}");
      } catch (e) {
        debugPrint('Failed to load asset for filter: $e');
      }
    }

    await _controller?.runJavaScript("if (window.arTracker) window.arTracker.setFilter('${filterName.replaceAll("'", "\\'")}');");
  }

  Future<void> flipCamera(bool isFront) async {
    await _controller?.runJavaScript("if (window.startAR) window.startAR(${isFront ? 'true' : 'false'});");
  }

  Future<void> captureFrame() async {
    await _controller?.runJavaScript('captureFrame();');
  }

  Future<void> startRecording() async {
    await _controller?.runJavaScript('startRecording();');
  }

  Future<void> stopRecording() async {
    await _controller?.runJavaScript('stopRecording();');
  }

  Future<void> stopCamera() async {
    await _controller?.runJavaScript('if (typeof stopAR === "function") stopAR();');
  }

  Future<void> updateFilterConfig(String name, double scale, double offsetX, double offsetY) async {
    await _controller?.runJavaScript(
      "updateFilterConfig('${name.replaceAll("'", "\\'")}', $scale, $offsetX, $offsetY);",
    );
  }

  Future<void> applyColorMatrix(List<double> matrix, double blurRadius) async {
    final matrixStr = '[${matrix.join(',')}]';
    await _controller?.runJavaScript('applyColorMatrix($matrixStr, $blurRadius);');
  }

  Future<void> applyBeautyFilter(double intensity) async {
    await _controller?.runJavaScript('if(window.arTracker) window.arTracker.setBeautyIntensity($intensity);');
  }


  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller!),
        if (!_ready)
          Container(
            color: Colors.black,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white54),
                  SizedBox(height: 12),
                  Text(
                    'Loading AR...',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
