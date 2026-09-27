import 'package:dashboard/src/data/comment_repository.dart';
import 'package:dashboard/src/data/team_repository.dart';

/// A team in memory. [role] is the signed-in user's.
class FakeTeam implements TeamRepository {
  FakeTeam({this.role = TeamRole.owner});

  TeamRole? role;
  final people = <TeamMember>[
    const TeamMember(
      userId: 'u-ana',
      email: 'ana@team.com',
      role: TeamRole.member,
      function: TeamFunction.qa,
    ),
  ];
  final invited = <TeamInvite>[];
  int accepted = 0;
  final removed = <String>[];

  @override
  Future<int> acceptInvites() async => ++accepted;

  @override
  Future<TeamRole?> myRole(String projectId) async => role;

  @override
  Future<List<TeamMember>> members(String projectId) async => List.of(people);

  @override
  Future<List<TeamInvite>> invites(String projectId) async {
    if (!(role?.managesTeam ?? false)) {
      throw const RepositoryException('not allowed');
    }
    return List.of(invited);
  }

  @override
  Future<void> invite({
    required String projectId,
    required String email,
    required TeamRole role,
    TeamFunction? function,
  }) async {
    if (invited.any((i) => i.email == email)) {
      throw const RepositoryException(
        'Could not invite. That person already has an invite.',
      );
    }
    invited.add(
      TeamInvite(
        id: 'i${invited.length}',
        email: email,
        role: role,
        function: function,
      ),
    );
  }

  @override
  Future<void> revokeInvite(String inviteId) async =>
      invited.removeWhere((i) => i.id == inviteId);

  @override
  Future<void> removeMember({
    required String projectId,
    required String userId,
  }) async {
    removed.add(userId);
    people.removeWhere((m) => m.userId == userId);
  }
}
