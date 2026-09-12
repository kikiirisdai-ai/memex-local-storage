import 'package:flutter/material.dart';

/// Centralized shadow definitions from the Figma design system.
class AppShadows {
  const AppShadows._();

  /// Standard card shadow: subtle elevation
  static const BoxShadow card = BoxShadow(
    color: Color(0x0D000000), // 5% black
    blurRadius: 16,
    offset: Offset(0, 2),
  );

  /// Snapshot/event card shadow
  static const BoxShadow cardAccent = BoxShadow(
    color: Color(0x0D111827), // #1118270D
    blurRadius: 24,
  );

  /// Event card shadow
  static const BoxShadow eventCard = BoxShadow(
    color: Color(0x08111827), // #11182708
    blurRadius: 18,
  );

  /// Back button shadow
  static const BoxShadow backButton = BoxShadow(
    color: Color(0x0A000000), // 4% black
    blurRadius: 9,
  );

  /// Floating element shadow
  static const BoxShadow floating = BoxShadow(
    color: Color(0x14000000), // 8% black
    blurRadius: 24,
    offset: Offset(0, 6),
  );
}
