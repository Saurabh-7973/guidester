import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/comment_repository.dart' show RepositoryException;
import '../data/team_repository.dart';
import '../theme/tokens.dart';
import 'controls.dart';

/// Who is on a project, and, for the owner and admins, inviting and removing.
///
/// Invites are by email and Guidester sends no mail: the page gives the
/// inviter the dashboard address to send, and the invite turns into access
/// when that person signs in with that email, confirmed.
class TeamPanel extends StatefulWidget {
  const TeamPanel({
    super.key,
    required this.repository,
    required this.projectId,
    required this.myUserId,
    required this.myEmail,
    required this.dashboardUrl,
    this.onLeft,
  });

  final TeamRepository repository;
  final String projectId;
  final String? myUserId;
  final String myEmail;

  /// What an invitee opens. They sign up there with the invited email.
  final String dashboardUrl;

  /// After leaving the project.
  final VoidCallback? onLeft;

  @override
  State<TeamPanel> createState() => _TeamPanelState();
}

class _TeamPanelState extends State<TeamPanel> {
  TeamRole? _me;
  List<TeamMember> _members = const [];
  List<TeamInvite> _invites = const [];
  bool _loaded = false;
  String? _error;

  final _email = TextEditingController();
  TeamRole _role = TeamRole.member;
  TeamFunction? _function;
  bool _sending = false;
  String? _inviteError;

  /// The last invite sent, for the "send them this" note.
  String? _justInvited;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(TeamPanel old) {
    super.didUpdateWidget(old);
    if (old.projectId != widget.projectId) unawaited(_load());
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = await widget.repository.myRole(widget.projectId);
      final members = await widget.repository.members(widget.projectId);
      final invites = (me?.managesTeam ?? false)
          ? await widget.repository.invites(widget.projectId)
          : const <TeamInvite>[];
      if (!mounted) return;
      setState(() {
        _me = me;
        _members = members;
        _invites = invites;
        _loaded = true;
        _error = null;
      });
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _error = e.message;
      });
    }
  }

  Future<void> _invite() async {
    final email = _email.text.trim().toLowerCase();
    if (!looksLikeEmail(email)) {
      setState(
        () => _inviteError = 'Enter an email address, like name@company.com.',
      );
      return;
    }
    if (email == widget.myEmail.toLowerCase()) {
      setState(() => _inviteError = "That's you. You're already on it.");
      return;
    }
    setState(() {
      _sending = true;
      _inviteError = null;
    });
    try {
      await widget.repository.invite(
        projectId: widget.projectId,
        email: email,
        role: _role,
        function: _function,
      );
      _email.clear();
      if (!mounted) return;
      setState(() => _justInvited = email);
      await _load();
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _inviteError = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _revoke(TeamInvite i) async {
    try {
      await widget.repository.revokeInvite(i.id);
      await _load();
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _remove(TeamMember m) async {
    final leaving = m.userId == widget.myUserId;
    try {
      await widget.repository.removeMember(
        projectId: widget.projectId,
        userId: m.userId,
      );
      if (leaving) {
        widget.onLeft?.call();
        return;
      }
      await _load();
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manage = _me?.managesTeam ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Team', style: T.heading),
        const SizedBox(height: 6),
        Text(
          'Everyone here sees this project\'s board and status. '
          '${manage ? 'You can invite and remove people.' : 'The owner and admins manage the team.'}',
          style: T.supporting.copyWith(color: T.text3),
        ),
        const SizedBox(height: 16),
        if (!_loaded)
          const LinearProgressIndicator(minHeight: 2)
        else ...[
          if (_error != null) ...[
            Text(_error!, style: T.supporting.copyWith(color: T.red)),
            const SizedBox(height: 12),
          ],
          _Row(
            title: _me == TeamRole.owner
                ? '${widget.myEmail} (you)'
                : 'Project owner',
            role: TeamRole.owner,
          ),
          for (final m in _members)
            _Row(
              title: m.userId == widget.myUserId
                  ? '${m.email ?? 'You'} (you)'
                  : (m.email ?? 'Team member'),
              role: m.role,
              function: m.function,
              action: m.userId == widget.myUserId
                  ? ('Leave', () => _remove(m))
                  : manage
                  ? ('Remove', () => _remove(m))
                  : null,
            ),
          for (final i in _invites)
            _Row(
              title: i.email,
              role: i.role,
              function: i.function,
              pending: true,
              action: ('Revoke', () => _revoke(i)),
            ),
          if (manage) ...[const SizedBox(height: 24), _inviteForm()],
        ],
      ],
    );
  }

  Widget _inviteForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Invite someone', style: T.ui.copyWith(color: T.text2)),
      const SizedBox(height: 8),
      GField(
        key: const ValueKey('invite-email'),
        controller: _email,
        hint: 'name@company.com',
        keyboardType: TextInputType.emailAddress,
        error: _inviteError,
        onSubmitted: (_) => _invite(),
      ),
      const SizedBox(height: 12),
      Text('Can', style: T.meta.copyWith(color: T.text3)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final r in TeamRole.invitable)
            _Choice(
              label: r.label,
              selected: _role == r,
              onTap: () => setState(() => _role = r),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Text(_role.can, style: T.meta.copyWith(color: T.text3)),
      const SizedBox(height: 12),
      Text('Works on', style: T.meta.copyWith(color: T.text3)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final f in TeamFunction.values)
            _Choice(
              label: f.label,
              selected: _function == f,
              onTap: () =>
                  setState(() => _function = _function == f ? null : f),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: GButton(
          label: _sending ? 'Inviting…' : 'Invite',
          icon: Icons.person_add_alt,
          onPressed: _sending ? null : _invite,
        ),
      ),
      if (_justInvited != null) ...[
        const SizedBox(height: 16),
        _SendThem(email: _justInvited!, url: widget.dashboardUrl),
      ],
    ],
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.role,
    this.function,
    this.pending = false,
    this.action,
  });

  final String title;
  final TeamRole role;
  final TeamFunction? function;
  final bool pending;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final initial = title.isEmpty ? '?' : title[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: T.line)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: pending ? T.surface3 : T.surface4,
            child: Text(
              initial,
              style: T.meta.copyWith(
                color: pending ? T.text3 : T.text1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: T.body.copyWith(color: pending ? T.text2 : T.text1),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    role.label,
                    if (function != null) function!.label,
                    if (pending) 'invited, not joined yet',
                  ].join(' · '),
                  style: T.meta.copyWith(color: T.text3),
                ),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: action!.$2,
              style: TextButton.styleFrom(foregroundColor: T.text3),
              child: Text(action!.$1),
            ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: Material(
      color: selected ? T.accentSubtle : Colors.transparent,
      borderRadius: BorderRadius.circular(T.rPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.rPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(T.rPill),
            border: Border.all(color: selected ? T.accent : T.borderDefault),
          ),
          child: Text(
            label,
            style: T.meta.copyWith(
              color: selected ? T.accentText : T.text2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Guidester sends no mail, so it says what to send.
class _SendThem extends StatefulWidget {
  const _SendThem({required this.email, required this.url});

  final String email;
  final String url;

  @override
  State<_SendThem> createState() => _SendThemState();
}

class _SendThemState extends State<_SendThem> {
  bool _copied = false;

  String get _message =>
      "I've added you to our Guidester project. Open ${widget.url} and sign "
      'up (or log in) with ${widget.email}. Once your email is confirmed, the '
      'project is on your Projects page.';

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: T.surface2,
      borderRadius: BorderRadius.circular(T.rCard),
      border: Border.all(color: T.borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invited ${widget.email}. Guidester sends no email, so send them this:',
          style: T.supporting.copyWith(color: T.text2),
        ),
        const SizedBox(height: 8),
        SelectableText(_message, style: T.supporting.copyWith(color: T.text1)),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _message));
            if (mounted) setState(() => _copied = true);
          },
          icon: Icon(_copied ? Icons.check : Icons.content_copy, size: 14),
          label: Text(_copied ? 'Copied' : 'Copy message'),
          style: TextButton.styleFrom(
            foregroundColor: T.accentText,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    ),
  );
}
