import 'package:flutter/material.dart';

import '../../../focus/card_focus_scope.dart';
import '../../../focus/focus_theme.dart';
import '../../../theme/mono_tokens.dart';

/// Focus chrome for a round player control sitting on video.
///
/// The app-wide translucent fill (`useBackgroundFocus`) is tuned for opaque
/// surfaces; over a scrim on top of a bright frame it disappears (#2383). Over
/// video the focused control instead becomes a solid disc with the icon
/// inverted — the treatment the tvOS system player, Netflix and Plex use — so
/// it reads at ten feet on any frame. An active control fills amber so that
/// state survives the inversion.
///
/// A theme with a coloured accent fills the disc with that accent and draws the
/// icon in `onPrimary`; an active control then fills white, since amber is
/// hard to tell from a warm accent on a TV. The monochrome themes keep white.
///
/// Reads the [CardFocusScope] installed by
/// `FocusableWrapper(delegateFocusBorder: true)`: a decoration-only wrapper
/// cannot recolour the icon, so the control builds its icon through [builder]
/// with the colour to use. Renders nothing extra in pointer/touch mode, where
/// no scope is present.
class PlayerFocusDisc extends StatelessWidget {
  const PlayerFocusDisc({
    super.key,
    required this.iconColor,
    this.isActive = false,
    this.borderRadius,
    required this.builder,
  });

  /// Idle icon colour. Its alpha is preserved when focused so a dimmed
  /// (unavailable) control stays visibly dimmed on the disc.
  final Color iconColor;

  /// Whether the control represents an engaged state (amber icon when idle).
  final bool isActive;

  /// Rounds a rectangular fill instead of the default disc, for a labelled
  /// control that is wider than it is tall.
  final BorderRadius? borderRadius;

  final Widget Function(BuildContext context, Color iconColor) builder;

  static const Color _fill = Colors.white;
  static const Color _activeFill = Colors.amber;

  @override
  Widget build(BuildContext context) {
    final showFocus = CardFocusScope.maybeOf(context) ?? false;
    final accent = _playerFocusAccent(context);
    final (fill, onFill) = switch ((isActive, accent)) {
      (true, null) => (_activeFill, Colors.black),
      (false, final color?) => (color, Theme.of(context).colorScheme.onPrimary),
      _ => (_fill, Colors.black),
    };
    return AnimatedContainer(
      duration: FocusTheme.getAnimationDuration(context),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        shape: borderRadius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: borderRadius,
        color: showFocus ? fill : Colors.transparent,
        boxShadow: showFocus ? const [playerFocusShadow] : const [],
      ),
      child: builder(context, showFocus ? onFill.withValues(alpha: iconColor.a) : iconColor),
    );
  }
}

/// The theme's accent when it has a hue of its own, else null. The monochrome
/// built-ins set the accent to the text colour, an off-white that would read
/// as a dirty white disc, so they keep the plain white treatment.
Color? _playerFocusAccent(BuildContext context) {
  final tokens = Theme.of(context).extension<MonoTokens>();
  if (tokens == null || tokens.accent == tokens.text) return null;
  return tokens.accent;
}

/// Fill of the focused-timeline knob, matching an idle [PlayerFocusDisc].
Color playerFocusKnobColor(BuildContext context) => _playerFocusAccent(context) ?? Colors.white;

/// Drop shadow that separates focused player chrome from a bright frame.
const BoxShadow playerFocusShadow = BoxShadow(color: Color(0x59000000), blurRadius: 14, offset: Offset(0, 4));

/// Radius of the knob a focused timeline shows in place of its handle.
const double playerFocusKnobRadius = 9;

/// Paints the focused-timeline knob: a [color] disc ([playerFocusKnobColor])
/// with the same shadow as [PlayerFocusDisc], shared by the VOD slider thumb
/// and the live-TV painter.
void paintPlayerFocusKnob(Canvas canvas, Offset center, Color color) {
  canvas.drawCircle(
    center + playerFocusShadow.offset / 2,
    playerFocusKnobRadius,
    Paint()
      ..color = playerFocusShadow.color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, playerFocusShadow.blurSigma),
  );
  canvas.drawCircle(center, playerFocusKnobRadius, Paint()..color = color);
}
