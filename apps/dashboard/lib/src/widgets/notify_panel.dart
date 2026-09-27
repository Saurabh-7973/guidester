import 'dart:async';

import 'package:flutter/material.dart';

import '../data/comment_repository.dart' show RepositoryException;
import '../data/team_repository.dart';
import '../theme/tokens.dart';
import 'controls.dart';

/// Where new comments are announced: a Slack, Discord or Microsoft Teams
/// channel's incoming webhook. Owner and admins only; the URL is a
/// credential, so it is never shown to anyone else.
class NotifyPanel extends StatefulWidget {
  const NotifyPanel({
    super.key,
    required this.repository,
    required this.projectId,
  });

  final TeamRepository repository;
  final String projectId;

  @override
  State<NotifyPanel> createState() => _NotifyPanelState();
}

class _NotifyPanelState extends State<NotifyPanel> {
  final _url = TextEditingController();
  String? _saved;
  bool _loaded = false;
  bool _busy = false;
  String? _error;
  String? _note;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final url = await widget.repository.webhook(widget.projectId);
      if (!mounted) return;
      setState(() {
        _saved = url;
        _loaded = true;
      });
    } on RepositoryException catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    final service = webhookService(url);
    if (service == null) {
      setState(
        () => _error =
            'Paste an incoming-webhook URL from Slack (hooks.slack.com), '
            'Discord (discord.com/api/webhooks) or Microsoft Teams '
            '(….webhook.office.com).',
      );
      return;
    }
    await _write(url, 'Saved. The next comment posts to $service.');
  }

  Future<void> _write(String? url, String done) async {
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    try {
      await widget.repository.setWebhook(widget.projectId, url);
      _url.clear();
      if (!mounted) return;
      setState(() {
        _saved = url;
        _note = done;
      });
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The service and the last few characters: enough to recognise, not
  /// enough to post with.
  static String _masked(String url) {
    final service = webhookService(url) ?? 'Webhook';
    final tail = url.length > 4 ? url.substring(url.length - 4) : url;
    return '$service ••••$tail';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Notifications', style: T.heading),
      const SizedBox(height: 6),
      Text(
        'Post each new comment to a team channel as it arrives: impact, '
        'screen, the tester\'s words, device and build. Paste the channel\'s '
        'incoming-webhook URL from Slack, Discord or Microsoft Teams.',
        style: T.supporting.copyWith(color: T.text3),
      ),
      const SizedBox(height: 16),
      if (!_loaded)
        const LinearProgressIndicator(minHeight: 2)
      else ...[
        if (_saved != null) ...[
          Row(
            children: [
              const Icon(Icons.notifications_active, size: 16, color: T.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _masked(_saved!),
                  style: T.code.copyWith(color: T.text1),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _write(null, 'Removed. Nothing posts now.'),
                style: TextButton.styleFrom(foregroundColor: T.text3),
                child: const Text('Remove'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        GField(
          key: const ValueKey('webhook-url'),
          controller: _url,
          hint: _saved == null
              ? 'https://hooks.slack.com/services/…'
              : 'Paste a new URL to replace it',
          error: _error,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: GButton(
            label: _busy ? 'Saving…' : 'Save channel',
            kind: GButtonKind.secondary,
            onPressed: _busy ? null : _save,
          ),
        ),
        if (_note != null) ...[
          const SizedBox(height: 8),
          Text(_note!, style: T.supporting.copyWith(color: T.green)),
        ],
      ],
    ],
  );
}
