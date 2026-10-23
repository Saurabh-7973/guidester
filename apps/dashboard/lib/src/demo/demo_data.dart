import '../app.dart';
import '../data/project_repository.dart';
import '../data/team_repository.dart';
import '../models/captured_error.dart';
import '../models/comment.dart';
import '../models/comment_status.dart';
import '../models/impact.dart';
import '../models/issue_type.dart';
import '../models/workflow.dart';

/// The demo's whole database: one project, a week of comments, a team.
///
/// Times are relative to [DemoData.seed]'s `now`, so the board always reads
/// "today" and "this week" the way a live one would. Every write the demo
/// makes lands here and is gone on reload.
class DemoData {
  DemoData._({
    required this.projects,
    required this.comments,
    required this.projectOf,
    required this.events,
    required this.keys,
    required this.members,
    required this.invites,
    required this.webhooks,
  });

  static const DashboardUser you = DashboardUser(
    id: 'demo-you',
    email: 'you@example.com',
    name: 'You',
  );

  static const String projectId = 'demo-checkout';

  /// Shaped like a key, usable by nothing.
  static String fakeKey(String projectId) =>
      'gd_live_demo_${projectId.hashCode.toRadixString(36)}_notarealkey';

  final List<Project> projects;
  final List<Comment> comments;

  /// Comment id to project id: `Comment` does not carry it.
  final Map<String, String> projectOf;

  /// Comment id to its history.
  final Map<String, List<CommentEvent>> events;
  final Map<String, List<ProjectKey>> keys;
  final Map<String, List<TeamMember>> members;
  final Map<String, List<TeamInvite>> invites;
  final Map<String, String?> webhooks;

  factory DemoData.seed(DateTime now) {
    DateTime ago({int days = 0, int hours = 0, int minutes = 0}) =>
        now.subtract(Duration(days: days, hours: hours, minutes: minutes));

    final comments = <Comment>[
      Comment(
        id: 'demo-1',
        body:
            'Tapped "Go to an unnamed route" and nothing happened. Had to kill '
            'the app to get out.',
        screenName: 'CHECKOUT',
        status: CommentStatus.open,
        createdAt: ago(minutes: 40),
        tapX: 0.5,
        tapY: 0.445,
        screenshotPath: 'demo/checkout.png',
        testerName: 'Ana',
        testerId: 'tester-ana',
        deviceModel: 'Pixel 8',
        osVersion: 'Android 15',
        appVersion: '1.4.2 (57)',
        foundInBuild: '1.4.2 (57)',
        environment: 'uat',
        issueType: IssueType.doesntWork,
        impact: Impact.blocked,
        errors: [
          CapturedError(
            exception: 'Bad state: Cannot add new events after calling close',
            library: 'widgets library',
            screen: 'CHECKOUT',
            at: ago(minutes: 41),
            stack: _stack([
              'StreamController.add (dart:async/stream_controller.dart:615:24)',
              'AddressBloc.update (package:checkout_app/checkout/address_bloc.dart:48:14)',
              '_CheckoutScreenState._onAddressChanged (package:checkout_app/checkout/checkout_screen.dart:131:22)',
              '_InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1176:21)',
            ]),
          ),
        ],
        context: const {
          'redaction': {'regions': 1},
          'text_scale_factor': 1.0,
          'platform_brightness': 'light',
          'is_physical_device': true,
          'route_stack': ['/home', '/checkout'],
        },
      ),
      Comment(
        id: 'demo-2',
        body:
            'The "Go to /checkout" label is cut off with the bigger font '
            'setting.',
        screenName: 'HOME',
        status: CommentStatus.inProgress,
        createdAt: ago(hours: 5),
        tapX: 0.5,
        tapY: 0.445,
        screenshotPath: 'demo/home.png',
        testerName: 'Ravi',
        testerId: 'tester-ravi',
        deviceModel: 'Galaxy A15',
        osVersion: 'Android 14',
        appVersion: '1.4.2 (57)',
        foundInBuild: '1.4.2 (57)',
        environment: 'uat',
        issueType: IssueType.looksWrong,
        impact: Impact.cosmetic,
        devVerdict: DevVerdict.inProgress,
        assignee: 'omar@example.com',
        context: const {
          'redaction': {'regions': 1},
          'text_scale_factor': 1.3,
          'platform_brightness': 'light',
          'is_physical_device': true,
          'route_stack': ['/home'],
        },
      ),
      Comment(
        id: 'demo-3',
        body: 'The back arrow needs two taps the first time.',
        screenName: 'CHECKOUT',
        status: CommentStatus.resolved,
        createdAt: ago(days: 2, hours: 3),
        tapX: 0.072,
        tapY: 0.032,
        screenshotPath: 'demo/checkout.png',
        testerName: 'Jo',
        testerId: 'tester-jo',
        deviceModel: 'iPhone 15',
        osVersion: 'iOS 18.1',
        appVersion: '1.4.1 (52)',
        foundInBuild: '1.4.1 (52)',
        fixedInBuild: '1.4.2 (57)',
        environment: 'uat',
        impact: Impact.annoying,
        devVerdict: DevVerdict.fixed,
        assignee: 'omar@example.com',
        context: const {
          'redaction': {'regions': 1},
          'text_scale_factor': 1.0,
          'platform_brightness': 'dark',
          'is_physical_device': true,
        },
      ),
      Comment(
        id: 'demo-4',
        body:
            '"Back to /" spins for a few seconds on a slow connection before '
            'anything happens.',
        screenName: 'SETTINGS/PROFILE',
        status: CommentStatus.resolved,
        createdAt: ago(days: 5),
        tapX: 0.5,
        tapY: 0.445,
        screenshotPath: 'demo/profile.png',
        testerName: 'Ana',
        testerId: 'tester-ana',
        deviceModel: 'Pixel 8',
        osVersion: 'Android 15',
        appVersion: '1.4.0 (48)',
        foundInBuild: '1.4.0 (48)',
        fixedInBuild: '1.4.1 (52)',
        verifiedInBuild: '1.4.2 (57)',
        environment: 'uat',
        issueType: IssueType.slow,
        impact: Impact.annoying,
        devVerdict: DevVerdict.fixed,
        testerVerdict: TesterVerdict.accepted,
        assignee: 'omar@example.com',
        context: const {
          'redaction': {'regions': 1},
        },
      ),
      Comment(
        id: 'demo-5',
        body:
            '"Throw an error, then comment" takes the whole app down, not just '
            'this screen.',
        screenName: 'CHECKOUT',
        status: CommentStatus.inProgress,
        createdAt: ago(days: 4),
        tapX: 0.5,
        tapY: 0.52,
        screenshotPath: 'demo/checkout.png',
        testerName: 'Ravi',
        testerId: 'tester-ravi',
        deviceModel: 'Galaxy A15',
        osVersion: 'Android 14',
        appVersion: '1.4.0 (48)',
        foundInBuild: '1.4.0 (48)',
        fixedInBuild: '1.4.1 (52)',
        environment: 'uat',
        issueType: IssueType.crash,
        impact: Impact.blocked,
        devVerdict: DevVerdict.inProgress,
        testerVerdict: TesterVerdict.rejected,
        assignee: 'lena@example.com',
        errors: [
          CapturedError(
            exception:
                'RangeError (index): Invalid value: Valid value range is '
                'empty: 0',
            library: 'widgets library',
            screen: 'CHECKOUT',
            at: ago(days: 4, minutes: 1),
            stack: _stack([
              'List.[] (dart:core-patch/growable_array.dart:264:36)',
              'CartModel.removeAt (package:checkout_app/cart/cart_model.dart:58:21)',
              '_CartListState._remove (package:checkout_app/cart/cart_list.dart:112:12)',
              '_InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1176:21)',
            ]),
          ),
          CapturedError(
            exception: 'A RenderFlex overflowed by 24 pixels on the bottom.',
            library: 'rendering library',
            screen: 'CHECKOUT',
            at: ago(days: 4, minutes: 1),
            stack: _stack([
              'RenderFlex.performLayout (package:flutter/src/rendering/flex.dart:1050:7)',
              'RenderObject.layout (package:flutter/src/rendering/object.dart:2627:7)',
            ]),
          ),
        ],
        context: const {
          'redaction': {'regions': 1},
        },
      ),
      Comment(
        id: 'demo-6',
        body:
            'Not sure what "Switch router style" is for. Should testers see '
            'it at all?',
        screenName: 'HOME',
        status: CommentStatus.open,
        createdAt: ago(days: 1, hours: 2),
        tapX: 0.5,
        tapY: 0.588,
        screenshotPath: 'demo/home.png',
        testerName: 'Jo',
        testerId: 'tester-jo',
        deviceModel: 'iPhone 15',
        osVersion: 'iOS 18.1',
        appVersion: '1.4.2 (57)',
        foundInBuild: '1.4.2 (57)',
        environment: 'uat',
        issueType: IssueType.confusing,
        impact: Impact.annoying,
        devVerdict: DevVerdict.blocked,
        blockedOn: 'product',
        assignee: 'lena@example.com',
        context: const {
          'redaction': {'regions': 1},
        },
      ),
      Comment(
        id: 'demo-7',
        body: 'The saved card shows as a black bar. Is that on purpose?',
        screenName: 'SETTINGS/PROFILE',
        status: CommentStatus.resolved,
        createdAt: ago(days: 6),
        tapX: 0.34,
        tapY: 0.337,
        screenshotPath: 'demo/profile.png',
        testerName: 'Ana',
        testerId: 'tester-ana',
        deviceModel: 'Pixel 8',
        osVersion: 'Android 15',
        appVersion: '1.4.0 (48)',
        foundInBuild: '1.4.0 (48)',
        environment: 'uat',
        issueType: IssueType.looksWrong,
        impact: Impact.cosmetic,
        devVerdict: DevVerdict.wontFix,
        context: const {
          'redaction': {'regions': 1},
        },
      ),
      Comment(
        id: 'demo-8',
        body: 'Paying with the saved card says the expiry date is invalid.',
        screenName: 'CHECKOUT',
        status: CommentStatus.open,
        createdAt: ago(days: 3, hours: 6),
        tapX: 0.34,
        tapY: 0.337,
        screenshotPath: 'demo/checkout.png',
        testerName: 'Ravi',
        testerId: 'tester-ravi',
        deviceModel: 'Galaxy A15',
        osVersion: 'Android 14',
        appVersion: '1.4.1 (52)',
        foundInBuild: '1.4.1 (52)',
        environment: 'uat',
        issueType: IssueType.doesntWork,
        impact: Impact.annoying,
        errors: [
          CapturedError(
            exception: "FormatException: Invalid date format\n'13/27'",
            screen: 'CHECKOUT',
            at: ago(days: 3, hours: 6, minutes: 1),
            stack: _stack([
              'DateTime.parse (dart:core/date_time.dart:347:7)',
              'ExpiryField._validate (package:checkout_app/checkout/card_form.dart:77:30)',
              'FormFieldState.validate (package:flutter/src/widgets/form.dart:617:5)',
            ]),
          ),
        ],
        context: const {
          'redaction': {'regions': 1},
        },
      ),
    ];

    var n = 0;
    CommentEvent event(
      DateTime at,
      String kind, {
      String? actor,
      String? field,
      String? from,
      String? to,
      String? build,
      String? body,
    }) => CommentEvent(
      id: 'demo-seed-${n++}',
      at: at,
      kind: kind,
      actor: actor,
      field: field,
      fromValue: from,
      toValue: to,
      build: build,
      body: body,
    );

    const omar = 'omar@example.com';
    const lena = 'lena@example.com';
    final events = <String, List<CommentEvent>>{
      'demo-2': [
        event(
          ago(hours: 4),
          'assigned',
          actor: lena,
          field: 'assignee',
          to: omar,
        ),
        event(
          ago(hours: 3),
          'verdict_changed',
          actor: omar,
          field: 'dev_verdict',
          from: 'new',
          to: 'in_progress',
        ),
      ],
      'demo-3': [
        event(
          ago(days: 2),
          'assigned',
          actor: lena,
          field: 'assignee',
          to: omar,
        ),
        event(
          ago(days: 1, hours: 20),
          'verdict_changed',
          actor: omar,
          field: 'dev_verdict',
          from: 'new',
          to: 'fixed',
          build: '1.4.2 (57)',
        ),
        event(
          ago(days: 1, hours: 20),
          'commented',
          actor: omar,
          body: 'Debounced the back button. In 1.4.2.',
        ),
      ],
      'demo-4': [
        event(
          ago(days: 4, hours: 20),
          'verdict_changed',
          actor: omar,
          field: 'dev_verdict',
          from: 'new',
          to: 'fixed',
          build: '1.4.1 (52)',
        ),
        event(
          ago(days: 3),
          'verdict_changed',
          actor: 'Ana',
          field: 'tester_verdict',
          from: 'open',
          to: 'verifying',
        ),
        event(
          ago(days: 1),
          'verdict_changed',
          actor: 'Ana',
          field: 'tester_verdict',
          from: 'verifying',
          to: 'accepted',
          build: '1.4.2 (57)',
        ),
      ],
      'demo-5': [
        event(
          ago(days: 3, hours: 22),
          'assigned',
          actor: lena,
          field: 'assignee',
          to: lena,
        ),
        event(
          ago(days: 3, hours: 18),
          'verdict_changed',
          actor: lena,
          field: 'dev_verdict',
          from: 'new',
          to: 'fixed',
          build: '1.4.1 (52)',
        ),
        event(
          ago(days: 2),
          'reopened',
          actor: 'Ravi',
          field: 'tester_verdict',
          from: 'open',
          to: 'rejected',
        ),
        event(
          ago(days: 2),
          'commented',
          actor: 'Ravi',
          body: 'Still crashes on 1.4.1 (52). Same trace.',
        ),
        event(
          ago(days: 1, hours: 23),
          'verdict_changed',
          actor: lena,
          field: 'dev_verdict',
          from: 'fixed',
          to: 'in_progress',
        ),
      ],
      'demo-6': [
        event(
          ago(days: 1),
          'verdict_changed',
          actor: lena,
          field: 'dev_verdict',
          from: 'new',
          to: 'blocked',
        ),
        event(
          ago(days: 1),
          'blocked',
          actor: lena,
          field: 'blocked_on',
          to: 'product',
        ),
        event(
          ago(days: 1),
          'commented',
          actor: lena,
          body: 'Waiting on product: does this button ship in release builds?',
        ),
      ],
      'demo-7': [
        event(
          ago(days: 5),
          'verdict_changed',
          actor: lena,
          field: 'dev_verdict',
          from: 'new',
          to: 'wont_fix',
        ),
        event(
          ago(days: 5),
          'commented',
          actor: lena,
          body:
              'On purpose: GuidesterRedact keeps card numbers out of '
              'screenshots.',
        ),
      ],
    };

    final project = Project(
      id: projectId,
      name: 'Checkout app (demo)',
      createdAt: ago(days: 14),
      ownerId: you.id,
    );

    return DemoData._(
      projects: [project],
      comments: comments,
      projectOf: {for (final c in comments) c.id: projectId},
      events: events,
      keys: {
        projectId: [
          ProjectKey(
            id: 'demo-key',
            key: fakeKey(projectId),
            label: 'default',
            createdAt: project.createdAt,
            lastUsedAt: ago(minutes: 12),
            lastUsedDevice: 'Pixel 8',
            lastUsedOs: 'Android 15',
          ),
        ],
      },
      members: {
        projectId: [
          const TeamMember(
            userId: 'demo-lena',
            email: lena,
            role: TeamRole.admin,
            function: TeamFunction.lead,
          ),
          const TeamMember(
            userId: 'demo-omar',
            email: omar,
            role: TeamRole.member,
            function: TeamFunction.developer,
          ),
          const TeamMember(
            userId: 'demo-kai',
            email: 'kai@example.com',
            role: TeamRole.viewer,
            function: TeamFunction.product,
          ),
        ],
      },
      invites: {projectId: []},
      webhooks: {
        projectId: 'https://hooks.slack.com/services/T0000/B0000/demo',
      },
    );
  }

  static String _stack(List<String> frames) => [
    for (var i = 0; i < frames.length; i++) '#$i      ${frames[i]}',
  ].join('\n');
}
