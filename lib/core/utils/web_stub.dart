// Empty implementations of web types to satisfy the compiler on native platforms.

class Event {}

class BlobEvent extends Event {
  dynamic get data => null;
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
  void removeAttribute(String name) {}
  void load() {}
  dynamic get onPlaying => null;
  dynamic get style => _Style();
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
  MediaRecorderOptions({int? videoBitsPerSecond});
}

class MediaRecorder {
  MediaRecorder(dynamic stream, [dynamic options]) {}
  void start([int? timeslice]) {}
  void stop() {}
  void addEventListener(String type, dynamic listener) {}
  dynamic get ondataavailable => null;
  dynamic get onstop => null;
}

class BlobPropertyBag {
  BlobPropertyBag({String? type});
}

class Blob {
  Blob(dynamic parts, [dynamic options]) {}
}

class HTMLCanvasElement {
  set width(dynamic value) {}
  set height(dynamic value) {}
  dynamic get style => _Style();
  String toDataUrl(String type, double quality) => '';
  dynamic captureStream([int? frameRate]) => null;
}

class DOMException implements Exception {
  final String name = '';
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

class MediaStreamConstraints {}

final window = Window();
