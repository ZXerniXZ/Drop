import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/transcript_segment.dart';
import '../../theme/drop_motion.dart';
import '../../theme/drop_theme.dart';

/// Trascrizione sincronizzata con l'audio: la frase in riproduzione viene
/// evidenziata e, al suo interno, le parole gia' pronunciate.
class KaraokeTranscript extends StatefulWidget {
  const KaraokeTranscript({
    super.key,
    required this.segments,
    required this.position,
    required this.onSeek,
  });

  final List<TranscriptSegment> segments;
  final Duration position;
  final ValueChanged<Duration> onSeek;

  @override
  State<KaraokeTranscript> createState() => _KaraokeTranscriptState();
}

class _KaraokeTranscriptState extends State<KaraokeTranscript> {
  static const _manualScrollPause = Duration(seconds: 5);

  final ScrollController _scrollController = ScrollController();
  late List<GlobalKey> _keys;
  int _activeIndex = -1;
  Timer? _resumeAutoScroll;
  bool _autoScrollEnabled = true;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.segments.length, (_) => GlobalKey());
    _activeIndex = TranscriptSegment.indexAt(widget.segments, widget.position);
  }

  @override
  void didUpdateWidget(KaraokeTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.segments.length != widget.segments.length) {
      _keys = List.generate(widget.segments.length, (_) => GlobalKey());
    }

    final index = TranscriptSegment.indexAt(widget.segments, widget.position);
    if (index != _activeIndex) {
      _activeIndex = index;
      if (_autoScrollEnabled) _scrollToActive();
    }
  }

  @override
  void dispose() {
    _resumeAutoScroll?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActive() {
    // Rimandato a fine frame: quando l'indice cambia durante il rebuild la
    // riga di destinazione non ha ancora la sua posizione definitiva.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_activeIndex < 0 || _activeIndex >= _keys.length) return;
      final target = _keys[_activeIndex].currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.3,
        duration: DropMotion.medium,
        curve: DropMotion.standard,
      );
    });
  }

  /// Lo scorrimento manuale ha la precedenza: l'inseguimento riprende solo
  /// dopo una pausa, altrimenti l'utente non riuscirebbe a leggere altrove.
  void _onManualScroll() {
    _resumeAutoScroll?.cancel();
    if (_autoScrollEnabled) setState(() => _autoScrollEnabled = false);
    _resumeAutoScroll = Timer(_manualScrollPause, () {
      if (!mounted) return;
      setState(() => _autoScrollEnabled = true);
      _scrollToActive();
    });
  }

  static String _timeLabel(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollUpdateNotification>(
          onNotification: (notification) {
            // dragDetails e' presente solo quando scorre l'utente, cosi'
            // l'inseguimento automatico non disattiva se stesso.
            if (notification.dragDetails != null) _onManualScroll();
            return false;
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.segments.length; i++)
                  _SegmentRow(
                    key: _keys[i],
                    segment: widget.segments[i],
                    isActive: i == _activeIndex,
                    position: widget.position,
                    timeLabel: _timeLabel(widget.segments[i].start),
                    onTap: () => widget.onSeek(widget.segments[i].start),
                  ),
              ],
            ),
          ),
        ),
        if (!_autoScrollEnabled)
          Positioned(
            right: 0,
            bottom: 4,
            child: _FollowButton(
              onTap: () {
                _resumeAutoScroll?.cancel();
                setState(() => _autoScrollEnabled = true);
                _scrollToActive();
              },
            ),
          ),
      ],
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    super.key,
    required this.segment,
    required this.isActive,
    required this.position,
    required this.timeLabel,
    required this.onTap,
  });

  final TranscriptSegment segment;
  final bool isActive;
  final Duration position;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spokenColor = theme.colorScheme.onSurface;
    final pendingColor = DropColors.muted(context).withValues(alpha: 0.55);

    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 15,
      height: 1.5,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: DropMotion.fast,
        curve: DropMotion.standard,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? DropColors.recordRed.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: isActive ? DropColors.recordRed : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              timeLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                letterSpacing: 0.4,
                color: isActive
                    ? DropColors.recordRed
                    : DropColors.muted(context).withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            _buildText(context, baseStyle, spokenColor, pendingColor),
          ],
        ),
      ),
    );
  }

  Widget _buildText(
    BuildContext context,
    TextStyle? baseStyle,
    Color spokenColor,
    Color pendingColor,
  ) {
    // Senza tempi per parola resta l'evidenziazione della sola frase.
    if (!isActive || segment.words.isEmpty) {
      return Text(
        segment.text,
        style: baseStyle?.copyWith(
          color: isActive ? spokenColor : pendingColor,
          fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
        ),
      );
    }

    final activeWord = segment.activeWordIndex(position);
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          for (var i = 0; i < segment.words.length; i++)
            TextSpan(
              text: i == 0 ? segment.words[i].text : ' ${segment.words[i].text}',
              style: TextStyle(
                color: i <= activeWord ? spokenColor : pendingColor,
                fontWeight:
                    i == activeWord ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DropColors.recordRed,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.vertical_align_center, size: 14, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Segui audio',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
