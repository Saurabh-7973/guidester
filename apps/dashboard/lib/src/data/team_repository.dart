import 'package:supabase_flutter/supabase_flutter.dart';

import 'comment_repository.dart' show RepositoryException;

/// What someone may do on a project. The owner is `projects.owner_id`, never a
/// row in `project_members` (0013), so nothing here can take a project away.
enum TeamRole {
  owner('owner', 'Owner', 'Everything, and the only one who can delete it'),
  admin('admin', 'Admin', 'Triage, delete, manage keys and the team'),
  member('member', 'Member', 'Triage: verdicts, notes, assignees'),
  viewer('viewer', 'Viewer', 'Reads the board and status, changes nothing');

  const TeamRole(this.wire, this.label, this.can);

  final String wire;
  final String label;

  /// One line on what the role allows, shown where it is chosen.
  final String can;

  bool get managesTeam => this == owner || this == admin;
  bool get triages => this != viewer;
  bool get deletes => this == owner || this == admin;

  static TeamRole? fromWire(String? v) =>
      values.where((r) => r.wire == v).firstOrNull;

  /// The roles an invite can carry.
  static const List<TeamRole> invitable = [member, admin, viewer];
}

/// What someone works on. Access never depends on it; the dashboard uses it
/// to open each person on their own list.
enum TeamFunction {
  developer('developer', 'Developer'),
  qa('qa', 'QA'),
  design('design', 'UI / UX'),
  product('product', 'Product / BA'),
  backend('backend', 'Backend'),
  frontend('frontend', 'Frontend'),
  support('support', 'Support'),
  lead('lead', 'Lead / CTO');

  const TeamFunction(this.wire, this.label);

  final String wire;
  final String label;

  static TeamFunction? fromWire(String? v) =>
      values.where((f) => f.wire == v).firstOrNull;
}

class TeamMember {
  const TeamMember({
    required this.userId,
    required this.role,
    this.email,
    this.function,
  });

  final String userId;
  final String? email;
  final TeamRole role;
  final TeamFunction? function;
}

class TeamInvite {
  const TeamInvite({
    required this.id,
    required this.email,
    required this.role,
    this.function,
  });

  final String id;
  final String email;
  final TeamRole role;
  final TeamFunction? function;
}

abstract class TeamRepository {
  /// Turns invites to the signed-in user's confirmed email into membership.
  /// Returns how many projects were joined.
  Future<int> acceptInvites();

  /// The signed-in user's role on [projectId], or null for none.
  Future<TeamRole?> myRole(String projectId);

  Future<List<TeamMember>> members(String projectId);

  /// Live invites: not accepted, not revoked. Owners and admins only (RLS).
  Future<List<TeamInvite>> invites(String projectId);

  Future<void> invite({
    required String projectId,
    required String email,
    required TeamRole role,
    TeamFunction? function,
  });

  Future<void> revokeInvite(String inviteId);

  /// Removes someone, or, with your own id, leaves.
  Future<void> removeMember({
    required String projectId,
    required String userId,
  });
}

/// A plausible address: something, @, something with a dot. The database
/// checks too; this is for saying so before the round trip.
bool looksLikeEmail(String s) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

class SupabaseTeamRepository implements TeamRepository {
  SupabaseTeamRepository(this._client);

  final SupabaseClient _client;

  Future<T> _run<T>(String doing, Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      final message = switch (e.code) {
        '23505' => '$doing That person already has an invite.',
        '42501' => '$doing Only the owner or an admin can do that.',
        '23514' => '$doing Check the email address.',
        _ => '$doing ${e.message}',
      };
      throw RepositoryException(message);
    } catch (_) {
      throw RepositoryException(
        '$doing Could not reach the database. Check your connection.',
        offline: true,
      );
    }
  }

  @override
  Future<int> acceptInvites() => _run('Could not accept invites.', () async {
    final n = await _client.rpc<dynamic>('accept_project_invites');
    return n is int ? n : int.tryParse('$n') ?? 0;
  });

  @override
  Future<TeamRole?> myRole(String projectId) =>
      _run('Could not read your role.', () async {
        final r = await _client.rpc<dynamic>(
          'project_role',
          params: {'p_project': projectId},
        );
        return TeamRole.fromWire(r?.toString());
      });

  @override
  Future<List<TeamMember>> members(String projectId) =>
      _run('Could not load the team.', () async {
        final rows = await _client
            .from('project_members')
            .select('user_id, email, role, team')
            .eq('project_id', projectId)
            .order('created_at');
        return [
          for (final r in rows)
            TeamMember(
              userId: r['user_id'].toString(),
              email: r['email']?.toString(),
              role: TeamRole.fromWire(r['role']?.toString()) ?? TeamRole.viewer,
              function: TeamFunction.fromWire(r['team']?.toString()),
            ),
        ];
      });

  @override
  Future<List<TeamInvite>> invites(String projectId) =>
      _run('Could not load invites.', () async {
        final rows = await _client
            .from('project_invites')
            .select('id, email, role, team')
            .eq('project_id', projectId)
            .isFilter('accepted_at', null)
            .isFilter('revoked_at', null)
            .order('created_at');
        return [
          for (final r in rows)
            TeamInvite(
              id: r['id'].toString(),
              email: r['email'].toString(),
              role: TeamRole.fromWire(r['role']?.toString()) ?? TeamRole.viewer,
              function: TeamFunction.fromWire(r['team']?.toString()),
            ),
        ];
      });

  @override
  Future<void> invite({
    required String projectId,
    required String email,
    required TeamRole role,
    TeamFunction? function,
  }) => _run('Could not invite.', () async {
    await _client.from('project_invites').insert({
      'project_id': projectId,
      'email': email.trim().toLowerCase(),
      'role': role.wire,
      'team': function?.wire,
    });
  });

  @override
  Future<void> revokeInvite(String inviteId) =>
      _run('Could not revoke the invite.', () async {
        await _client
            .from('project_invites')
            .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', inviteId);
      });

  @override
  Future<void> removeMember({
    required String projectId,
    required String userId,
  }) => _run('Could not remove them.', () async {
    await _client
        .from('project_members')
        .delete()
        .eq('project_id', projectId)
        .eq('user_id', userId);
  });
}
