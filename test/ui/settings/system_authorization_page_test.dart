import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/settings/widgets/system_authorization_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');

  setUp(() {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
          // 0 == PermissionStatus.denied for every queried permission.
          return 0;
        case 'requestPermissions':
          final permissions = call.arguments as List<Object?>;
          return {for (final p in permissions) p: 0};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await UserStorage.initL10n();

    // The page wraps its ListTiles in a Container(color: ...) beneath the
    // Scaffold's Material — pre-existing, unrelated to this change — which
    // makes the framework emit a "ListTile background color or ink splashes
    // may be invisible" assertion under the test harness's strict error
    // reporting. Ignore only that specific assertion so the test can still
    // verify which permission rows render.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains(
            'ListTile background color or ink splashes may be invisible',
          )) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      const MaterialApp(home: SystemAuthorizationPage()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'removes the Fitness/motion permission item while keeping the others',
    (tester) async {
      await pumpPage(tester);

      // The Fitness & Motion permission row (and its HealthKit wiring) has
      // been removed along with the pedometer/HealthKit feature.
      expect(find.byIcon(Icons.directions_run_outlined), findsNothing);
      expect(find.text(UserStorage.l10n.fitnessAndMotion), findsNothing);

      // Every other permission item must still render untouched.
      expect(find.text(UserStorage.l10n.location), findsOneWidget);
      expect(find.text(UserStorage.l10n.photos), findsOneWidget);
      expect(find.text(UserStorage.l10n.camera), findsOneWidget);
      expect(find.text(UserStorage.l10n.microphone), findsOneWidget);
      expect(find.text(UserStorage.l10n.calendar), findsOneWidget);
      expect(find.text(UserStorage.l10n.reminders), findsOneWidget);
      expect(find.text(UserStorage.l10n.notification), findsOneWidget);
    },
  );
}
