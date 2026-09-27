import 'package:dashboard/src/models/captured_error.dart';
import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/models/issue_export.dart';
import 'package:dashboard/src/models/workflow.dart';
import 'package:flutter_test/flutter_test.dart';

Comment _c({
  String body = 'The pay button hides behind the keyboard',
  List<CapturedError> errors = const [],
  Map<String, dynamic> context = const {},
}) => Comment(
  id: 'c1',
  body: body,
  screenName: 'CHECKOUT',
  status: CommentStatus.open,
  createdAt: DateTime(2026, 9, 27, 14, 5),
  impact: Impact.blocked,
  testerName: 'Priya',
  testerId: 'tester-uuid-should-not-leak',
  deviceModel: 'Pixel 7',
  osVersion: 'Android 15',
  appVersion: '1.0.1',
  devVerdict: DevVerdict.fixed,
  testerVerdict: TesterVerdict.rejected,
  assignee: 'ana',
  errors: errors,
  context: context,
);

void main() {
  test('title, body and the facts a developer asks for', () {
    final md = issueMarkdown(_c(), link: 'https://dash/#/p/1/c/c1');
    final lines = md.split('\n');
    expect(lines.first, '# [Blocked] The pay button hides behind the keyboard');
    expect(md, contains('The pay button hides behind the keyboard'));
    expect(md, contains('| Screen | CHECKOUT |'));
    expect(md, contains('| Device | Pixel 7, Android 15 |'));
    expect(md, contains('| App version | 1.0.1 |'));
    expect(md, contains('| Reported | Priya, 27 Sep 2026 14:05 |'));
    expect(md, contains('| Verdicts | Dev: Fixed · Tester: Still broken |'));
    expect(md, contains('| Assignee | ana |'));
    expect(md, contains('[Open in Guidester](https://dash/#/p/1/c/c1)'));
  });

  test('never carries the tester id', () {
    expect(issueMarkdown(_c()), isNot(contains('tester-uuid')));
  });

  test('a long first line is cut for the title, the body stays whole', () {
    final long = 'word ' * 40;
    final md = issueMarkdown(_c(body: '$long\nsecond line'));
    final title = md.split('\n').first;
    expect(title.length, lessThanOrEqualTo(90));
    expect(title, endsWith('…'));
    expect(md, contains('second line'));
  });

  test('the error before the report goes in a code block, trimmed', () {
    final stack = List.generate(40, (i) => '#$i frame$i').join('\n');
    final md = issueMarkdown(
      _c(
        errors: [CapturedError(exception: 'StateError: bad', stack: stack)],
      ),
    );
    expect(md, contains('### Error before the report'));
    expect(md, contains('```\nStateError: bad\n#0 frame0'));
    expect(md, contains('#11 frame11'));
    expect(md, isNot(contains('#12 frame12')));
  });

  test('route and text size come along when the SDK sent them', () {
    final md = issueMarkdown(
      _c(
        context: {
          'route_stack': ['/home', '/cart'],
          'text_scale_factor': 2.0,
        },
      ),
    );
    expect(md, contains('| Route | /home → /cart |'));
    expect(md, contains('| Text size | 2× |'));
  });

  test('a pipe in a value does not break the table', () {
    final c = _c().copyWith(assignee: 'a|b');
    expect(issueMarkdown(c), contains(r'| Assignee | a\|b |'));
  });
}
