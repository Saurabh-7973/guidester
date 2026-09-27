import 'package:flutter/material.dart';

import '../models/comment_status.dart';
import '../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final CommentStatus status;

  Color get _color => switch (status) {
    CommentStatus.open => AppTheme.statusOpen,
    CommentStatus.inProgress => AppTheme.statusInProgress,
    CommentStatus.resolved => AppTheme.statusResolved,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Relative time, rounded down. Absolute timestamps are in the detail pane.
String relativeTime(DateTime then, {DateTime? now}) {
  final delta = (now ?? DateTime.now()).difference(then);
  if (delta.inSeconds < 60) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  return '${(delta.inDays / 7).floor()}w ago';
}
