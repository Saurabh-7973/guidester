@Tags(['golden'])
library;

import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/theme/tokens.dart';
import 'package:dashboard/src/widgets/comment_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The §5 list, both row states, at the frames' own width.
///
/// Regenerate deliberately:
///   flutter test --update-goldens test/comment_row_golden_test.dart
void main() {
  Comment c({
    required String id,
    required String body,
    required String screen,
    required Impact impact,
    required String tester,
    String device = 'Pixel 7',
    Map<String, dynamic> context = const {},
    CommentStatus status = CommentStatus.open,
    required Duration ago,
  }) => Comment(
    id: id,
    body: body,
    screenName: screen,
    status: status,
    createdAt: DateTime.now().subtract(ago),
    testerName: tester,
    deviceModel: device,
    impact: impact,
    context: context,
  );

  testWidgets('the comment list at 624', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final comments = [
      c(
        id: '1',
        body:
            'The blue chat circle sits on top of the Next button so I keep '
            'tapping the wrong thing',
        screen: 'CONNECTION SCREEN',
        impact: Impact.blocked,
        tester: 'Priya',
        context: const {'text_scale': 2.0},
        ago: const Duration(minutes: 5),
      ),
      c(
        id: '2',
        body: 'The hammock drawing is too faint to see on my phone',
        screen: 'CONNECTION SCREEN',
        impact: Impact.blocked,
        tester: 'Ana',
        context: const {'brightness': 'dark'},
        ago: const Duration(minutes: 41),
      ),
      c(
        id: '3',
        body: 'Ye screen pe text bahut chota hai, buzurg log padh nahi payenge',
        screen: 'GOALS',
        impact: Impact.annoying,
        tester: 'Ravi',
        device: 'Redmi Note 12',
        status: CommentStatus.inProgress,
        ago: const Duration(hours: 3),
      ),
      c(
        id: '4',
        body: 'The back arrow is a little small to hit with a thumb',
        screen: 'GOALS',
        impact: Impact.cosmetic,
        tester: 'Meera',
        context: const {'orientation': 'landscape'},
        status: CommentStatus.resolved,
        ago: const Duration(days: 2),
      ),
    ];

    // Row 2 is selected, so the golden shows both states side by side: the
    // raised card and the flat rows around it, which is the whole of §5.
    final duplicates = <String, int>{};
    for (final x in comments) {
      final k = '${x.screenName}|${x.impact.wire}';
      duplicates[k] = (duplicates[k] ?? 0) + 1;
    }
    final seen = <String>{};

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // A Material ancestor is required: the row's actions are InkWells, and
        // without one they lay out unbounded.
        home: Material(
          color: T.page,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 624,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 24),
                  for (final x in comments)
                    CommentRow(
                      comment: x,
                      selected: x.id == '2',
                      duplicateCount:
                          duplicates['${x.screenName}|${x.impact.wire}'] ?? 0,
                      collapsed: !seen.add('${x.screenName}|${x.impact.wire}'),
                      onTap: () {},
                      onMarkInProgress: () {},
                      onResolve: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/comment_list_624.png'),
    );
  });
}
