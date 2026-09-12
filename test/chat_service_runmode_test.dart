import 'package:test/test.dart';
import 'package:memex/data/services/chat_service.dart';

void main() {
  test('agent runMode skips quick capture', () {
    expect(shouldSkipQuickCapture('agent'), isTrue);
    expect(shouldSkipQuickCapture('auto'), isFalse);
    expect(shouldSkipQuickCapture('card'), isFalse);
  });
  test('card runMode forces card', () {
    expect(shouldForceCard('card'), isTrue);
    expect(shouldForceCard('auto'), isFalse);
  });
}
