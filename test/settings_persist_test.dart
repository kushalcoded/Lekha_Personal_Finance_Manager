import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/category/expense_category.dart';
import 'package:personal_expanse_tracker/screens/settings/providers/settings_providers.dart';
import 'package:personal_expanse_tracker/services/storage/hive_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // initFlutter() asks path_provider for the documents dir, which has no
    // implementation under flutter_test.
    final dir = await Directory.systemTemp.createTemp('lekha_settings');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    await HiveService.initialize();
  });

  test('saving a setting keeps keys owned by other features', () async {
    // The bug: _persist wrote a fresh map literal and saveSettings replaces
    // wholesale, so toggling any switch deleted settings['categories'] and
    // every custom category silently reverted to the defaults.
    const userId = 'u1';
    final hive = HiveService();

    await hive.saveCustomCategories(userId, const [
      ExpenseCategory(name: 'Rakhi', iconKey: 'gift', colorHex: '#F0A13B'),
    ]);

    final notifier = SettingsNotifier(hive, userId);
    await notifier.setSmsNotifyEnabled(true);

    expect(hive.getCustomCategories(userId).map((c) => c.name), ['Rakhi']);
    expect(hive.getSettings(userId)['smsNotifyEnabled'], isTrue);
  });

  test('a cleared nullable still overwrites the stored value', () async {
    // Merging must not resurrect an old value: setSalaryDay(null) has to win
    // over whatever was on disk.
    const userId = 'u2';
    final hive = HiveService();
    final notifier = SettingsNotifier(hive, userId);

    await notifier.setSalaryDay(7);
    expect(hive.getSettings(userId)['salaryDay'], 7);

    await notifier.setSalaryDay(null);
    expect(hive.getSettings(userId)['salaryDay'], isNull);
  });
}
