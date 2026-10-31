import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsRepository avatar persistence', () {
    test('saveAvatarBytes stores base64 backup and can be restored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final SettingsRepository repo = SettingsRepository(prefs);

      // Dummy 10x10 byte array representing image bytes
      final Uint8List fakeBytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      await repo.saveAvatarBytes(fakeBytes);

      // Verify that base64 is in SharedPreferences
      final String? b64 = prefs.getString('profile.avatar_b64');
      expect(b64, isNotNull);
      expect(base64Decode(b64!), fakeBytes);

      // Simulate app reinstall / new SettingsRepository instance
      final SettingsRepository repo2 = SettingsRepository(prefs);
      expect(repo2.displayName, 'Hoàng');
      expect(prefs.getString('profile.avatar_b64'), b64);
    });

    test('clearAvatar removes path and base64 backup', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final SettingsRepository repo = SettingsRepository(prefs);

      final Uint8List fakeBytes = Uint8List.fromList(<int>[10, 20, 30]);
      await repo.saveAvatarBytes(fakeBytes);
      expect(prefs.getString('profile.avatar_b64'), isNotNull);

      await repo.setAvatarPath(null);
      expect(prefs.getString('profile.avatar_b64'), isNull);
      expect(prefs.getString('profile.avatar_path'), isNull);
    });
  });
}
