import 'dart:async';

import 'package:flutter/material.dart';

import '../config/env.dart';
import '../data/auth_gateway.dart';

import '../data/comment_repository.dart' show RepositoryException;
import '../data/project_repository.dart';
import '../data/team_repository.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/notify_panel.dart';
import '../widgets/team_panel.dart';
import 'onboarding_screen.dart' show CodeBlock, installSnippet;

/// Spec §7. Two columns at x=409 and x=773, each 250 wide.
///
/// The right column holds **API keys, not a subscription**. Billing does not
/// exist, and a plan you cannot change is dead furniture; keys are what a user
/// actually opens Settings for. Same geometry, same row style as the frame's
/// subscription block.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.email,
    this.name,
    this.auth,
    this.onNameSaved,
    this.projectName,
    this.onProjectDeleted,
    this.projects,
    this.projectId,
    this.apiKeyMasked,
    this.apiKeyCreated,
    this.apiKeyLastUsed,
    this.onRotate,
    this.onRevoke,
    this.team,
    this.myUserId,
    this.dashboardUrl = '',
    this.onLeftProject,
  });

  final String email;
  final String? name;

  /// Saves the name. Null leaves Save Changes out.
  final AuthGateway? auth;
  final ValueChanged<String>? onNameSaved;

  /// The project whose key this is; its name is what the delete asks for.
  final String? projectName;

  /// After the project is gone. Null leaves Delete project out.
  final VoidCallback? onProjectDeleted;

  /// Where the key column gets its data. Both of these or neither: with no
  /// project selected there is no key to show, and Settings renders the
  /// account half alone rather than guessing which project was meant.
  final ProjectRepository? projects;
  final String? projectId;

  /// Masked on purpose. The full key is shown once, during onboarding, and
  /// never again — a key that can be read off a screen is a key in a
  /// screenshot. These three are for callers that already hold a key, such as
  /// a test; a repository supersedes them.
  final String? apiKeyMasked;
  final String? apiKeyCreated;
  final String? apiKeyLastUsed;

  final VoidCallback? onRotate;
  final VoidCallback? onRevoke;

  /// The project's team. Null leaves the Team section out, and with it the
  /// role checks: a solo owner sees Settings as before.
  final TeamRepository? team;
  final String? myUserId;

  /// Where an invitee signs up.
  final String dashboardUrl;

  /// After leaving someone else's project.
  final VoidCallback? onLeftProject;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const double _columnWidth = 250;
  static const double _columnGap = 364 - _columnWidth;

  ProjectKey? _key;
  bool _busy = false;
  String? _error;

  /// The signed-in user's role here. Null until known, or with no team repo:
  /// then everything shows, as it did before teams, and RLS still decides.
  TeamRole? _role;

  bool get _managesKeys => _role == null || _role!.managesTeam;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadRole());
  }

  Future<void> _loadRole() async {
    final team = widget.team;
    final id = widget.projectId;
    if (team == null || id == null) return;
    try {
      final role = await team.myRole(id);
      if (mounted) setState(() => _role = role);
    } on RepositoryException {
      // Unknown role: show what the owner would see; RLS still decides.
    }
  }

  /// §5.6 row 8: the install, again, for when onboarding was skipped or the
  /// key was rotated. Shown masked like the key above; Copy copies it whole.
  List<Widget> _install() {
    final key = _key;
    if (key == null || key.isRevoked) return const [];
    final endpoint = Env.ingestEndpoint;
    return [
      const SizedBox(height: 32),
      Text('Install', style: T.ui.copyWith(color: T.text2)),
      const SizedBox(height: 8),
      CodeBlock(
        code: installSnippet(apiKey: key.masked, endpoint: endpoint),
        copyText: installSnippet(apiKey: key.key, endpoint: endpoint),
        copyable: true,
      ),
    ];
  }

  /// §5.6 row 8: delete the project, confirmed by typing its name.
  List<Widget> _danger() {
    final repo = widget.projects;
    final id = widget.projectId;
    final name = widget.projectName;
    if (repo == null || id == null || name == null) return const [];
    if (widget.onProjectDeleted == null) return const [];
    // Only the owner can delete a project (0010); an admin cannot.
    if (_role != null && _role != TeamRole.owner) return const [];
    return [
      const SizedBox(height: 40),
      Text('Delete project', style: T.ui.copyWith(color: T.text2)),
      const SizedBox(height: 8),
      Text(
        'Removes the project, every comment and screenshot in it, and its '
        'keys. Builds with its key stop sending.',
        style: T.supporting.copyWith(color: T.text3),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: GButton(
          label: 'Delete project',
          kind: GButtonKind.danger,
          onPressed: () => _confirmDelete(repo, id, name),
        ),
      ),
    ];
  }

  Future<void> _confirmDelete(
    ProjectRepository repo,
    String id,
    String name,
  ) async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteProjectDialog(
        name: name,
        onDelete: () => repo.deleteProject(id),
      ),
    );
    if (deleted == true && mounted) widget.onProjectDeleted?.call();
  }

  Future<void> _load() async {
    final repo = widget.projects;
    final projectId = widget.projectId;
    if (repo == null || projectId == null) return;
    try {
      final keys = await repo.keys(projectId);
      if (!mounted) return;
      // The live one. A revoked key stays in the table so its comments keep a
      // provenance, but it is not what Settings is about.
      setState(() {
        _key = keys.where((k) => !k.isRevoked).firstOrNull ?? keys.firstOrNull;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// Both actions stop installed builds from reporting, which is not something
  /// to discover after clicking. The dialog says what breaks, in those words.
  Future<bool> _confirm(String title, String detail, String action) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: T.surface1,
        title: Text(title, style: T.heading),
        content: SizedBox(
          width: 380,
          child: Text(detail, style: T.body.copyWith(color: T.text2)),
        ),
        actions: [
          GButtonOutlined(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          GButton(
            label: action,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _rotate() async {
    final repo = widget.projects;
    final projectId = widget.projectId;
    final current = _key;
    if (repo == null || projectId == null || current == null || _busy) return;
    final ok = await _confirm(
      'Rotate this key?',
      'A new key is created and this one is revoked. Every build already '
          'installed on a tester\'s device stops reporting until they install '
          'a build carrying the new key.',
      'Rotate',
    );
    if (!ok) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fresh = await repo.rotate(
        projectId: projectId,
        replacing: current.id,
      );
      if (!mounted) return;
      setState(() => _key = fresh);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    final repo = widget.projects;
    final current = _key;
    if (repo == null || current == null || _busy) return;
    final ok = await _confirm(
      'Revoke this key?',
      'Every installed build stops reporting immediately, and no new key is '
          'created. Rotate instead if you want the project to keep working.',
      'Revoke',
    );
    if (!ok) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.revoke(current.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _masked => _key?.masked ?? widget.apiKeyMasked;

  String? get _created =>
      _key == null ? widget.apiKeyCreated : _date(_key!.createdAt);

  String? get _lastUsed {
    final key = _key;
    if (key == null) return widget.apiKeyLastUsed;
    if (key.lastUsedAt == null) return null;
    final device = key.lastUsedDescription;
    final when = _date(key.lastUsedAt!);
    return device == null ? when : '$device, $when';
  }

  static String _date(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final account = _Account(
      email: widget.email,
      name: widget.name,
      auth: widget.auth,
      onSaved: widget.onNameSaved,
    );
    final keys = _ApiKey(
      masked: _masked,
      created: _created,
      lastUsed: _lastUsed,
      revoked: _key?.isRevoked ?? false,
      canManage: _managesKeys,
      error: _error,
      busy: _busy,
      onRotate: !_managesKeys
          ? null
          : (widget.projects != null ? _rotate : widget.onRotate),
      onRevoke: !_managesKeys
          ? null
          : (widget.projects != null ? _revoke : widget.onRevoke),
    );
    final team = widget.team;
    final id = widget.projectId;
    final notify = team == null || id == null || !(_role?.managesTeam ?? false)
        ? null
        : NotifyPanel(repository: team, projectId: id);
    final teamPanel = team == null || id == null
        ? null
        : TeamPanel(
            repository: team,
            projectId: id,
            myUserId: widget.myUserId,
            myEmail: widget.email,
            dashboardUrl: widget.dashboardUrl,
            onLeft: widget.onLeftProject,
          );
    // Two columns where they fit, as in the frame; stacked on a phone.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _columnWidth * 2 + _columnGap) {
          final row = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: _columnWidth, child: account),
              const SizedBox(width: _columnGap),
              SizedBox(
                width: _columnWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [keys, ..._install(), ..._danger()],
                ),
              ),
            ],
          );
          if (teamPanel == null) {
            return Padding(padding: const EdgeInsets.only(top: 58), child: row);
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.only(top: 58, bottom: 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row,
                const SizedBox(height: 48),
                teamPanel,
                if (notify != null) ...[const SizedBox(height: 48), notify],
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              account,
              const SizedBox(height: 40),
              keys,
              ..._install(),
              ..._danger(),
              if (teamPanel != null) ...[const SizedBox(height: 40), teamPanel],
              if (notify != null) ...[const SizedBox(height: 40), notify],
            ],
          ),
        );
      },
    );
  }
}

class _Account extends StatefulWidget {
  const _Account({required this.email, this.name, this.auth, this.onSaved});

  final String email;
  final String? name;
  final AuthGateway? auth;
  final ValueChanged<String>? onSaved;

  @override
  State<_Account> createState() => _AccountState();
}

class _AccountState extends State<_Account> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.email,
  );
  late String _savedName = widget.name ?? '';
  bool _busy = false;
  String? _message;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (_message != null && _name.text.trim() != _savedName) {
        setState(() => _message = null);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  // §7: Save Changes stays disabled until the name actually changes.
  bool get _dirty {
    final n = _name.text.trim();
    return n.isNotEmpty && n != _savedName;
  }

  Future<void> _save() async {
    final auth = widget.auth;
    if (auth == null || !_dirty || _busy) return;
    final name = _name.text.trim();
    setState(() => _busy = true);
    final outcome = await auth.saveName(name);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (outcome is AuthFailed) {
        _failed = true;
        _message = outcome.message;
      } else {
        _failed = false;
        _message = 'Saved';
        _savedName = name;
      }
    });
    if (outcome is! AuthFailed) widget.onSaved?.call(name);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Account Info', style: T.heading),
        const SizedBox(height: 37),
        GField(
          controller: _name,
          hint: 'Name',
          enabled: widget.auth != null && !_busy,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 14),
        // Read-only: changing the sign-in address needs a confirmation mail
        // to both addresses, and that flow does not exist yet.
        GField(controller: _email, hint: 'Email', enabled: false),
        const SizedBox(height: 26),
        Row(
          children: [
            GButton(
              label: 'Save Changes',
              busy: _busy,
              onPressed: _dirty && widget.auth != null ? _save : null,
            ),
            if (_message != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _message!,
                    style: T.supporting.copyWith(
                      color: _failed ? T.red : T.text2,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ApiKey extends StatelessWidget {
  const _ApiKey({
    required this.masked,
    required this.created,
    required this.lastUsed,
    required this.onRotate,
    required this.onRevoke,
    this.canManage = true,
    this.revoked = false,
    this.busy = false,
    this.error,
  });

  final String? masked;
  final String? created;
  final String? lastUsed;
  final bool revoked;
  final bool busy;
  final String? error;
  final VoidCallback? onRotate;
  final VoidCallback? onRevoke;

  /// False for a member: the key shows, the buttons do not.
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('API Keys', style: T.heading),
        const SizedBox(height: 37),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: T.surface2,
            borderRadius: BorderRadius.circular(T.rControl),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  masked ?? 'No key yet',
                  style: T.supporting.copyWith(fontFamily: T.mono),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (created != null) _MetaLine(label: 'Created', value: created!),
        if (lastUsed != null) _MetaLine(label: 'Last used', value: lastUsed!),
        if (lastUsed == null && masked != null)
          const _MetaLine(label: 'Last used', value: 'never'),
        if (revoked) const _MetaLine(label: 'Status', value: 'revoked'),
        const SizedBox(height: 18),
        if (canManage)
          Row(
            children: [
              GButton(label: 'Rotate', busy: busy, onPressed: onRotate),
              const SizedBox(width: 12),
              GButtonOutlined(
                label: 'Revoke',
                onPressed: revoked ? null : onRevoke,
              ),
            ],
          )
        else
          Text(
            'The owner or an admin rotates and revokes keys.',
            style: T.supporting.copyWith(color: T.text3),
          ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: T.supporting.copyWith(color: T.red)),
        ],
        const SizedBox(height: 14),
        Text(
          'The key ships inside your test build and is extractable from any '
          'APK by design. Rotate it before a closed test, and after anyone '
          'leaves it.',
          style: T.supporting.copyWith(fontSize: 12, color: T.text3),
        ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label, style: T.supporting.copyWith(color: T.text3)),
          const SizedBox(width: 8),
          // The value flexes and the label does not: "Pixel 7, Android 15,
          // 2026-09-09" is longer than the 250 column, and a device name
          // nobody anticipated will be longer still.
          Expanded(
            child: Text(
              value,
              style: T.supporting.copyWith(color: T.text2),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteProjectDialog extends StatefulWidget {
  const _DeleteProjectDialog({required this.name, required this.onDelete});

  final String name;
  final Future<void> Function() onDelete;

  @override
  State<_DeleteProjectDialog> createState() => _DeleteProjectDialogState();
}

class _DeleteProjectDialogState extends State<_DeleteProjectDialog> {
  final _typed = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _matches => _typed.text.trim() == widget.name;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDelete();
      if (mounted) Navigator.of(context).pop(true);
    } on RepositoryException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: T.surface1,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Delete ${widget.name}?', style: T.heading),
              const SizedBox(height: 10),
              Text(
                'Every comment, screenshot and key in it goes, for good. '
                'Type ${widget.name} to confirm.',
                style: T.supporting.copyWith(color: T.text2),
              ),
              const SizedBox(height: 16),
              GField(
                controller: _typed,
                hint: widget.name,
                autofocus: true,
                enabled: !_busy,
                error: _error,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GButton(
                    label: 'Cancel',
                    kind: GButtonKind.ghost,
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  GButton(
                    label: 'Delete forever',
                    kind: GButtonKind.danger,
                    busy: _busy,
                    onPressed: _matches ? _delete : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
