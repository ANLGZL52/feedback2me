import 'package:flutter_test/flutter_test.dart';
import 'package:feedback_to_me/services/openai_audience_client.dart';

// Pure unit tests for the callable-response envelope parsing (no Firebase needed).
// The provider failure / unauthenticated paths surface as a null callable result
// or a FirebaseFunctionsException — both are mapped to null by the client and the
// caller (report_service) then uses the heuristic report. These tests lock the
// success + failure envelope contract that decides "AI content" vs "fallback".
void main() {
  group('OpenAiAudienceClient.contentFromCallableData', () {
    test('valid {ok:true, content} -> trimmed content (AI path)', () {
      final r = OpenAiAudienceClient.contentFromCallableData(
        {'ok': true, 'content': '  {"partOzeti":"x"}  '},
      );
      expect(r, '{"partOzeti":"x"}');
    });

    test('ok:false -> null (heuristic fallback)', () {
      expect(
        OpenAiAudienceClient.contentFromCallableData({'ok': false, 'content': 'x'}),
        isNull,
      );
    });

    test('empty / whitespace content -> null', () {
      expect(OpenAiAudienceClient.contentFromCallableData({'ok': true, 'content': '   '}), isNull);
      expect(OpenAiAudienceClient.contentFromCallableData({'ok': true, 'content': ''}), isNull);
    });

    test('non-Map / null / missing content -> null (never throws)', () {
      expect(OpenAiAudienceClient.contentFromCallableData(null), isNull);
      expect(OpenAiAudienceClient.contentFromCallableData('nope'), isNull);
      expect(OpenAiAudienceClient.contentFromCallableData({'ok': true}), isNull);
      expect(OpenAiAudienceClient.contentFromCallableData({'ok': true, 'content': 42}), isNull);
    });

    test('handles Map<Object?,Object?> (plugin decode shape) without cast crash', () {
      final Map<Object?, Object?> data = <Object?, Object?>{'ok': true, 'content': 'ok'};
      expect(OpenAiAudienceClient.contentFromCallableData(data), 'ok');
    });
  });
}
