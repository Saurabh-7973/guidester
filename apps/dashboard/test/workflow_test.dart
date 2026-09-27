import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/models/workflow.dart';
import 'package:dashboard/src/theme/tokens.dart';
import 'package:dashboard/src/widgets/workflow_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The loop: a tester reports, a developer moves it, a tester retests.
///
/// Modelled from a real team's sheet, where the two verdicts lived in two
/// columns that drifted apart and the history was typed into a cell.
Comment _c({
  TesterVerdict tester = TesterVerdict.open,
  DevVerdict dev = DevVerdict.isNew,
  String? blockedOn,
  String? assignee,
  String? foundIn,
  String? fixedIn,
  String? env,
}) => Comment(
  id: '1',
  body: 'the chart does not load',
  screenName: 'CHART',
  status: CommentStatus.open,
  createdAt: DateTime.now(),
  impact: Impact.blocked,
  testerVerdict: tester,
  devVerdict: dev,
  blockedOn: blockedOn,
  assignee: assignee,
  foundInBuild: foundIn,
  fixedInBuild: fixedIn,
  environment: env,
);

void main() {
  group('model', () {
    test('a fix nobody retested is the state worth surfacing', () {
      // The two-column spreadsheet hides exactly this: dev says done, tester
      // never checked. It is invisible until someone reads both columns.
      expect(_c(dev: DevVerdict.fixed).fixedNotVerified, isTrue);
      expect(
        _c(
          dev: DevVerdict.fixed,
          tester: TesterVerdict.accepted,
        ).fixedNotVerified,
        isFalse,
      );
      expect(_c(dev: DevVerdict.inProgress).fixedNotVerified, isFalse);
    });

    test('the two verdicts are independent', () {
      final c = _c(dev: DevVerdict.fixed, tester: TesterVerdict.rejected);
      expect(c.devVerdict, DevVerdict.fixed);
      expect(c.testerVerdict, TesterVerdict.rejected);
    });

    test('blocked_on is free text, not a shipped taxonomy', () {
      // A team that blocks on "exchange" or "master data" must not have to
      // pick a wrong value from someone else's list.
      expect(BlockedOn.fromWire('exchange'), 'exchange');
      expect(BlockedOn.fromWire(''), isNull);
      expect(BlockedOn.fromWire(null), isNull);
      expect(BlockedOn.label('third-party'), 'Third party');
      expect(BlockedOn.label('master_data'), 'Master data');
    });

    test('the defaults are general, not domain-specific', () {
      expect(BlockedOn.defaults, [
        'backend',
        'frontend',
        'design',
        'product',
        'qa',
        'third-party',
      ]);
    });

    test('an unknown verdict degrades rather than throwing', () {
      // One bad row must never blank a list.
      expect(DevVerdict.fromWire('nonsense'), DevVerdict.isNew);
      expect(TesterVerdict.fromWire(null), TesterVerdict.open);
    });
  });

  group('event summaries', () {
    CommentEvent e(Map<String, dynamic> row) => CommentEvent.fromRow({
      'id': 'e1',
      'at': DateTime.now().toIso8601String(),
      ...row,
    });

    test('a verdict change reads as a transition', () {
      expect(
        e({
          'kind': 'verdict_changed',
          'field': 'dev_verdict',
          'from_value': 'in_progress',
          'to_value': 'fixed',
        }).summary,
        'Dev in progress → fixed',
      );
    });

    test('a first-time set has no arrow', () {
      expect(
        e({
          'kind': 'verdict_changed',
          'field': 'tester_verdict',
          'to_value': 'verifying',
        }).summary,
        'Tester set to verifying',
      );
    });

    test('assignment, blocking and unblocking each read plainly', () {
      expect(
        e({'kind': 'assigned', 'to_value': 'Ana'}).summary,
        'Assigned to Ana',
      );
      expect(e({'kind': 'assigned'}).summary, 'Unassigned');
      expect(
        e({'kind': 'blocked', 'to_value': 'backend'}).summary,
        'Blocked on backend',
      );
      expect(e({'kind': 'blocked'}).summary, 'Unblocked');
    });

    test('a note is its own text', () {
      expect(
        e({'kind': 'commented', 'body': 'cannot reproduce on 1.0.46'}).summary,
        'cannot reproduce on 1.0.46',
      );
    });
  });

  _blankRegionTests();

  group('panel', () {
    Future<void> pump(
      WidgetTester tester,
      Comment comment, {
      List<CommentEvent> events = const [],
      void Function(DevVerdict)? onDev,
      void Function(TesterVerdict)? onTester,
      ValueChanged<String?>? onBlocked,
      ValueChanged<String>? onNote,
    }) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: T.page,
            body: SingleChildScrollView(
              child: WorkflowPanel(
                comment: comment,
                events: events,
                blockedOnOptions: BlockedOn.defaults,
                onDevVerdict: (v, {String? build}) => onDev?.call(v),
                onTesterVerdict: (v, {String? build}) => onTester?.call(v),
                onBlockedOn: (v) => onBlocked?.call(v),
                onAssign: (_) {},
                onNote: (n) => onNote?.call(n),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('it warns when a fix has not been verified', (tester) async {
      await pump(tester, _c(dev: DevVerdict.fixed));
      expect(find.textContaining('Fixed, not verified'), findsOneWidget);

      await pump(
        tester,
        _c(dev: DevVerdict.fixed, tester: TesterVerdict.accepted),
      );
      expect(find.textContaining('Fixed, not verified'), findsNothing);
    });

    testWidgets('both verdict rows are offered', (tester) async {
      await pump(tester, _c());
      for (final v in DevVerdict.values) {
        expect(find.text(v.label), findsWidgets, reason: v.label);
      }
      for (final v in TesterVerdict.values) {
        expect(find.text(v.label), findsWidgets, reason: v.label);
      }
    });

    testWidgets('moving a verdict reports it', (tester) async {
      DevVerdict? dev;
      TesterVerdict? testerVerdict;
      await pump(
        tester,
        _c(),
        onDev: (v) => dev = v,
        onTester: (v) => testerVerdict = v,
      );

      await tester.tap(find.text('Fixed'));
      expect(dev, DevVerdict.fixed);

      await tester.tap(find.text('Still broken'));
      expect(testerVerdict, TesterVerdict.rejected);
    });

    testWidgets('the blocker can be set and cleared', (tester) async {
      String? blocked = 'unset';
      await pump(
        tester,
        _c(blockedOn: 'backend'),
        onBlocked: (v) => blocked = v,
      );

      await tester.tap(find.text('Nothing'));
      expect(blocked, isNull, reason: 'clearing passes null');

      await tester.tap(find.text('Frontend'));
      expect(blocked, 'frontend');
    });

    testWidgets('builds are shown, and a missing one is a dash', (
      tester,
    ) async {
      await pump(tester, _c(foundIn: '1.0.44', env: 'uat'));
      expect(find.text('1.0.44'), findsOneWidget);
      expect(find.text('uat'), findsOneWidget, reason: 'env, from the SDK');
      // Fixed and verified are both unset on a new report.
      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('the history renders, oldest first', (tester) async {
      await pump(
        tester,
        _c(dev: DevVerdict.fixed),
        events: [
          CommentEvent.fromRow({
            'id': 'a',
            'at': '2026-06-24T10:00:00Z',
            'kind': 'verdict_changed',
            'field': 'dev_verdict',
            'from_value': 'new',
            'to_value': 'fixed',
          }),
          CommentEvent.fromRow({
            'id': 'b',
            'at': '2026-07-30T10:00:00Z',
            'kind': 'commented',
            'body': 'Pls recheck',
          }),
        ],
      );

      // This is the spreadsheet cell "24/06 : Fixed\n30/07 : Pls Recheck",
      // rendered from data instead of typed by a person.
      expect(find.text('Dev new → fixed'), findsOneWidget);
      expect(find.text('Pls recheck'), findsOneWidget);
      expect(find.text('24 Jun'), findsOneWidget);
      expect(find.text('30 Jul'), findsOneWidget);
    });

    testWidgets('an empty history says so rather than rendering nothing', (
      tester,
    ) async {
      await pump(tester, _c());
      expect(
        find.textContaining('Every verdict change lands here'),
        findsOneWidget,
      );
    });

    testWidgets('a note is trimmed and cleared after sending', (tester) async {
      String? note;
      await pump(tester, _c(), onNote: (n) => note = n);

      await tester.enterText(
        find.widgetWithText(TextField, 'Add a note'),
        '  cannot reproduce  ',
      );
      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(note, 'cannot reproduce');
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Add a note'))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('an empty note sends nothing', (tester) async {
      var calls = 0;
      await pump(tester, _c(), onNote: (_) => calls++);
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(calls, 0);
    });
  });
}

/// Platform views are the most-reported area of a real app's sheet (charts,
/// option chains) and precisely the widgets a Flutter screenshot cannot record.
/// Pointing a capture tool at that app without saying so delivers a black
/// rectangle for the thing it gets the most reports about.
void _blankRegionTests() {
  group('blank regions', () {
    Comment withRegions(List<Map<String, dynamic>> regions) => Comment(
      id: '1',
      body: 'the chart is empty',
      screenName: 'CHART',
      status: CommentStatus.open,
      createdAt: DateTime.now(),
      context: {'blank_regions': regions},
    );

    test('a comment with no regions reports none', () {
      expect(withRegions(const []).blankRegions, isEmpty);
      expect(
        Comment(
          id: '1',
          body: 'b',
          screenName: 'S',
          status: CommentStatus.open,
          createdAt: DateTime.now(),
        ).blankRegions,
        isEmpty,
      );
    });

    test('regions parse with their geometry intact', () {
      final r = withRegions([
        {'kind': 'RenderAndroidView', 'x': 0, 'y': 0.2, 'w': 1, 'h': 0.5},
      ]).blankRegions.single;

      expect(r.kind, 'RenderAndroidView');
      expect(r.y, 0.2);
      expect(r.h, 0.5);
    });

    test('the label is what a developer would recognise, not a class name', () {
      expect(
        const BlankRegion(
          kind: 'RenderAndroidView',
          x: 0,
          y: 0,
          w: 1,
          h: 1,
        ).label,
        'map, chart or web view',
      );
      expect(
        const BlankRegion(kind: 'TextureBox', x: 0, y: 0, w: 1, h: 1).label,
        'video or camera',
      );
    });

    test('a malformed region degrades instead of throwing', () {
      // One bad row must never blank a detail pane.
      final regions = withRegions([
        {'kind': 'TextureBox', 'x': 'oops', 'y': null, 'w': '0.5', 'h': 1},
      ]).blankRegions;

      expect(regions.single.x, 0);
      expect(regions.single.w, 0.5, reason: 'a numeric string still parses');
    });

    test('a non-list payload is ignored', () {
      final c = Comment(
        id: '1',
        body: 'b',
        screenName: 'S',
        status: CommentStatus.open,
        createdAt: DateTime.now(),
        context: const {'blank_regions': 'nonsense'},
      );
      expect(c.blankRegions, isEmpty);
    });
  });
}
