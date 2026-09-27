import 'package:dashboard/src/data/comment_repository.dart';
import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/models/workflow.dart';
import 'package:dashboard/src/routing/location.dart';
import 'package:dashboard/src/screens/status_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 28, 12);

Comment _c(
  String id, {
  Impact impact = Impact.annoying,
  DevVerdict dev = DevVerdict.isNew,
  TesterVerdict tester = TesterVerdict.open,
  String? blockedOn,
}) => Comment(
  id: id,
  body: 'comment $id',
  screenName: 'HOME',
  status: CommentStatus.open,
  createdAt: _now.subtract(const Duration(days: 2)),
  impact: impact,
  devVerdict: dev,
  testerVerdict: tester,
  blockedOn: blockedOn,
);

class _Source implements ReportSource {
  _Source(this.data, {this.fail = false});

  final Map<String, List<Comment>> data;
  final bool fail;
  int calls = 0;

  @override
  Future<Map<String, List<Comment>>> reportComments({String? projectId}) async {
    calls++;
    if (fail) throw const RepositoryException('Could not reach the database.');
    return data;
  }
}

const _projects = <StatusProject>[
  (id: 'a', name: 'Shop'),
  (id: 'b', name: 'Bank'),
];

void main() {
  late String? openedReport;
  late (String, String?)? openedBoard;
  late String? copied;

  setUp(() {
    openedReport = 'unset';
    openedBoard = null;
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });

  Future<void> pump(
    WidgetTester tester,
    ReportSource source, {
    String? projectId,
  }) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: StatusScreen(
            source: source,
            projects: _projects,
            projectId: projectId,
            now: () => _now,
            onOpenReport: (id) => openedReport = id,
            onOpenBoard: (p, c) => openedBoard = (p, c),
            linkFor: (id) => 'https://dash.example/#/p/$id/status',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final source = _Source({
    'a': [_c('1', impact: Impact.blocked), _c('2', dev: DevVerdict.fixed)],
    'b': [_c('3', dev: DevVerdict.fixed, tester: TesterVerdict.accepted)],
  });

  testWidgets('the overview shows every project and whether it can ship', (
    tester,
  ) async {
    await pump(tester, source);

    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Bank'), findsOneWidget);
    expect(find.text('Not ready to release'), findsOneWidget);
    expect(find.text('Ready to release'), findsOneWidget);
    expect(find.textContaining('1 not ready'), findsOneWidget);

    await tester.tap(find.text('Shop'));
    expect(openedReport, 'a');
  });

  testWidgets('copy all puts every project on the clipboard', (tester) async {
    await pump(tester, source);
    await tester.tap(find.text('Copy all as text'));
    await tester.pump();

    expect(copied, contains('## Shop: status 28 Sep 2026'));
    expect(copied, contains('## Bank: status 28 Sep 2026'));
    expect(copied, contains('https://dash.example/#/p/a/status'));
    expect(find.textContaining('Copied'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('a project report lists each team and opens the comment', (
    tester,
  ) async {
    await pump(tester, source, projectId: 'a');

    expect(find.text('Not ready to release'), findsOneWidget);
    expect(find.textContaining('1 blocking issue stops testers'), findsOne);
    expect(find.text('Lead / CTO'), findsOneWidget);
    expect(find.text('QA'), findsOneWidget);

    // Narrow to QA: only the fixed, unverified one.
    await tester.tap(find.text('QA 1'));
    await tester.pumpAndSettle();
    expect(find.text('Lead / CTO'), findsNothing);
    await tester.tap(find.text('comment 2'));
    expect(openedBoard, ('a', '2'));

    await tester.tap(find.text('All projects'));
    expect(openedReport, isNull);
  });

  testWidgets('copy report is the project alone, with its link', (
    tester,
  ) async {
    await pump(tester, source, projectId: 'a');
    await tester.tap(find.text('Copy report'));
    await tester.pump();
    expect(copied, startsWith('## Shop'));
    expect(copied, isNot(contains('Bank')));
    expect(copied, contains('https://dash.example/#/p/a/status'));
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('an empty project says so rather than drawing zeros', (
    tester,
  ) async {
    await pump(tester, _Source({}), projectId: 'b');
    expect(find.textContaining('No comments yet'), findsOneWidget);
    expect(find.text('Open work'), findsNothing);
  });

  testWidgets('an unknown project offers the way back', (tester) async {
    await pump(tester, source, projectId: 'zzz');
    expect(find.textContaining("doesn't exist"), findsOneWidget);
    await tester.tap(find.text('All projects'));
    expect(openedReport, isNull);
  });

  testWidgets('a failed load says why and retries', (tester) async {
    final failing = _Source({}, fail: true);
    await pump(tester, failing);
    expect(find.text('Could not reach the database.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(failing.calls, 2);
  });

  testWidgets('a phone-width report stacks without overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: StatusScreen(
            source: source,
            projects: _projects,
            projectId: 'a',
            now: () => _now,
            onOpenReport: (_) {},
            onOpenBoard: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('addresses', () {
    test('/status and /p/:id/status round-trip', () {
      for (final path in ['/status', '/p/abc/status']) {
        final loc = DashboardLocation.parse(Uri.parse(path))!;
        expect(loc.path, path);
      }
      expect(
        DashboardLocation.parse(Uri.parse('/p/abc/status')),
        const DashboardLocation.status(projectId: 'abc'),
      );
      expect(
        DashboardLocation.parse(Uri.parse('/p/abc/status'))!.isBoard,
        isFalse,
      );
    });
  });
}
