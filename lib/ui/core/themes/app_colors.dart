import 'package:flutter/material.dart';

/// Centralized color constants from the Figma design system.
/// All UI code should reference these instead of hardcoding hex values.
class AppColors {
  const AppColors._();

  // Brand
  static const Color primary = Color(0xFF5B6CFF);

  // Backgrounds
  static const Color background = Color(0xFFF7F8FA);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color iconBgLight = Color(0xFFF2F4FF);

  // Text
  static const Color textPrimary = Color(0xFF0A0A0A);
  static const Color textSecondary = Color(0xFF4A5565);
  static const Color textTertiary = Color(0xFF99A1AF);

  // Navigation
  static const Color tabActive = Color(0xFF1F1F1F);
  static const Color tabInactive = Color(0xFF888888);
  static const Color tagActiveBg = Color(0xFF1A1A1A);

  // Semantic
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFF43F5E);

  // Shadows (as Color values — use with BoxShadow)
  static const Color shadowLight = Color(0x0D000000); // 5% black
  static const Color shadowCard = Color(0x0D111827); // card shadow

  // Avatar gradient
  static const List<Color> avatarGradient = [
    Color(0xFF5B6CFF),
    Color(0xFF5E6FFF),
    Color(0xFF6172FF),
    Color(0xFF6375FF),
    Color(0xFF6677FF),
    Color(0xFF697AFF),
    Color(0xFF6C7DFF),
    Color(0xFF6F80FF),
    Color(0xFF7282FF),
    Color(0xFF7585FF),
    Color(0xFF7887FF),
    Color(0xFF7B8AFF),
  ];

  static const List<double> avatarGradientStops = [
    0.0,
    0.0909,
    0.1818,
    0.2727,
    0.3636,
    0.4545,
    0.5455,
    0.6364,
    0.7273,
    0.8182,
    0.9091,
    1.0,
  ];
}
