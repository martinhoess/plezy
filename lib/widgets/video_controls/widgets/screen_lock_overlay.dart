import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../app_icon.dart';

/// Touch shield over the player while the screen lock is on.
///
/// A hold anywhere unlocks, so it works by feel on a device dimmed for an
/// external display, where no button can be seen. A tap only toggles the hint,
/// and a contact that puts a second finger down counts for nothing.
class ScreenLockOverlay extends StatefulWidget {
  const ScreenLockOverlay({super.key, required this.onUnlock});

  final VoidCallback onUnlock;

  /// How long the hint stays up.
  static const promptDuration = Duration(seconds: 3);

  @override
  State<ScreenLockOverlay> createState() => _ScreenLockOverlayState();
}

class _ScreenLockOverlayState extends State<ScreenLockOverlay> {
  // Locking shows the hint straight away so the viewer sees the way out.
  bool _hintVisible = true;
  Timer? _hideTimer;
  int _pointersDown = 0;

  /// Whether the current contact sequence has had two fingers down at once.
  /// Cleared only when the next sequence starts: gestures resolve after the
  /// overlay's own pointer-up bookkeeping, so the last finger lifting must not
  /// clear it before the gesture that finger completes is judged.
  bool _multiTouch = false;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _setHintVisible(bool visible) {
    _hideTimer?.cancel();
    setState(() => _hintVisible = visible);
    if (visible) _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer = Timer(ScreenLockOverlay.promptDuration, () {
      if (mounted) setState(() => _hintVisible = false);
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointersDown == 0) _multiTouch = false;
    _pointersDown++;
    if (_pointersDown > 1 && !_multiTouch) {
      _multiTouch = true;
      _setHintVisible(false);
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (_pointersDown > 0) _pointersDown--;
  }

  void _handleTap() {
    if (_multiTouch) return;
    _setHintVisible(!_hintVisible);
  }

  void _handleLongPress() {
    if (_multiTouch) return;
    _hideTimer?.cancel();
    widget.onUnlock();
  }

  @override
  Widget build(BuildContext context) {
    final label = t.videoControls.holdToUnlock;
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              container: true,
              label: t.videoControls.screenLockButton,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleTap,
                onLongPress: _handleLongPress,
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Align(
                alignment: .topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _hintVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Semantics(
                        container: true,
                        liveRegion: true,
                        label: label,
                        child: ExcludeSemantics(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: const BorderRadius.all(Radius.circular(28)),
                            ),
                            child: Row(
                              mainAxisSize: .min,
                              children: [
                                const AppIcon(Symbols.lock_rounded, fill: 1, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  label,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: .w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
