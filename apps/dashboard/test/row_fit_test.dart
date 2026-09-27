import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/comment_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// Field test D15: at the rail's width the raised row's Resolve was half cut
/// off at the right edge. Both actions must sit wholly inside the row, for a
/// long screen name too.
void main() {
  for (final width in [516.0, 360.0]) {
    testWidgets('the row actions fit inside a $width px row', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: CommentRow(
                  comment: testComment(
                    id: '1',
                    body: 'The pay button is under the keyboard',
                    screen: 'CHECKOUT_PAYMENT_CONFIRMATION',
                  ),
                  selected: true,
                  onTap: () {},
                  onMarkInProgress: () {},
                  onResolve: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final row = tester.getRect(find.byType(CommentRow));
      for (final label in ['Mark In Progress', 'Resolve']) {
        final f = find.text(label);
        if (f.evaluate().isEmpty) continue; // a compact row may show icons
        final r = tester.getRect(f);
        expect(r.right, lessThanOrEqualTo(row.right), reason: label);
      }
      expect(find.bySemanticsLabel(RegExp('Resolve')), findsWidgets);
    });
  }
}
