import 'package:flutter/material.dart';

class SkeletonLine extends StatelessWidget {
  final SkeletonLineStyle style;
  const SkeletonLine({super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: style.width,
      height: style.height,
      margin: style.margin,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: style.borderRadius is BorderRadius
            ? style.borderRadius
            : BorderRadius.circular(style.borderRadius?.toDouble() ?? 4),
      ),
    );
  }
}

class SkeletonLineStyle {
  final double? width;
  final double? height;
  final dynamic borderRadius;
  final EdgeInsetsGeometry? margin;
  const SkeletonLineStyle({
    this.width,
    this.height,
    this.borderRadius,
    this.margin,
  });
}

class SkeletonAvatar extends StatelessWidget {
  final SkeletonAvatarStyle style;
  const SkeletonAvatar({super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: style.width,
      height: style.height,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        shape: style.shape ?? BoxShape.rectangle,
        borderRadius: style.shape == BoxShape.circle
            ? null
            : (style.borderRadius is BorderRadius
                  ? style.borderRadius
                  : BorderRadius.circular(style.borderRadius?.toDouble() ?? 8)),
      ),
    );
  }
}

class SkeletonAvatarStyle {
  final double? width;
  final double? height;
  final BoxShape? shape;
  final dynamic borderRadius;
  const SkeletonAvatarStyle({
    this.width,
    this.height,
    this.shape,
    this.borderRadius,
  });
}

class SkeletonListView extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int)? itemBuilder;
  final EdgeInsetsGeometry? padding;
  final double? spacing;
  const SkeletonListView({
    super.key,
    required this.itemCount,
    this.itemBuilder,
    this.padding,
    this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      shrinkWrap: true,
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder:
          itemBuilder ??
          (context, index) {
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: spacing ?? 8,
              ),
              child: Row(
                children: [
                  const SkeletonAvatar(
                    style: SkeletonAvatarStyle(
                      width: 40,
                      height: 40,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonLine(
                          style: SkeletonLineStyle(
                            width: double.infinity,
                            height: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SkeletonLine(
                          style: SkeletonLineStyle(
                            width: MediaQuery.of(context).size.width * 0.4,
                            height: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
    );
  }
}
