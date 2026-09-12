import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:memex/domain/models/tag_model.dart';
import 'package:memex/utils/icon_map.dart';

/// Adaptive icon widget that supports SVG and Emoji
class AdaptiveIcon extends StatelessWidget {
  final String? icon;
  final TagIconType? iconType;
  final double size;
  final Color color;

  const AdaptiveIcon({
    super.key,
    required this.icon,
    this.iconType,
    this.size = 12,
    this.color = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    if (icon == null || iconType == null) {
      return const SizedBox.shrink();
    }

    switch (iconType!) {
      case TagIconType.svg:
        return _buildSvgIcon(icon!);
      case TagIconType.emoji:
        return _buildEmojiIcon(icon!);
      case TagIconType.flutter_icon:
        return _buildFlutterIcon(icon!);
    }
  }

  Widget _buildSvgIcon(String svgUrl) {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.network(
        svgUrl,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        placeholderBuilder: (context) => SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiIcon(String emoji) {
    return Text(
      emoji,
      style: TextStyle(
        fontSize: size,
        color: color,
      ),
    );
  }

  Widget _buildFlutterIcon(String iconName) {
    var iconData = IconMap.getIcon(iconName);
    if (iconData == null && iconName.startsWith('Icons.')) {
      iconName = iconName.substring(6);
      iconData = IconMap.getIcon(iconName);
    }
    // If not found, use a neutral icon (category_outlined)
    return Icon(
      iconData ?? Icons.widgets_rounded,
      size: size,
      color: color,
    );
  }
}
