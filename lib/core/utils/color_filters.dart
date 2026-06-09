import 'package:flutter/material.dart';

class AppColorFilters {
  static const List<double> normal = [
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static const List<double> clarendon = [
    1.27, 0, 0, 0, -25.4,
    0, 1.27, 0, 0, -25.4,
    0, 0, 1.27, 0, -25.4,
    0, 0, 0, 1, 0,
  ];

  static const List<double> gingham = [
    1.1, 0, 0, 0, 0,
    0, 1.1, 0, 0, 0,
    0, 0, 1.1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static const List<double> moon = [
    0.333, 0.333, 0.333, 0, 0,
    0.333, 0.333, 0.333, 0, 0,
    0.333, 0.333, 0.333, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static const List<double> lark = [
    1.1, 0, 0, 0, 0,
    0, 1.2, 0, 0, 0,
    0, 0, 1.1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static List<double> getFilterMatrix(String name) {
    switch (name) {
      case 'Clarendon':
        return clarendon;
      case 'Gingham':
        return gingham;
      case 'Moon':
        return moon;
      case 'Lark':
        return lark;
      case 'Normal':
      default:
        return normal;
    }
  }
}
