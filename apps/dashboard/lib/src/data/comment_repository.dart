import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/comment.dart';
import '../models/comment_status.dart';
import '../models/impact.dart';
import '../models/workflow.dart';
import 'db_errors.dart';

/// Raised for anything the UI should show the user. Carries a message that is
/// safe to display — Postgres error text is deliberately not passed through.
class RepositoryException implements Exception {
  const RepositoryException(this.message, {this.offline = false});
  final String message;

  /// The network, not the database: worth retrying on its own.
  final bool offline;
  @override
  String toString() => message;
}

/// All database access for the dashboard.
///
/// The UI never touches Supabase directly: keeping every query behind this
/// seam means the query shape, the signed-URL lifetime and the error mapping
/// each live in exactly one place, and the screens stay testable against a
/// fake.
abstract class CommentRepository {
  /// [impact] null means every impact.
  ///
  /// Filtered by impact, not issue type: the SDK asks testers for impact and
  /// never for a type (D51), so issue_type is null on every real row and a
  /// type filter could only ever come back empty.
  Future<List<Comment>> fetch({
    required String projectId,
    required CommentStatus status,
    Impact? impact,
  });

  Future<Comment> updateStatus({
    required String commentId,
    required CommentStatus status,
  });

  /// Screenshots are in a private bucket; this mints a short-lived signed URL.
  Future<String?> signedScreenshotUrl(String path);

  /// Deletes one comment and its screenshot object.
  ///
  /// G4: a tester screenshots a screen carrying their own data and asks for it
  /// to be removed. Under the DPDP Act that is not optional. The row alone is
  /// not enough — a deleted comment whose screenshot survives in storage is
  /// exactly the failure the request was about.
  Future<void> deleteComment(Comment comment);

  /// Moves a verdict, and records the move.
  ///
  /// Every change writes a [CommentEvent]. That is the whole point: the sheet's
  /// status column silently lagged its remark column because a person updated
  /// one and not the other. Here the verdict and its history are written
  /// together or not at all.
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
  });

  /// The history, oldest first.
  Future<List<CommentEvent>> events(String commentId);

  /// The counts a developer opens the board to ask for.
  Future<Board> board({required String projectId});

  /// Deletes every comment from one tester, and every screenshot with them.
  ///
  /// Returns how many rows went. The whole-tester case is the one a request
  /// under the Act actually looks like: "remove everything of mine", not
  /// "remove comment 4".
  Future<int> deleteTester({
    required String projectId,
    required String testerId,
  });
}

class SupabaseCommentRepository implements CommentRepository {
  SupabaseCommentRepository(this._client);

  final SupabaseClient _client;

  /// Long enough to read a comment, short enough that a copied URL goes stale.
  static const int _signedUrlTtlSeconds = 3600;

  /// Matches `comments_project_status_idx` exactly: project, status, then
  /// created_at descending. Confirmed with EXPLAIN to use an index scan.
  static const String _columns =
      'id, body, screen_name, tap_x, tap_y, screenshot_path, tester_name, '
      'tester_id, device_model, os_version, app_version, context, status, '
      'issue_type, impact, tester_verdict, dev_verdict, blocked_on, assignee, '
      'found_in_build, fixed_in_build, verified_in_build, environment, '
      'errors, created_at';

  @override
  Future<List<Comment>> fetch({
    required String projectId,
    required CommentStatus status,
    Impact? impact,
  }) async {
    try {
      // Filtered in Postgres, not in Dart: comments_impact_idx exists so
      // the filter stays an index scan as the table grows.
      var query = _client
          .from('comments')
          .select(_columns)
          .eq('project_id', projectId)
          .eq('status', status.wire);
      if (impact != null) {
        query = query.eq('impact', impact.wire);
      }
      final rows = await query.order('created_at', ascending: false);
      return rows.map(Comment.fromRow).toList(growable: false);
    } on PostgrestException catch (e) {
      throw RepositoryException(_describe(e));
    } catch (_) {
      throw const RepositoryException(_unreachable, offline: true);
    }
  }

  @override
  Future<Comment> updateStatus({
    required String commentId,
    required CommentStatus status,
  }) async {
    try {
      final rows = await _client
          .from('comments')
          .update({'status': status.wire})
          .eq('id', commentId)
          .select(_columns);
      if (rows.isEmpty) {
        // RLS returns zero rows rather than an error when the row is not
        // yours. Surfacing that honestly beats a silent no-op.
        throw const RepositoryException(
          'That comment could not be updated. It may belong to another project.',
        );
      }
      return Comment.fromRow(rows.first);
    } on PostgrestException catch (e) {
      throw RepositoryException(_describe(e));
    } on RepositoryException {
      rethrow;
    } catch (_) {
      throw const RepositoryException(_unreachable, offline: true);
    }
  }

  @override
  Future<String?> signedScreenshotUrl(String path) async {
    try {
      return await _client.storage
          .from('screenshots')
          .createSignedUrl(path, _signedUrlTtlSeconds);
    } catch (_) {
      // A missing screenshot is not a page failure.
      return null;
    }
  }

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
    try {
      final patch = <String, dynamic>{
        if (tester != null) 'tester_verdict': tester.wire,
        if (dev != null) 'dev_verdict': dev.wire,
        if (clearBlockedOn) 'blocked_on': null else 'blocked_on': ?blockedOn,
        'assignee': ?assignee,
        // A build is only meaningful attached to the verdict it belongs to:
        // the developer marks what they fixed it in, the tester marks what
        // they verified it on.
        if (build != null && dev == DevVerdict.fixed) 'fixed_in_build': build,
        if (build != null && tester == TesterVerdict.accepted)
          'verified_in_build': build,
      };

      final events = <Map<String, dynamic>>[
        if (dev != null)
          {
            'comment_id': comment.id,
            'actor': actor,
            'kind': 'verdict_changed',
            'field': 'dev_verdict',
            'from_value': comment.devVerdict.wire,
            'to_value': dev.wire,
            'build': dev == DevVerdict.fixed ? build : null,
          },
        if (tester != null)
          {
            'comment_id': comment.id,
            'actor': actor,
            // A tester saying "still broken" is a reopen, and reopens are what
            // the sheet's QA Remark column is mostly made of.
            'kind': tester == TesterVerdict.rejected
                ? 'reopened'
                : 'verdict_changed',
            'field': 'tester_verdict',
            'from_value': comment.testerVerdict.wire,
            'to_value': tester.wire,
            'build': tester == TesterVerdict.accepted ? build : null,
          },
        if (assignee != null)
          {
            'comment_id': comment.id,
            'actor': actor,
            'kind': 'assigned',
            'field': 'assignee',
            'from_value': comment.assignee,
            'to_value': assignee,
          },
        if (clearBlockedOn || blockedOn != null)
          {
            'comment_id': comment.id,
            'actor': actor,
            'kind': 'blocked',
            'field': 'blocked_on',
            'from_value': comment.blockedOn,
            'to_value': clearBlockedOn ? null : blockedOn,
          },
        if (note != null && note.trim().isNotEmpty)
          {
            'comment_id': comment.id,
            'actor': actor,
            'kind': 'commented',
            'body': note.trim(),
          },
      ];

      if (patch.isEmpty && events.isEmpty) return comment;

      var updated = comment;
      if (patch.isNotEmpty) {
        final rows = await _client
            .from('comments')
            .update(patch)
            .eq('id', comment.id)
            .select(_columns);
        if (rows.isEmpty) {
          throw const RepositoryException(
            'That comment could not be updated. It may belong to another '
            'project.',
          );
        }
        updated = Comment.fromRow(rows.first);
      }

      // After the row, so a failed update never leaves a history entry
      // claiming something that did not happen.
      if (events.isNotEmpty) {
        await _client.from('comment_events').insert(events);
      }
      return updated;
    } on PostgrestException catch (e) {
      throw RepositoryException(_describe(e));
    } on RepositoryException {
      rethrow;
    } catch (_) {
      throw const RepositoryException(_unreachable, offline: true);
    }
  }

  @override
  Future<List<CommentEvent>> events(String commentId) async {
    try {
      final rows = await _client
          .from('comment_events')
          .select(
            'id, at, actor, kind, body, field, from_value, to_value, '
            'build',
          )
          .eq('comment_id', commentId)
          .order('at');
      return rows.map(CommentEvent.fromRow).toList(growable: false);
    } on PostgrestException catch (e) {
      throw RepositoryException(_describe(e));
    } on RepositoryException {
      rethrow;
    } catch (_) {
      throw const RepositoryException(_unreachable, offline: true);
    }
  }

  @override
  Future<Board> board({required String projectId}) async {
    try {
      // One read, counted in Dart. The alternative is six count queries or a
      // view, and at v0 volumes the round trips cost more than the rows.
      final rows = await _client
          .from('comments')
          .select(
            'created_at, dev_verdict, tester_verdict, blocked_on, '
            'assignee',
          )
          .eq('project_id', projectId);

      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final weekAgo = startOfToday.subtract(const Duration(days: 6));

      var today = 0;
      var week = 0;
      var fixedNotVerified = 0;
      var blocked = 0;
      final blockedBy = <String, int>{};
      final openByAssignee = <String, int>{};

      for (final r in rows) {
        final at = DateTime.tryParse(
          r['created_at']?.toString() ?? '',
        )?.toLocal();
        if (at != null) {
          if (!at.isBefore(startOfToday)) today++;
          if (!at.isBefore(weekAgo)) week++;
        }

        final dev = DevVerdict.fromWire(r['dev_verdict']?.toString());
        final tester = TesterVerdict.fromWire(r['tester_verdict']?.toString());

        if (dev == DevVerdict.fixed && tester != TesterVerdict.accepted) {
          fixedNotVerified++;
        }
        if (dev == DevVerdict.blocked) {
          blocked++;
          final on = BlockedOn.fromWire(r['blocked_on']?.toString());
          if (on != null) blockedBy[on] = (blockedBy[on] ?? 0) + 1;
        }

        final who = r['assignee']?.toString();
        final settled =
            dev == DevVerdict.wontFix || tester == TesterVerdict.accepted;
        if (who != null && who.isNotEmpty && !settled) {
          openByAssignee[who] = (openByAssignee[who] ?? 0) + 1;
        }
      }

      return Board(
        reportedToday: today,
        reportedThisWeek: week,
        fixedNotVerified: fixedNotVerified,
        blocked: blocked,
        blockedBy: blockedBy,
        openByAssignee: openByAssignee,
      );
    } on PostgrestException catch (e) {
      throw RepositoryException(_describe(e));
    } on RepositoryException {
      rethrow;
    } catch (_) {
      throw const RepositoryException(_unreachable, offline: true);
    }
  }

  @override
  Future<void> deleteComment(Comment comment) async {
    try {
      // Storage first. If the row goes and the object fails, the screenshot is
      // orphaned with nothing left pointing at it — undeletable through the UI
      // and invisible in the list. The other order leaves a comment whose
      // screenshot is already gone, which the detail pane already handles.
      await _deleteObjects([
        if (comment.screenshotPath != null) comment.screenshotPath!,
      ]);

      final rows = await _client
          .from('comments')
          .delete()
          .eq('id', comment.id)
          .select('id');
      if (rows.isEmpty) {
        // RLS returns zero rows rather than an error when the row is not yours.
        throw const RepositoryException(
          'That comment could not be deleted. It may belong to another project.',
        );
      }
    } on PostgrestException catch (e) {
      throw RepositoryException(_describe(e));
    } on RepositoryException {
      rethrow;
    } catch (_) {
      throw const RepositoryException(_unreachable, offline: true);
    }
  }

  @override
  Future<int> deleteTester({
    required String projectId,
    required String testerId,
  }) async {
    try {
      // Read the paths before the rows go: afterwards there is nothing left to
      // tell us which objects belonged to them.
      final rows = await _client
          .from('comments')
          .select('screenshot_path')
          .eq('project_id', projectId)
          .eq('tester_id', testerId);
      await _deleteObjects([
        for (final r in rows)
          if (r['screenshot_path'] != null) r['screenshot_path'] as String,
      ]);

      final deleted = await _client
          .from('comments')
          .delete()
          .eq('project_id', projectId)
          .eq('tester_id', testerId)
          .select('id');
      return deleted.length;
    } on PostgrestException catch (e) {
      throw RepositoryException(_describe(e));
    } on RepositoryException {
      rethrow;
    } catch (_) {
      throw const RepositoryException(_unreachable, offline: true);
    }
  }

  /// Storage removal is best-effort by design.
  ///
  /// An object that is already gone must not block the row deletion — a request
  /// to erase someone's data that fails because part of it was erased already
  /// is the worst possible outcome.
  Future<void> _deleteObjects(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from('screenshots').remove(paths);
    } catch (_) {
      // Deliberately swallowed. See above.
    }
  }

  static String _describe(PostgrestException e) => describeDbError(e);

  /// Offline, the client throws the HTTP layer's own exception rather than a
  /// PostgrestException. Every call turns it into this, so a failed save is
  /// always reported and an optimistic change always rolls back.
  static const String _unreachable =
      'Could not reach the database. Check your connection.';
}
