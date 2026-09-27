import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../theme/tokens.dart';

/// One comment in the list. Spec §5.
///
/// **One component, two states, not two components.** `Home__8_`'s flat rows
/// are the resting state; `Group_11`'s lifted card is the same row on hover and
/// on keyboard focus — that is what its `Mark In Progress | Resolve` actions
/// and raised surface are showing.
class CommentRow extends StatefulWidget {
  const CommentRow({
    super.key,
    required this.comment,
    required this.onTap,
    this.onMarkInProgress,
    this.onResolve,
    this.duplicateCount = 0,
    this.collapsed = false,
    this.selected = false,
  });

  final Comment comment;
  final VoidCallback onTap;

  /// Shown only in the raised state, top-right.
  final VoidCallback? onMarkInProgress;
  final VoidCallback? onResolve;

  /// Open comments sharing this row's screen *and* impact.
  final int duplicateCount;

  /// True for every row of a duplicate group **except the first**.
  ///
  /// §5 collapses "the lower row", not the group: the first occurrence keeps
  /// its full meta line, and the ones under it collapse to the merge line.
  /// Collapsing all of them would delete impact, tester and device from every
  /// row of the most-reported bug on the board — the opposite of the point.
  final bool collapsed;

  final bool selected;

  @override
  State<CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<CommentRow> {
  bool _hovered = false;
  bool _focused = false;

  bool get _raised => _hovered || _focused || widget.selected;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        onFocusChange: (has) => setState(() => _focused = has),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            button: true,
            label: widget.comment.body,
            child: _raised ? _RaisedRow(row: widget) : _FlatRow(row: widget),
          ),
        ),
      ),
    );
  }
}

/// Rest: height 98, a full-width `--line` divider, no surface of its own.
class _FlatRow extends StatelessWidget {
  const _FlatRow({required this.row});

  final CommentRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 98,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: T.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(
                  row.comment.body,
                  style: T.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 22 - 8),
                // §5: "the lower row collapses to" the merge line — it
                // replaces the meta row rather than being added beneath it,
                // which is also what keeps the row at its specified 98.
                if (row.collapsed && row.duplicateCount >= 2)
                  _DuplicateLine(count: row.duplicateCount)
                else
                  _MetaRow(comment: row.comment),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.only(top: 34),
            child: Icon(row.comment.status.icon, size: 18, color: T.text3),
          ),
        ],
      ),
    );
  }
}

/// Hover and focus: `--surface-3`, radius 12, padding 20, no divider. The
/// screen tag moves to the top as an amber chip and the actions appear.
class _RaisedRow extends StatelessWidget {
  const _RaisedRow({required this.row});

  final CommentRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: T.surface3,
        borderRadius: BorderRadius.circular(T.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The chip gives way before the actions do: a long screen name
          // ellipsizes, and a narrow row shows the actions as icons.
          LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _ScreenTagChip(screenName: row.comment.screenName),
                  ),
                ),
                const SizedBox(width: 12),
                if (row.onMarkInProgress != null || row.onResolve != null)
                  _RowActions(
                    onMarkInProgress: row.onMarkInProgress,
                    onResolve: row.onResolve,
                    compact: constraints.maxWidth < 340,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            row.comment.body,
            style: T.cardBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          // The screen tag has moved to the chip above, so it does not repeat
          // here — the rest of the meta row is unchanged, same field order.
          if (row.collapsed && row.duplicateCount >= 2)
            _DuplicateLine(count: row.duplicateCount)
          else
            _MetaRow(comment: row.comment, includeScreen: false),
        ],
      ),
    );
  }
}

/// `CONNECTION SCREEN • BLOCKED • PRIYA • PIXEL 7 • TEXT SCALE 2.0 • 5 MINS AGO`
///
/// Field order is fixed on purpose: impact sits second so the eye finds it in
/// the same place down the whole column. Impact is the only coloured field.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.comment, this.includeScreen = true});

  final Comment comment;
  final bool includeScreen;

  @override
  Widget build(BuildContext context) {
    final parts = <({String text, Color color})>[
      if (includeScreen) (text: comment.screenName, color: T.text3),
      (text: comment.impact.label, color: comment.impact.color),
      // BY GUEST was the gap this project opened by asking to close it.
      (text: (comment.testerName ?? 'Unknown').toUpperCase(), color: T.text3),
      for (final field in _context(comment)) (text: field, color: T.text3),
      (text: _ago(comment.createdAt), color: T.text3),
    ];

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          Text(parts[i].text, style: T.meta.copyWith(color: parts[i].color)),
          if (i != parts.length - 1)
            Text(' • ', style: T.meta.copyWith(color: T.text3)),
        ],
      ],
    );
  }

  /// Device, then any context field that is **off-default**.
  ///
  /// A normal device prints nothing extra. The font-scale comment and the
  /// font-scale setting belong on the same line — burying that in a collapsed
  /// panel puts the single most useful fact about a UI bug one click away from
  /// the list you actually scan.
  static List<String> _context(Comment c) {
    final out = <String>[];
    final device = c.deviceModel;
    if (device != null && device.isNotEmpty) out.add(device.toUpperCase());

    final scale = _num(c.context['text_scale']);
    if (scale != null && (scale - 1.0).abs() > 0.01) {
      out.add('TEXT SCALE ${scale.toStringAsFixed(1)}');
    }
    if (c.context['brightness']?.toString().toLowerCase() == 'dark') {
      out.add('DARK MODE');
    }
    if (c.context['orientation']?.toString().toLowerCase() == 'landscape') {
      out.add('LANDSCAPE');
    }
    if (c.context['is_physical_device'] == false) out.add('EMULATOR');
    return out;
  }

  static double? _num(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static String _ago(DateTime then) {
    final d = DateTime.now().difference(then);
    if (d.inMinutes < 1) return 'JUST NOW';
    if (d.inMinutes < 60) return '${d.inMinutes} MINS AGO';
    if (d.inHours < 24) return '${d.inHours} HOURS AGO';
    if (d.inDays < 30) return '${d.inDays} DAYS AGO';
    return '${(d.inDays / 30).floor()} MONTHS AGO';
  }
}

class _ScreenTagChip extends StatelessWidget {
  const _ScreenTagChip({required this.screenName});

  final String screenName;

  /// `--amber` on `--amber-ground`. The one place a screen tag is coloured;
  /// in the flat row it is muted like every other meta field.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: T.amberGround,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        screenName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: T.meta.copyWith(color: T.amber),
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.onMarkInProgress,
    required this.onResolve,
    this.compact = false,
  });

  final VoidCallback? onMarkInProgress;
  final VoidCallback? onResolve;

  /// Icons only, labels in tooltips and for screen readers.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onMarkInProgress != null)
          _Action(
            icon: Icons.timelapse,
            label: 'Mark In Progress',
            onTap: onMarkInProgress!,
            compact: compact,
          ),
        if (onMarkInProgress != null && onResolve != null)
          Container(
            width: 1,
            height: 16,
            color: T.line,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
        if (onResolve != null)
          _Action(
            icon: Icons.check_circle_outline,
            label: 'Resolve',
            onTap: onResolve!,
            compact: compact,
          ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final body = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: compact ? 18 : 16, color: T.text3),
        if (!compact) ...[
          const SizedBox(width: 6),
          Text(label, style: T.ui.copyWith(color: T.text3)),
        ],
      ],
    );
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: compact ? label : '',
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: EdgeInsets.all(compact ? 6 : 0), child: body),
        ),
      ),
    );
  }
}

class _DuplicateLine extends StatelessWidget {
  const _DuplicateLine({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$count similar on this screen · merge',
      style: T.supporting.copyWith(fontSize: 12, color: T.text3),
    );
  }
}
