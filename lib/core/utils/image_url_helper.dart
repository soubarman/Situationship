import 'package:flutter/foundation.dart' show kIsWeb;

class ImageUrlHelper {
  /// Transforms image URLs on Flutter Web to route through our Netlify Edge Function
  /// to add CORS headers and bypass CanvasKit WebGL restrictions.
  static String proxy(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    
    // On native mobile/desktop platforms, CORS does not apply
    if (!kIsWeb) return trimmed;

    // Already a local data/blob URL or already proxied
    if (trimmed.startsWith('data:') ||
        trimmed.startsWith('blob:') ||
        trimmed.contains('/api/image-proxy')) {
      return trimmed;
    }

    // Known services with full native CORS headers and access tokens
    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final host = uri.host.toLowerCase();
      if (host.endsWith('ui-avatars.com') ||
          host.endsWith('googleusercontent.com') ||
          host.endsWith('unsplash.com') ||
          host.endsWith('firebasestorage.googleapis.com') ||
          host.endsWith('storage.googleapis.com')) {
        return trimmed;
      }
    }

    // Determine the proxy endpoint:
    // If running on Netlify, use origin; otherwise use production Netlify proxy URL
    final origin = Uri.base.origin;
    if (origin.isNotEmpty && origin.startsWith('http') && origin.contains('netlify.app')) {
      return '$origin/api/image-proxy?url=${Uri.encodeComponent(trimmed)}';
    } else {
      return 'https://situatioship.netlify.app/api/image-proxy?url=${Uri.encodeComponent(trimmed)}';
    }
  }
}
