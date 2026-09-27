import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// 27 Sep audit: a screen reader read each impact filter twice ("All All"):
/// the chip's label and its own text, merged.
void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.reset);
  });

  testWidgets('each impact filter is announced once, and still taps', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repo = FakeRepository({
      CommentStatus.open: [testComment(id: '1', body: 'one')],
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: CommentsScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();

    final all = find.byKey(const ValueKey('impact-filter-all'));
    expect(tester.getSemantics(all).label, 'All');
    final chip = tester.getSemantics(all);
    expect(chip.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });
}
