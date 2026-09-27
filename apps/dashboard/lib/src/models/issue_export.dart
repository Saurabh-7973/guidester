import 'comment.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// A comment as an issue: pasted into GitHub, Jira, Linear or a chat, it
/// carries what a developer would otherwise ask the tester for.
///
/// The tester id never goes out: an issue tracker is a wider audience than
/// the dashboard, and the id is only a handle for erasing someone's data.
String issueMarkdown(Comment c, {String? link}) {
  final firstLine = c.body.trim().split('\n').first.trim();
  final impact = c.impact.label[0] + c.impact.label.substring(1).toLowerCase();
  var title = '[$impact] $firstLine';
  if (title.length > 88) title = '${title.substring(0, 87).trimRight()}…';

  final at = c.createdAt;
  final when =
      '${at.day} ${_months[at.month - 1]} ${at.year} '
      '${_two(at.hour)}:${_two(at.minute)}';
  final device = [c.deviceModel, c.osVersion].whereType<String>().join(', ');
  final route = c.context['route_stack'];
  final scale = c.context['text_scale_factor'];

  final rows = <(String, String)>[
    ('Screen', c.screenName),
    if (device.isNotEmpty) ('Device', device),
    if (c.appVersion != null) ('App version', c.appVersion!),
    ('Reported', c.testerName == null ? when : '${c.testerName}, $when'),
    (
      'Verdicts',
      'Dev: ${c.devVerdict.label} · Tester: ${c.testerVerdict.label}',
    ),
    if (c.assignee != null && c.assignee!.isNotEmpty) ('Assignee', c.assignee!),
    if (route is List && route.isNotEmpty) ('Route', route.join(' → ')),
    if (scale is num && scale != 1) ('Text size', '${_number(scale)}×'),
  ];

  final b = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln(c.body.trim())
    ..writeln()
    ..writeln('| | |')
    ..writeln('|---|---|');
  for (final (k, v) in rows) {
    b.writeln('| $k | ${v.replaceAll('|', r'\|').replaceAll('\n', ' ')} |');
  }
  final error = c.errors.lastOrNull;
  if (error != null) {
    final frames = error.stack
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(12);
    b
      ..writeln()
      ..writeln('### Error before the report')
      ..writeln()
      ..writeln('```')
      ..writeln(error.exception.replaceAll('```', "'''"));
    for (final f in frames) {
      b.writeln(f.replaceAll('```', "'''"));
    }
    b.writeln('```');
  }
  if (link != null) {
    b
      ..writeln()
      ..writeln('[Open in Guidester]($link)');
  }
  return b.toString();
}

String _number(num n) =>
    n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(2);
