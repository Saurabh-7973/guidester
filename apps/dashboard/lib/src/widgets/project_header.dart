import 'package:flutter/material.dart';

import '../models/comment_status.dart';
import '../models/workflow.dart';
import '../screens/projects_screen.dart' show InitialBadge;
import '../theme/tokens.dart';
import 'controls.dart';
import 'guides.dart';

/// Spec §4: breadcrumb, 48/700 title, meta row, learn card, status tabs.
class ProjectHeader extends StatelessWidget {
  const ProjectHeader({
    super.key,
    required this.projectName,
    required this.createdBy,
    required this.collaborators,
    required this.commentCount,
    required this.status,
    required this.counts,
    required this.onStatusSelected,
    this.onLearn,
    this.board,
  });

  final String projectName;
  final String createdBy;
  final int collaborators;

  /// Drives whether the learn card is still worth its space.
  final int commentCount;

  final CommentStatus status;
  final Map<CommentStatus, int> counts;
  final ValueChanged<CommentStatus> onStatusSelected;

  /// The counts a developer opens the board to ask for. Null while loading.
  final Board? board;
  final ValueChanged<String>? onLearn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 34),
        Row(
          children: [
            Text('Projects', style: T.supporting.copyWith(color: T.text3)),
            const Icon(Icons.chevron_right, size: 14, color: T.text3),
            Flexible(
              child: Text(
                projectName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.supporting.copyWith(color: T.text3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(projectName, style: T.title),
        const SizedBox(height: 20),
        _MetaRow(createdBy: createdBy, collaborators: collaborators),
        if (board != null) ...[
          const SizedBox(height: 22),
          _BoardStrip(board: board!),
        ],
        // §4: hide the learn card once the project has 3+ comments. It is
        // scaffolding for an empty project, not furniture for a full one.
        if (commentCount < 3) ...[
          const SizedBox(height: 45),
          _LearnCard(onLearn: onLearn),
        ],
        const SizedBox(height: 40),
        _StatusTabs(
          status: status,
          counts: counts,
          onSelected: onStatusSelected,
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.createdBy, required this.collaborators});

  final String createdBy;
  final int collaborators;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InitialBadge(name: createdBy),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Created by $createdBy',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.ui,
          ),
        ),
        // §4: the collaborator count renders only when there is one.
        // "0 Collaborators" advertises an empty feature.
        if (collaborators > 0) ...[
          const SizedBox(width: 16),
          Container(width: 1, height: 16, color: T.line),
          const SizedBox(width: 16),
          const Icon(Icons.people_outline, size: 16, color: T.text1),
          const SizedBox(width: 8),
          Text(
            collaborators == 1
                ? '1 Collaborator'
                : '$collaborators Collaborators',
            style: T.ui,
          ),
        ],
      ],
    );
  }
}

class _LearnCard extends StatelessWidget {
  const _LearnCard({required this.onLearn});

  final ValueChanged<String>? onLearn;

  /// The frame's "How to share with clients" is "How to invite testers":
  /// there is no client sharing, and inviting testers is what the second row
  /// is for.
  static const List<Guide> _rows = [Guide.leaveComment, Guide.inviteTesters];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: T.surface1,
        borderRadius: BorderRadius.circular(T.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LEARN HOW TO USE GUIDESTER', style: T.meta),
          const SizedBox(height: 14),
          for (var i = 0; i < _rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 20),
            Semantics(
              button: true,
              child: InkWell(
                onTap: () {
                  onLearn?.call(_rows[i].title);
                  _rows[i].show(context);
                },
                child: Row(
                  children: [
                    const Icon(Icons.play_arrow, size: 16, color: T.accent),
                    const SizedBox(width: 12),
                    Text(_rows[i].title, style: T.body),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// §4/§5: icon plus label, active in `--teal` with a 2px teal underline.
///
/// Teal is the only status colour in the system and appears nowhere else;
/// `--accent` is for actions. Counts render in brackets, in the tab's own
/// colour.
class _StatusTabs extends StatelessWidget {
  const _StatusTabs({
    required this.status,
    required this.counts,
    required this.onSelected,
  });

  final CommentStatus status;
  final Map<CommentStatus, int> counts;
  final ValueChanged<CommentStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final s in CommentStatus.values) ...[
          _Tab(
            status: s,
            active: s == status,
            count: counts[s],
            onTap: () => onSelected(s),
          ),
          if (s != CommentStatus.values.last) const SizedBox(width: 28),
        ],
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.status,
    required this.active,
    required this.count,
    required this.onTap,
  });

  final CommentStatus status;
  final bool active;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = active ? T.teal : T.text3;
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(status.icon, size: 16, color: colour),
                  const SizedBox(width: 8),
                  Text(
                    count == null ? status.label : '${status.label} [$count]',
                    style: T.ui.copyWith(color: colour),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(height: 2, color: active ? T.teal : T.page),
            ],
          ),
        ),
      ),
    );
  }
}

/// §4's empty state. "tap", not "click" — the tester is on a phone.
/// When the SDK last reached this project, and on what.
class LastLaunch {
  const LastLaunch({required this.at, this.device});

  final DateTime at;
  final String? device;

  String describe(DateTime now) {
    final d = now.difference(at);
    final String when;
    if (d.inMinutes < 1) {
      when = 'just now';
    } else if (d.inMinutes < 60) {
      when = d.inMinutes == 1 ? '1 minute ago' : '${d.inMinutes} minutes ago';
    } else if (d.inHours < 24) {
      when = d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
    } else {
      when = d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago';
    }
    return device == null
        ? 'Last launch $when'
        : 'Last launch $when on $device';
  }
}

/// A project nobody has commented on yet (§5.6 row 9). Whether the SDK has
/// ever reached it is what separates "no comments yet" from "the install is
/// not working", so it says which, when it can find out.
class ProjectEmptyState extends StatefulWidget {
  const ProjectEmptyState({super.key, this.lastLaunch, this.onSetup});

  final Future<LastLaunch?> Function()? lastLaunch;
  final VoidCallback? onSetup;

  @override
  State<ProjectEmptyState> createState() => _ProjectEmptyStateState();
}

class _ProjectEmptyStateState extends State<ProjectEmptyState> {
  late final Future<LastLaunch?>? _launch = widget.lastLaunch?.call();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 41),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('No comments left yet', style: T.body),
          const SizedBox(height: 17),
          Row(
            children: [
              Text(
                'Open the app and tap ',
                style: T.ui.copyWith(color: T.text3),
              ),
              const Icon(Icons.mode_comment_outlined, size: 15, color: T.text3),
              Text(' to test it out', style: T.ui.copyWith(color: T.text3)),
            ],
          ),
          if (_launch != null)
            FutureBuilder<LastLaunch?>(
              future: _launch,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done ||
                    snap.hasError) {
                  return const SizedBox.shrink();
                }
                final launch = snap.data;
                if (launch != null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 14,
                          color: T.green,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            launch.describe(DateTime.now()),
                            style: T.supporting.copyWith(color: T.text2),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No launch seen yet. A test build with this '
                        "project's key reports itself when it opens.",
                        style: T.supporting.copyWith(color: T.amber),
                      ),
                      if (widget.onSetup != null) ...[
                        const SizedBox(height: 12),
                        GButton(
                          label: 'Open setup',
                          kind: GButtonKind.secondary,
                          onPressed: widget.onSetup,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The four numbers the spreadsheet could not produce without reading it.
///
/// Not a dashboard — a strip. "Fixed, not verified" is first because it is the
/// one that costs a release, and it is invisible in any tool that keeps a
/// single status.
class _BoardStrip extends StatelessWidget {
  const _BoardStrip({required this.board});

  final Board board;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 28,
      runSpacing: 12,
      children: [
        _Stat(
          value: board.fixedNotVerified,
          label: 'fixed, not verified',
          highlight: board.fixedNotVerified > 0,
        ),
        _Stat(value: board.reportedToday, label: 'reported today'),
        _Stat(value: board.reportedThisWeek, label: 'this week'),
        _Stat(
          value: board.blocked,
          label: board.blockedBy.isEmpty
              ? 'blocked'
              : 'blocked · ${_topBlocker(board)}',
        ),
      ],
    );
  }

  static String _topBlocker(Board board) {
    final top = board.blockedBy.entries.reduce(
      (a, b) => b.value > a.value ? b : a,
    );
    return '${BlockedOn.label(top.key)} ${top.value}';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final int value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$value',
          style: T.heading.copyWith(color: highlight ? T.amber : T.text1),
        ),
        const SizedBox(width: 6),
        Text(label, style: T.meta),
      ],
    );
  }
}
