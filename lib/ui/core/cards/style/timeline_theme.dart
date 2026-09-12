import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/design_system.dart';

/// Legacy theme for Timeline Cards — delegates to the centralized design system.
/// New code should import `design_system.dart` directly.
class TimelineTheme {
  const TimelineTheme._();

  static const colors = _Colors();
  static const typography = _Typography();
  static const shadows = _Shadows();
}

class _Colors {
  const _Colors();

  Color get primary => AppColors.primary;
  Color get success => AppColors.success;
  Color get warning => AppColors.warning;
  Color get danger => AppColors.danger;
  Color get textPrimary => AppColors.textPrimary;
  Color get textSecondary => AppColors.textSecondary;
  Color get textTertiary => AppColors.textTertiary;
  Color get background => AppColors.background;
  Color get backgroundSecondary => AppColors.background;
  Color get cardBackground => AppColors.cardBackground;
  Color get glassBorder => Colors.white;
}

class _Typography {
  const _Typography();

  TextStyle get title => AppTextStyles.cardListTitle;
  TextStyle get body => const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
      );
  TextStyle get small => const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.4,
      );
  TextStyle get label => AppTextStyles.timestampHeader;
  TextStyle get data => const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        height: 1.0,
        letterSpacing: -1.0,
      );
}

class _Shadows {
  const _Shadows();

  BoxShadow get card => AppShadows.card;
  BoxShadow get float => AppShadows.floating;
}
