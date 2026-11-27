import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/livetv_capture_buffer.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/video_controls/widgets/live_timeline_bar.dart';
import 'package:plezy/widgets/video_controls/widgets/player_focus_disc.dart';
import 'package:plezy/widgets/video_controls/widgets/timeline_slider.dart';

import '../test_helpers/watch_together_fakes.dart';

/// Matches a render tree that draws a [playerFocusKnobRadius] disc in [color].
/// Compared as ARGB: Paint keeps its colour in float32.
PaintPattern paintsKnob(Color color) => paints
  ..something(
    (method, args) =>
        method == #drawCircle &&
        args[1] == playerFocusKnobRadius &&
        (args[2] as Paint).color.toARGB32() == color.toARGB32(),
  );

void main() {
  setUpAll(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
  });

  /// Pumps [timeline] under [palette]'s theme in keyboard mode and focuses it.
  Future<void> pumpFocused(WidgetTester tester, MonoPalette palette, Widget timeline, FocusNode focusNode) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      InputModeTracker(
        child: TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(palette),
            home: Scaffold(
              backgroundColor: Colors.black,
              body: Center(child: SizedBox(width: 400, child: timeline)),
            ),
          ),
        ),
      ),
    );
    InputModeTracker.reportNonPointerInput();
    focusNode.requestFocus();
    await tester.pumpAndSettle();
  }

  // The knob follows the focused disc: the accent on a coloured theme, white on
  // the monochrome ones.
  final cases = {MonoPalette.ember: MonoPalette.ember.accent, MonoPalette.dark: Colors.white};

  testWidgets('the focused VOD timeline knob takes the focus fill', (tester) async {
    for (final MapEntry(key: palette, value: knob) in cases.entries) {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await pumpFocused(
        tester,
        palette,
        TimelineSlider(
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 10),
          chapters: const [],
          chaptersLoaded: true,
          focusNode: focusNode,
          onSeek: (_) {},
          onSeekEnd: (_) {},
        ),
        focusNode,
      );
      expect(tester.renderObject(find.byType(Slider)), paintsKnob(knob), reason: '$palette');
    }
  });

  testWidgets('the focused live timeline knob takes the focus fill', (tester) async {
    final startEpoch = DateTime(2026, 1, 1, 12).millisecondsSinceEpoch ~/ 1000;
    for (final MapEntry(key: palette, value: knob) in cases.entries) {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final player = FakeSyncPlayer(position: const Duration(seconds: 60));
      addTearDown(player.dispose);
      await pumpFocused(
        tester,
        palette,
        LiveTimelineBar(
          player: player,
          captureBuffer: CaptureBuffer(startedAt: startEpoch.toDouble(), seekStartSeconds: 0, seekEndSeconds: 120),
          epochForPosition: (position) => startEpoch + position.inSeconds,
          onSeekEnd: (_) {},
          focusNode: focusNode,
        ),
        focusNode,
      );
      final paint = find.descendant(of: find.byType(LiveTimelineBar), matching: find.byType(CustomPaint)).last;
      expect(tester.renderObject(paint), paintsKnob(knob), reason: '$palette');
    }
  });
}
