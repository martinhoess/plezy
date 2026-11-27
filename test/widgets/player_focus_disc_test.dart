import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/card_focus_scope.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/video_controls/widgets/player_focus_disc.dart';

void main() {
  /// Pumps a focused disc under [palette]'s theme and returns the fill and the
  /// icon colour it hands its builder.
  Future<({Color? fill, Color icon})> pumpFocused(
    WidgetTester tester,
    MonoPalette palette, {
    bool isActive = false,
    Color iconColor = Colors.white,
  }) async {
    late Color builtIconColor;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(palette),
        home: CardFocusScope(
          showFocus: true,
          child: PlayerFocusDisc(
            iconColor: iconColor,
            isActive: isActive,
            builder: (context, color) {
              builtIconColor = color;
              return const SizedBox(width: 40, height: 40);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    return (fill: (container.decoration! as BoxDecoration).color, icon: builtIconColor);
  }

  testWidgets('monochrome themes keep the white disc with a black icon', (tester) async {
    for (final palette in [MonoPalette.dark, MonoPalette.oled, MonoPalette.light]) {
      final result = await pumpFocused(tester, palette);
      expect(result.fill, Colors.white);
      expect(result.icon, Colors.black);
    }
  });

  testWidgets('monochrome themes keep the amber disc for an active control', (tester) async {
    final result = await pumpFocused(tester, MonoPalette.dark, isActive: true);
    expect(result.fill, Colors.amber);
  });

  testWidgets('a coloured accent fills the disc with the accent and its on-colour', (tester) async {
    final result = await pumpFocused(tester, MonoPalette.ember);
    expect(result.fill, MonoPalette.ember.accent);
    expect(result.icon, MonoPalette.ember.onAccent);
  });

  testWidgets('an active control under a coloured accent focuses white, not amber', (tester) async {
    final result = await pumpFocused(tester, MonoPalette.ember, isActive: true);
    expect(result.fill, Colors.white);
    expect(result.icon, Colors.black);
  });

  testWidgets('a dimmed control stays dimmed on the accent disc', (tester) async {
    final result = await pumpFocused(tester, MonoPalette.ember, iconColor: Colors.white.withValues(alpha: 0.4));
    expect(result.icon, MonoPalette.ember.onAccent.withValues(alpha: 0.4));
  });

  testWidgets('focused timeline knob takes the same fill as the disc', (tester) async {
    late Color knob;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.ember),
        home: Builder(
          builder: (context) {
            knob = playerFocusKnobColor(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(knob, MonoPalette.ember.accent);
  });
}
