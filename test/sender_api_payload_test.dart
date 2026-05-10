import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vll_sms/packages/http_requests.dart';
import 'package:vll_sms/shared/sender_api_payload.dart';

void main() {
  test('extractSendersList reads data.senders envelope', () {
    final list = SenderApiPayload.extractSendersList({
      'senders': [
        {'sender_id': 'A', 'id_type': 'Public', 'id_status': 'Active'},
      ],
      'current_sender': [],
    });
    expect(list.length, 1);
    expect((list.first as Map)['sender_id'], 'A');
  });

  test('ensureHttpAndEnvelopeSuccess rejects HTTP 500 even if JSON success is true', () {
    final res = http.Response(
      '{"success":true,"message":"ok","data":{"senders":[]}}',
      500,
      headers: {'content-type': 'application/json'},
    );
    expect(
      () => ApiClient.ensureHttpAndEnvelopeSuccess(res),
      throwsException,
    );
  });

  test('ensureHttpAndEnvelopeSuccess accepts HTTP 200 with success true', () {
    final res = http.Response(
      '{"success":true,"message":"ok","data":{"senders":[]}}',
      200,
      headers: {'content-type': 'application/json'},
    );
    expect(() => ApiClient.ensureHttpAndEnvelopeSuccess(res), returnsNormally);
  });
}
