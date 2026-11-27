import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/card_focus_scope.dart';
import '../../../focus/focus_theme.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_source_info.dart';
import '../../../theme/mono_tokens.dart';
import '../../app_icon.dart';
import 'player_focus_disc.dart';

class SkipMarkerButton extends StatelessWidget {
  final MediaMarker marker;
  final Duration playerDuration;
  final bool hasNextEpisode;
  final bool isAutoSkipActive;
  final bool shouldShowAutoSkip;
  final int autoSkipDelay;
  final double autoSkipProgress;
  final FocusNode focusNode;
  final VoidCallback onActivate;
  final VoidCallback onFocusDown;

  const SkipMarkerButton({
    super.key,
    required this.marker,
    required this.playerDuration,
    required this.hasNextEpisode,
    required this.isAutoSkipActive,
    required this.shouldShowAutoSkip,
    required this.autoSkipDelay,
    required this.autoSkipProgress,
    required this.focusNode,
    required this.onActivate,
    required this.onFocusDown,
  });

  @override
  Widget build(BuildContext context) {
    final isCredits = marker.isCredits;
    final creditsAtEnd =
        isCredits && playerDuration > Duration.zero && (playerDuration - marker.endTime).inMilliseconds <= 1000;
    final showNextEpisode = creditsAtEnd && hasNextEpisode;
    String baseButtonText;
    if (showNextEpisode) {
      baseButtonText = t.videoControls.nextEpisode;
    } else if (isCredits) {
      baseButtonText = t.videoControls.skipCredits;
    } else {
      baseButtonText = t.videoControls.skipIntro;
    }

    final remainingSeconds = isAutoSkipActive && shouldShowAutoSkip
        ? (autoSkipDelay - (autoSkipProgress * autoSkipDelay)).ceil().clamp(0, autoSkipDelay)
        : 0;

    final showAutoSkipCountdown = isAutoSkipActive && shouldShowAutoSkip;
    final buttonText = showAutoSkipCountdown && remainingSeconds > 0
        ? '$baseButtonText ($remainingSeconds)'
        : baseButtonText;
    final buttonIcon = showNextEpisode ? Symbols.skip_next_rounded : Symbols.fast_forward_rounded;

    return FocusableWrapper(
      focusNode: focusNode,
      onSelect: _activate,
      borderRadius: tokens(context).radiusSm,
      delegateFocusBorder: true,
      autoScroll: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onFocusDown();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _activate,
          borderRadius: BorderRadius.circular(tokens(context).radiusSm),
          child: Stack(
            children: [
              _SkipMarkerPill(
                child: (labelColor) => Row(
                  mainAxisSize: .min,
                  children: [
                    Text(
                      buttonText,
                      style: TextStyle(color: labelColor, fontSize: 16, fontWeight: .w600),
                    ),
                    const SizedBox(width: 8),
                    AppIcon(buttonIcon, fill: 1, color: labelColor, size: 20),
                  ],
                ),
              ),
              if (isAutoSkipActive && shouldShowAutoSkip)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                    child: Row(
                      children: [
                        Expanded(
                          flex: (autoSkipProgress * 100).round(),
                          // Below the focus scope, so a focused accent pill
                          // can switch the fill to onPrimary.
                          child: Builder(
                            builder: (context) => Container(
                              decoration: BoxDecoration(
                                color: _countdownColor(context).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: ((1.0 - autoSkipProgress) * 100).round(),
                          child: Container(decoration: const BoxDecoration(color: Colors.transparent)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _activate() => onActivate();

  /// primary vanishes on a pill filled with the accent, so that pill gets
  /// onPrimary.
  static Color _countdownColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onAccentPill = (CardFocusScope.maybeOf(context) ?? false) && playerFocusAccent(context) != null;
    return onAccentPill ? colorScheme.onPrimary : colorScheme.primary;
  }
}

/// The skip button's pill and its focus chrome.
///
/// The app-wide translucent focus fill vanished behind the 90 % white pill, so
/// a focused button looked idle on a TV. Like [PlayerFocusDisc], a theme with a
/// coloured accent fills the focused pill with that accent; the monochrome
/// themes keep the white pill and ring it instead, with a gap so the ring
/// reads against the pill.
class _SkipMarkerPill extends StatelessWidget {
  const _SkipMarkerPill({required this.child});

  final Widget Function(Color labelColor) child;

  static const double _ringWidth = 3;
  static const double _ringGap = 3;

  @override
  Widget build(BuildContext context) {
    final showFocus = CardFocusScope.maybeOf(context) ?? false;
    final accent = showFocus ? playerFocusAccent(context) : null;
    final radius = tokens(context).radiusSm;
    final duration = FocusTheme.getAnimationDuration(context);
    final pill = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: accent ?? Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child(accent == null ? Colors.black : Theme.of(context).colorScheme.onPrimary),
    );
    // The ring sits outside the pill's rect, so it never moves or grows the
    // button, its tap target or the countdown overlay.
    const ringInset = -(_ringWidth + _ringGap);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        pill,
        Positioned.fill(
          left: ringInset,
          top: ringInset,
          right: ringInset,
          bottom: ringInset,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius + _ringWidth + _ringGap),
                border: Border.all(
                  color: showFocus && accent == null ? Colors.white : Colors.transparent,
                  width: _ringWidth,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
