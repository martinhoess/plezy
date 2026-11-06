import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../utils/app_logger.dart';
import 'settings_export_service.dart';
import 'settings_mutation_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// Syncs the portable settings through iCloud's key-value store on iOS and
/// tvOS (#1979). The store holds one snapshot in the settings export format,
/// so it carries exactly what Export settings carries; the latest write wins.
///
/// The main screen pushes this device's settings every half minute and when
/// the app goes to the background, and applies another device's snapshot on
/// launch, on resume and whenever iCloud reports a change.
class ICloudSettingsSyncService {
  static const _channel = MethodChannel('com.plezy/icloud_settings');

  /// `exportedAt` of the snapshot this device last pushed or applied.
  static const _lastSyncedKey = 'icloud_settings_last_synced';

  /// How long turning sync on waits for a fresh install's first iCloud
  /// download before it treats the store as empty.
  static const initialDownloadTimeout = Duration(seconds: 20);

  static bool get isSupported => Platform.isIOS;

  static final _externalChanges = StreamController<void>.broadcast();
  static bool _listening = false;

  /// Fires when iCloud delivers a change, including a fresh install's first
  /// download.
  static Stream<void> get externalChanges {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changedExternally') _externalChanges.add(null);
      });
    }
    return _externalChanges.stream;
  }

  static Future<bool> _isEnabled() async =>
      isSupported && (await SettingsService.getInstance()).read(SettingsService.icloudSettingsSync);

  /// Whether [remote] is a snapshot this device has not seen and that differs
  /// from its own settings.
  static bool shouldApply({
    required Map<String, dynamic>? remote,
    required Map<String, dynamic> local,
    required String? lastSynced,
  }) => remote != null && remote['exportedAt'] != lastSynced && !samePrefs(remote, local);

  /// Whether this device should write [local] over [remote]. It never writes
  /// over a snapshot it has not applied yet (one that arrived during playback,
  /// say), which would undo another device's change. An empty store is only
  /// written when seeding: on a device that has not downloaded the store yet
  /// it reads empty too, and writing then would replace every other device's
  /// settings.
  static bool shouldPush({
    required Map<String, dynamic>? remote,
    required Map<String, dynamic> local,
    required String? lastSynced,
    required bool seed,
  }) {
    if (remote == null) return seed;
    return remote['exportedAt'] == lastSynced && !samePrefs(remote, local);
  }

  static bool samePrefs(Map<String, dynamic> a, Map<String, dynamic> b) =>
      const DeepCollectionEquality().equals(a['prefs'], b['prefs']);

  static Future<Map<String, dynamic>?> _readRemote() async {
    final raw = await _channel.invokeMethod<String>('get');
    if (raw == null) return null;
    final decoded = json.decode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static Future<Map<String, dynamic>> _localSnapshot(SettingsService settings) async {
    final storage = await StorageService.getInstance();
    return SettingsExportService.buildExportMap(settings.prefs, currentUserUuid: storage.activeUserScope());
  }

  /// Stores this device's settings when they differ from iCloud's. [seed]
  /// also writes an empty store, which only turning sync on may do.
  static Future<void> push({bool seed = false}) async {
    if (!await _isEnabled()) return;
    try {
      final settings = await SettingsService.getInstance();
      final local = await _localSnapshot(settings);
      final remote = await _readRemote();
      final lastSynced = settings.readNullableString(_lastSyncedKey);
      if (!shouldPush(remote: remote, local: local, lastSynced: lastSynced, seed: seed)) return;
      await _channel.invokeMethod<void>('set', json.encode(local));
      await settings.writeString(_lastSyncedKey, local['exportedAt'] as String);
      appLogger.i('iCloud settings: pushed ${(local['prefs'] as Map).length} settings');
    } catch (e, st) {
      appLogger.w('iCloud settings push failed', error: e, stackTrace: st);
    }
  }

  /// Applies a snapshot another device stored since this one last synced.
  /// [force] applies any differing snapshot, for turning sync on.
  /// Returns whether this device's settings changed.
  static Future<bool> pull(BuildContext context, {bool force = false}) async {
    if (!await _isEnabled()) return false;
    try {
      final settings = await SettingsService.getInstance();
      final uuid = (await StorageService.getInstance()).activeUserScope();
      if (uuid == null || uuid.isEmpty) return false;
      final remote = await _readRemote();
      final local = await _localSnapshot(settings);
      final lastSynced = force ? null : settings.readNullableString(_lastSyncedKey);
      if (remote != null && samePrefs(remote, local)) {
        // Nothing to apply, but this device has now seen the snapshot and may push over it.
        if (remote['exportedAt'] != lastSynced) {
          await settings.writeString(_lastSyncedKey, remote['exportedAt'] as String);
        }
        return false;
      }
      if (!shouldApply(remote: remote, local: local, lastSynced: lastSynced)) return false;

      final previousRootConfiguration = SettingsMutationService.captureRootConfiguration();
      await SettingsExportService.applyImportMap(remote!, settings.prefs, currentUserUuid: uuid);
      await settings.writeString(_lastSyncedKey, remote['exportedAt'] as String);
      appLogger.i('iCloud settings: applied snapshot from ${remote['exportedAt']}');
      if (context.mounted) {
        await const SettingsMutationService().applyImportedSettings(
          context,
          previousRootConfiguration: previousRootConfiguration,
        );
      }
      return true;
    } catch (e, st) {
      appLogger.w('iCloud settings pull failed', error: e, stackTrace: st);
      return false;
    }
  }

  /// Turning sync on adopts the settings already in iCloud. A fresh install
  /// reads the store empty until its first download lands, so an empty store
  /// is seeded with this device's settings only once that wait runs out.
  static Future<void> adopt(BuildContext context) async {
    final firstDownload = externalChanges.first.timeout(initialDownloadTimeout, onTimeout: () {});
    if (await pull(context, force: true)) return;
    if (await _readRemote() == null) {
      await firstDownload;
      if (!context.mounted) return;
      if (await pull(context, force: true)) return;
    }
    await push(seed: true);
  }
}
