import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_first_app/services/cloud_sync_service.dart';
import 'package:my_first_app/services/cpanel_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('account switch parks the previous hotel and does not leak it', () async {
    SharedPreferences.setMockInitialValues({
      CloudSyncService.roomKey: '[{"roomNumber":101}]',
      'hp_cpanel_active_user': 'user-a',
      'hp_outbox': '[{"recordId":"room_101"}]',
    });
    await CpanelSession.parkActiveCache('user-b');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(CloudSyncService.roomKey), isNull);
    expect(prefs.getString('hp_outbox'), isNull);
    expect(
      prefs.getString('${CpanelSession.cachePrefix('user-a')}_${CloudSyncService.roomKey}'),
      '[{"roomNumber":101}]',
    );
    await CpanelSession.restoreCache('user-a');
    expect(prefs.getString(CloudSyncService.roomKey), '[{"roomNumber":101}]');
    expect(prefs.getString('hp_cpanel_active_user'), 'user-a');
  });
}
