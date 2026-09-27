import 'package:flutter/foundation.dart';

import '../models/comment_status.dart';
import '../models/impact.dart';
import '../widgets/app_shell.dart';

/// Every place the dashboard can be, as a value the URL can hold.
///
/// Found 25 Sep: the URL was `/` on every screen, so back left the app,
/// reload dropped to the project list, and no comment could be linked.
///
///   /projects                    the project list
///   /projects/new                onboarding a new project
///   /settings                    account settings
///   /p/:id                       a project's board
///   /p/:id/c/:commentId          one comment on it
///   /p/:id/settings              that project's settings
///   /status                      every project's status, at a glance
///   /p/:id/status                one project's status report
///
/// A board also carries `?status=`, `?impact=` and `?screen=`, left out at their defaults
/// so the common link stays short.
@immutable
class DashboardLocation {
  const DashboardLocation._({
    required this.tab,
    this.projectId,
    this.commentId,
    this.onboarding = false,
    this.status = CommentStatus.open,
    this.impact,
    this.screen,
  });

  const DashboardLocation.projects() : this._(tab: ShellTab.projects);

  const DashboardLocation.newProject()
    : this._(tab: ShellTab.projects, onboarding: true);

  const DashboardLocation.settings({String? projectId})
    : this._(tab: ShellTab.settings, projectId: projectId);

  const DashboardLocation.status({String? projectId})
    : this._(tab: ShellTab.status, projectId: projectId);

  const DashboardLocation.board(
    String projectId, {
    String? commentId,
    CommentStatus status = CommentStatus.open,
    Impact? impact,
    String? screen,
  }) : this._(
         tab: ShellTab.projects,
         projectId: projectId,
         commentId: commentId,
         status: status,
         impact: impact,
         screen: screen,
       );

  final ShellTab tab;
  final String? projectId;
  final String? commentId;
  final bool onboarding;
  final CommentStatus status;
  final Impact? impact;

  /// The screen the board is narrowed to, or null for every screen.
  final String? screen;

  /// True on a project's board, with or without a comment open.
  bool get isBoard => tab == ShellTab.projects && projectId != null;

  /// Null when the URL names no place; the router shows that as a 404.
  static DashboardLocation? parse(Uri uri) {
    final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    switch (s) {
      case ['projects']:
        return const DashboardLocation.projects();
      case ['projects', 'new']:
        return const DashboardLocation.newProject();
      case ['settings']:
        return const DashboardLocation.settings();
      case ['status']:
        return const DashboardLocation.status();
      case ['p', final id, 'status']:
        return DashboardLocation.status(projectId: id);
      case ['p', final id, 'settings']:
        return DashboardLocation.settings(projectId: id);
      case ['p', final id]:
        return _board(id, null, uri.queryParameters);
      case ['p', final id, 'c', final comment]:
        return _board(id, comment, uri.queryParameters);
    }
    return null;
  }

  static DashboardLocation _board(
    String id,
    String? comment,
    Map<String, String> q,
  ) {
    final status = CommentStatus.values.firstWhere(
      (s) => s.wire == q['status'],
      orElse: () => CommentStatus.open,
    );
    final impact = Impact.values
        .where((i) => i.wire == q['impact'])
        .firstOrNull;
    return DashboardLocation.board(
      id,
      commentId: comment,
      status: status,
      impact: impact,
      screen: (q['screen']?.isEmpty ?? true) ? null : q['screen'],
    );
  }

  String get path {
    if (onboarding) return '/projects/new';
    if (tab == ShellTab.settings) {
      return projectId == null ? '/settings' : '/p/$projectId/settings';
    }
    if (tab == ShellTab.status) {
      return projectId == null ? '/status' : '/p/$projectId/status';
    }
    if (projectId == null) return '/projects';
    final base = commentId == null
        ? '/p/$projectId'
        : '/p/$projectId/c/$commentId';
    final query = {
      if (status != CommentStatus.open) 'status': status.wire,
      if (impact != null) 'impact': impact!.wire,
      'screen': ?screen,
    };
    return query.isEmpty
        ? base
        : Uri(path: base, queryParameters: query).toString();
  }

  DashboardLocation withComment(String? id) => DashboardLocation._(
    tab: tab,
    projectId: projectId,
    commentId: id,
    status: status,
    impact: impact,
    screen: screen,
  );

  @override
  bool operator ==(Object other) =>
      other is DashboardLocation &&
      other.tab == tab &&
      other.projectId == projectId &&
      other.commentId == commentId &&
      other.onboarding == onboarding &&
      other.status == status &&
      other.impact == impact &&
      other.screen == screen;

  @override
  int get hashCode => Object.hash(
    tab,
    projectId,
    commentId,
    onboarding,
    status,
    impact,
    screen,
  );

  @override
  String toString() => 'DashboardLocation($path)';
}

/// This page's address with no query and no fragment: where the dashboard is
/// served. A comment's link and the password-reset return both hang off it.
///
/// Not `Uri.base.origin`, which throws for any scheme but http(s).
String pageUrl([Uri? base]) {
  final b = base ?? Uri.base;
  return Uri(
    scheme: b.scheme,
    host: b.host,
    port: b.hasPort ? b.port : null,
    path: b.path,
  ).toString();
}
