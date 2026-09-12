import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Maps common emoji to SVG assets. Falls back to rendering the emoji as text.
class EmojiIcon extends StatelessWidget {
  final String emoji;
  final double size;

  const EmojiIcon({super.key, required this.emoji, this.size = 20});

  static const Map<String, String> _emojiToSvg = {
    '🎨': 'assets/icons/emoji_design.svg',
    '💻': 'assets/icons/emoji_code.svg',
    '📚': 'assets/icons/emoji_reading.svg',
    '🗣️': 'assets/icons/emoji_meeting.svg',
    '🗣': 'assets/icons/emoji_meeting.svg',
  };

  @override
  Widget build(BuildContext context) {
    final svgPath = _emojiToSvg[emoji];
    if (svgPath != null) {
      return SvgPicture.asset(
        svgPath,
        width: size,
        height: size,
      );
    }
    return Text(emoji, style: TextStyle(fontSize: size));
  }
}
