import 'package:flutter/material.dart';

import '../../theme/drop_theme.dart';

class ReasoningAccordion extends StatefulWidget {
  const ReasoningAccordion({
    super.key,
    required this.reasoning,
    this.isStreamingReasoning = false,
    this.autoCollapseOnContent = false,
  });

  final String reasoning;
  final bool isStreamingReasoning;
  final bool autoCollapseOnContent;

  @override
  State<ReasoningAccordion> createState() => _ReasoningAccordionState();
}

class _ReasoningAccordionState extends State<ReasoningAccordion> {
  bool _expanded = false;
  bool _userToggled = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isStreamingReasoning;
  }

  @override
  void didUpdateWidget(ReasoningAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isStreamingReasoning) {
      _expanded = true;
      _userToggled = false;
    } else if (widget.autoCollapseOnContent && oldWidget.isStreamingReasoning) {
      if (!_userToggled) _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reasoning.trim().isEmpty && !widget.isStreamingReasoning) {
      return const SizedBox.shrink();
    }

    final muted = DropColors.muted(context);
    final showBody = _expanded || widget.isStreamingReasoning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() {
              _userToggled = true;
              _expanded = !_expanded;
            }),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Text(
                  _expanded ? '−' : '+',
                  style: TextStyle(
                    fontSize: 14,
                    color: muted,
                    fontWeight: FontWeight.w300,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'ragionamento',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.3,
                        color: muted,
                        fontWeight: FontWeight.w400,
                      ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: showBody
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 14,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                width: 1,
                                color: muted.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.reasoning.isEmpty &&
                                      widget.isStreamingReasoning
                                  ? '...'
                                  : widget.reasoning,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontSize: 11,
                                    height: 1.45,
                                    color: muted.withValues(alpha: 0.75),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}
