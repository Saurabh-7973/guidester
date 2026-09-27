import 'package:dashboard/src/data/team_repository.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/notify_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/team_fake.dart';

void main() {
  test('only the three services, like the edge function', () {
    expect(webhookService('https://hooks.slack.com/services/T/B/x'), 'Slack');
    expect(webhookService('https://discord.com/api/webhooks/1/x'), 'Discord');
    expect(
      webhookService('https://acme.webhook.office.com/webhookb2/x'),
      'Microsoft Teams',
    );
    for (final bad in [
      'http://hooks.slack.com/services/x',
      'https://hooks.slack.com.evil.com/services/x',
      'https://user:pw@hooks.slack.com/services/x',
      'https://hooks.slack.com:8443/services/x',
      'https://evil.com/api/webhooks/1',
      'https://a.b.webhook.office.com/x',
      '',
    ]) {
      expect(webhookService(bad), isNull, reason: bad);
    }
  });

  Future<FakeTeam> pump(WidgetTester tester, {String? hook}) async {
    final team = FakeTeam()..hook = hook;
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: NotifyPanel(repository: team, projectId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return team;
  }

  testWidgets('saves a Slack channel and shows it masked', (tester) async {
    final team = await pump(tester);
    await tester.enterText(
      find.byType(TextField),
      ' https://hooks.slack.com/services/T0/B0/abcd1234 ',
    );
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();

    expect(team.hook, 'https://hooks.slack.com/services/T0/B0/abcd1234');
    expect(find.text('Slack ••••1234'), findsOneWidget);
    expect(find.textContaining('abcd1234'), findsNothing, reason: 'masked');
    expect(find.textContaining('next comment posts to Slack'), findsOneWidget);
  });

  testWidgets('refuses anything that is not a webhook', (tester) async {
    final team = await pump(tester);
    await tester.enterText(find.byType(TextField), 'https://example.com/x');
    await tester.tap(find.text('Save channel'));
    await tester.pumpAndSettle();
    expect(team.hook, isNull);
    expect(
      find.textContaining('Paste an incoming-webhook URL'),
      findsOneWidget,
    );
  });

  testWidgets('removes the channel', (tester) async {
    final team = await pump(
      tester,
      hook: 'https://discord.com/api/webhooks/1/zzzz',
    );
    expect(find.text('Discord ••••zzzz'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(team.hook, isNull);
    expect(find.textContaining('Nothing posts now'), findsOneWidget);
  });
}
