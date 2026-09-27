import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../theme/tokens.dart';

/// The rail, collapsed to a 56px strip.
///
/// Between 720 and 1099 you are reading one comment — screenshot, pin, context
/// — not scanning a rail, so the pane wins the width. The strip keeps position
/// visible: where you are in the list, and that three below you are blocked,
/// without spending width on text you would only skim.
///
/// Navigation never depends on it. `j`/`k` and Prev/Next move the selection
/// whether the strip is here, expanded, or gone entirely.
class CommentStrip extends StatelessWidget {
  const CommentStrip({
    super.key,
    required this.comments,
    required this.selected,
    required this.onSelect,
    required this.onExpand,
  });

  final List<Comment> comments;
  final Comment? selected;
  final ValueChanged<Comment> onSelect;

  /// Opens the full 516 rail over the pane.
  final VoidCallback onExpand;

  static const double width = 56;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        children: [
          Semantics(
            button: true,
            label: 'Expand the comment list',
            child: IconButton(
              icon: const Icon(Icons.menu, size: 18, color: T.text3),
              onPressed: onExpand,
              tooltip: 'Expand list',
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: comments.length,
              itemBuilder: (context, i) {
                final c = comments[i];
                return _StripDot(
                  comment: c,
                  selected: c.id == selected?.id,
                  onTap: () => onSelect(c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StripDot extends StatelessWidget {
  const _StripDot({
    required this.comment,
    required this.selected,
    required this.onTap,
  });

  final Comment comment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      // The strip carries no text, so the label has to. A screen reader user
      // is not served by a column of unlabelled dots.
      label: '${comment.impact.label}, ${comment.screenName}',
      child: Tooltip(
        message: '${comment.impact.label} · ${comment.screenName}',
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 32,
            child: Row(
              children: [
                // The selection bar, so position is readable at a glance.
                Container(
                  width: 2,
                  height: 32,
                  color: selected ? T.accentText : T.page,
                ),
                Expanded(
                  child: Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: comment.impact.color,
                        shape: BoxShape.circle,
                      ),
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
