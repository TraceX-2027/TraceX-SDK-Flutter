import 'package:flutter_test/flutter_test.dart';
import 'package:tracex/src/data_scrubber.dart';

void main() {
  group('T2.16: DataScrubber Invariants & Redaction Tests', () {
    test('Redacts Bearer tokens in headers and error strings', () {
      const input = 'Authorization: Bearer secretToken_12345.xyz== occurred';
      final result = DataScrubber.scrubString(input);
      expect(result, equals('Authorization: Bearer [REDACTED] occurred'));
    });

    test('Redacts valid 16-digit credit cards using Luhn algorithm', () {
      // 4111111111111111 is a valid test Visa card passing Luhn
      const input = 'Transaction failed for card 4111111111111111';
      final result = DataScrubber.scrubString(input);
      expect(result, equals('Transaction failed for card [CARD_REDACTED]'));

      // Non-Luhn number is NOT redacted
      const invalidCard = 'Order reference 1234567890123456';
      expect(DataScrubber.scrubString(invalidCard), equals(invalidCard));
    });

    test('Redacts sensitive dictionary keys in breadcrumbs data', () {
      final input = {
        'password': 'superSecretPassword',
        'api_key': 'tracex-live-key',
        'auth_token': 'Bearer 12345',
        'public_info': 'user_name_123',
      };

      final scrubbed = DataScrubber.scrubMap(input);
      expect(scrubbed['password'], equals('[REDACTED]'));
      expect(scrubbed['api_key'], equals('[REDACTED]'));
      expect(scrubbed['auth_token'], equals('[REDACTED]'));
      expect(scrubbed['public_info'], equals('user_name_123'));
    });

    test('Redacts local file system user directory paths', () {
      const windowsPath =
          r'Crash at C:\Users\JohnDoe\AppData\Local\Temp\file.dart';
      expect(
        DataScrubber.scrubString(windowsPath),
        equals(r'Crash at [PATH_REDACTED]\AppData\Local\Temp\file.dart'),
      );

      const unixPath = 'Crash at /home/johndoe/project/lib/main.dart';
      expect(
        DataScrubber.scrubString(unixPath),
        equals('Crash at [PATH_REDACTED]/project/lib/main.dart'),
      );
    });

    test('Redaction performance completes in < 1ms per event payload', () {
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        DataScrubber.scrubString(
          'Error Bearer token123 at C:\\Users\\Dev\\app with card 4111111111111111',
        );
        DataScrubber.scrubMap({
          'password': 'pass',
          'token': 'secret',
          'nested': {'api_key': '123'},
        });
      }
      stopwatch.stop();
      final avgTimeMs = stopwatch.elapsedMicroseconds / (100 * 1000);
      expect(avgTimeMs, lessThan(1.0));
    });
  });
}
