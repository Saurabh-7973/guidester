import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/screenshot_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

FakeRepository _repo({String? shot}) => FakeRepository({
  CommentStatus.open: [
    testComment(id: 'c1', body: 'first problem', shot: shot),
    testComment(id: 'c2', body: 'second problem', shot: shot),
  ],
});

Future<void> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  String Function(String id)? linkFor,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: CommentsScreen(repository: repo, linkFor: linkFor),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollableState _paneScroll(WidgetTester tester) => tester.state(
  find
      .descendant(
        of: find.byKey(const ValueKey('detail-scroll')),
        matching: find.byType(Scrollable),
      )
      .first,
);

void main() {
  testWidgets('the next comment opens at its top, not where the last was', (
    tester,
  ) async {
    // Narrow enough that the pane stacks and scrolls; wide panes do not.
    await _pump(tester, _repo(), size: const Size(700, 700));
    _paneScroll(
      tester,
    ).position.jumpTo(_paneScroll(tester).position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.text('Next comment »'));
    await tester.pumpAndSettle();
    expect(_paneScroll(tester).position.pixels, 0);
  });

  testWidgets('Copy link puts the comment URL on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, _repo(), linkFor: (id) => 'https://dash.test/#/c/$id');
    await tester.tap(find.text('Copy link'));
    await tester.pump();
    expect(copied, 'https://dash.test/#/c/c1');
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('clicking the screenshot opens it full size; Esc closes', (
    tester,
  ) async {
    await _pump(tester, _repo(shot: 'p/a.png'));
    await tester.tap(find.byType(ScreenshotView));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lightbox')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lightbox')), findsNothing);
  });

  testWidgets('an image that fails re-signs once, then says why (G7)', (
    tester,
  ) async {
    // Image.network always fails under the test binding: the expired link.
    final repo = _repo(shot: 'p/a.png');
    await _pump(tester, repo);
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c == 'sign:p/a.png'), hasLength(2));
    expect(
      find.text('Screenshot link expired. Reopen the comment.'),
      findsOneWidget,
    );
  });
}
