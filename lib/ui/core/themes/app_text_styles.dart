import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Centralized text styles from the Figma design system.
/// All UI code should reference these instead of inline TextStyle definitions.
class AppTextStyles {
  const AppTextStyles._();

  // ── Brand ──

  static TextStyle brandTitle({Color? color}) => GoogleFonts.bricolageGrotesque(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.41,
        height: 22 / 32,
        color: color ?? AppColors.textPrimary,
      );

  // ── Card Detail ──

  static const TextStyle cardTitle = TextStyle(
    fontFamily: 'PingFang SC',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 33 / 24,
    letterSpacing: -0.45,
    color: AppColors.textPrimary,
  );

  static const TextStyle cardListTitle = TextStyle(
    fontSize: 20, // uses GoogleFonts.inter() at call site
    fontWeight: FontWeight.w600,
    height: 23 / 20,
    letterSpacing: -0.45,
    color: AppColors.textPrimary,
  );

  static const TextStyle tag = TextStyle(
    fontFamily: 'PingFang SC',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 20 / 16,
    letterSpacing: 0,
    color: AppColors.primary,
  );

  // ── Comments ──

  static const TextStyle commentName = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 20 / 16,
    letterSpacing: -0.15,
    color: AppColors.textPrimary,
  );

  static const TextStyle commentContent = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    letterSpacing: 0,
    color: AppColors.textSecondary,
  );

  static const TextStyle commentDate = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    letterSpacing: -0.15,
    color: AppColors.textTertiary,
  );

  // ── Timeline ──

  static const TextStyle timestampHeader = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 20 / 12,
    letterSpacing: -0.15,
    color: AppColors.textTertiary,
  );

  static const TextStyle filterTabLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 20 / 14,
    letterSpacing: -0.15,
  );

  static const TextStyle bottomNavLabel = TextStyle(
    fontSize: 14,
    letterSpacing: 0.14,
    height: 1.0,
  );

  // ── Knowledge ──

  static const TextStyle fileCardTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 20 / 14,
    letterSpacing: -0.15,
    color: AppColors.textPrimary,
  );

  static const TextStyle aiGeneratedLabel = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    height: 20 / 10,
    letterSpacing: -0.15,
    color: AppColors.primary,
  );

  // ── General ──

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.15,
    color: AppColors.textSecondary,
  );
}
