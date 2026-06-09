@JS()
library ar_interop;

import 'dart:html' as html;
import 'package:js/js.dart';

@JS('window.arTracker.initialize')
external html.CanvasElement initializeARTracker(html.VideoElement videoElement);

@JS('window.arTracker.setFilter')
external void setARFilter(String filterName);

@JS('window.arTracker.stop')
external void stopARTracker();
