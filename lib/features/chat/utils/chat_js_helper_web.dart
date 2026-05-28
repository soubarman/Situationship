import 'dart:async';
import 'dart:js' as js;
import 'dart:js_util' as js_util;

Future<bool> startJsRecording() async {
  try {
    final promise = js.context.callMethod('startRecording');
    final success = await js_util.promiseToFuture<dynamic>(promise);
    return success == true;
  } catch (e) {
    print('Web JS helper startRecording error: $e');
    return false;
  }
}

Future<String?> stopJsRecording() async {
  try {
    final promise = js.context.callMethod('stopRecording');
    final url = await js_util.promiseToFuture<dynamic>(promise) as String?;
    return url;
  } catch (e) {
    print('Web JS helper stopRecording error: $e');
    return null;
  }
}

void playJsAudio(String url) {
  try {
    js.context.callMethod('playAudio', [url]);
  } catch (e) {
    print('Web JS helper playAudio error: $e');
  }
}

void pauseJsAudio() {
  try {
    js.context.callMethod('pauseAudio');
  } catch (e) {
    print('Web JS helper pauseAudio error: $e');
  }
}

void openJsUrl(String url) {
  try {
    js.context.callMethod('open', [url]);
  } catch (e) {
    print('Web JS helper open error: $e');
  }
}
