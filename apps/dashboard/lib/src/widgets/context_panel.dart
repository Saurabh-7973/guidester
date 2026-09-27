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
          for (final e in promoted.entries) _Row(name: e.key, value: e.value),
          if (promoted.isNotEmpty && columns.isNotEmpty)
            const Divider(height: 16),
          for (final e in columns.entries) _Row(name: e.key, value: e.value),
          if (extra.isNotEmpty) const Divider(height: 16),
          for (final e in extra.entries) _Row(name: e.key, value: e.value),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.name, required this.value});

  /// The key as the SDK sent it.
  final String name;
  final Object? value;

  /// Words for the keys the SDK sends today. Anything else is spaced out, so
  /// a key added later still shows (27 Sep audit: "text_scale_factor 2.00").
  static const Map<String, String> _labels = {
    'text_scale_factor': 'Text size',
    'platform_brightness': 'Theme',
    'is_physical_device': 'Physical device',
    'screen_resolver': 'Screen named by',
    'route_stack': 'Route stack',
    'device_model': 'Device',
    'os_version': 'OS',
    'app_version': 'App version',
    'build_number': 'Build',
    'package_name': 'Package',
    'sdk_version': 'Guidester SDK',
    'tester_name': 'Tester',
    'tester_id': 'Tester id',
    'device_pixel_ratio': 'Pixel ratio',
    'screen_w': 'Screen width',
    'screen_h': 'Screen height',
    'queued_at': 'Queued offline at',
  };

  /// Scales read as multipliers.
  static const Set<String> _times = {'text_scale_factor', 'device_pixel_ratio'};

  String get _label {
    final known = _labels[name];
    if (known != null) return known;
    final spaced = name.replaceAll('_', ' ').trim();
    return spaced.isEmpty
        ? name
        : spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// 2.0 is "2", 2.625 is "2.63": no padding zeros.
  static String _number(num n) {
    if (n == n.roundToDouble()) return n.round().toString();
    return n
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String get _rendered {
    final v = value;
    if (name == 'is_physical_device' && v is bool) {
      return v ? 'yes' : 'no (emulator or simulator)';
    }
    if (v is num && _times.contains(name)) return '${_number(v)}×';
    return switch (v) {
      null => '—',
      final List<dynamic> l => l.isEmpty ? '—' : l.join(' → '),
      final num n => _number(n),
      final bool b => b ? 'yes' : 'no',
      final Map<dynamic, dynamic> m => m.toString(),
      final Object o => o.toString(),
    };
  }

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
              _label,
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
