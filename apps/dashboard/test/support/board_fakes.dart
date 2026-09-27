import 'dart:async';

import 'package:dashboard/src/data/comment_repository.dart';
import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/models/issue_type.dart';
import 'package:dashboard/src/models/workflow.dart';

/// In-memory stand-in for Supabase. Records calls so we can assert the screen
/// asks for the right things, and can be told to fail on demand.
class FakeRepository implements CommentRepository {
  FakeRepository(this._byStatus);

  final Map<CommentStatus, List<Comment>> _byStatus;
  final List<String> calls = [];

  String? failFetchWith;

  /// With [failFetchWith]: the failure is the network, not the database.
  bool failFetchOffline = false;

  /// When set, fetch waits for it: the loading state, held open.
  Completer<void>? fetchGate;
  String? failUpdateWith;

  /// When set, setVerdict fails with it.
  String? failVerdictWith;

  /// When set, setVerdict waits for it: the save, held in flight.
  Completer<void>? verdictGate;
  bool signedUrlReturnsNull = false;

  @override
  Future<List<Comment>> fetch({
    required String projectId,
    required CommentStatus status,
    Impact? impact,
  }) async {
    calls.add('fetch:${status.wire}:${impact?.wire ?? 'all'}');
    if (fetchGate != null) await fetchGate!.future;
    if (failFetchWith != null) {
      throw RepositoryException(failFetchWith!, offline: failFetchOffline);
    }
    final rows = _byStatus[status] ?? const <Comment>[];
    // The real filter runs in Postgres. Mirroring it here keeps the fake
    // honest: a screen that filtered in Dart instead would pass either way.
    if (impact == null) return rows;
    return rows.where((c) => c.impact == impact).toList(growable: false);
  }

  @override
  Future<Comment> updateStatus({
    required String commentId,
    required CommentStatus status,
  }) async {
    calls.add('update:$commentId:${status.wire}');
    if (failUpdateWith != null) throw RepositoryException(failUpdateWith!);
    for (final list in _byStatus.values) {
      for (final c in list) {
        if (c.id == commentId) return c.copyWith(status: status);
      }
    }
    throw const RepositoryException('missing');
  }

  final List<String> deleted = [];

  @override
  Future<void> deleteComment(Comment comment) async {
    calls.add('delete:${comment.id}');
    if (failUpdateWith != null) throw RepositoryException(failUpdateWith!);
    deleted.add(comment.id);
    for (final list in _byStatus.values) {
      list.removeWhere((c) => c.id == comment.id);
    }
  }

  @override
  Future<int> deleteTester({
    required String projectId,
    required String testerId,
  }) async {
    calls.add('deleteTester:$testerId');
    var n = 0;
    for (final list in _byStatus.values) {
      n += list.where((c) => c.testerId == testerId).length;
      list.removeWhere((c) => c.testerId == testerId);
    }
    return n;
  }

  final List<Map<String, Object?>> verdicts = [];

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
    if (verdictGate != null) await verdictGate!.future;
    if (failVerdictWith != null) throw RepositoryException(failVerdictWith!);
    verdicts.add({
      'id': comment.id,
      'tester': tester?.wire,
      'dev': dev?.wire,
      'blockedOn': clearBlockedOn ? null : blockedOn,
      'assignee': assignee,
      'build': build,
      'note': note,
    });
    return comment.copyWith(
      testerVerdict: tester,
      devVerdict: dev,
      blockedOn: blockedOn,
      clearBlockedOn: clearBlockedOn,
      assignee: assignee,
      fixedInBuild: dev == DevVerdict.fixed ? build : null,
      verifiedInBuild: tester == TesterVerdict.accepted ? build : null,
    );
  }

  List<CommentEvent> history = const [];

  @override
  Future<List<CommentEvent>> events(String commentId) async => history;

  @override
  Future<Board> board({required String projectId}) async => const Board(
    reportedToday: 0,
    reportedThisWeek: 0,
    fixedNotVerified: 0,
    blocked: 0,
    blockedBy: {},
    openByAssignee: {},
  );

  @override
  Future<String?> signedScreenshotUrl(String path) async {
    calls.add('sign:$path');
    return signedUrlReturnsNull ? null : 'https://signed.test/$path';
  }
}

/// A comment with sensible defaults for board tests.
Comment testComment({
  required String id,
  required String body,
  String screen = 'HOME',
  CommentStatus status = CommentStatus.open,
  String? shot,
  String? tester = 'Ana',
  IssueType? issueType,
  Impact impact = Impact.annoying,
  Map<String, dynamic> context = const {},
}) => Comment(
  id: id,
  body: body,
  screenName: screen,
  status: status,
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  tapX: 0.5,
  tapY: 0.5,
  screenshotPath: shot,
  testerName: tester,
  issueType: issueType,
  impact: impact,
  context: context,
);
