import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_first_app/services/otp_request_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('rapid taps and reopened login share the persisted cooldown', () async {
    var now = DateTime(2026, 10, 12);
    final gate = OtpRequestGate(now: () => now);
    await gate.begin('+919999999995');
    await expectLater(gate.begin('+919999999995'), throwsStateError);
    gate.finish();
    final reopened = OtpRequestGate(now: () => now);
    await expectLater(reopened.begin('+919999999995'), throwsStateError);
    now = now.add(const Duration(seconds: 60));
    await reopened.begin('+919999999995');
    reopened.finish();
  });
  test(
    'server throttle has a longer local pause and preserves other numbers',
    () async {
      var now = DateTime(2026, 10, 12);
      final gate = OtpRequestGate(now: () => now);
      await gate.begin('+919999999995');
      await gate.rateLimited('+919999999995');
      now = now.add(const Duration(minutes: 1));
      await expectLater(gate.begin('+919999999995'), throwsStateError);
      await gate.begin('+919999999994');
      gate.finish();
      now = now.add(const Duration(minutes: 4));
      await gate.begin('+919999999995');
      gate.finish();
    },
  );
}
