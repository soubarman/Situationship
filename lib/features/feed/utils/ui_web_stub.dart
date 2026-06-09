class PlatformViewRegistry {
  bool registerViewFactory(String viewTypeId, dynamic Function(int viewId) viewFactory) => false;
}
final platformViewRegistry = PlatformViewRegistry();
