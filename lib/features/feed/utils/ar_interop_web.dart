// Web-only AR interop using dart:js_util (no package:js required)
// This file is only compiled when dart.library.html is available (web).
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:js_util' as js_util;

html.CanvasElement initializeARTracker(html.VideoElement videoElement) {
  final tracker = js_util.getProperty<Object>(html.window, 'arTracker');
  return js_util.callMethod<html.CanvasElement>(tracker, 'initialize', [videoElement]);
}

void setARFilter(String filterName) {
  final tracker = js_util.getProperty<Object>(html.window, 'arTracker');
  js_util.callMethod<void>(tracker, 'setFilter', [filterName]);
}

void stopARTracker() {
  final tracker = js_util.getProperty<Object>(html.window, 'arTracker');
  js_util.callMethod<void>(tracker, 'stop', []);
}

void updateARFilterConfig(
  String filterName,
  double scale,
  double offsetX,
  double offsetY,
) {
  final tracker = js_util.getProperty<Object>(html.window, 'arTracker');
  js_util.callMethod<void>(tracker, 'updateFilterConfig', [filterName, scale, offsetX, offsetY]);
}
