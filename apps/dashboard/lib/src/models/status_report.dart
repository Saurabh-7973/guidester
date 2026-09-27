import 'comment.dart';
import 'impact.dart';
import 'workflow.dart';

/// Where a comment is in its life, from both verdicts. Exactly one per
/// comment, so the stages add up to the total and a chart of them is honest.
enum Stage {
  fresh('New'),
  inProgress('In progress'),
  blocked('Blocked'),
  stillBroken('Still broken'),
  awaitingVerification('Waiting for QA'),
  verified('Verified'),
  deferred('Deferred'),
  wontFix("Won't fix");

  const Stage(this.label);

  final String label;

  /// Someone owes work on it.
  bool get isOpenWork =>
      this == fresh ||
      this == inProgress ||
      this == blocked ||
      this == stillBroken;

  /// The tester's word decides first: an accepted fix is done whatever the
  /// dev verdict says, and a rejected one is back on the developer's desk.
  static Stage of(Comment c) {
    if (c.testerVerdict == TesterVerdict.accepted) return verified;
    return switch (c.devVerdict) {
      DevVerdict.wontFix => wontFix,
      DevVerdict.deferred => deferred,
      _ when c.testerVerdict == TesterVerdict.rejected => stillBroken,
      DevVerdict.fixed => awaitingVerification,
      DevVerdict.blocked => blocked,
      DevVerdict.inProgress => inProgress,
      DevVerdict.isNew => fresh,
    };
  }
}

/// Can this build ship? The question a lead asks first.
enum Readiness {
  notReady('Not ready to release'),
  verifyFirst('Fixed, waiting for QA to verify'),
  ready('Ready to release');

  const Readiness(this.label);

  final String label;
}

/// One team's view of the same project: what is theirs to move.
enum Lens {
  lead('Lead / CTO', 'What stops the release'),
  developers('Developers', 'Open work, still broken first'),
  qa('QA', 'Fixed, waiting to be verified'),
  design('UI / UX', 'Blocked on design, and cosmetic issues'),
  product('Product / BA', 'Waiting on a product decision'),
  backend('Backend', 'Blocked on the backend'),
  frontend('Frontend', 'Blocked on the frontend'),
  thirdParty('Third party', 'Waiting on someone outside the team');

  const Lens(this.label, this.question);

  final String label;

  /// What the list answers, under its title.
  final String question;
}

/// A project's status, for everyone, from its comments. Pure: the same
/// comments and clock give the same report, so it is tested without a
/// database and pasted anywhere as Markdown.
class StatusReport {
  StatusReport._({
    required this.projectName,
    required this.now,
    required List<Comment> comments,
  }) : _comments = comments,
       _stages = {for (final c in comments) c.id: Stage.of(c)};

  factory StatusReport.from({
    required String projectName,
    required List<Comment> comments,
    DateTime? now,
  }) => StatusReport._(
    projectName: projectName,
    now: now ?? DateTime.now(),
    comments: List.unmodifiable(comments),
  );

  final String projectName;
  final DateTime now;
  final List<Comment> _comments;
  final Map<String, Stage> _stages;

  int get total => _comments.length;

  Stage stageOf(Comment c) => _stages[c.id] ?? Stage.of(c);

  int count(Stage s) => _comments.where((c) => stageOf(c) == s).length;

  Iterable<Comment> _in(Stage s) => _comments.where((c) => stageOf(c) == s);

  Iterable<Comment> get _open => _comments.where((c) => stageOf(c).isOpenWork);

  int get openWork => _open.length;

  /// Open work that stops a tester in their tracks.
  List<Comment> get blockers =>
      _sorted(_open.where((c) => c.impact == Impact.blocked));

  Readiness get readiness {
    if (blockers.isNotEmpty) return Readiness.notReady;
    if (count(Stage.awaitingVerification) > 0) return Readiness.verifyFirst;
    return Readiness.ready;
  }

  /// Verified out of everything meant to be fixed: won't fix and deferred are
  /// decisions, not progress. Null with nothing to fix.
  double? get verifiedShare {
    final meant = total - count(Stage.wontFix) - count(Stage.deferred);
    if (meant <= 0) return null;
    return count(Stage.verified) / meant;
  }

  DateTime get _weekAgo =>
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));

  int get reportedThisWeek =>
      _comments.where((c) => !c.createdAt.isBefore(_weekAgo)).length;

  /// Days the oldest open comment has waited. Null with none open.
  int? get oldestOpenDays {
    final open = _open.toList();
    if (open.isEmpty) return null;
    final oldest = open
        .map((c) => c.createdAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return now.difference(oldest).inDays;
  }

  /// Screens with the most open work, most first, at most five.
  List<(String, int)> get hotScreens {
    final n = <String, int>{};
    for (final c in _open) {
      n[c.screenName] = (n[c.screenName] ?? 0) + 1;
    }
    final list = n.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2 != a.$2 ? b.$2 - a.$2 : a.$1.compareTo(b.$1));
    return list.take(5).toList();
  }

  /// Open work per person; nobody's is "Unassigned".
  Map<String, int> get byAssignee {
    final n = <String, int>{};
    for (final c in _open) {
      final who = (c.assignee == null || c.assignee!.isEmpty)
          ? 'Unassigned'
          : c.assignee!;
      n[who] = (n[who] ?? 0) + 1;
    }
    return n;
  }

  /// Blocked comments per team they wait on.
  Map<String, int> get blockedBy {
    final n = <String, int>{};
    for (final c in _in(Stage.blocked)) {
      final on = c.blockedOn ?? 'unknown';
      n[on] = (n[on] ?? 0) + 1;
    }
    return n;
  }

  /// What is this team's to move.
  List<Comment> lens(Lens l) {
    Iterable<Comment> on(String team) =>
        _in(Stage.blocked).where((c) => c.blockedOn == team);
    return switch (l) {
      Lens.lead => blockers,
      Lens.developers => _sorted(
        _open.where((c) => stageOf(c) != Stage.blocked),
      ),
      Lens.qa => _oldestFirst(_in(Stage.awaitingVerification)),
      Lens.design => [
        ..._sorted(on('design')),
        ..._sorted(
          _open.where(
            (c) => c.impact == Impact.cosmetic && stageOf(c) != Stage.blocked,
          ),
        ),
      ],
      Lens.product => _sorted(on('product')),
      Lens.backend => _sorted(on('backend')),
      Lens.frontend => _sorted(on('frontend')),
      Lens.thirdParty => _sorted(on('third-party')),
    };
  }

  /// Still broken first (a fix that failed costs twice), then by impact, then
  /// the one that has waited longest.
  List<Comment> _sorted(Iterable<Comment> cs) => cs.toList()
    ..sort((a, b) {
      final broken =
          (stageOf(b) == Stage.stillBroken ? 1 : 0) -
          (stageOf(a) == Stage.stillBroken ? 1 : 0);
      if (broken != 0) return broken;
      final impact = a.impact.index - b.impact.index;
      if (impact != 0) return impact;
      return a.createdAt.compareTo(b.createdAt);
    });

  List<Comment> _oldestFirst(Iterable<Comment> cs) =>
      cs.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get dateLabel => '${now.day} ${_months[now.month - 1]} ${now.year}';

  String _age(Comment c) {
    final d = now.difference(c.createdAt).inDays;
    return d <= 0 ? 'today' : (d == 1 ? '1 day' : '$d days');
  }

  String _line(Comment c) {
    final body = c.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = body.length > 90 ? '${body.substring(0, 89)}…' : body;
    final who = c.assignee == null || c.assignee!.isEmpty
        ? ''
        : ', ${c.assignee}';
    return '- [${c.impact.label}] $short (${c.screenName}, ${_age(c)}$who)';
  }

  /// Pastes into Slack, Jira, GitHub or an email as it is.
  String toMarkdown({String? link, int perList = 5}) {
    final b = StringBuffer('## $projectName: status $dateLabel\n\n');
    if (total == 0) {
      b.writeln('No comments yet.');
      if (link != null) b.writeln('\n$link');
      return b.toString();
    }
    final share = verifiedShare;
    b
      ..writeln('**${readiness.label}**')
      ..writeln()
      ..writeln(
        '- $openWork open (${blockers.length} blocking), '
        '${count(Stage.stillBroken)} still broken after a fix',
      )
      ..writeln(
        '- ${count(Stage.awaitingVerification)} fixed, waiting for QA; '
        '${count(Stage.verified)} verified'
        '${share == null ? '' : ' (${(share * 100).round()}%)'}',
      )
      ..writeln(
        '- $reportedThisWeek reported this week'
        '${oldestOpenDays == null ? '' : '; oldest open: $oldestOpenDays days'}',
      );
    if (blockedBy.isNotEmpty) {
      final parts = blockedBy.entries
          .map((e) => '${BlockedOn.label(e.key)} ${e.value}')
          .join(', ');
      b.writeln('- Blocked on: $parts');
    }
    for (final l in Lens.values) {
      final items = lens(l);
      if (items.isEmpty) continue;
      b
        ..writeln()
        ..writeln('### ${l.label}: ${l.question} (${items.length})');
      for (final c in items.take(perList)) {
        b.writeln(_line(c));
      }
      if (items.length > perList) {
        b.writeln('- …and ${items.length - perList} more');
      }
    }
    if (link != null) b.writeln('\n$link');
    return b.toString();
  }
}
