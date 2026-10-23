import '../data/auth_gateway.dart';
import '../data/comment_repository.dart';
import '../data/project_repository.dart';
import '../data/team_repository.dart';
import '../models/comment.dart';
import '../models/comment_status.dart';
import '../models/impact.dart';
import '../models/workflow.dart';
import 'demo_data.dart';

/// What the demo says when an action needs a real server.
const String notInDemo = 'Not available in the demo.';

/// Shows [notInDemo] (or another line) to whoever is looking.
typedef DemoNotice = void Function(String message);

/// Every repository the dashboard needs, in memory and seeded.
///
/// Nothing here talks to a network. A reload starts again from [DemoData].
class DemoBackend {
  DemoBackend({required DemoNotice notice, DateTime? now})
    : this._(DemoData.seed(now ?? DateTime.now()), notice);

  DemoBackend._(DemoData data, DemoNotice notice)
    : comments = DemoCommentRepository(data),
      projects = DemoProjectRepository(data, notice),
      team = DemoTeamRepository(data, notice),
      auth = const DemoAuthGateway();

  final DemoCommentRepository comments;
  final DemoProjectRepository projects;
  final DemoTeamRepository team;
  final DemoAuthGateway auth;
}

/// Mirrors `public.status_for_verdict` (migration 0009): the database derives
/// `status` from `dev_verdict` on every write, so the fake does too.
CommentStatus statusForVerdict(DevVerdict v) => switch (v) {
  DevVerdict.inProgress => CommentStatus.inProgress,
  DevVerdict.fixed ||
  DevVerdict.wontFix ||
  DevVerdict.deferred => CommentStatus.resolved,
  DevVerdict.isNew || DevVerdict.blocked => CommentStatus.open,
};

/// Mirrors the other half of 0009: a status-only write moves the verdict.
DevVerdict _verdictForStatus(CommentStatus s, DevVerdict old) => switch (s) {
  CommentStatus.resolved => DevVerdict.fixed,
  CommentStatus.inProgress => DevVerdict.inProgress,
  CommentStatus.open =>
    old == DevVerdict.blocked ? DevVerdict.blocked : DevVerdict.isNew,
};

class DemoCommentRepository implements CommentRepository, ReportSource {
  DemoCommentRepository(this._data);

  final DemoData _data;
  int _nextEvent = 1;

  List<Comment> get _all => _data.comments;

  @override
  Future<List<Comment>> fetch({
    required String projectId,
    required CommentStatus status,
    Impact? impact,
  }) async {
    final rows = _all.where(
      (c) =>
          _data.projectOf[c.id] == projectId &&
          c.status == status &&
          (impact == null || c.impact == impact),
    );
    return rows.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _replace(Comment next) {
    final i = _all.indexWhere((c) => c.id == next.id);
    if (i < 0) {
      throw const RepositoryException(
        'That comment could not be updated. It may belong to another project.',
      );
    }
    _all[i] = next;
  }

  Comment _byId(String id) => _all.firstWhere(
    (c) => c.id == id,
    orElse: () => throw const RepositoryException(
      'That comment could not be updated. It may belong to another project.',
    ),
  );

  @override
  Future<Comment> updateStatus({
    required String commentId,
    required CommentStatus status,
  }) async {
    final old = _byId(commentId);
    final verdict = _verdictForStatus(status, old.devVerdict);
    final next = old.copyWith(
      devVerdict: verdict,
      status: statusForVerdict(verdict),
    );
    _replace(next);
    return next;
  }

  /// Relative to the page, so the base href decides where it is fetched from:
  /// `web/demo/` ships beside `index.html`.
  @override
  Future<String?> signedScreenshotUrl(String path) async => path;

  @override
  Future<void> deleteComment(Comment comment) async {
    _all.removeWhere((c) => c.id == comment.id);
    _data.events.remove(comment.id);
  }

  @override
  Future<int> deleteTester({
    required String projectId,
    required String testerId,
  }) async {
    final gone = _all
        .where(
          (c) => _data.projectOf[c.id] == projectId && c.testerId == testerId,
        )
        .map((c) => c.id)
        .toSet();
    _all.removeWhere((c) => gone.contains(c.id));
    gone.forEach(_data.events.remove);
    return gone.length;
  }

  /// The same patch and the same events as the Supabase repository, written
  /// to memory instead.
  @override
  Future<Comment> setVerdict({
    required Comment comment,
    TesterVerdict? tester,
    DevVerdict? dev,
    String? blockedOn,
    bool clearBlockedOn = false,
    String? assignee,
    String? build,
    String? note,
    String? actor,
  }) async {
    final current = _byId(comment.id);
    final now = DateTime.now();
    CommentEvent event({
      required String kind,
      String? field,
      String? from,
      String? to,
      String? build,
      String? body,
    }) => CommentEvent(
      id: 'demo-ev-${_nextEvent++}',
      at: now,
      kind: kind,
      actor: actor,
      field: field,
      fromValue: from,
      toValue: to,
      build: build,
      body: body,
    );

    final events = <CommentEvent>[
      if (dev != null)
        event(
          kind: 'verdict_changed',
          field: 'dev_verdict',
          from: comment.devVerdict.wire,
          to: dev.wire,
          build: dev == DevVerdict.fixed ? build : null,
        ),
      if (tester != null)
        event(
          kind: tester == TesterVerdict.rejected
              ? 'reopened'
              : 'verdict_changed',
          field: 'tester_verdict',
          from: comment.testerVerdict.wire,
          to: tester.wire,
          build: tester == TesterVerdict.accepted ? build : null,
        ),
      if (assignee != null)
        event(
          kind: 'assigned',
          field: 'assignee',
          from: comment.assignee,
          to: assignee,
        ),
      if (clearBlockedOn || blockedOn != null)
        event(
          kind: 'blocked',
          field: 'blocked_on',
          from: comment.blockedOn,
          to: clearBlockedOn ? null : blockedOn,
        ),
      if (note != null && note.trim().isNotEmpty)
        event(kind: 'commented', body: note.trim()),
    ];

    final verdict = dev ?? current.devVerdict;
    final next = current.copyWith(
      testerVerdict: tester,
      devVerdict: dev,
      blockedOn: blockedOn,
      clearBlockedOn: clearBlockedOn,
      assignee: assignee,
      fixedInBuild: build != null && dev == DevVerdict.fixed ? build : null,
      verifiedInBuild: build != null && tester == TesterVerdict.accepted
          ? build
          : null,
      status: statusForVerdict(verdict),
    );
    _replace(next);
    (_data.events[comment.id] ??= []).addAll(events);
    return next;
  }

  @override
  Future<List<CommentEvent>> events(String commentId) async =>
      List.of(_data.events[commentId] ?? const <CommentEvent>[])
        ..sort((a, b) => a.at.compareTo(b.at));

  @override
  Future<Board> board({required String projectId}) async =>
      Board.count(_all.where((c) => _data.projectOf[c.id] == projectId));

  @override
  Future<Map<String, List<Comment>>> reportComments({String? projectId}) async {
    final out = <String, List<Comment>>{};
    final sorted = List.of(_all)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final c in sorted) {
      final id = _data.projectOf[c.id];
      if (id == null || (projectId != null && id != projectId)) continue;
      (out[id] ??= []).add(c);
    }
    return out;
  }
}

class DemoProjectRepository implements ProjectRepository {
  DemoProjectRepository(this._data, this._notice);

  final DemoData _data;
  final DemoNotice _notice;
  int _next = 1;

  @override
  Future<List<Project>> list() async => [
    for (final p in _data.projects)
      Project(
        id: p.id,
        name: p.name,
        createdAt: p.createdAt,
        ownerId: p.ownerId,
        total: _data.comments
            .where((c) => _data.projectOf[c.id] == p.id)
            .length,
        unread: _data.comments
            .where(
              (c) =>
                  _data.projectOf[c.id] == p.id &&
                  c.status == CommentStatus.open,
            )
            .length,
      ),
  ];

  /// Like the `projects_default_key` trigger (0006): a project never exists
  /// without a key.
  @override
  Future<(Project, ProjectKey)> create(String name) async {
    final id = 'demo-project-${_next++}';
    final project = Project(
      id: id,
      name: name,
      createdAt: DateTime.now(),
      ownerId: DemoData.you.id,
    );
    final key = ProjectKey(
      id: '$id-key',
      key: DemoData.fakeKey(id),
      label: 'default',
      createdAt: project.createdAt,
    );
    _data.projects.add(project);
    _data.keys[id] = [key];
    return (project, key);
  }

  @override
  Future<List<ProjectKey>> keys(String projectId) async =>
      List.of(_data.keys[projectId] ?? const <ProjectKey>[]);

  /// Rotating needs the database to mint a key a real build could use.
  @override
  Future<ProjectKey> rotate({
    required String projectId,
    required String replacing,
  }) async {
    _notice(notInDemo);
    return (_data.keys[projectId] ?? const <ProjectKey>[]).firstWhere(
      (k) => k.id == replacing,
    );
  }

  @override
  Future<void> revoke(String keyId) async => _notice(notInDemo);

  @override
  Future<void> deleteProject(String projectId) async {
    _data.projects.removeWhere((p) => p.id == projectId);
    _data.keys.remove(projectId);
    final gone = _data.projectOf.entries
        .where((e) => e.value == projectId)
        .map((e) => e.key)
        .toSet();
    _data.comments.removeWhere((c) => gone.contains(c.id));
    gone.forEach(_data.events.remove);
  }
}

class DemoTeamRepository implements TeamRepository {
  DemoTeamRepository(this._data, this._notice);

  final DemoData _data;
  final DemoNotice _notice;
  int _next = 1;

  @override
  Future<int> acceptInvites() async => 0;

  /// The visitor owns the demo project, so every panel is theirs to try.
  @override
  Future<TeamRole?> myRole(String projectId) async =>
      _data.projects.any((p) => p.id == projectId) ? TeamRole.owner : null;

  @override
  Future<List<TeamMember>> members(String projectId) async =>
      List.of(_data.members[projectId] ?? const <TeamMember>[]);

  @override
  Future<List<TeamInvite>> invites(String projectId) async =>
      List.of(_data.invites[projectId] ?? const <TeamInvite>[]);

  @override
  Future<void> invite({
    required String projectId,
    required String email,
    required TeamRole role,
    TeamFunction? function,
  }) async {
    final list = _data.invites[projectId] ??= [];
    final address = email.trim().toLowerCase();
    if (list.any((i) => i.email == address)) {
      throw const RepositoryException(
        'Could not invite. That person already has an invite.',
      );
    }
    list.add(
      TeamInvite(
        id: 'demo-invite-${_next++}',
        email: address,
        role: role,
        function: function,
      ),
    );
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    for (final list in _data.invites.values) {
      list.removeWhere((i) => i.id == inviteId);
    }
  }

  @override
  Future<void> removeMember({
    required String projectId,
    required String userId,
  }) async => _data.members[projectId]?.removeWhere((m) => m.userId == userId);

  @override
  Future<String?> webhook(String projectId) async => _data.webhooks[projectId];

  /// Posting to a chat needs the ingest function. Thrown, so the panel keeps
  /// the channel it had instead of claiming a save.
  @override
  Future<void> setWebhook(String projectId, String? url) async {
    _notice(notInDemo);
    throw const RepositoryException('Not saved: this is the demo.');
  }
}

/// The demo opens signed in and stays that way. Saving a name works for the
/// visit; nothing else has an account to act on.
class DemoAuthGateway implements AuthGateway {
  const DemoAuthGateway();

  static const _no = AuthFailed(notInDemo);

  @override
  Future<AuthOutcome> saveName(String name) async => const SignedIn();

  @override
  Future<AuthOutcome> logIn({
    required String email,
    required String password,
  }) async => _no;

  @override
  Future<AuthOutcome> createAccount({
    required String email,
    required String password,
  }) async => _no;

  @override
  Future<AuthOutcome> sendPasswordReset({required String email}) async => _no;

  @override
  Future<AuthOutcome> setNewPassword({required String password}) async => _no;
}
