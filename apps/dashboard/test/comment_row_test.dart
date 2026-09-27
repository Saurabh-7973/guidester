import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/theme/tokens.dart';
import 'package:dashboard/src/widgets/comment_row.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Comment _comment({
  String body = 'The blue circle covers the Next button',
  String screen = 'CONNECTION SCREEN',
  Impact impact = Impact.blocked,
  String? tester = 'Priya',
  String? device = 'Pixel 7',
  Map<String, dynamic> context = const {},
  CommentStatus status = CommentStatus.open,
}) => Comment(
  id: '1',
  body: body,
  screenName: screen,
  status: status,
  createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
  testerName: tester,
  deviceModel: device,
  impact: impact,
  context: context,
);

Future<void> _pump(
  WidgetTester tester,
  Comment comment, {
  int duplicates = 0,
  bool collapsed = false,
  bool selected = false,
  VoidCallback? onResolve,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 624,
          child: CommentRow(
            comment: comment,
            onTap: () {},
            onMarkInProgress: () {},
            onResolve: onResolve ?? () {},
            duplicateCount: duplicates,
            collapsed: collapsed,
            selected: selected,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Reads the meta line as the eye does — every 11px fragment, in order.
List<String> _meta(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .where((t) => t.style?.fontSize == 11)
    .map((t) => t.data ?? '')
    .where((s) => s.trim() != '•')
    .toList();

void main() {
  testWidgets('the meta row is in the specified field order', (tester) async {
    await _pump(tester, _comment(context: const {'text_scale': 2.0}));

    expect(_meta(tester), [
      'CONNECTION SCREEN',
      'BLOCKED',
      'PRIYA',
      'PIXEL 7',
      'TEXT SCALE 2.0',
      '5 MINS AGO',
    ]);
  });

  testWidgets('impact sits second, in a fixed position', (tester) async {
    // The reason for the fixed position: the eye finds it in the same place
    // down a column of thirty rows.
    for (final impact in Impact.values) {
      await _pump(tester, _comment(impact: impact));
      expect(_meta(tester)[1], impact.label);
    }
  });

  testWidgets('impact owns colour, and nothing else is coloured', (
    tester,
  ) async {
    await _pump(tester, _comment(impact: Impact.blocked));

    final coloured = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.style?.fontSize == 11)
        .where((t) => t.style?.color != T.text3)
        .toList();

    expect(coloured, hasLength(1));
    expect(coloured.single.data, 'BLOCKED');
    expect(coloured.single.style!.color, T.red);
  });

  testWidgets('each impact carries its own colour', (tester) async {
    for (final (impact, colour) in [
      (Impact.blocked, T.red),
      (Impact.annoying, T.text2),
      (Impact.cosmetic, T.text3),
    ]) {
      await _pump(tester, _comment(impact: impact));
      final label = tester.widget<Text>(find.text(impact.label));
      expect(label.style!.color, colour, reason: impact.label);
    }
  });

  testWidgets('a normal device prints no extra context', (tester) async {
    await _pump(
      tester,
      _comment(context: const {'text_scale': 1.0, 'brightness': 'light'}),
    );

    // Only off-default context earns a slot; everything else is noise on a
    // line that has to stay scannable.
    expect(_meta(tester), [
      'CONNECTION SCREEN',
      'BLOCKED',
      'PRIYA',
      'PIXEL 7',
      '5 MINS AGO',
    ]);
  });

  testWidgets('off-default context appears, each on the same line', (
    tester,
  ) async {
    await _pump(
      tester,
      _comment(
        context: const {
          'text_scale': 2.0,
          'brightness': 'dark',
          'orientation': 'landscape',
          'is_physical_device': false,
        },
      ),
    );

    final meta = _meta(tester);
    expect(meta, contains('TEXT SCALE 2.0'));
    expect(meta, contains('DARK MODE'));
    expect(meta, contains('LANDSCAPE'));
    expect(meta, contains('EMULATOR'));
  });

  testWidgets('a tester with no name does not render BY GUEST', (tester) async {
    await _pump(tester, _comment(tester: null));
    expect(find.text('BY GUEST'), findsNothing);
    expect(_meta(tester)[2], 'UNKNOWN');
  });

  testWidgets('at rest it is flat: 98 tall, a divider, no card', (
    tester,
  ) async {
    await _pump(tester, _comment());

    expect(tester.getSize(find.byType(CommentRow)).height, 98);
    // No raised surface, and the actions are not offered.
    expect(find.text('Mark In Progress'), findsNothing);
    expect(find.text('Resolve'), findsNothing);
    // The screen tag is muted meta, not an amber chip.
    expect(
      tester.widget<Text>(find.text('CONNECTION SCREEN')).style!.color,
      T.text3,
    );
  });

  testWidgets('selected raises the same row: card, chip, actions', (
    tester,
  ) async {
    await _pump(tester, _comment(), selected: true);

    expect(find.text('Mark In Progress'), findsOneWidget);
    expect(find.text('Resolve'), findsOneWidget);
    // The screen tag has moved up and become the amber chip.
    expect(
      tester.widget<Text>(find.text('CONNECTION SCREEN')).style!.color,
      T.amber,
    );
    // And it is not repeated in the meta line below.
    expect(find.text('CONNECTION SCREEN'), findsOneWidget);
    // Body steps up from 15 to 17.
    expect(tester.widget<Text>(find.text(_comment().body)).style!.fontSize, 17);
  });

  testWidgets('hovering raises it and leaving lowers it again', (tester) async {
    await _pump(tester, _comment());
    expect(find.text('Resolve'), findsNothing);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final centre = tester.getCenter(find.byType(CommentRow));
    await tester.sendEventToBinding(pointer.hover(centre));
    await tester.pump();
    expect(find.text('Resolve'), findsOneWidget, reason: 'raised on hover');

    await tester.sendEventToBinding(pointer.hover(const Offset(-100, -100)));
    await tester.pump();
    expect(find.text('Resolve'), findsNothing, reason: 'flat again');
  });

  testWidgets('the first of a duplicate group keeps its meta line', (
    tester,
  ) async {
    await _pump(tester, _comment(), duplicates: 3);
    expect(find.textContaining('similar on this screen'), findsNothing);
    expect(_meta(tester), contains('BLOCKED'));
  });

  testWidgets('the rows below it collapse to the merge line', (tester) async {
    await _pump(tester, _comment(), duplicates: 3, collapsed: true);
    expect(find.text('3 similar on this screen · merge'), findsOneWidget);
    // The meta line is replaced, not appended — which is what keeps the row
    // at its specified 98.
    expect(find.text('BLOCKED'), findsNothing);
    expect(tester.getSize(find.byType(CommentRow)).height, 98);
  });

  testWidgets('a lone comment never collapses', (tester) async {
    await _pump(tester, _comment(), duplicates: 1, collapsed: true);
    expect(find.textContaining('similar on this screen'), findsNothing);
  });

  testWidgets('status is told by shape, never by colour', (tester) async {
    // Design-system Rule 1: status owns shape. Its glyph changes; its colour
    // does not.
    final colours = <Color?>{};
    for (final status in CommentStatus.values) {
      await _pump(tester, _comment(status: status));
      final icon = tester.widget<Icon>(find.byIcon(status.icon));
      colours.add(icon.color);
    }
    expect(colours, {T.text3}, reason: 'one colour across all three statuses');
  });

  testWidgets('resolve fires from the raised row', (tester) async {
    var resolved = 0;
    await _pump(
      tester,
      _comment(),
      selected: true,
      onResolve: () => resolved++,
    );

    await tester.tap(find.text('Resolve'));
    expect(resolved, 1);
  });

  testWidgets('a long comment is clamped to two lines', (tester) async {
    await _pump(tester, _comment(body: 'word ' * 200));
    final body = tester.widget<Text>(find.textContaining('word'));
    expect(body.maxLines, 2);
    expect(body.overflow, TextOverflow.ellipsis);
  });
}
