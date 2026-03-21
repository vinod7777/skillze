import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? name;
  final double radius;
  final double? fontSize;
  final Color? backgroundColor;
  final Color? textColor;
  final BoxBorder? border;
  final Gradient? gradient;
  final bool showOnlineStatus;

  const UserAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.radius = 24,
    this.fontSize,
    this.backgroundColor,
    this.textColor,
    this.border,
    this.gradient,
    this.showOnlineStatus = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage =
        imageUrl != null &&
        imageUrl is String &&
        imageUrl!.trim().isNotEmpty &&
        imageUrl!.toLowerCase() != 'null' &&
        (imageUrl!.startsWith('http') || imageUrl!.startsWith('https') || imageUrl!.startsWith('www.'));
    
    final initials = (name != null && name!.isNotEmpty)
        ? name!.trim()[0].toUpperCase()
        : '?';

    return Stack(
      children: [
        Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: backgroundColor ?? const Color(0xFFE5E7EB),
            border: border,
            gradient: gradient,
          ),
          child: hasImage
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl!.startsWith('www.') ? 'https://${imageUrl!}' : imageUrl!,
                    width: radius * 2,
                    height: radius * 2,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: const Color(0xFF0F2F6A).withValues(alpha: 0.3),
                      ),
                    ),
                    errorWidget: (context, url, error) => _buildInitials(initials),
                  ),
                )
              : _buildInitials(initials),
        ),
        if (showOnlineStatus)
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: radius * 0.45,
              height: radius * 0.45,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E), // Vibrant Green
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInitials(String initials) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: textColor ?? const Color(0xFF0F2F6A),
          fontWeight: FontWeight.bold,
          fontSize: fontSize ?? radius * 0.8,
        ),
      ),
    );
  }
}
