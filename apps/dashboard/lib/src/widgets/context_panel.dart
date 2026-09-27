import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../theme/app_theme.dart';

/// Renders the jsonb long tail. This is the v0 answer to "which device were
/// you on?", so it favours completeness over prettiness — anything the SDK
/// sends shows up here, including keys added after this code was written.
class ContextPanel extends StatelessWidget {
  const ContextPanel({super.key, required this.comment});

  final Comment comment;

  /// Surfaced first because they close most UI reports: a large font scale,
  /// dark mode, or an emulator.
  static const List<String> _priority = [
    'text_scale_factor',
    'platform_brightness',
    'is_physical_device',
    'screen_resolver',
    'route_stack',
  ];

  @override
  Widget build(BuildContext context) {
    final columns = <String, Object?>{
      'device_model': comment.deviceModel,
      'os_version': comment.osVersion,
      'app_version': comment.appVersion,
      'tester_name': comment.testerName,
      'tester_id': comment.testerId,
    }..removeWhere((_, v) => v == null);

    final extra = Map<String, Object?>.from(comment.context);
    final promoted = {
      for (final k in _priority)
        if (extra.containsKey(k)) k: extra.remove(k),
    };

    return Card(
      child: ExpansionTile(
        title: const Text('Device context', style: TextStyle(fontSize: 14)),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        initiallyExpanded: true,
        children: [
          for (final e in promoted.entries) _Row(label: e.key, value: e.value),
          if (promoted.isNotEmpty && columns.isNotEmpty)
            const Divider(height: 16),
          for (final e in columns.entries) _Row(label: e.key, value: e.value),
          if (extra.isNotEmpty) const Divider(height: 16),
          for (final e in extra.entries) _Row(label: e.key, value: e.value),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final Object? value;

  String get _rendered => switch (value) {
    null => '—',
    final List<dynamic> l => l.isEmpty ? '—' : l.join(' → '),
    final double d => d.toStringAsFixed(2),
    final Map<dynamic, dynamic> m => m.toString(),
    final Object o => o.toString(),
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.muted,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              _rendered,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
