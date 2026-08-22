import 'package:flutter/material.dart';

/// Clean background widget - previously rendered blurred color orbs.
/// Now returns empty widget for crisp, clean normal dark mode.
class BackgroundOrbs extends StatelessWidget {
  const BackgroundOrbs({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
