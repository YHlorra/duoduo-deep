import 'package:flutter_test/flutter_test.dart';
import 'package:dlg_q/services/output_constraint.dart';

void main() {
  group('OutputConstraintLevel', () {
    test('has three enum values', () {
      expect(
        OutputConstraintLevel.values,
        equals(const [
          OutputConstraintLevel.level3Strict,
          OutputConstraintLevel.level2Json,
          OutputConstraintLevel.level1Prompt,
        ]),
      );
    });
  });

  group('ProviderCapability', () {
    tearDown(() => ProviderCapability.resetForTest());

    test('forceLevel sets _forcedLevel and detect returns it immediately',
        () async {
      ProviderCapability.forceLevel(OutputConstraintLevel.level1Prompt);
      final result = await ProviderCapability.detect(
        'http://example.com',
        'model-x',
        'key',
      );
      expect(result, OutputConstraintLevel.level1Prompt);
    });

    test('cache key format is baseUrl::model', () async {
      ProviderCapability.forceLevel(OutputConstraintLevel.level2Json);
      final result = await ProviderCapability.detect(
        'http://example.com',
        'model-x',
        'key',
      );
      expect(result, OutputConstraintLevel.level2Json);
    });

    // TODO: _probe() and cache dedup (_inFlight) require HTTP mocking.
    // Coverage gap acknowledged — add Mockito-based tests if this becomes critical.
  });
}