import 'package:flutter/material.dart';

class AvatarHelper {
  /// Extract the most likely profile image URL from a data map.
  /// Prioritizes various field names used across the app.
  static String? getAvatarUrl(Map<String, dynamic>? data) {
    if (data == null) return null;

    final fields = [
      'profileImageUrl',
      'photoUrl',
      'photoURL',
      'avatarUrl',
      'avatarURL',
      'image_url',
      'authorProfileImageUrl',
      'authorAvatar',
      'userAvatar',
    ];

    for (final field in fields) {
      final value = data[field];
      if (value is String && _isValidUrl(value)) {
        return value;
      }
    }

    return null;
  }

  static bool _isValidUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final clean = url.trim().toLowerCase();
    if (clean == 'null' || clean == 'undefined') return false;
    return clean.startsWith('http') || clean.startsWith('https') || clean.startsWith('www.');
  }

  /// Get a consistent color for a name to use as a background for initials.
  static Color getNameColor(String? name) {
    if (name == null || name.isEmpty) return const Color(0xFF94A3B8);

    final List<Color> colors = [
      const Color(0xFF1F1F1F), // Darkest Grey
      const Color(0xFF2D2D2D), 
      const Color(0xFF3C3C3C),
      const Color(0xFF4B4B4B),
      const Color(0xFF5A5A5A),
      const Color(0xFF696969),
      const Color(0xFF787878),
      const Color(0xFF878787),
      const Color(0xFF969696),
      const Color(0xFFA5A5A5), // Lightest for these purposes
    ];

    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }

    return colors[hash.abs() % colors.length];
  }

  static ImageProvider getAvatarProvider(String? url, String? name) {
    if (url != null && _isValidUrl(url)) {
      return NetworkImage(url);
    }
    // Fallback if URL is invalid - using a stable PNG format to avoid decoding issues
    final encodedName = Uri.encodeComponent(name ?? 'User');
    return NetworkImage('https://ui-avatars.com/api/?name=$encodedName&background=random&color=fff&size=256&format=png');
  }
}
