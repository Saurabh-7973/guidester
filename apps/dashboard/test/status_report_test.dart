import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/models/status_report.dart';
import 'package:dashboard/src/models/workflow.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 28, 12);

Comment _c(
  String id, {
  Impact impact = Impact.annoying,
  DevVerdict dev = DevVerdict.isNew,
  TesterVerdict tester = TesterVerdict.open,
  String? blockedOn,
  String? assignee,
  String screen = 'HOME',
  int daysAgo = 0,
}) => Comment(
  id: id,
  body: 'comment $id',
  screenName: screen,
  status: CommentStatus.open,
  createdAt: _now.subtract(Duration(days: daysAgo)),
  impact: impact,
  devVerdict: dev,
  testerVerdict: tester,
  blockedOn: blockedOn,
  assignee: assignee,
);

StatusReport _r(List<Comment> cs) =>
    StatusReport.from(projectName: 'Shop', comments: cs, now: _now);

void main() {
  group('stages', () {
    test('each comment lands in exactly one stage, by verdict', () {
      final r = _r([
        _c('new'),
        _c('wip', dev: DevVerdict.inProgress),
        _c('blk', dev: DevVerdict.blocked, blockedOn: 'backend'),
        _c('fix', dev: DevVerdict.fixed),
        _c('ver', dev: DevVerdict.fixed, tester: TesterVerdict.verifying),
        _c('bad', dev: DevVerdict.fixed, tester: TesterVerdict.rejected),
        _c('ok', dev: DevVerdict.fixed, tester: TesterVerdict.accepted),
        _c('def', dev: DevVerdict.deferred),
        _c('wf', dev: DevVerdict.wontFix),
      ]);
      expect(r.count(Stage.fresh), 1);
      expect(r.count(Stage.inProgress), 1);
      expect(r.count(Stage.blocked), 1);
      expect(r.count(Stage.awaitingVerification), 2);
      expect(r.count(Stage.stillBroken), 1);
      expect(r.count(Stage.verified), 1);
      expect(r.count(Stage.deferred), 1);
      expect(r.count(Stage.wontFix), 1);
      expect(r.total, 9);
      expect(r.openWork, 4, reason: 'new, in progress, blocked, still broken');
    });

    test('accepted wins over a later dev verdict', () {
      final r = _r([
        _c('1', dev: DevVerdict.wontFix, tester: TesterVerdict.accepted),
      ]);
      expect(r.count(Stage.verified), 1);
    });
  });

  group('release readiness', () {
    test('an open blocking comment means not ready', () {
      final r = _r([_c('1', impact: Impact.blocked), _c('2')]);
      expect(r.readiness, Readiness.notReady);
      expect(r.blockers.map((c) => c.id), ['1']);
    });

    test('a blocking comment still broken after a fix means not ready', () {
      final r = _r([
        _c(
          '1',
          impact: Impact.blocked,
          dev: DevVerdict.fixed,
          tester: TesterVerdict.rejected,
        ),
      ]);
      expect(r.readiness, Readiness.notReady);
    });

    test('fixes nobody checked mean verify first', () {
      final r = _r([
        _c('1', impact: Impact.blocked, dev: DevVerdict.fixed),
        _c('2', impact: Impact.cosmetic),
      ]);
      expect(r.readiness, Readiness.verifyFirst);
    });

    test('only minor work open is ready', () {
      final r = _r([
        _c('1', impact: Impact.cosmetic),
        _c('2', dev: DevVerdict.fixed, tester: TesterVerdict.accepted),
      ]);
      expect(r.readiness, Readiness.ready);
    });

    test('an empty project is ready and says so', () {
      final r = _r([]);
      expect(r.readiness, Readiness.ready);
      expect(r.verifiedShare, isNull);
    });
  });

  group('numbers', () {
    test('verified share ignores won\'t fix and deferred', () {
      final r = _r([
        _c('1', dev: DevVerdict.fixed, tester: TesterVerdict.accepted),
        _c('2'),
        _c('3', dev: DevVerdict.wontFix),
        _c('4', dev: DevVerdict.deferred),
      ]);
      expect(r.verifiedShare, 0.5);
    });

    test('this week, and the oldest open comment', () {
      final r = _r([
        _c('1', daysAgo: 1),
        _c('2', daysAgo: 20),
        _c('3', daysAgo: 30, dev: DevVerdict.wontFix),
      ]);
      expect(r.reportedThisWeek, 1);
      expect(r.oldestOpenDays, 20);
    });

    test('hot screens rank open work, most first', () {
      final r = _r([
        _c('1', screen: 'CART'),
        _c('2', screen: 'CART'),
        _c('3', screen: 'HOME'),
        _c('4', screen: 'HOME', dev: DevVerdict.wontFix),
      ]);
      expect(r.hotScreens, [('CART', 2), ('HOME', 1)]);
    });

    test('open work per assignee', () {
      final r = _r([
        _c('1', assignee: 'ana'),
        _c('2', assignee: 'ana'),
        _c('3', assignee: 'ana', dev: DevVerdict.wontFix),
        _c('4'),
      ]);
      expect(r.byAssignee, {'ana': 2, 'Unassigned': 1});
    });
  });

  group('lenses', () {
    test('every team gets its own list', () {
      final r = _r([
        _c('dev', impact: Impact.blocked),
        _c('qa', dev: DevVerdict.fixed),
        _c('ui', impact: Impact.cosmetic),
        _c('uiBlocked', dev: DevVerdict.blocked, blockedOn: 'design'),
        _c('ba', dev: DevVerdict.blocked, blockedOn: 'product'),
        _c('be', dev: DevVerdict.blocked, blockedOn: 'backend'),
        _c('fe', dev: DevVerdict.blocked, blockedOn: 'frontend'),
        _c('3p', dev: DevVerdict.blocked, blockedOn: 'third-party'),
      ]);
      List<String> ids(Lens l) => r.lens(l).map((c) => c.id).toList();

      expect(ids(Lens.developers), containsAll(['dev', 'ui']));
      expect(ids(Lens.developers), isNot(contains('qa')));
      expect(ids(Lens.qa), ['qa']);
      expect(ids(Lens.design), ['uiBlocked', 'ui']);
      expect(ids(Lens.product), ['ba']);
      expect(ids(Lens.backend), ['be']);
      expect(ids(Lens.frontend), ['fe']);
      expect(ids(Lens.lead), ['dev'], reason: 'the lead sees what blocks');
    });

    test('developers see still broken first, then by impact, then oldest', () {
      final r = _r([
        _c('cos', impact: Impact.cosmetic, daysAgo: 9),
        _c('old', daysAgo: 5),
        _c('new', daysAgo: 1),
        _c('blk', impact: Impact.blocked),
        _c(
          'again',
          impact: Impact.cosmetic,
          dev: DevVerdict.fixed,
          tester: TesterVerdict.rejected,
        ),
      ]);
      expect(r.lens(Lens.developers).map((c) => c.id), [
        'again',
        'blk',
        'old',
        'new',
        'cos',
      ]);
    });
  });

  group('markdown', () {
    test('pastes into Slack, Jira or mail with the numbers and lists', () {
      final r = _r([
        _c('1', impact: Impact.blocked, screen: 'CART'),
        _c('2', dev: DevVerdict.fixed),
      ]);
      final md = r.toMarkdown(link: 'https://example.com/p/1');
      expect(md, startsWith('## Shop: status 28 Sep 2026'));
      expect(md, contains('**Not ready to release**'));
      expect(md, contains('1 blocking'));
      expect(md, contains('fixed, waiting for QA'));
      expect(md, contains('- [BLOCKED] comment 1 (CART'));
      expect(md, contains('https://example.com/p/1'));
    });

    test('an empty project still reads as a report', () {
      expect(_r([]).toMarkdown(), contains('No comments yet.'));
    });
  });
}
