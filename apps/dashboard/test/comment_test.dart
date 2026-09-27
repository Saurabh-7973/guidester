import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/issue_type.dart';
import 'package:dashboard/src/widgets/status_chip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommentStatus', () {
    test('wire values match the Postgres enum exactly', () {
      expect(CommentStatus.open.wire, 'open');
      expect(CommentStatus.inProgress.wire, 'in_progress');
      expect(CommentStatus.resolved.wire, 'resolved');
    });

    test('unknown or null wire values fall back to open', () {
      expect(CommentStatus.fromWire(null), CommentStatus.open);
      expect(CommentStatus.fromWire('wontfix'), CommentStatus.open);
      expect(CommentStatus.fromWire('in_progress'), CommentStatus.inProgress);
    });
  });

  group('Comment.fromRow', () {
    test('parses a full row', () {
      final c = Comment.fromRow({
        'id': 'abc',
        'body': 'the button is off',
        'screen_name': 'CHECKOUT',
        'status': 'in_progress',
        'created_at': '2026-09-01T10:00:00Z',
        'tap_x': 0.25,
        'tap_y': 0.75,
        'screenshot_path': 'proj/shot.png',
        'tester_name': 'Ana',
        'device_model': 'Pixel 8',
        'context': {'text_scale_factor': 1.3},
      });
      expect(c.id, 'abc');
      expect(c.screenName, 'CHECKOUT');
      expect(c.status, CommentStatus.inProgress);
      expect(c.tapX, 0.25);
      expect(c.hasPin, isTrue);
      expect(c.context['text_scale_factor'], 1.3);
    });

    test('a partial row degrades instead of throwing', () {
      final c = Comment.fromRow({'id': 'x'});
      expect(c.body, '');
      expect(c.screenName, 'UNKNOWN');
      expect(c.status, CommentStatus.open);
      expect(c.hasPin, isFalse);
      expect(c.context, isEmpty);
    });

    test('an entirely empty row does not throw', () {
      expect(() => Comment.fromRow(const {}), returnsNormally);
    });

    test('numeric taps arriving as strings or ints still parse', () {
      final c = Comment.fromRow({'tap_x': '0.5', 'tap_y': 1});
      expect(c.tapX, 0.5);
      expect(c.tapY, 1.0);
    });

    test('a malformed timestamp does not throw', () {
      final c = Comment.fromRow({'created_at': 'not-a-date'});
      expect(c.createdAt.millisecondsSinceEpoch, 0);
    });

    test('a non-map context is ignored', () {
      expect(Comment.fromRow({'context': 'oops'}).context, isEmpty);
    });

    test('only one pin coordinate means no pin', () {
      expect(Comment.fromRow({'tap_x': 0.5}).hasPin, isFalse);
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 9, 4, 12);
    test('seconds', () {
      expect(
        relativeTime(now.subtract(const Duration(seconds: 5)), now: now),
        'just now',
      );
    });
    test('minutes, hours, days, weeks', () {
      expect(
        relativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        '5m ago',
      );
      expect(
        relativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(
        relativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
      expect(
        relativeTime(now.subtract(const Duration(days: 21)), now: now),
        '3w ago',
      );
    });
  });

  group('issue type', () {
    // These six strings live in four files and nothing at compile time makes
    // them agree. A drift here is silent in Dart and only shows up as a CHECK
    // violation in production, so pin the wire values literally.
    test('the wire values match migration 0002 exactly', () {
      expect(IssueType.values.map((t) => t.wire).toList(), const [
        'looks_wrong',
        'doesnt_work',
        'confusing',
        'crash',
        'slow',
        'idea',
      ]);
    });

    test(
      'the set is fixed at six',
      () => expect(IssueType.values, hasLength(6)),
    );

    test('a null, empty or unknown value parses to null', () {
      expect(IssueType.fromWire(null), isNull);
      expect(IssueType.fromWire(''), isNull);
      // A value from a newer SDK than this dashboard must not blank the row.
      expect(IssueType.fromWire('teleportation_failure'), isNull);
    });

    test('every wire value round-trips', () {
      for (final t in IssueType.values) {
        expect(IssueType.fromWire(t.wire), t);
      }
    });

    test('a row carries its type through parsing', () {
      final c = Comment.fromRow(const {
        'id': '1',
        'body': 'it froze',
        'issue_type': 'crash',
      });
      expect(c.issueType, IssueType.crash);
    });

    test('a row with no type parses to null, not a default', () {
      expect(Comment.fromRow(const {'id': '1', 'body': 'x'}).issueType, isNull);
    });

    test('copyWith keeps the type', () {
      final c = Comment.fromRow(const {
        'id': '1',
        'body': 'x',
        'issue_type': 'idea',
      });
      expect(
        c.copyWith(status: CommentStatus.resolved).issueType,
        IssueType.idea,
      );
    });
  });
}
