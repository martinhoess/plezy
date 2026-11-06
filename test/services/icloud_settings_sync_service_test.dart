import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/icloud_settings_sync_service.dart';

Map<String, dynamic> _snapshot(String exportedAt, Map<String, dynamic> prefs) => {
  'formatVersion': 1,
  'exportedAt': exportedAt,
  'prefs': prefs,
};

void main() {
  final darkTheme = {
    'theme_mode': {'type': 'string', 'value': 'dark'},
  };
  final lightTheme = {
    'theme_mode': {'type': 'string', 'value': 'light'},
  };

  group('ICloudSettingsSyncService.shouldApply', () {
    test('applies a differing snapshot this device has not seen', () {
      expect(
        ICloudSettingsSyncService.shouldApply(
          remote: _snapshot('2026-11-06T10:00:00Z', darkTheme),
          local: _snapshot('2026-11-06T11:00:00Z', lightTheme),
          lastSynced: '2026-11-05T09:00:00Z',
        ),
        isTrue,
      );
    });

    test('skips the snapshot this device pushed or applied last', () {
      expect(
        ICloudSettingsSyncService.shouldApply(
          remote: _snapshot('2026-11-06T10:00:00Z', darkTheme),
          local: _snapshot('2026-11-06T11:00:00Z', lightTheme),
          lastSynced: '2026-11-06T10:00:00Z',
        ),
        isFalse,
      );
    });

    test('skips a snapshot whose settings already match', () {
      expect(
        ICloudSettingsSyncService.shouldApply(
          remote: _snapshot('2026-11-06T10:00:00Z', darkTheme),
          local: _snapshot('2026-11-06T11:00:00Z', {...darkTheme}),
          lastSynced: null,
        ),
        isFalse,
      );
    });

    test('skips when iCloud holds no snapshot', () {
      expect(
        ICloudSettingsSyncService.shouldApply(
          remote: null,
          local: _snapshot('2026-11-06T11:00:00Z', lightTheme),
          lastSynced: null,
        ),
        isFalse,
      );
    });
  });

  group('ICloudSettingsSyncService.shouldPush', () {
    test('writes changed settings over the snapshot this device last synced', () {
      expect(
        ICloudSettingsSyncService.shouldPush(
          remote: _snapshot('2026-11-06T10:00:00Z', darkTheme),
          local: _snapshot('2026-11-06T11:00:00Z', lightTheme),
          lastSynced: '2026-11-06T10:00:00Z',
          seed: false,
        ),
        isTrue,
      );
    });

    test('never writes over a snapshot this device has not applied', () {
      expect(
        ICloudSettingsSyncService.shouldPush(
          remote: _snapshot('2026-11-06T12:00:00Z', darkTheme),
          local: _snapshot('2026-11-06T11:00:00Z', lightTheme),
          lastSynced: '2026-11-06T10:00:00Z',
          seed: false,
        ),
        isFalse,
      );
    });

    test('leaves an identical snapshot alone', () {
      expect(
        ICloudSettingsSyncService.shouldPush(
          remote: _snapshot('2026-11-06T10:00:00Z', darkTheme),
          local: _snapshot('2026-11-06T11:00:00Z', {...darkTheme}),
          lastSynced: '2026-11-06T10:00:00Z',
          seed: true,
        ),
        isFalse,
      );
    });

    test('never writes an empty store unless seeding', () {
      final local = _snapshot('2026-11-06T11:00:00Z', lightTheme);
      expect(ICloudSettingsSyncService.shouldPush(remote: null, local: local, lastSynced: null, seed: false), isFalse);
      expect(ICloudSettingsSyncService.shouldPush(remote: null, local: local, lastSynced: null, seed: true), isTrue);
    });
  });
}
