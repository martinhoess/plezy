import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/video_controls/widgets/skip_marker_button.dart';

/// The pill: the nearest container around the label.
Finder pillFinder() =>
    find.ancestor(of: find.textContaining(t.videoControls.skipIntro), matching: find.byType(AnimatedContainer)).first;

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  /// Pumps the skip button under [palette]'s theme in keyboard mode, focused or
  /// not, and returns the pill's decoration, the ring around it and the label
  /// colour.
  Future<({BoxDecoration pill, BoxDecoration ring, Color? label})> pumpButton(
    WidgetTester tester,
    MonoPalette palette, {
    required bool focused,
    bool autoSkip = false,
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
              isAutoSkipActive: autoSkip,
              shouldShowAutoSkip: autoSkip,
              autoSkipDelay: 5,
              autoSkipProgress: autoSkip ? 0.5 : 0,
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

    final label = find.textContaining(t.videoControls.skipIntro);
    final pill = tester.widget<AnimatedContainer>(pillFinder());
    final ring = tester
        .widgetList<AnimatedContainer>(
          find.descendant(of: find.byType(SkipMarkerButton), matching: find.byType(AnimatedContainer)),
        )
        .firstWhere((container) => (container.decoration! as BoxDecoration).border != null);
    return (
      pill: pill.decoration! as BoxDecoration,
      ring: ring.decoration! as BoxDecoration,
      label: tester.widget<Text>(label).style?.color,
    );
  }

  Finder overlayFinder() => find.descendant(of: find.byType(SkipMarkerButton), matching: find.byType(ClipRRect));

  Color? overlayColor(WidgetTester tester) {
    final fill = tester.widgetList<Container>(find.descendant(of: overlayFinder(), matching: find.byType(Container)));
    return (fill.first.decoration! as BoxDecoration).color;
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

  // The focus ring must not take layout space: an idle button keeps the pill,
  // its tap target and the auto-skip countdown on the same rect as before.
  testWidgets('the idle pill, the button and the countdown share one rect', (tester) async {
    for (final palette in [MonoPalette.dark, MonoPalette.ember]) {
      await pumpButton(tester, palette, focused: false, autoSkip: true);
      final pill = tester.getRect(pillFinder());
      expect(tester.getRect(find.byType(SkipMarkerButton)), pill, reason: '$palette');
      expect(tester.getRect(overlayFinder()), pill, reason: '$palette');

      await pumpButton(tester, palette, focused: true, autoSkip: true);
      expect(tester.getRect(find.byType(SkipMarkerButton)), pill, reason: 'focus must not resize, $palette');
    }
  });

  // primary at 20 % on a pill filled with primary was invisible.
  testWidgets('the countdown on the accent-filled pill draws in onPrimary', (tester) async {
    await pumpButton(tester, MonoPalette.ember, focused: true, autoSkip: true);
    expect(overlayColor(tester), MonoPalette.ember.onAccent.withValues(alpha: 0.2));

    await pumpButton(tester, MonoPalette.ember, focused: false, autoSkip: true);
    expect(overlayColor(tester), MonoPalette.ember.accent.withValues(alpha: 0.2));

    await pumpButton(tester, MonoPalette.dark, focused: true, autoSkip: true);
    expect(overlayColor(tester), MonoPalette.dark.accent.withValues(alpha: 0.2));
  });
}
