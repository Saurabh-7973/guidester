import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../widgets/controls.dart';

/// One row of §3's table.
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.total,
    required this.unread,
  });

  final String id;
  final String name;
  final String createdBy;
  final int total;

  /// The "(2 New)" half of the count.
  final int unread;
}

/// Spec §3. The centred 624 column, a three-column table, one row per project.
///
/// The nav tabs, the trailing `New project` slot and the user chip belong to
/// `AppShell`; this is only what sits under them.
class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({
    super.key,
    required this.projects,
    required this.onOpen,
    this.onNew,
    this.onSettings,
  });

  final List<ProjectSummary> projects;
  final ValueChanged<ProjectSummary> onOpen;

  /// Starts onboarding. Offered when there is nothing to open.
  final VoidCallback? onNew;

  /// A project's settings, from its row menu.
  final ValueChanged<ProjectSummary>? onSettings;

  @override
  Widget build(BuildContext context) {
    // The frame's three columns need about 560 px. Below that, "Created by"
    // goes (it is the signed-in user on every row of a solo account) and the
    // name takes the room.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Nav sits at y=61 and the header rule at y=167, measured from the
        // frame; the shell owns everything above this.
        const SizedBox(height: 55),
        _TableHeader(narrow: narrow),
        Container(height: 1, color: T.line),
        for (final p in projects)
          _ProjectRow(
            project: p,
            onOpen: onOpen,
            onSettings: onSettings,
            narrow: narrow,
          ),
        if (projects.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No projects yet', style: T.body.copyWith(color: T.text3)),
                if (onNew != null) ...[
                  const SizedBox(height: 16),
                  GButton(
                    label: 'Create your first project',
                    icon: Icons.add,
                    onPressed: onNew,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.narrow});

  final bool narrow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // Columns at x=408 / 650 / 910 in a 624-wide column: 242, 236, rest, and
          // 24 for the row menu the frame did not have.
          if (narrow)
            Expanded(
              child: Text('Name', style: T.ui.copyWith(color: T.text3)),
            )
          else ...[
            SizedBox(
              width: 242,
              child: Text('Name', style: T.ui.copyWith(color: T.text3)),
            ),
            SizedBox(
              width: 236,
              child: Text('Created by', style: T.ui.copyWith(color: T.text3)),
            ),
          ],
          Flexible(
            flex: narrow ? 0 : 1,
            child: Text(
              'Total Comments',
              style: T.ui.copyWith(color: T.text3),
              textAlign: TextAlign.right,
            ),
          ),
          // Room for each row's menu.
          const SizedBox(width: 24),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.onOpen,
    required this.narrow,
    this.onSettings,
  });

  final ValueChanged<ProjectSummary>? onSettings;

  final bool narrow;
  final ProjectSummary project;

  Widget _name() => Text(
    project.name,
    style: T.body.copyWith(fontWeight: FontWeight.w500),
    overflow: TextOverflow.ellipsis,
  );
  final ValueChanged<ProjectSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${project.name}, ${project.total} comments',
      child: InkWell(
        onTap: () => onOpen(project),
        child: SizedBox(
          height: 38,
          child: Row(
            children: [
              if (narrow)
                Expanded(child: _name())
              else
                SizedBox(width: 242, child: _name()),
              if (!narrow)
                SizedBox(
                  width: 236,
                  child: Row(
                    children: [
                      InitialBadge(name: project.createdBy),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          project.createdBy,
                          style: T.ui,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(
                      Icons.mode_comment_outlined,
                      size: 16,
                      color: T.text1,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      project.unread > 0
                          ? '${project.total} (${project.unread} New)'
                          : '${project.total}',
                      style: T.body,
                    ),
                    // §5.6 row 6: Open, Settings, Copy project ID.
                    PopupMenuButton<String>(
                      tooltip: 'More for ${project.name}',
                      color: T.surface2,
                      // A 24 px target inside the 38 px row; the default
                      // 48 px icon button overflows it.
                      child: const SizedBox(
                        width: 24,
                        height: 24,
                        child: Icon(Icons.more_horiz, size: 16, color: T.text3),
                      ),
                      onSelected: (v) {
                        switch (v) {
                          case 'open':
                            onOpen(project);
                          case 'settings':
                            onSettings?.call(project);
                          case 'copy':
                            Clipboard.setData(ClipboardData(text: project.id));
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'open',
                          child: Text('Open', style: T.supporting),
                        ),
                        if (onSettings != null)
                          const PopupMenuItem(
                            value: 'settings',
                            child: Text('Settings', style: T.supporting),
                          ),
                        const PopupMenuItem(
                          value: 'copy',
                          child: Text('Copy project ID', style: T.supporting),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The amber initial badge, 16×16 radius 4, with a dark letter on it.
///
/// Shared with §4's meta row.
class InitialBadge extends StatelessWidget {
  const InitialBadge({super.key, required this.name, this.size = 16});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: T.amber,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: T.family,
          fontSize: size * 0.65,
          fontWeight: FontWeight.w700,
          height: 1,
          // The frame's letter is a dark brown on the amber, which is the
          // amber-ground token doing the same job it does on the screen tag.
          color: T.amberGround,
        ),
      ),
    );
  }
}
