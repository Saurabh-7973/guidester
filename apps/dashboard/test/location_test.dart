import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/routing/location.dart';
import 'package:dashboard/src/widgets/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';

/// Found 25 Sep: the URL was `/` on every screen, so back left the app,
/// reload dropped to the project list, and no comment could be linked.
/// Every place the dashboard can be is now a URL, and every URL a place.
void main() {
  DashboardLocation? parse(String s) => DashboardLocation.parse(Uri.parse(s));

  test('the project list', () {
    final l = parse('/projects')!;
    expect(l.tab, ShellTab.projects);
    expect(l.projectId, isNull);
    expect(l.onboarding, isFalse);
  });

  test('a new project is onboarding', () {
    expect(parse('/projects/new')!.onboarding, isTrue);
  });

  test('account settings, with no project', () {
    final l = parse('/settings')!;
    expect(l.tab, ShellTab.settings);
    expect(l.projectId, isNull);
  });

  test("a project's settings", () {
    final l = parse('/p/abc/settings')!;
    expect(l.tab, ShellTab.settings);
    expect(l.projectId, 'abc');
  });

  test('a project board defaults to open and every impact', () {
    final l = parse('/p/abc')!;
    expect(l.tab, ShellTab.projects);
    expect(l.projectId, 'abc');
    expect(l.commentId, isNull);
    expect(l.status, CommentStatus.open);
    expect(l.impact, isNull);
  });

  test('one comment, with its tab and filter', () {
    final l = parse('/p/abc/c/42?status=resolved&impact=blocked')!;
    expect(l.projectId, 'abc');
    expect(l.commentId, '42');
    expect(l.status, CommentStatus.resolved);
    expect(l.impact, Impact.blocked);
  });

  test('an unknown status or impact falls back rather than failing', () {
    final l = parse('/p/abc?status=nonsense&impact=nope')!;
    expect(l.status, CommentStatus.open);
    expect(l.impact, isNull);
  });

  test('a path that is no place is null, which the router shows as 404', () {
    expect(parse('/nowhere'), isNull);
    expect(parse('/p'), isNull);
    expect(parse('/p/abc/c'), isNull);
    expect(parse('/p/abc/extra/bits'), isNull);
  });

  test('every location round-trips through its URL', () {
    const cases = [
      DashboardLocation.projects(),
      DashboardLocation.newProject(),
      DashboardLocation.settings(),
      DashboardLocation.settings(projectId: 'abc'),
      DashboardLocation.board('abc'),
      DashboardLocation.board('abc', commentId: '42'),
      DashboardLocation.board(
        'abc',
        commentId: '42',
        status: CommentStatus.inProgress,
        impact: Impact.cosmetic,
      ),
    ];
    for (final l in cases) {
      expect(DashboardLocation.parse(Uri.parse(l.path)), l, reason: l.path);
    }
  });

  test('defaults stay out of the URL', () {
    expect(const DashboardLocation.board('abc').path, '/p/abc');
    expect(
      const DashboardLocation.board('abc', commentId: '42').path,
      '/p/abc/c/42',
    );
  });

  test('a board carries ?screen=, and round-trips it', () {
    final loc = DashboardLocation.parse(
      Uri.parse('/p/abc?impact=blocked&screen=CHECKOUT'),
    )!;
    expect(loc.screen, 'CHECKOUT');
    expect(loc.impact, Impact.blocked);
    expect(DashboardLocation.parse(Uri.parse(loc.path)), loc);
  });

  test('a comment link keeps the screen filter', () {
    const loc = DashboardLocation.board(
      'abc',
      commentId: 'c1',
      screen: 'HOME PAGE',
    );
    expect(DashboardLocation.parse(Uri.parse(loc.path))!.screen, 'HOME PAGE');
  });

  test('no screen filter leaves the link short', () {
    expect(const DashboardLocation.board('abc').path, '/p/abc');
  });

  test('opening a comment keeps the screen filter', () {
    const loc = DashboardLocation.board('abc', screen: 'CHECKOUT');
    expect(loc.withComment('c1').screen, 'CHECKOUT');
  });

  test('pageUrl drops query and fragment, and keeps the port', () {
    expect(
      pageUrl(Uri.parse('http://127.0.0.1:8765/app/?code=x#/p/1')),
      'http://127.0.0.1:8765/app/',
    );
    expect(pageUrl(Uri.parse('file:///tmp/dash/')), 'file:///tmp/dash/');
  });
}
