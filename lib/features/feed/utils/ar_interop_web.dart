// Web-only AR interop using dart:js_interop (Wasm compatible)
// ignore_for_file: avoid_web_libraries_in_flutter

import 'package:web/web.dart' as web;
import 'dart:js_interop';

@JS('arTracker.initialize')
external web.HTMLCanvasElement _initializeARTracker(web.HTMLVideoElement videoElement, JSString facingMode);

web.HTMLCanvasElement initializeARTracker(web.HTMLVideoElement videoElement, String facingMode) {
  return _initializeARTracker(videoElement, facingMode.toJS);
}

@JS('arTracker.setFilter')
external void _setARFilter(JSString filterName);

void setARFilter(String filterName) {
  _setARFilter(filterName.toJS);
}

@JS('arTracker.stop')
external void stopARTracker();

@JS('arTracker.updateFilterConfig')
external void _updateFilterConfig(JSString filterName, JSNumber scale, JSNumber offsetX, JSNumber offsetY);

void updateARFilterConfig(String filterName, double scale, double offsetX, double offsetY) {
  _updateFilterConfig(filterName.toJS, scale.toJS, offsetX.toJS, offsetY.toJS);
}

@JS('applyColorMatrix')
external void _applyColorMatrixJS(JSArray<JSNumber> matrix, JSNumber blurRadius);

void applyColorMatrixJS(List<double> matrix, double blurRadius) {
  final jsMatrix = matrix.map((e) => e.toJS).toList().toJS;
  _applyColorMatrixJS(jsMatrix, blurRadius.toJS);
}

@JS('arTracker.setBeautyIntensity')
external void _setBeautyIntensity(JSNumber intensity);

void applyBeautyFilterJS(double intensity) {
  _setBeautyIntensity(intensity.toJS);
}
