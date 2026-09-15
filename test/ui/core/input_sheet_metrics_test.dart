import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/core/input_sheet_metrics.dart';

void main() {
  testWidgets('caps an input sheet below the full screen height', (
    tester,
  ) async {
    late BoxConstraints constraints;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            constraints = inputSheetConstraints(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final screenHeight =
        (tester.view.physicalSize / tester.view.devicePixelRatio).height;

    expect(constraints.maxHeight, screenHeight * kInputSheetMaxHeightFraction);
    // A sheet must always leave a visible gap at the top of the screen so its
    // header and confirm button stay clear of the status bar.
    expect(constraints.maxHeight, lessThan(screenHeight));
    expect(kInputSheetMaxHeightFraction, lessThan(1.0));
  });
}
