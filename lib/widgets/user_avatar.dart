import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/avatar_helper.dart';
import '../theme/app_theme.dart';

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
  
  /// For Story Rings (Instagram Style)
  final bool hasStory;
  final bool isStorySeen;

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
    this.hasStory = false,
    this.isStorySeen = false,
  });

  @override
  Widget build(BuildContext context) {
    // Normalize image URL
    String? cleanUrl = imageUrl;
    if (cleanUrl != null) {
      cleanUrl = cleanUrl.trim();
      if (cleanUrl.toLowerCase() == 'null' || cleanUrl.isEmpty) {
        cleanUrl = null;
      } else if (cleanUrl.startsWith('www.')) {
        cleanUrl = 'https://$cleanUrl';
      }
    }

    final hasImage =
        cleanUrl != null &&
        (cleanUrl.startsWith('http') || cleanUrl.startsWith('https'));
    
    final initials = (name != null && name!.isNotEmpty)
        ? name!.trim()[0].toUpperCase()
        : '?';

    // 1. Create the base avatar content
    Widget avatarContent = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? AvatarHelper.getNameColor(name).withOpacity(0.15),
        border: border,
        gradient: gradient,
      ),
      child: hasImage
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: cleanUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                placeholder: (context, url) => _PulseSkeleton(radius: radius),
                errorWidget: (context, url, error) => _buildInitials(initials),
                cacheKey: cleanUrl,
              ),
            )
          : _buildInitials(initials),
    );

    // 2. Add Story Ring if needed
    if (hasStory) {
      avatarContent = _buildStoryRing(context, avatarContent);
    }

    // 3. Final Stack with online status
    return Stack(
      children: [
        avatarContent,
        if (showOnlineStatus)
          Positioned(
            right: radius * 0.05,
            bottom: radius * 0.05,
            child: Container(
              width: radius * 0.45,
              height: radius * 0.45,
              decoration: BoxDecoration(
                color: Colors.white, // Monochrome Online Status
                shape: BoxShape.circle,
                border: Border.all(color: context.isDark ? Colors.black : Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInitials(String initials) {
    final bgColor = AvatarHelper.getNameColor(name);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor.withOpacity(0.1),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: textColor ?? bgColor,
            fontWeight: FontWeight.bold,
            fontSize: fontSize ?? radius * 0.9,
          ),
        ),
      ),
    );
  }

  Widget _buildStoryRing(BuildContext context, Widget child) {
    final ringWidth = radius * 0.12;
    final padding = radius * 0.08;

    return Container(
      padding: EdgeInsets.all(padding + ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isStorySeen
            ? LinearGradient(colors: [context.textLow, context.textLow.withOpacity(0.5)])
            : const LinearGradient(
                colors: [
                  Color(0xFF833AB4), // Purple
                  Color(0xFFFD1D1D), // Red
                  Color(0xFFFCAF45), // Orange
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: context.bg,
          shape: BoxShape.circle,
        ),
        child: child,
      ),
    );
  }
}

class _PulseSkeleton extends StatefulWidget {
  final double radius;
  const _PulseSkeleton({required this.radius});

  @override
  State<_PulseSkeleton> createState() => _PulseSkeletonState();
}

class _PulseSkeletonState extends State<_PulseSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.1, end: 0.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.radius * 2,
          height: widget.radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.textLow.withOpacity(_animation.value),
          ),
        );
      },
    );
  }
}
