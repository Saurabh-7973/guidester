import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/comment_repository.dart';
import '../models/comment.dart';
import '../models/status_report.dart';
import '../models/workflow.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/skeleton.dart';

/// A project as the status screen needs it: an id and a name.
typedef StatusProject = ({String id, String name});

/// Status, at a glance. With no [projectId], every project on one page, each
/// with whether it can ship; with one, that project's report, per team.
///
/// Built for the people who never open the board: a lead deciding whether to
/// release, a designer looking for what is theirs, a manager pasting status
/// into Slack. Everything here can be copied out as plain Markdown.
class StatusScreen extends StatefulWidget {
  const StatusScreen({
    super.key,
    required this.source,
    required this.projects,
    this.projectId,
    required this.onOpenReport,
    required this.onOpenBoard,
    this.linkFor,
    this.now,
  });

  final ReportSource source;
  final List<StatusProject> projects;
  final String? projectId;

  /// A project's report, or the overview when null.
  final ValueChanged<String?> onOpenReport;

  /// The board, at a comment when one is given.
  final void Function(String projectId, String? commentId) onOpenBoard;

  /// The shareable address of a project's report, pasted under the copy.
  final String Function(String projectId)? linkFor;

  /// The clock; a test fixes it.
  final DateTime Function()? now;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  Map<String, List<Comment>>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(StatusScreen old) {
    super.didUpdateWidget(old);
    if (old.projectId != widget.projectId) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      // Everything, once: the overview needs every project, and a report
      // opened from it then draws without another round trip.
      final data = await widget.source.reportComments();
      if (!mounted) return;
      setState(() => _data = data);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  StatusReport _reportFor(StatusProject p) => StatusReport.from(
    projectName: p.name,
    comments: _data?[p.id] ?? const [],
    now: widget.now?.call(),
  );

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Copied. Paste it into Slack, Jira, GitHub or an email.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_error != null) {
      body = _Failed(message: _error!, onRetry: _load);
    } else if (_data == null) {
      body = StatusSkeleton.rows;
    } else {
      final id = widget.projectId;
      final project = id == null
          ? null
          : widget.projects.where((p) => p.id == id).firstOrNull;
      body = id == null
          ? _Overview(
              reports: [for (final p in widget.projects) (p, _reportFor(p))],
              onOpen: (p) => widget.onOpenReport(p.id),
              onCopyAll: () => _copy(
                [
                  for (final p in widget.projects)
                    _reportFor(
                      p,
                    ).toMarkdown(link: widget.linkFor?.call(p.id), perList: 3),
                ].join('\n'),
              ),
            )
          : project == null
          ? _Failed(
              message: "This project doesn't exist or you don't have access.",
              onRetry: () => widget.onOpenReport(null),
              retryLabel: 'All projects',
            )
          : _ProjectReport(
              report: _reportFor(project),
              onBack: () => widget.onOpenReport(null),
              onOpenBoard: (commentId) =>
                  widget.onOpenBoard(project.id, commentId),
              onCopy: (r) =>
                  _copy(r.toMarkdown(link: widget.linkFor?.call(project.id))),
            );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
          // The new page fades up; the old one is simply gone. A cross-fade
          // stacked two layouts of different heights on each other.
          child: TweenAnimationBuilder<double>(
            key: ValueKey(
              '${widget.projectId}-${_data == null}-${_error != null}',
            ),
            tween: Tween(begin: 0, end: 1),
            duration: _motion(context, 240),
            curve: Curves.easeOutCubic,
            child: body,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - t)),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The status page before its numbers arrive. One placeholder from the first
/// frame to the data: Home shows it while projects load, this screen while
/// comments do, in the same place.
class StatusSkeleton extends StatelessWidget {
  const StatusSkeleton({super.key});

  static const Widget rows = Padding(
    padding: EdgeInsets.only(top: 40),
    child: BoardSkeleton(key: ValueKey('status-skeleton'), rows: 3),
  );

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1080),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 96),
        child: rows,
      ),
    ),
  );
}

/// Motion that switches off when the platform asks for less of it.
Duration _motion(BuildContext context, int ms) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false
    ? Duration.zero
    : Duration(milliseconds: ms);

Color _readinessColor(Readiness r) => switch (r) {
  Readiness.notReady => T.red,
  Readiness.verifyFirst => T.amber,
  Readiness.ready => T.green,
};

Color _stageColor(Stage s) => switch (s) {
  Stage.blocked => T.red,
  Stage.stillBroken => T.amber,
  Stage.fresh => T.text2,
  Stage.inProgress => T.teal,
  Stage.awaitingVerification => T.accentText,
  Stage.verified => T.green,
  Stage.deferred => T.text3,
  Stage.wontFix => T.borderStrong,
};

/// The order the bar is drawn in: the work still owed first, then what is
/// done, so the green grows from the right as a release comes together.
const List<Stage> _barOrder = [
  Stage.blocked,
  Stage.stillBroken,
  Stage.fresh,
  Stage.inProgress,
  Stage.awaitingVerification,
  Stage.verified,
  Stage.deferred,
  Stage.wontFix,
];

// ---------------------------------------------------------------- overview

class _Overview extends StatelessWidget {
  const _Overview({
    required this.reports,
    required this.onOpen,
    required this.onCopyAll,
  });

  final List<(StatusProject, StatusReport)> reports;
  final ValueChanged<StatusProject> onOpen;
  final VoidCallback onCopyAll;

  @override
  Widget build(BuildContext context) {
    int sum(int Function(StatusReport) f) =>
        reports.fold(0, (n, e) => n + f(e.$2));
    final blocking = sum((r) => r.blockers.length);
    int inState(Readiness r) =>
        reports.where((e) => e.$2.readiness == r).length;
    final notReady = inState(Readiness.notReady);
    final verify = inState(Readiness.verifyFirst);
    final summary = [
      if (notReady > 0) '$notReady not ready',
      if (verify > 0) '$verify waiting for QA',
      if (notReady == 0 && verify == 0) 'all clear to ship',
    ].join(', ');
    final date = reports.isEmpty
        ? StatusReport.from(projectName: '', comments: const []).dateLabel
        : reports.first.$2.dateLabel;
    return Column(
      key: const ValueKey('status-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TitleRow(
          title: 'Status',
          subtitle: reports.isEmpty
              ? 'No projects yet.'
              : '$date · ${reports.length} '
                    '${reports.length == 1 ? 'project' : 'projects'}'
                    ', $summary',
          actions: [
            if (reports.isNotEmpty)
              GButton(
                label: 'Copy all as text',
                icon: Icons.content_copy,
                kind: GButtonKind.secondary,
                onPressed: onCopyAll,
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (reports.isNotEmpty) ...[
          _MetricStrip(
            metrics: [
              _Metric('Open work', sum((r) => r.openWork)),
              _Metric('Blocking', blocking, alert: blocking > 0),
              _Metric(
                'Still broken',
                sum((r) => r.count(Stage.stillBroken)),
                alert: sum((r) => r.count(Stage.stillBroken)) > 0,
              ),
              _Metric(
                'Waiting for QA',
                sum((r) => r.count(Stage.awaitingVerification)),
              ),
              _Metric('Reported this week', sum((r) => r.reportedThisWeek)),
            ],
          ),
          const SizedBox(height: 24),
        ],
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth >= 900
                ? 3
                : c.maxWidth >= 600
                ? 2
                : 1;
            const gap = 16.0;
            final w = (c.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (i, e) in reports.indexed)
                  SizedBox(
                    width: w,
                    child: _Rise(
                      index: i,
                      child: _ProjectCard(
                        project: e.$1,
                        report: e.$2,
                        onOpen: () => onOpen(e.$1),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ProjectCard extends StatefulWidget {
  const _ProjectCard({
    required this.project,
    required this.report,
    required this.onOpen,
  });

  final StatusProject project;
  final StatusReport report;
  final VoidCallback onOpen;

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final share = r.verifiedShare;
    final hot = r.hotScreens.firstOrNull;
    return Semantics(
      button: true,
      label:
          '${widget.project.name}: ${r.readiness.label}. '
          '${r.openWork} open, ${r.blockers.length} blocking.',
      excludeSemantics: true,
      onTap: widget.onOpen,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onOpen,
          child: AnimatedContainer(
            duration: _motion(context, 160),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _hover ? T.surface2 : T.surface1,
              borderRadius: BorderRadius.circular(T.rCard),
              border: Border.all(
                color: _hover ? T.borderStrong : T.borderSubtle,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.project.name,
                        style: T.heading.copyWith(fontSize: 18),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: _hover ? T.text1 : T.text3,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ReadinessPill(readiness: r.readiness, compact: true),
                const SizedBox(height: 18),
                _StageBar(report: r, height: 8),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _Mini('open', r.openWork),
                    _Mini(
                      'blocking',
                      r.blockers.length,
                      color: r.blockers.isEmpty ? null : T.red,
                    ),
                    _Mini('for QA', r.count(Stage.awaitingVerification)),
                    _Mini.text(
                      'verified',
                      share == null ? '–' : '${(share * 100).round()}%',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  r.total == 0
                      ? 'No comments yet'
                      : hot == null
                      ? 'Nothing open'
                      : 'Most open on ${hot.$1} (${hot.$2})',
                  style: T.meta.copyWith(color: T.text3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, int value, {this.color}) : value = '$value';
  const _Mini.text(this.label, this.value) : color = null;

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: T.heading.copyWith(
            fontSize: 20,
            color: color ?? T.text1,
            fontFeatures: T.tabular,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: T.meta.copyWith(color: T.text3)),
      ],
    ),
  );
}

// ---------------------------------------------------------- project report

class _ProjectReport extends StatefulWidget {
  const _ProjectReport({
    required this.report,
    required this.onBack,
    required this.onOpenBoard,
    required this.onCopy,
  });

  final StatusReport report;
  final VoidCallback onBack;
  final ValueChanged<String?> onOpenBoard;
  final ValueChanged<StatusReport> onCopy;

  @override
  State<_ProjectReport> createState() => _ProjectReportState();
}

class _ProjectReportState extends State<_ProjectReport> {
  /// Null: every team's list, one after another.
  Lens? _lens;

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final share = r.verifiedShare;
    final oldest = r.oldestOpenDays;
    final lenses = [
      for (final l in Lens.values)
        if (r.lens(l).isNotEmpty) l,
    ];
    return Column(
      key: ValueKey('status-report-${r.projectName}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, size: 14),
            label: const Text('All projects'),
            style: TextButton.styleFrom(foregroundColor: T.text3),
          ),
        ),
        const SizedBox(height: 8),
        _TitleRow(
          title: r.projectName,
          subtitle: 'Status on ${r.dateLabel}',
          actions: [
            GButton(
              label: 'Copy report',
              icon: Icons.content_copy,
              kind: GButtonKind.secondary,
              onPressed: () => widget.onCopy(r),
            ),
            GButton(
              label: 'Open board',
              icon: Icons.view_list,
              onPressed: () => widget.onOpenBoard(null),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: _ReadinessPill(readiness: r.readiness),
        ),
        const SizedBox(height: 8),
        Text(_verdictLine(r), style: T.body.copyWith(color: T.text2)),
        const SizedBox(height: 24),
        if (r.total == 0)
          Text(
            'No comments yet. When testers report, the status shows up here.',
            style: T.body.copyWith(color: T.text3),
          )
        else ...[
          _StageBar(report: r, height: 12, legend: true),
          const SizedBox(height: 24),
          _MetricStrip(
            metrics: [
              _Metric('Open work', r.openWork),
              _Metric(
                'Blocking',
                r.blockers.length,
                alert: r.blockers.isNotEmpty,
              ),
              _Metric(
                'Still broken',
                r.count(Stage.stillBroken),
                alert: r.count(Stage.stillBroken) > 0,
              ),
              _Metric('Waiting for QA', r.count(Stage.awaitingVerification)),
              _Metric.text(
                'Verified',
                share == null ? '–' : '${(share * 100).round()}%',
              ),
              _Metric('This week', r.reportedThisWeek),
              _Metric.text(
                'Oldest open',
                oldest == null ? '–' : (oldest == 0 ? 'today' : '${oldest}d'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (context, c) {
              final side = _Breakdowns(report: r);
              final lists = _LensLists(
                report: r,
                lenses: lenses,
                selected: _lens,
                onSelect: (l) => setState(() => _lens = l),
                onOpen: widget.onOpenBoard,
              );
              if (c.maxWidth < 860) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [lists, const SizedBox(height: 32), side],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: lists),
                  const SizedBox(width: 32),
                  SizedBox(width: 280, child: side),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  /// One sentence a lead can repeat in stand-up.
  static String _verdictLine(StatusReport r) {
    if (r.total == 0) return 'Nothing reported yet.';
    final b = r.blockers.length;
    final qa = r.count(Stage.awaitingVerification);
    return switch (r.readiness) {
      Readiness.notReady =>
        '$b blocking ${b == 1 ? 'issue stops' : 'issues stop'} testers. '
            'Fix ${b == 1 ? 'it' : 'them'} before release.',
      Readiness.verifyFirst =>
        'Nothing blocking is open, but $qa '
            '${qa == 1 ? 'fix has' : 'fixes have'} not been checked by QA.',
      Readiness.ready =>
        r.openWork == 0
            ? 'Every reported issue is verified or decided.'
            : 'Nothing blocking. ${r.openWork} minor '
                  '${r.openWork == 1 ? 'issue' : 'issues'} open.',
    };
  }
}

class _LensLists extends StatelessWidget {
  const _LensLists({
    required this.report,
    required this.lenses,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });

  final StatusReport report;
  final List<Lens> lenses;
  final Lens? selected;
  final ValueChanged<Lens?> onSelect;
  final ValueChanged<String?> onOpen;

  @override
  Widget build(BuildContext context) {
    if (lenses.isEmpty) {
      return Text(
        "Nobody owes anything. That's the whole list.",
        style: T.body.copyWith(color: T.text3),
      );
    }
    final shown = selected == null ? lenses : [selected!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('By team', style: T.ui.copyWith(color: T.text3)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _LensChip(
              label: 'Everyone',
              selected: selected == null,
              onTap: () => onSelect(null),
            ),
            for (final l in lenses)
              _LensChip(
                label: '${l.label} ${report.lens(l).length}',
                selected: selected == l,
                onTap: () => onSelect(selected == l ? null : l),
              ),
          ],
        ),
        const SizedBox(height: 20),
        for (final l in shown) ...[
          _LensSection(
            lens: l,
            items: report.lens(l),
            report: report,
            onOpen: onOpen,
            limit: selected == null ? 5 : null,
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _LensSection extends StatelessWidget {
  const _LensSection({
    required this.lens,
    required this.items,
    required this.report,
    required this.onOpen,
    this.limit,
  });

  final Lens lens;
  final List<Comment> items;
  final StatusReport report;
  final ValueChanged<String?> onOpen;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final shown = limit == null ? items : items.take(limit!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(lens.label, style: T.heading.copyWith(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                lens.question,
                style: T.meta.copyWith(color: T.text3),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${items.length}',
              style: T.ui.copyWith(color: T.text3, fontFeatures: T.tabular),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: T.surface1,
            borderRadius: BorderRadius.circular(T.rCard),
            border: Border.all(color: T.borderSubtle),
          ),
          child: Column(
            children: [
              for (final (i, c) in shown.indexed) ...[
                if (i > 0) Container(height: 1, color: T.line),
                _ItemRow(
                  comment: c,
                  stage: report.stageOf(c),
                  now: report.now,
                  onTap: () => onOpen(c.id),
                ),
              ],
              if (items.length > shown.length)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '+${items.length - shown.length} more. '
                      'Pick ${lens.label} above to see all.',
                      style: T.meta.copyWith(color: T.text3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    required this.comment,
    required this.stage,
    required this.now,
    required this.onTap,
  });

  final Comment comment;
  final Stage stage;
  final DateTime now;
  final VoidCallback onTap;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final days = widget.now.difference(c.createdAt).inDays;
    final age = days <= 0 ? 'today' : '${days}d';
    final meta = [
      c.screenName,
      widget.stage.label,
      if (c.blockedOn != null && widget.stage == Stage.blocked)
        'on ${BlockedOn.label(c.blockedOn!)}',
      if (c.assignee != null && c.assignee!.isNotEmpty) c.assignee!,
      age,
    ].join(' · ');
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: _motion(context, 120),
            color: _hover ? T.surface2 : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _stageColor(widget.stage),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.body,
                        style: T.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: T.meta.copyWith(color: T.text3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  c.impact.label,
                  style: T.meta.copyWith(
                    color: c.impact.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: _motion(context, 120),
                  child: const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: T.text3,
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

class _Breakdowns extends StatelessWidget {
  const _Breakdowns({required this.report});

  final StatusReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final blocked = r.blockedBy.entries.toList()
      ..sort((a, b) => b.value - a.value);
    final people = r.byAssignee.entries.toList()
      ..sort((a, b) => b.value - a.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Breakdown(
          title: 'Waiting on',
          empty: 'Nothing blocked.',
          rows: [for (final e in blocked) (BlockedOn.label(e.key), e.value)],
          color: T.red,
        ),
        const SizedBox(height: 24),
        _Breakdown(
          title: 'Open work by person',
          empty: 'No open work.',
          rows: [for (final e in people) (e.key, e.value)],
          color: T.accentText,
        ),
        const SizedBox(height: 24),
        _Breakdown(
          title: 'Screens with most open',
          empty: 'No open work.',
          rows: r.hotScreens,
          color: T.amber,
        ),
      ],
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.title,
    required this.empty,
    required this.rows,
    required this.color,
  });

  final String title;
  final String empty;
  final List<(String, int)> rows;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final top = rows.isEmpty
        ? 1
        : rows.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: T.ui.copyWith(color: T.text3)),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Text(empty, style: T.meta.copyWith(color: T.text3))
        else
          for (final (name, n) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      name,
                      style: T.meta.copyWith(color: T.text2),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => Align(
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: n / top),
                          duration: _motion(context, 500),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => Container(
                            width: c.maxWidth * v,
                            height: 6,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '$n',
                      textAlign: TextAlign.right,
                      style: T.meta.copyWith(
                        color: T.text2,
                        fontFeatures: T.tabular,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

// ------------------------------------------------------------------ pieces

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: T.title),
        const SizedBox(height: 6),
        Text(subtitle, style: T.supporting.copyWith(color: T.text3)),
      ],
    );
    final buttons = Wrap(spacing: 8, runSpacing: 8, children: actions);
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < 600
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 16), buttons],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: text),
                buttons,
              ],
            ),
    );
  }
}

class _ReadinessPill extends StatelessWidget {
  const _ReadinessPill({required this.readiness, this.compact = false});

  final Readiness readiness;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = _readinessColor(readiness);
    return Semantics(
      label: readiness.label,
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(T.rPill),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Pulse(color: color, animate: readiness == Readiness.notReady),
            const SizedBox(width: 8),
            Text(
              readiness.label,
              style: (compact ? T.meta : T.ui).copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The readiness dot. It breathes when something blocks the release, the one
/// state worth drawing an eye to, and holds still otherwise.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, required this.animate});

  final Color color;
  final bool animate;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    // Three breaths, then still: enough to draw the eye on arrival without
    // nagging. A reader who asked for less motion gets none.
    final still =
        !widget.animate ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (still) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.repeat(reverse: true, count: 6);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.5 * _c.value),
            blurRadius: 8 * _c.value,
            spreadRadius: 2 * _c.value,
          ),
        ],
      ),
    ),
  );
}

class _StageBar extends StatelessWidget {
  const _StageBar({
    required this.report,
    required this.height,
    this.legend = false,
  });

  final StatusReport report;
  final double height;
  final bool legend;

  @override
  Widget build(BuildContext context) {
    final total = report.total;
    final parts = [
      for (final s in _barOrder)
        if (report.count(s) > 0) (s, report.count(s)),
    ];
    final bar = Semantics(
      label: total == 0
          ? 'No comments'
          : parts.map((p) => '${p.$2} ${p.$1.label}').join(', '),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: Container(
          height: height,
          color: T.surface3,
          child: total == 0
              ? null
              : TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: _motion(context, 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => LayoutBuilder(
                    builder: (context, c) => Row(
                      children: [
                        for (final (s, n) in parts)
                          Container(
                            width: c.maxWidth * t * n / total,
                            height: height,
                            decoration: BoxDecoration(
                              color: _stageColor(s),
                              border: const Border(
                                right: BorderSide(color: T.page, width: 1),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
    if (!legend) return bar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final (s, n) in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _stageColor(s),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${s.label} $n', style: T.meta.copyWith(color: T.text2)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _Metric {
  const _Metric(this.label, int value, {this.alert = false}) : value = '$value';
  const _Metric.text(this.label, this.value) : alert = false;

  final String label;
  final String value;
  final bool alert;
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.metrics});

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: T.surface1,
        borderRadius: BorderRadius.circular(T.rCard),
        border: Border.all(color: T.borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Wrap(
        spacing: 32,
        runSpacing: 16,
        children: [
          for (final m in metrics)
            Semantics(
              label: '${m.label}: ${m.value}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.value,
                    style: T.title.copyWith(
                      fontSize: 28,
                      color: m.alert ? T.red : T.text1,
                      fontFeatures: T.tabular,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(m.label, style: T.meta.copyWith(color: T.text3)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LensChip extends StatelessWidget {
  const _LensChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: Material(
      color: selected ? T.accentSubtle : Colors.transparent,
      borderRadius: BorderRadius.circular(T.rPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.rPill),
        child: AnimatedContainer(
          duration: _motion(context, 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(T.rPill),
            border: Border.all(color: selected ? T.accent : T.borderDefault),
          ),
          child: Text(
            label,
            style: T.meta.copyWith(
              color: selected ? T.accentText : T.text2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Cards rise into place one after another, 40 ms apart.
class _Rise extends StatelessWidget {
  const _Rise({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final total = _motion(context, 360 + 40 * index.clamp(0, 8));
    if (total == Duration.zero) return child;
    final start = (40 * index.clamp(0, 8)) / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: T.body.copyWith(color: T.text3)),
        const SizedBox(height: 16),
        GButton(
          label: retryLabel,
          kind: GButtonKind.secondary,
          onPressed: onRetry,
        ),
      ],
    ),
  );
}
