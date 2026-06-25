import 'package:flutter/material.dart';

import '../../theme/drop_theme.dart';

class ReasoningAccordion extends StatefulWidget {
  const ReasoningAccordion({
    super.key,
    required this.reasoning,
    this.isStreamingReasoning = false,
    this.forceExpanded = false,
    this.autoCollapseOnContent = false,
  });

  final String reasoning;
  final bool isStreamingReasoning;
  final bool forceExpanded;
  final bool autoCollapseOnContent;

  @override
  State<ReasoningAccordion> createState() => _ReasoningAccordionState();
}

class _ReasoningAccordionState extends State<ReasoningAccordion> {
  bool _expanded = false;
  bool _userToggled = false;

  @override
  void didUpdateWidget(ReasoningAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isStreamingReasoning) {
      _expanded = true;
      _userToggled = false;
    } else if (widget.autoCollapseOnContent && oldWidget.isStreamingReasoning) {
      if (!_userToggled) _expanded = false;
    } else if (widget.forceExpanded) {
      _expanded = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.isStreamingReasoning || widget.forceExpanded;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reasoning.trim().isEmpty && !widget.isStreamingReasoning) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = DropColors.muted(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => setState(() {
            _userToggled = true;
            _expanded = !_expanded;
          }),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(color: muted.withValues(alpha: 0.5), width: 2),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 14,
                      color: muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.isStreamingReasoning
                            ? 'RAGIONAMENTO...'
                            : 'RAGIONAMENTO',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              letterSpacing: 1,
                              color: muted,
                            ),
                      ),
                    ),
                    if (widget.isStreamingReasoning)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: muted,
                        ),
                      )
                    else
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: muted,
                      ),
                  ],
                ),
                if (_expanded || widget.isStreamingReasoning) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.reasoning.isEmpty && widget.isStreamingReasoning
                        ? '...'
                        : widget.reasoning,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                          color: muted.withValues(alpha: 0.85),
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
