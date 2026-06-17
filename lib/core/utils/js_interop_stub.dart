// Empty implementations of js_interop types to satisfy the compiler on native platforms.

extension JSAnyExtension on Object? {
  dynamic get toJS => this;
  dynamic get toDart => this;
  dynamic jsify() => this;
}
