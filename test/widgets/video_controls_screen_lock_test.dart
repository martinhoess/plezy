import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:plezy/database/app_database.dart';
import 'package:plezy/focus/transport_keys.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/video_volume_controller.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/watch_together/providers/watch_together_provider.dart';
import 'package:plezy/widgets/video_controls/player_chrome_controller.dart';
import 'package:plezy/widgets/video_controls/video_controls.dart';
import 'package:plezy/widgets/video_controls/widgets/player_toast_indicator.dart';
import 'package:plezy/widgets/video_controls/widgets/screen_lock_overlay.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/player_streams.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/theme.dart';

/// The touch lock has to open by feel, because a device dimmed for an external
/// display shows nothing to aim at: a hold anywhere unlocks. A tap only toggles
/// the hint, and a contact with a second finger counts for nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingPlayer player;
  late PlayerChromeController chrome;
  late PlayerToastController toast;
  late VideoVolumeController volume;
  late PlaybackStateProvider playbackState;
  late WatchTogetherProvider watchTogether;
  late AppDatabase database;
  late List<TransportCommand> transportCommands;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    final settings = await SettingsService.getInstance();

    // Phone layout: the screen lock button exists only on mobile, not TV.
    TvDetectionService.debugSetAppleTVOverride(false);
    PlatformDetector.debugSetIsDesktopOSOverride(false);

    database = AppDatabase.forTesting(NativeDatabase.memory());
    player = _RecordingPlayer();
    chrome = PlayerChromeController();
    toast = PlayerToastController();
    volume = VideoVolumeController(player: player, settings: settings, initialVolume: 100);
    playbackState = PlaybackStateProvider();
    watchTogether = WatchTogetherProvider();
    transportCommands = [];
  });

  tearDown(() async {
    TvDetectionService.debugSetAppleTVOverride(null);
    PlatformDetector.debugSetIsDesktopOSOverride(null);
    volume.dispose();
    playbackState.dispose();
    watchTogether.dispose();
    chrome.dispose();
    toast.dispose();
    await database.close();
  });

  const surface = Size(800, 600);

  /// Opens the player and locks it through the lock button in the chrome.
  Future<void> pumpLockedControls(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: database),
          ChangeNotifierProvider<PlaybackStateProvider>.value(value: playbackState),
          ChangeNotifierProvider<WatchTogetherProvider>.value(value: watchTogether),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android, extensions: const [testMonoTokens]),
          home: Scaffold(
            body: SizedBox(
              width: surface.width,
              height: surface.height,
              child: PlexVideoControls(
                player: player,
                volumeController: volume,
                metadata: testMediaItem(id: 'screen-lock'),
                toastController: toast,
                chromeController: chrome,
                canNavigateMediaItems: false,
                onPlayPauseRequested: (command) async {
                  transportCommands.add(command);
                  await switch (command) {
                    TransportCommand.play => player.play(),
                    TransportCommand.pause => player.pause(),
                    TransportCommand.toggle => player.playOrPause(),
                  };
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    chrome.show();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip(t.videoControls.lockScreen));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ScreenLockOverlay), findsOneWidget);
    expect(chrome.controlsVisible, isFalse);
  }

  bool isLocked() => find.byType(ScreenLockOverlay).evaluate().isNotEmpty;

  /// Whether the viewer can currently see the hint.
  bool hintVisible(WidgetTester tester) {
    final text = find.text(t.videoControls.holdToUnlock);
    return tester.widget<AnimatedOpacity>(find.ancestor(of: text, matching: find.byType(AnimatedOpacity))).opacity > 0;
  }

  Offset pictureCentre(WidgetTester tester) => tester.getRect(find.byType(PlexVideoControls)).center;

  Future<void> tapAndSettle(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> close(WidgetTester tester) async {
    chrome.cancelAutoHide();
    toast.hide();
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('a hold anywhere unlocks without touching playback', (tester) async {
    await pumpLockedControls(tester);
    await tester.pump(ScreenLockOverlay.promptDuration);
    expect(hintVisible(tester), isFalse, reason: 'the hint fades after locking');

    final hold = await tester.startGesture(pictureCentre(tester));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await hold.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(isLocked(), isFalse);

    // Past the double-tap window: the hold must not reach the picture's own
    // tap handling once the shield is gone.
    await tester.pump(const Duration(milliseconds: 400));
    expect(chrome.controlsVisible, isTrue);
    expect(transportCommands, isEmpty);
    expect(player.state.playing, isTrue);

    await close(tester);
  });

  testWidgets('a tap only toggles the hint', (tester) async {
    await pumpLockedControls(tester);
    expect(hintVisible(tester), isTrue);

    await tapAndSettle(tester, pictureCentre(tester));
    expect(hintVisible(tester), isFalse);

    await tapAndSettle(tester, pictureCentre(tester));
    expect(hintVisible(tester), isTrue);

    expect(isLocked(), isTrue);
    expect(transportCommands, isEmpty);

    await close(tester);
  });

  testWidgets('a contact with a second finger counts for nothing', (tester) async {
    await pumpLockedControls(tester);
    await tester.pump(ScreenLockOverlay.promptDuration);

    final first = await tester.startGesture(pictureCentre(tester), pointer: 11);
    final second = await tester.startGesture(pictureCentre(tester) + const Offset(80, 0), pointer: 12);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 250));

    expect(hintVisible(tester), isFalse, reason: 'neither finger may reveal the hint');
    expect(isLocked(), isTrue);
    expect(transportCommands, isEmpty, reason: 'the two-finger pause is locked out too');
    expect(player.state.playing, isTrue);

    // The next single-finger sequence works normally again.
    final hold = await tester.startGesture(pictureCentre(tester), pointer: 13);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await hold.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(isLocked(), isFalse);

    await close(tester);
  });
}

/// Minimal [Player] tracking playback state against a fixed 45-minute item.
class _RecordingPlayer implements Player {
  bool _playing = true;

  @override
  String get playerType => 'mpv';

  @override
  PlayerState get state => PlayerState(
    playing: _playing,
    position: const Duration(minutes: 10),
    duration: const Duration(minutes: 45),
    seekable: true,
  );

  @override
  PlayerStreams get streams => emptyPlayerStreams();

  @override
  Future<void> play() async => _playing = true;

  @override
  Future<void> pause() async => _playing = false;

  @override
  Future<void> playOrPause() async => _playing = !_playing;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
