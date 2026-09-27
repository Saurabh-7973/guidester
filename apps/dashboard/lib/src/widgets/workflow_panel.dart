import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../models/workflow.dart';
import '../theme/tokens.dart';
import 'controls.dart';

/// The two verdicts, the blocker, the assignee, and the history.
///
/// Replaces four columns of a spreadsheet: `QA Status`, `Dev Status`,
/// `Dev Remark` and `QA Remark`. The first two disagreed and drifted; the last
/// two were append-only prose that had to be read top-to-bottom to learn the
/// current state. Here a change writes the verdict and its history together, so
/// the verdict cannot lag the note.
class WorkflowPanel extends StatelessWidget {
  const WorkflowPanel({
    super.key,
    required this.comment,
    required this.events,
    required this.blockedOnOptions,
    required this.onDevVerdict,
    required this.onTesterVerdict,
    required this.onBlockedOn,
    required this.onAssign,
    required this.onNote,
  });

  final Comment comment;
  final List<CommentEvent> events;

  /// What the picker offers. Project-configurable — the defaults are the six
  /// that hold anywhere, and a team adds its own.
  final List<String> blockedOnOptions;

  final void Function(DevVerdict, {String? build}) onDevVerdict;
  final void Function(TesterVerdict, {String? build}) onTesterVerdict;
  final ValueChanged<String?> onBlockedOn;
  final ValueChanged<String> onAssign;
  final ValueChanged<String> onNote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The one state a two-column sheet hides: shipped, unchecked.
        if (comment.fixedNotVerified) ...[
          const _NeedsVerifying(),
          const SizedBox(height: 14),
        ],

        _Row(
          label: 'Dev',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in DevVerdict.values)
                _VerdictChip(
                  label: v.label,
                  selected: comment.devVerdict == v,
                  color: devVerdictColor(v),
                  onTap: () => onDevVerdict(v),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Row(
          label: 'Tester',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in TesterVerdict.values)
                _VerdictChip(
                  label: v.label,
                  selected: comment.testerVerdict == v,
                  color: testerVerdictColor(v),
                  onTap: () => onTesterVerdict(v),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Row(
          label: 'Blocked on',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _VerdictChip(
                label: 'Nothing',
                selected: comment.blockedOn == null,
                color: T.text2,
                onTap: () => onBlockedOn(null),
              ),
              for (final option in blockedOnOptions)
                _VerdictChip(
                  label: BlockedOn.label(option),
                  selected: comment.blockedOn == option,
                  color: T.red,
                  onTap: () => onBlockedOn(option),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Row(
          label: 'Assignee',
          child: _AssigneeField(current: comment.assignee, onAssign: onAssign),
        ),
        const SizedBox(height: 12),
        _Row(
          label: 'Builds',
          child: _Builds(comment: comment),
        ),

        const SizedBox(height: 14),
        Container(height: 1, color: T.line),
        const SizedBox(height: 12),

        Text('History', style: T.ui.copyWith(color: T.text3)),
        const SizedBox(height: 12),
        if (events.isEmpty)
          Text(
            'Nothing yet. Every verdict change lands here.',
            style: T.supporting.copyWith(color: T.text3),
          )
        else
          _History(events: events),

        const SizedBox(height: 14),
        _NoteField(onNote: onNote),
      ],
    );
  }
}

/// The board's whole reason for existing, stated on the row it applies to.
class _NeedsVerifying extends StatelessWidget {
  const _NeedsVerifying();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(T.rControl),
        border: Border.all(color: T.amber),
      ),
      child: Row(
        children: [
          const Icon(Icons.pending_outlined, size: 16, color: T.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Fixed, not verified. The tester has not retested this.',
              style: T.supporting.copyWith(color: T.amber),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(label, style: T.supporting.copyWith(color: T.text3)),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _VerdictChip extends StatelessWidget {
  const _VerdictChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.rPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? T.surface3 : T.page,
            borderRadius: BorderRadius.circular(T.rPill),
            border: Border.all(color: selected ? color : T.line),
          ),
          child: Text(
            label,
            style: T.supporting.copyWith(
              fontSize: 12,
              color: selected ? color : T.text3,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssigneeField extends StatefulWidget {
  const _AssigneeField({required this.current, required this.onAssign});

  final String? current;
  final ValueChanged<String> onAssign;

  @override
  State<_AssigneeField> createState() => _AssigneeFieldState();
}

class _AssigneeFieldState extends State<_AssigneeField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.current ?? '',
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 220 where there is room; less on a phone, never more.
        Flexible(
          child: SizedBox(
            width: 220,
            child: GField(
              controller: _c,
              hint: 'Unassigned',
              onSubmitted: widget.onAssign,
            ),
          ),
        ),
        const SizedBox(width: 10),
        GButtonOutlined(
          label: 'Assign',
          onPressed: () => widget.onAssign(_c.text.trim()),
        ),
      ],
    );
  }
}

/// Found / fixed / verified. The first is never typed — the SDK sends it.
class _Builds extends StatelessWidget {
  const _Builds({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _Build(label: 'Found', value: comment.foundInBuild),
        _Build(label: 'Fixed', value: comment.fixedInBuild),
        _Build(label: 'Verified', value: comment.verifiedInBuild),
        if (comment.environment != null)
          _Build(label: 'Env', value: comment.environment),
      ],
    );
  }
}

class _Build extends StatelessWidget {
  const _Build({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: T.supporting.copyWith(color: T.text3)),
        Text(
          value ?? '—',
          style: T.supporting.copyWith(
            color: value == null ? T.text3 : T.text1,
            fontFamily: T.mono,
          ),
        ),
      ],
    );
  }
}

/// One line of what used to be `"24/06 : Fixed\n30/07 : Pls Recheck"`.
class _EventLine extends StatelessWidget {
  const _EventLine({required this.event});

  final CommentEvent event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              _date(event.at),
              style: T.supporting.copyWith(color: T.text3, fontSize: 12),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.summary, style: T.supporting),
                if (event.body != null && event.kind != 'commented')
                  Text(
                    event.body!,
                    style: T.supporting.copyWith(color: T.text2),
                  ),
                if (event.actor != null)
                  Text(
                    event.actor!,
                    style: T.supporting.copyWith(color: T.text3, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime at) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${at.day} ${months[at.month - 1]}';
  }
}

class _NoteField extends StatefulWidget {
  const _NoteField({required this.onNote});

  final ValueChanged<String> onNote;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _send() {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    widget.onNote(text);
    _c.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GField(
            controller: _c,
            hint: 'Add a note',
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 10),
        GButton(label: 'Add', onPressed: _send),
      ],
    );
  }
}

/// The latest few events, and the rest on request. A comment with a long
/// history would otherwise push the pane into a scroll on every visit.
class _History extends StatefulWidget {
  const _History({required this.events});

  final List<CommentEvent> events;

  static const int shown = 3;

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final events = widget.events;
    final hidden = events.length - _History.shown;
    final visible = _all || hidden <= 0
        ? events
        : events.sublist(events.length - _History.shown);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in visible) _EventLine(event: e),
        if (hidden > 0)
          InkWell(
            onTap: () => setState(() => _all = !_all),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _all ? 'Show fewer' : 'Show all ${events.length}',
                style: T.supporting.copyWith(color: T.accentText),
              ),
            ),
          ),
      ],
    );
  }
}
