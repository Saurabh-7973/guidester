import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// Field test Stage D 16: finding every comment on one screen meant scrolling
/// the whole list. The board narrows to a screen, and the URL says which.
FakeRepository _repo() => FakeRepository({
  CommentStatus.open: [
    testComment(id: '1', body: 'pay button hidden', screen: 'CHECKOUT'),
    testComment(id: '2', body: 'tabs too small', screen: 'HOME'),
    testComment(id: '3', body: 'total is wrong', screen: 'CHECKOUT'),
  ],
});

Future<List<String?>> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  String? screen,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final reported = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: CommentsScreen(
          repository: repo,
          screen: screen,
          onChanged: (_, _, _, s) => reported.add(s),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return reported;
}

Finder get _picker => find.byKey(const ValueKey('screen-filter'));

void main() {
  testWidgets('the picker lists every screen with its count', (tester) async {
    await _pump(tester, _repo());
    await tester.tap(_picker);
    await tester.pumpAndSettle();
    expect(find.text('All screens'), findsWidgets);
    expect(find.text('CHECKOUT  2'), findsOneWidget);
    expect(find.text('HOME  1'), findsOneWidget);
  });

  testWidgets('choosing a screen narrows the list and the URL', (tester) async {
    final reported = await _pump(tester, _repo());
    await tester.tap(_picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CHECKOUT  2'));
    await tester.pumpAndSettle();
    expect(find.text('tabs too small'), findsNothing);
    expect(find.text('pay button hidden'), findsWidgets);
    expect(find.text('total is wrong'), findsWidgets);
    expect(reported.last, 'CHECKOUT');
  });

  testWidgets('a screen from the URL applies on arrival', (tester) async {
    await _pump(tester, _repo(), screen: 'HOME');
    expect(find.text('tabs too small'), findsWidgets);
    expect(find.text('pay button hidden'), findsNothing);
  });

  testWidgets('a screen with nothing here says so and offers Clear', (
    tester,
  ) async {
    final reported = await _pump(tester, _repo(), screen: 'SETTINGS');
    expect(find.text('No comments match these filters.'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('tabs too small'), findsWidgets);
    expect(reported.last, isNull);
  });

  testWidgets('Back to a filtered URL does not leave a hidden comment open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo();
    Widget board(String? screen) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: CommentsScreen(
          repository: repo,
          commentId: '2',
          screen: screen,
          onChanged: (_, _, _, _) {},
        ),
      ),
    );
    await tester.pumpWidget(board(null));
    await tester.pumpAndSettle();
    // 'tabs too small' (HOME) is open; the URL now narrows to CHECKOUT.
    await tester.pumpWidget(board('CHECKOUT'));
    await tester.pumpAndSettle();
    expect(find.text('tabs too small'), findsNothing);
    expect(find.text('pay button hidden'), findsWidgets);
  });
}
