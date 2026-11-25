import 'dart:async';
import 'dart:js_interop';

@JS('startRecording')
external JSPromise<JSBoolean> _startRecording();

@JS('getLastRecordingError')
external JSString? _getLastRecordingError();

@JS('stopRecording')
external JSPromise<JSString?> _stopRecording();

@JS('playAudio')
external void _playAudio(JSString url);

@JS('pauseAudio')
external void _pauseAudio();

@JS('open')
external void _open(JSString url);

Future<bool> startJsRecording() async {
  try {
    final jsBool = await _startRecording().toDart;
    return jsBool.toDart;
  } catch (e) {
    print('Web JS helper startRecording error: $e');
    return false;
  }
}

String? getJsRecordingError() {
  try {
    final err = _getLastRecordingError();
    if (err != null && err.toDart.isNotEmpty) {
      return err.toDart;
    }
  } catch (_) {}
  return null;
}

Future<String?> stopJsRecording() async {
  try {
    final jsStr = await _stopRecording().toDart;
    return jsStr?.toDart;
  } catch (e) {
    print('Web JS helper stopRecording error: $e');
    return null;
  }
}

void playJsAudio(String url) {
  try {
    _playAudio(url.toJS);
  } catch (e) {
    print('Web JS helper playAudio error: $e');
  }
}

void pauseJsAudio() {
  try {
    _pauseAudio();
  } catch (e) {
    print('Web JS helper pauseAudio error: $e');
  }
}

void openJsUrl(String url) {
  try {
    _open(url.toJS);
  } catch (e) {
    print('Web JS helper open error: $e');
  }
}
