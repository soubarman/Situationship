// Empty implementations of web types to satisfy the compiler on native platforms.
// On web, these are replaced by package:web/web.dart via conditional imports.

class Event {}

class BlobEvent extends Event {
  dynamic get data => _Blob();
}

class _Blob {
  int get size => 0;
}

class FileReader {
  dynamic get result => null;
  void addEventListener(String type, dynamic listener) {}
  void readAsArrayBuffer(dynamic blob) {}
  void readAsDataURL(dynamic blob) {}
}

class HTMLVideoElement {
  set srcObject(dynamic value) {}
  set src(String value) {}
  set autoplay(bool value) {}
  set muted(bool value) {}
  set loop(bool value) {}
  void setAttribute(String name, String value) {}
  void pause() {}
  void play() {}
  void removeAttribute(String name) {}
  void load() {}
  dynamic get onPlaying => _EventStream();
  dynamic get style => _Style();
  int get videoWidth => 0;
  int get videoHeight => 0;
  double get duration => 0.0;
  double currentTime = 0.0;
  void addEventListener(String type, dynamic listener) {}
}

class _EventStream {
  Future<dynamic> get first => Future.value(null);
}

class _Style {
  set width(String value) {}
  set height(String value) {}
  set objectFit(String value) {}
  set transform(String value) {}
}

class MediaStream {
  dynamic getTracks() => [];
}

class MediaRecorderOptions {
  final String? mimeType;
  final int? videoBitsPerSecond;
  MediaRecorderOptions({this.mimeType, this.videoBitsPerSecond});
}

class MediaRecorder {
  MediaRecorder(dynamic stream, [dynamic options]) {}
  void start([int? timeslice]) {}
  void stop() {}
  void addEventListener(String type, dynamic listener) {}
  dynamic get ondataavailable => null;
  set ondataavailable(dynamic handler) {}
  dynamic get onstop => null;
  set onstop(dynamic handler) {}
  static bool isTypeSupported(String type) => false;
}

class BlobPropertyBag {
  BlobPropertyBag({String? type});
}

class Blob {
  int get size => 0;
  Blob([dynamic parts, dynamic options]) {}
  dynamic arrayBuffer() => null;
}

class HTMLCanvasElement {
  int width  = 0;
  int height = 0;
  dynamic get style => _Style();
  String toDataUrl(String type, [double quality = 0.92]) => '';
  dynamic captureStream([int? frameRate]) => null;
  dynamic getContext(String contextId) => _CanvasRenderingContext2D();
}

class _CanvasRenderingContext2D {
  void translate(num x, num y) {}
  void scale(num x, num y) {}
  void drawImage(dynamic image, num dx, num dy) {}
}

// Alias so cast syntax works: `as CanvasRenderingContext2D`
typedef CanvasRenderingContext2D = _CanvasRenderingContext2D;

class DOMException implements Exception {
  final String name    = '';
  final String message = '';
}

class URL {
  static String createObjectURL(dynamic blob) => '';
  static void revokeObjectURL(String url) {}
}

class Window {
  final navigator = Navigator();
}

class Navigator {
  final mediaDevices = MediaDevices();
}

class MediaDevices {
  dynamic getUserMedia(dynamic constraints) => null;
}

class MediaStreamConstraints {
  final dynamic video;
  final dynamic audio;
  MediaStreamConstraints({this.video, this.audio});
}

class MediaTrackConstraints {
  final dynamic width;
  final dynamic height;
  final dynamic facingMode;
  MediaTrackConstraints({this.width, this.height, this.facingMode});
}

class ConstrainULongRange {
  final int? ideal;
  final int? exact;
  final int? min;
  final int? max;
  ConstrainULongRange({this.ideal, this.exact, this.min, this.max});
}

final window = Window();
