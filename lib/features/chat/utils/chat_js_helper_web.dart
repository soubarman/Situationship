// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:js_util' as js_util;

Future<bool> startJsRecording() async {
  try {
    final promise = js_util.callMethod<dynamic>(js_util.globalThis, 'startRecording', []);
    final success = await js_util.promiseToFuture<dynamic>(promise);
    return success == true;
  } catch (e) {
    print('Web JS helper startRecording error: $e');
    return false;
  }
}

String? getJsRecordingError() {
  try {
    final err = js_util.callMethod<dynamic>(js_util.globalThis, 'getLastRecordingError', []);
    if (err != null && err.toString().isNotEmpty) {
      return err.toString();
    }
  } catch (_) {}
  return null;
}

Future<String?> stopJsRecording() async {
  try {
    final promise = js_util.callMethod<dynamic>(js_util.globalThis, 'stopRecording', []);
    final result = await js_util.promiseToFuture<dynamic>(promise);
    return result?.toString();
  } catch (e) {
    print('Web JS helper stopRecording error: $e');
    return null;
  }
}

void playJsAudio(String url) {
  try {
    js_util.callMethod<dynamic>(js_util.globalThis, 'playAudio', [url]);
  } catch (e) {
    print('Web JS helper playAudio error: $e');
  }
}

void pauseJsAudio() {
  try {
    js_util.callMethod<dynamic>(js_util.globalThis, 'pauseAudio', []);
  } catch (e) {
    print('Web JS helper pauseAudio error: $e');
  }
}

void openJsUrl(String url) {
  try {
    js_util.callMethod<dynamic>(js_util.globalThis, 'open', [url]);
  } catch (e) {
    print('Web JS helper open error: $e');
  }
}
