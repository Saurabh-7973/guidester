import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

void main() {
  testWidgets('Copy as issue puts the comment on the clipboard as Markdown', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository({
      CommentStatus.open: [testComment(id: '1', body: 'Cart total is wrong')],
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CommentsScreen(
            repository: repo,
            linkFor: (id) => 'https://dash/#/p/x/c/$id',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy as issue'));
    await tester.pumpAndSettle();

    expect(copied, startsWith('# ['));
    expect(copied, contains('Cart total is wrong'));
    expect(copied, contains('[Open in Guidester](https://dash/#/p/x/c/1)'));
    expect(find.text('Issue copied'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget, reason: 'each says its own');
  });
}
