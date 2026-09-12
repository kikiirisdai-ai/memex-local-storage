import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/external_backup_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.memexlab.memex/backup_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('pickICloudFolder maps result', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'icloudPickFolder');
      return {'path': '/iCloud/x', 'displayName': 'x'};
    });
    final f = await ExternalBackupChannel(channel: channel).pickICloudFolder();
    expect(f!.path, '/iCloud/x');
    expect(f.displayName, 'x');
  });

  test('pickICloudFolder returns null on cancelled', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'cancelled');
    });
    expect(await ExternalBackupChannel(channel: channel).pickICloudFolder(),
        isNull);
  });

  test('writeFile passes args and returns path', () async {
    late MethodCall seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return {'path': '/iCloud/x/memex_daily.memex', 'isStale': false};
    });
    final p = await ExternalBackupChannel(channel: channel)
        .writeFile(sourcePath: '/tmp/a.memex', fileName: 'memex_daily.memex');
    expect(seen.arguments['fileName'], 'memex_daily.memex');
    expect(p, '/iCloud/x/memex_daily.memex');
  });

  test('readFileToTemp passes fileName and returns temp path', () async {
    late MethodCall seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return {'path': '/tmp/icloud_read_abc/memex_daily.memex'};
    });
    final p = await ExternalBackupChannel(channel: channel)
        .readFileToTemp('memex_daily.memex');
    expect(seen.method, 'icloudReadFileToTemp');
    expect(seen.arguments['fileName'], 'memex_daily.memex');
    expect(p, '/tmp/icloud_read_abc/memex_daily.memex');
  });

  test('listFiles maps entries', () async {
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
              'files': [
                {
                  'name': 'memex_daily.memex',
                  'path': '/i/d.memex',
                  'sizeBytes': 10,
                  'modifiedMs': 1000
                },
              ]
            });
    final files = await ExternalBackupChannel(channel: channel).listFiles();
    expect(files.single.name, 'memex_daily.memex');
    expect(files.single.sizeBytes, 10);
  });

  test('uploadStatus maps entries with correct booleans and defaults',
      () async {
    messenger.setMockMethodCallHandler(
        channel,
        (call) async {
          expect(call.method, 'icloudUploadStatus');
          return {
            'files': [
              {
                'name': 'memex_daily.memex',
                'uploaded': true,
                'uploading': false,
                'hasError': false
              },
              {
                'name': 'memex_daily_prev.memex',
                'uploaded': false,
                'uploading': true,
                'hasError': false
              },
            ]
          };
        });
    final statuses =
        await ExternalBackupChannel(channel: channel).uploadStatus();
    expect(statuses, hasLength(2));
    expect(statuses[0].name, 'memex_daily.memex');
    expect(statuses[0].uploaded, isTrue);
    expect(statuses[0].uploading, isFalse);
    expect(statuses[0].hasError, isFalse);
    expect(statuses[1].name, 'memex_daily_prev.memex');
    expect(statuses[1].uploaded, isFalse);
    expect(statuses[1].uploading, isTrue);
    expect(statuses[1].hasError, isFalse);
  });

  test('uploadStatus defaults missing keys to false', () async {
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
              'files': [
                {'name': 'memex_daily.memex'},
              ]
            });
    final statuses =
        await ExternalBackupChannel(channel: channel).uploadStatus();
    expect(statuses.single.name, 'memex_daily.memex');
    expect(statuses.single.uploaded, isFalse);
    expect(statuses.single.uploading, isFalse);
    expect(statuses.single.hasError, isFalse);
  });

  test('uploadStatus returns empty list on channel error', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'no_bookmark');
    });
    expect(await ExternalBackupChannel(channel: channel).uploadStatus(),
        isEmpty);
  });
}
