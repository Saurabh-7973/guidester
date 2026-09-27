import 'package:dashboard/src/data/comment_repository.dart';
import 'package:dashboard/src/data/project_repository.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/workflow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/board_fakes.dart';

/// Offline, the Supabase client throws the HTTP client's own exception, not
/// a PostgrestException. Every write must still turn that into the
/// RepositoryException the screens catch, or a failed save goes unreported
/// and the optimistic verdict stays on screen as if it had been saved.
void main() {
  final offline = MockClient(
    (_) async => throw http.ClientException('Failed to fetch'),
  );
  final repo = SupabaseCommentRepository(
    SupabaseClient('https://offline.test', 'anon', httpClient: offline),
  );
  final c = testComment(id: 'c1', body: 'x');

  const said = 'Could not reach the database. Check your connection.';

  Future<void> expectReported(Future<Object?> Function() call) async {
    await expectLater(
      call(),
      throwsA(
        isA<RepositoryException>().having((e) => e.message, 'message', said),
      ),
    );
  }

  test(
    'fetch',
    () => expectReported(
      () => repo.fetch(projectId: 'p', status: CommentStatus.open),
    ),
  );
  test(
    'updateStatus',
    () => expectReported(
      () => repo.updateStatus(commentId: 'c1', status: CommentStatus.resolved),
    ),
  );
  test(
    'setVerdict',
    () => expectReported(
      () => repo.setVerdict(comment: c, dev: DevVerdict.fixed),
    ),
  );
  test('events', () => expectReported(() => repo.events('c1')));
  test('deleteComment', () => expectReported(() => repo.deleteComment(c)));
  test(
    'deleteTester',
    () =>
        expectReported(() => repo.deleteTester(projectId: 'p', testerId: 't')),
  );

  group('projects', () {
    final projects = SupabaseProjectRepository(
      SupabaseClient('https://offline.test', 'anon', httpClient: offline),
    );
    Future<void> reported(Future<Object?> Function() call) => expectLater(
      call(),
      throwsA(
        isA<RepositoryException>().having(
          (e) => e.message,
          'message',
          endsWith(said),
        ),
      ),
    );
    test('list', () => reported(projects.list));
    test('keys', () => reported(() => projects.keys('p')));
    test('revoke', () => reported(() => projects.revoke('k')));
  });
}
