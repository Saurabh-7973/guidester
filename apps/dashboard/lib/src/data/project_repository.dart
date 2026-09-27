import 'package:supabase_flutter/supabase_flutter.dart';

import 'comment_repository.dart' show RepositoryException;
import 'db_errors.dart';

/// A project as the projects table holds it, with the count the list shows.
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    this.total = 0,
    this.unread = 0,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  /// Comments on the board, and how many of those are still `open`.
  final int total;
  final int unread;
}

/// One key, as `project_keys` holds it since migration 0006.
class ProjectKey {
  const ProjectKey({
    required this.id,
    required this.key,
    required this.label,
    required this.createdAt,
    this.revokedAt,
    this.lastUsedAt,
    this.lastUsedDevice,
    this.lastUsedOs,
  });

  final String id;

  /// The value that goes into a build. Shown in full during onboarding,
  /// because a key nobody can read is a key nobody can install, and masked
  /// everywhere after that.
  final String key;
  final String label;
  final DateTime createdAt;
  final DateTime? revokedAt;

  /// When something last reported on this key, and what reported. Written by
  /// the ingest function on a comment and on a launch ping; this is the whole
  /// of the onboarding connection check.
  final DateTime? lastUsedAt;
  final String? lastUsedDevice;
  final String? lastUsedOs;

  bool get isRevoked => revokedAt != null;
  bool get hasBeenUsed => lastUsedAt != null;

  /// `gd_live_…4f2a`. Enough to tell two keys apart, not enough to use.
  String get masked {
    if (key.length <= 12) return key;
    final head = key.startsWith('gd_live_') || key.startsWith('gd_test_')
        ? key.substring(0, 8)
        : key.substring(0, 4);
    return '$head••••${key.substring(key.length - 4)}';
  }

  /// "Pixel 7, Android 15", or null when the ping came from an SDK build old
  /// enough not to send device facts.
  String? get lastUsedDescription {
    final parts = [lastUsedDevice, lastUsedOs].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// Everything the dashboard does with projects and their keys.
///
/// Split from `CommentRepository` rather than added to it: comments are read
/// constantly and projects are read twice a session, and a fake for one should
/// not have to implement the other.
abstract class ProjectRepository {
  /// Every project the signed-in user owns, oldest first — a list that
  /// reorders itself as comments arrive is a list nobody can point at. RLS does
  /// the
  /// filtering — there is no owner clause here, and that is deliberate: a
  /// query that filters in the client is one policy change away from leaking.
  Future<List<Project>> list();

  /// Create a project and return it with the key the trigger minted for it.
  ///
  /// Two round trips, not one: the key is written by a database trigger, so
  /// it does not come back from the insert.
  Future<(Project, ProjectKey)> create(String name);

  /// The project's live keys, newest first. Revoked ones are included —
  /// Settings has to be able to show that a key was turned off.
  Future<List<ProjectKey>> keys(String projectId);

  /// Mint a new key and revoke the one it replaces, in that order.
  ///
  /// The order is the whole point: a project is never keyless, and a build
  /// carrying the old key keeps working until the new one exists.
  Future<ProjectKey> rotate({
    required String projectId,
    required String replacing,
  });

  Future<void> revoke(String keyId);

  /// Deletes the project, its comments and keys, and its screenshots.
  Future<void> deleteProject(String projectId);
}

class SupabaseProjectRepository implements ProjectRepository {
  SupabaseProjectRepository(this._client);

  final SupabaseClient _client;

  static const String _keyColumns =
      'id, key, label, revoked_at, last_used_at, last_used_device, '
      'last_used_os, created_at';

  @override
  Future<List<Project>> list() async {
    try {
      final rows = await _client
          .from('projects')
          .select('id, name, created_at')
          .order('created_at');
      // Two reads, counted in Dart, the same trade `board()` makes: one row
      // per comment beats one count query per project, and RLS already scopes
      // the comments to the projects this user owns.
      final counts = await _client
          .from('comments')
          .select('project_id, status');

      final total = <String, int>{};
      final open = <String, int>{};
      for (final c in counts) {
        final id = c['project_id']?.toString();
        if (id == null) continue;
        total[id] = (total[id] ?? 0) + 1;
        if (c['status']?.toString() == 'open') {
          open[id] = (open[id] ?? 0) + 1;
        }
      }

      return [for (final row in rows) _project(row, total: total, open: open)];
    } on PostgrestException catch (e) {
      throw RepositoryException(
        describeDbError(e, doing: 'Could not load projects.'),
      );
    } on RepositoryException {
      rethrow;
    } catch (_) {
      // Offline: the HTTP layer's own exception, not a PostgrestException.
      throw const RepositoryException(
        'Could not load projects. Could not reach the database. Check your connection.',
        offline: true,
      );
    }
  }

  @override
  Future<(Project, ProjectKey)> create(String name) async {
    final owner = _client.auth.currentUser?.id;
    if (owner == null) {
      throw const RepositoryException('Sign in before creating a project.');
    }
    try {
      final row = await _client
          .from('projects')
          .insert({'owner_id': owner, 'name': name})
          .select('id, name, created_at')
          .single();
      final project = _project(row);
      final keys = await this.keys(project.id);
      if (keys.isEmpty) {
        // The trigger in 0006 makes this unreachable. Saying so beats
        // returning a project with a key nobody can use.
        throw const RepositoryException(
          'The project was created without a key. Check migration 0006.',
        );
      }
      return (project, keys.first);
    } on PostgrestException catch (e) {
      throw RepositoryException(
        describeDbError(e, doing: 'Could not create that project.'),
      );
    } on RepositoryException {
      rethrow;
    } catch (_) {
      // Offline: the HTTP layer's own exception, not a PostgrestException.
      throw const RepositoryException(
        'Could not create that project. Could not reach the database. Check your connection.',
        offline: true,
      );
    }
  }

  @override
  Future<List<ProjectKey>> keys(String projectId) async {
    try {
      final rows = await _client
          .from('project_keys')
          .select(_keyColumns)
          .eq('project_id', projectId)
          .order('created_at', ascending: false);
      return [for (final row in rows) _key(row)];
    } on PostgrestException catch (e) {
      throw RepositoryException(
        describeDbError(e, doing: 'Could not read the project keys.'),
      );
    } on RepositoryException {
      rethrow;
    } catch (_) {
      // Offline: the HTTP layer's own exception, not a PostgrestException.
      throw const RepositoryException(
        'Could not read the project keys. Could not reach the database. Check your connection.',
        offline: true,
      );
    }
  }

  @override
  Future<ProjectKey> rotate({
    required String projectId,
    required String replacing,
  }) async {
    try {
      final row = await _client
          .from('project_keys')
          .insert({'project_id': projectId, 'label': 'default'})
          .select(_keyColumns)
          .single();
      await revoke(replacing);
      return _key(row);
    } on PostgrestException catch (e) {
      throw RepositoryException(
        describeDbError(e, doing: 'Could not rotate that key.'),
      );
    } on RepositoryException {
      rethrow;
    } catch (_) {
      // Offline: the HTTP layer's own exception, not a PostgrestException.
      throw const RepositoryException(
        'Could not rotate that key. Could not reach the database. Check your connection.',
        offline: true,
      );
    }
  }

  @override
  Future<void> revoke(String keyId) async {
    try {
      final rows = await _client
          .from('project_keys')
          .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', keyId)
          .select('id');
      // RLS returns zero rows rather than an error for a key that is not
      // yours. A silent no-op here would read as a successful revocation.
      if (rows.isEmpty) {
        throw const RepositoryException(
          'That key could not be revoked. It may belong to another account.',
        );
      }
    } on PostgrestException catch (e) {
      throw RepositoryException(
        describeDbError(e, doing: 'Could not revoke that key.'),
      );
    } on RepositoryException {
      rethrow;
    } catch (_) {
      // Offline: the HTTP layer's own exception, not a PostgrestException.
      throw const RepositoryException(
        'Could not revoke that key. Could not reach the database. Check your connection.',
        offline: true,
      );
    }
  }

  static Project _project(
    Map<String, dynamic> row, {
    Map<String, int> total = const {},
    Map<String, int> open = const {},
  }) {
    final id = row['id'].toString();
    return Project(
      id: id,
      name: row['name']?.toString() ?? 'Untitled',
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      total: total[id] ?? 0,
      unread: open[id] ?? 0,
    );
  }

  static ProjectKey _key(Map<String, dynamic> row) => ProjectKey(
    id: row['id'].toString(),
    key: row['key']?.toString() ?? '',
    label: row['label']?.toString() ?? 'default',
    createdAt:
        DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    revokedAt: DateTime.tryParse(
      row['revoked_at']?.toString() ?? '',
    )?.toLocal(),
    lastUsedAt: DateTime.tryParse(
      row['last_used_at']?.toString() ?? '',
    )?.toLocal(),
    lastUsedDevice: _nonEmpty(row['last_used_device']),
    lastUsedOs: _nonEmpty(row['last_used_os']),
  );

  static String? _nonEmpty(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  @override
  Future<void> deleteProject(String projectId) async {
    // Screenshots first: the storage policy that lets an owner delete them
    // checks project ownership, so once the row is gone nobody could. A
    // failure here stops the delete rather than orphaning them (0010).
    final bucket = _client.storage.from('screenshots');
    try {
      while (true) {
        final page = await bucket.list(
          path: projectId,
          searchOptions: const SearchOptions(limit: 1000),
        );
        final paths = [for (final o in page) '$projectId/${o.name}'];
        if (paths.isEmpty) break;
        await bucket.remove(paths);
        if (page.length < 1000) break;
      }
    } catch (_) {
      throw const RepositoryException(
        'Could not delete the screenshots, so the project was not deleted. '
        'Try again.',
      );
    }
    try {
      await _client.from('projects').delete().eq('id', projectId);
    } on PostgrestException catch (e) {
      throw RepositoryException(
        describeDbError(e, doing: 'Could not delete the project.'),
      );
    } catch (_) {
      throw const RepositoryException(
        'Could not delete the project. '
        'Could not reach the database. Check your connection.',
        offline: true,
      );
    }
  }
}
