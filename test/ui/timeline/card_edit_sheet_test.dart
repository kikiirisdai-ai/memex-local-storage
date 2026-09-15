import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/core/input_sheet_metrics.dart';
import 'package:memex/ui/timeline/widgets/card_edit_sheet.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures what the sheet pops so tests can assert on the edits.
class _SheetHost extends StatefulWidget {
  const _SheetHost({
    super.key,
    required this.title,
    required this.bodyFields,
  });

  final String title;
  final List<CardBodyField> bodyFields;

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  CardTextEdits? result;
  bool closed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ElevatedButton(
        onPressed: () async {
          result = await showModalBottomSheet<CardTextEdits>(
            context: context,
            // Mirrors the detail screen, which needs this so the sheet can
            // grow with the keyboard.
            isScrollControlled: true,
            builder: (_) => CardEditSheet(
              initialTitle: widget.title,
              bodyFields: widget.bodyFields,
            ),
          );
          closed = true;
        },
        child: const Text('open'),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
  });

  Future<_SheetHostState> openSheet(
    WidgetTester tester, {
    required String title,
    List<CardBodyField> bodyFields = const [],
  }) async {
    final key = GlobalKey<_SheetHostState>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _SheetHost(key: key, title: title, bodyFields: bodyFields),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  group('editableBodyFields', () {
    test('picks the prose field out of each supported config', () {
      final fields = editableBodyFields(const [
        UiConfig(templateId: 'snapshot', data: {'caption': 'a photo'}),
        UiConfig(templateId: 'snippet', data: {'text': 'some prose'}),
        UiConfig(templateId: 'metric', data: {'title': 'structured'}),
      ]);

      expect(fields.length, 2);
      expect(fields[0].configIndex, 0);
      expect(fields[0].dataKey, 'caption');
      expect(fields[0].text, 'a photo');
      expect(fields[1].configIndex, 1);
      expect(fields[1].dataKey, 'text');
      expect(fields[1].text, 'some prose');
    });

    test('treats a missing prose value as empty text', () {
      final fields = editableBodyFields(const [
        UiConfig(templateId: 'snippet', data: {}),
      ]);

      expect(fields.single.text, '');
    });

    test('skips legacy_html, which the renderer substitutes for user HTML '
        'templates and whose payload is not prose', () {
      expect(
        editableBodyFields(const [
          UiConfig(templateId: 'legacy_html', data: {'html': '<p>hi</p>'}),
          UiConfig(templateId: 'snippet', data: {'text': 'prose'}),
        ]),
        hasLength(1),
      );
    });

    test('returns nothing when no config has editable prose', () {
      expect(
        editableBodyFields(const [
          UiConfig(templateId: 'insight_summary', data: {'x': 1}),
        ]),
        isEmpty,
      );
    });
  });

  testWidgets('prefills the current title and body', (tester) async {
    await openSheet(
      tester,
      title: 'AI guessed this',
      bodyFields: const [
        CardBodyField(configIndex: 0, dataKey: 'text', text: 'wrong wording'),
      ],
    );

    expect(find.text('AI guessed this'), findsOneWidget);
    expect(find.text('wrong wording'), findsOneWidget);
  });

  testWidgets('reports only the body when the title was left alone', (
    tester,
  ) async {
    final host = await openSheet(
      tester,
      title: 'keep me',
      bodyFields: const [
        CardBodyField(configIndex: 2, dataKey: 'text', text: 'old body'),
      ],
    );

    await tester.enterText(
      find.byKey(const ValueKey('card_edit_body_0')),
      'fixed body',
    );
    await tester.tap(find.byKey(const ValueKey('card_edit_save')));
    await tester.pumpAndSettle();

    expect(host.result, isNotNull);
    expect(host.result!.title, isNull);
    // Keyed by ui_configs index, not by position in the sheet.
    expect(host.result!.bodies, {2: 'fixed body'});
  });

  testWidgets('reports an edited title', (tester) async {
    final host = await openSheet(tester, title: 'wrong word');

    await tester.enterText(
      find.byKey(const ValueKey('card_edit_title')),
      'right word',
    );
    await tester.tap(find.byKey(const ValueKey('card_edit_save')));
    await tester.pumpAndSettle();

    expect(host.result!.title, 'right word');
    expect(host.result!.bodies, isEmpty);
  });

  testWidgets('saving an untouched sheet reports no edits at all', (
    tester,
  ) async {
    final host = await openSheet(
      tester,
      title: 'unchanged',
      bodyFields: const [
        CardBodyField(configIndex: 0, dataKey: 'text', text: 'same'),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('card_edit_save')));
    await tester.pumpAndSettle();

    expect(host.result!.isEmpty, isTrue);
  });

  testWidgets('clearing the title reports an empty string, not null', (
    tester,
  ) async {
    final host = await openSheet(tester, title: 'delete this title');

    await tester.enterText(find.byKey(const ValueKey('card_edit_title')), '');
    await tester.tap(find.byKey(const ValueKey('card_edit_save')));
    await tester.pumpAndSettle();

    expect(host.result!.title, '');
  });

  testWidgets('leaves a gap at the top of the screen so the save button is '
      'never tucked under the status bar', (tester) async {
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    await openSheet(
      tester,
      title: 'a title',
      bodyFields: [
        CardBodyField(
          configIndex: 0,
          dataKey: 'text',
          // Long enough that an unconstrained sheet would fill the screen.
          text: List.filled(80, 'a long line of body text').join('\n'),
        ),
      ],
    );

    final sheetHeight = tester.getSize(find.byType(CardEditSheet)).height;
    expect(
      sheetHeight,
      lessThanOrEqualTo(screen.height * kTallInputSheetMaxHeightFraction + 1),
    );
    // The cap must actually bite: an unconstrained sheet would fill the screen.
    expect(sheetHeight, lessThan(screen.height));

    final saveTop = tester.getTopLeft(
      find.byKey(const ValueKey('card_edit_save')),
    );
    expect(saveTop.dy, greaterThan(0));
  });

  testWidgets('cancelling discards typed text', (tester) async {
    final host = await openSheet(tester, title: 'unchanged');

    await tester.enterText(
      find.byKey(const ValueKey('card_edit_title')),
      'typed but abandoned',
    );
    await tester.tap(find.text(UserStorage.l10n.cancel));
    await tester.pumpAndSettle();

    expect(host.closed, isTrue);
    expect(host.result, isNull);
  });
}
