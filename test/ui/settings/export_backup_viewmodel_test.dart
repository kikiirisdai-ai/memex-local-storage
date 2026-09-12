import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/settings/view_models/export_backup_viewmodel.dart';

void main() {
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return ctx;
  }

  testWidgets(
    'export success calls create, share, record and updates lastExportAt',
    (tester) async {
      final context = await pumpContext(tester);
      String? createdPath;
      String? sharedPath;
      DateTime? recordedAt;
      final fixedNow = DateTime(2026, 9, 5, 12, 0, 0);

      final vm = ExportBackupViewModel.forTesting(
        createFn: () async {
          createdPath = '/tmp/memex_backup_test.memex';
          return createdPath!;
        },
        shareFn: (path) async {
          sharedPath = path;
        },
        recordFn: (when) async {
          recordedAt = when;
        },
        now: () => fixedNow,
      );

      await vm.export(context);

      expect(sharedPath, createdPath);
      expect(recordedAt, fixedNow);
      expect(vm.lastExportAt, fixedNow);
      expect(vm.generating, isFalse);
      expect(vm.error, isNull);
    },
  );

  testWidgets(
    'createFn throws sets error and does not share or record',
    (tester) async {
      final context = await pumpContext(tester);
      bool shared = false;
      bool recorded = false;

      final vm = ExportBackupViewModel.forTesting(
        createFn: () async => throw Exception('boom'),
        shareFn: (path) async {
          shared = true;
        },
        recordFn: (when) async {
          recorded = true;
        },
      );

      await vm.export(context);

      expect(vm.error, isNotNull);
      expect(shared, isFalse);
      expect(recorded, isFalse);
      expect(vm.generating, isFalse);
      expect(vm.lastExportAt, isNull);
    },
  );

  testWidgets(
    'shareFn throws sets error and does not record (record only after successful share)',
    (tester) async {
      final context = await pumpContext(tester);
      bool recorded = false;

      final vm = ExportBackupViewModel.forTesting(
        createFn: () async => '/tmp/x.memex',
        shareFn: (path) async => throw Exception('share failed'),
        recordFn: (when) async {
          recorded = true;
        },
      );

      await vm.export(context);

      expect(vm.error, isNotNull);
      expect(recorded, isFalse);
      expect(vm.generating, isFalse);
      expect(vm.lastExportAt, isNull);
    },
  );

  testWidgets(
    're-entrant export calls while generating are ignored',
    (tester) async {
      final context = await pumpContext(tester);
      int createCalls = 0;
      final completer = Completer<String>();

      final vm = ExportBackupViewModel.forTesting(
        createFn: () async {
          createCalls++;
          return completer.future;
        },
        shareFn: (path) async {},
        recordFn: (when) async {},
      );

      final first = vm.export(context);
      expect(vm.generating, isTrue);
      final second = vm.export(context);
      completer.complete('/tmp/x.memex');
      await first;
      await second;

      expect(createCalls, 1);
      expect(vm.generating, isFalse);
    },
  );
}
