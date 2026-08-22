import 'dart:typed_data';

// Empty implementations of js_interop types to satisfy the compiler on native platforms.

class JSArrayBuffer {}
class JSAny {}
class JSObject {}

extension JSAnyExtension on Object? {
  dynamic get toJS => this;
  dynamic get toDart => this;
  dynamic jsify() => this;
  Uint8List asUint8List() => Uint8List(0);
}
