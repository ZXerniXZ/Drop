import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';

/// Swipe sulla card: a destra condividi, a sinistra elimina.
/// Lo swipe breve torna al posto; oltre la soglia, o con un flick, parte l'azione.
class NoteSwipeActions extends StatefulWidget {
  const NoteSwipeActions({
    super.key,
    required this.child,
    required this.onShare,
    required this.onDelete,
    required this.confirmDelete,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final Future<bool> Function() confirmDelete;
  final bool enabled;

  @override
  State<NoteSwipeActions> createState() => _NoteSwipeActionsState();
}

class _NoteSwipeActionsState extends State<NoteSwipeActions>
    with SingleTickerProviderStateMixin {
  static const _threshold = 88.0;
  static const _limit = 132.0;
  static const _flick = 900.0;

  late final AnimationController _motion;
  double _offset = 0;
  double _open = 1;
  bool _busy = false;
  bool _armed = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: DropMotion.medium);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  void _setArmed(bool next) {
    if (next == _armed) return;
    _armed = next;
    if (next) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _onDrag(DragUpdateDetails details) {
    if (_busy || !widget.enabled) return;
    final next = (_offset + details.delta.dx).clamp(-_limit, _limit);
    _setArmed(next.abs() >= _threshold);
    setState(() => _offset = next);
  }

  Future<void> _onRelease(DragEndDetails details) async {
    if (_busy || !widget.enabled) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final share = _offset >= _threshold || (_offset > 8 && velocity > _flick);
    final remove =
        _offset <= -_threshold || (_offset < -8 && velocity < -_flick);

    if (remove && !share) {
      await _commitDelete();
      return;
    }
    if (share && !remove) {
      await _commitShare();
      return;
    }
    _busy = true;
    await _settle(0);
    if (!mounted) return;
    _setArmed(false);
    setState(() => _busy = false);
  }

  Future<void> _commitShare() async {
    _busy = true;
    _setArmed(true);
    await _settle(0, curve: DropMotion.spring);
    if (!mounted) return;
    _setArmed(false);
    _busy = false;
    widget.onShare();
  }

  Future<void> _commitDelete() async {
    _busy = true;
    _setArmed(true);
    final confirmed = await widget.confirmDelete();
    if (!mounted) return;
    if (!confirmed) {
      await _settle(0, curve: DropMotion.spring);
      if (!mounted) return;
      _setArmed(false);
      _busy = false;
      return;
    }

    setState(() => _leaving = true);
    final width = MediaQuery.sizeOf(context).width;
    await _settle(-width, curve: DropMotion.exit, duration: DropMotion.fast);
    if (!mounted) return;
    await _collapse();
    if (!mounted) return;
    widget.onDelete();
  }

  Future<void> _settle(
    double target, {
    Curve curve = DropMotion.standard,
    Duration duration = DropMotion.medium,
  }) async {
    final begin = _offset;
    if ((begin - target).abs() < 0.5) {
      if (mounted) setState(() => _offset = target);
      return;
    }
    _motion.duration = duration;
    void listener() {
      if (!mounted) return;
      final t = curve.transform(_motion.value);
      setState(() => _offset = begin + (target - begin) * t);
    }

    _motion.addListener(listener);
    try {
      await _motion.forward(from: 0);
    } finally {
      _motion.removeListener(listener);
    }
    if (mounted) setState(() => _offset = target);
  }

  Future<void> _collapse() async {
    _motion.duration = DropMotion.medium;
    void listener() {
      if (!mounted) return;
      final t = DropMotion.exit.transform(_motion.value);
      setState(() => _open = 1 - t);
    }

    _motion.addListener(listener);
    try {
      await _motion.forward(from: 0);
    } finally {
      _motion.removeListener(listener);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final sharing = _offset >= 0;
    final progress = (_offset.abs() / _threshold).clamp(0.0, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actionColor = sharing
        ? (isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B))
        : DropColors.recordRed;
    final actionInk = sharing && isDark ? Colors.black : Colors.white;
    final iconScale =
        Curves.easeOutBack.transform(progress).clamp(0.0, 1.15);
    final labelOpacity = ((progress - 0.38) / 0.62).clamp(0.0, 1.0);
    final enterShift = (1 - progress) * 16;

    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: _open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: GestureDetector(
            onHorizontalDragUpdate: _onDrag,
            onHorizontalDragEnd: (details) => _onRelease(details),
            onHorizontalDragCancel: () {
              if (_busy) return;
              _busy = true;
              _settle(0).whenComplete(() {
                if (!mounted) return;
                _setArmed(false);
                setState(() => _busy = false);
              });
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: actionColor,
                    child: Align(
                      alignment: sharing
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 26),
                        child: Transform.translate(
                          offset: Offset(
                            sharing ? -enterShift : enterShift,
                            0,
                          ),
                          child: Opacity(
                            opacity: Curves.easeOut.transform(progress),
                            child: Transform.scale(
                              scale: iconScale,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    sharing
                                        ? Icons.ios_share
                                        : (_armed
                                            ? Icons.delete
                                            : Icons.delete_outline),
                                    color: actionInk,
                                    size: 22,
                                  ),
                                  const SizedBox(height: 6),
                                  Opacity(
                                    opacity: labelOpacity,
                                    child: Text(
                                      sharing ? 'CONDIVIDI' : 'ELIMINA',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: actionInk,
                                            fontSize: 9,
                                            letterSpacing: 0.8,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
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
                Transform.translate(
                  offset: Offset(_offset, 0),
                  child: Opacity(
                    opacity: _leaving
                        ? (1 - (_offset.abs() / 420).clamp(0.0, 1.0))
                        : 1,
                    child: IgnorePointer(
                      ignoring: _offset.abs() > 1 || _busy,
                      child: widget.child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
