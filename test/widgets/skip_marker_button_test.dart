import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/video_controls/widgets/skip_marker_button.dart';

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  /// Pumps the skip button under [palette]'s theme in keyboard mode, focused or
  /// not, and returns the pill's decoration, the ring around it and the label
  /// colour.
  Future<({BoxDecoration pill, BoxDecoration ring, Color? label})> pumpButton(
    WidgetTester tester,
    MonoPalette palette, {
    required bool focused,
  }) async {
    final focusNode = FocusNode(debugLabel: 'SkipMarkerButton');
    addTearDown(focusNode.dispose);
    // A fresh tree, so a previous pump's focus does not carry over.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          theme: monoTheme(palette),
          home: Center(
            child: SkipMarkerButton(
              marker: MediaMarker(id: 1, type: 'intro', startTimeOffset: 0, endTimeOffset: 45000),
              playerDuration: const Duration(minutes: 40),
              hasNextEpisode: false,
              isAutoSkipActive: false,
              shouldShowAutoSkip: false,
              autoSkipDelay: 5,
              autoSkipProgress: 0,
              focusNode: focusNode,
              onActivate: () {},
              onFocusDown: () {},
            ),
          ),
        ),
      ),
    );
    InputModeTracker.reportNonPointerInput();
    if (focused) focusNode.requestFocus();
    await tester.pumpAndSettle();

    final label = find.text(t.videoControls.skipIntro);
    final containers = tester
        .widgetList<AnimatedContainer>(find.ancestor(of: label, matching: find.byType(AnimatedContainer)))
        .toList();
    return (
      pill: containers.first.decoration! as BoxDecoration,
      ring: containers.last.decoration! as BoxDecoration,
      label: tester.widget<Text>(label).style?.color,
    );
  }

  // On a TV the 20 % white focus fill sat behind a 90 % white pill, so the
  // focused button looked exactly like the idle one and a viewer could not
  // tell that Select would skip.
  testWidgets('a coloured accent fills the focused pill with the accent', (tester) async {
    final focused = await pumpButton(tester, MonoPalette.ember, focused: true);
    expect(focused.pill.color, MonoPalette.ember.accent);
    expect(focused.label, MonoPalette.ember.onAccent);

    final idle = await pumpButton(tester, MonoPalette.ember, focused: false);
    expect(idle.pill.color, Colors.white.withValues(alpha: 0.9));
    expect(idle.label, Colors.black);
  });

  testWidgets('monochrome themes ring the focused white pill', (tester) async {
    for (final palette in [MonoPalette.dark, MonoPalette.oled, MonoPalette.light]) {
      final focused = await pumpButton(tester, palette, focused: true);
      expect(focused.pill.color, Colors.white.withValues(alpha: 0.9));
      expect((focused.ring.border! as Border).top.color, Colors.white);

      final idle = await pumpButton(tester, palette, focused: false);
      expect((idle.ring.border! as Border).top.color, Colors.transparent);
    }
  });
}
