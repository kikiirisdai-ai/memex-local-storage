import 'package:flutter/material.dart';

/// Cap on how tall a keyboard-driven input sheet may grow, as a fraction of
/// screen height.
///
/// Without a cap, a sheet holding an unbounded text field grows until it fills
/// the screen once the keyboard pushes it up, leaving its header — and the
/// save/confirm button in that header — tucked under the status bar.
const double kInputSheetMaxHeightFraction = 0.85;

/// Cap for sheets built around an unbounded multi-line field, where the user
/// wants as much of the text visible as possible. Taller than
/// [kInputSheetMaxHeightFraction], so it trades top margin for visible lines.
const double kTallInputSheetMaxHeightFraction = 0.92;

/// Constraints for a keyboard-driven input sheet. Apply to any bottom sheet
/// whose height follows the text the user types.
BoxConstraints inputSheetConstraints(
  BuildContext context, {
  double fraction = kInputSheetMaxHeightFraction,
}) =>
    BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * fraction,
    );
