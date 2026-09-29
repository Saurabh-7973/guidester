import 'captured_error.dart';
import 'comment_status.dart';
import 'impact.dart';
import 'issue_type.dart';
import 'workflow.dart';

/// One tester comment, as stored.
///
/// Parsing is total: a malformed or partial row degrades to sensible defaults
/// rather than throwing, because one bad row must never blank the whole list.
class Comment {
  const Comment({
    required this.id,
    required this.body,
    required this.screenName,
    required this.status,
    required this.createdAt,
    this.tapX,
    this.tapY,
    this.screenshotPath,
    this.testerName,
    this.testerId,
    this.deviceModel,
    this.osVersion,
    this.appVersion,
    this.issueType,
    this.impact = Impact.fallback,
    this.testerVerdict = TesterVerdict.open,
    this.devVerdict = DevVerdict.isNew,
    this.blockedOn,
    this.assignee,
    this.foundInBuild,
    this.fixedInBuild,
    this.verifiedInBuild,
    this.environment,
    this.errors = const [],
    this.context = const {},
  });

  final String id;
  final String body;
  final String screenName;
  final CommentStatus status;
  final DateTime createdAt;

  /// Normalised 0..1, or null when the comment was not pinned.
  final double? tapX;
  final double? tapY;

  /// Storage object path, not a URL. Screenshots live in a private bucket and
  /// are only ever read through a short-lived signed URL.
  final String? screenshotPath;

  final String? testerName;
  final String? testerId;
  final String? deviceModel;
  final String? osVersion;
  final String? appVersion;

  /// Null unless a developer set it at triage, or the row came from an SDK
  /// build that still shipped the type chips. The SDK stopped asking (D51).
  final IssueType? issueType;

  /// What the problem cost the tester. Never null: the column is NOT NULL with
  /// a default, and a row without one predates the chips.
  final Impact impact;

  /// What the tester says, and what the developer says. They move
  /// independently — a fix is not done until the tester has retested it.
  final TesterVerdict testerVerdict;
  final DevVerdict devVerdict;

  /// Who owes the next move, kept out of the verdict so both stay countable.
  final String? blockedOn;
  final String? assignee;

  /// Filled by the SDK from app_version; never typed.
  final String? foundInBuild;
  final String? fixedInBuild;
  final String? verifiedInBuild;

  /// Which backend the build pointed at. `uat`, `live`, whatever the team says.
  final String? environment;

  /// What the app threw before the tester wrote this, oldest first, at most
  /// three. Empty for every comment written before the SDK started chaining
  /// Flutter's error handlers, and for every session where nothing broke.
  final List<CapturedError> errors;

  /// The jsonb long tail: route breadcrumb, text scale, brightness, and so on.
  final Map<String, dynamic> context;

  /// Shipped, and nobody has checked it. The state two spreadsheet columns
  /// make invisible, and the one that costs a release.
  bool get fixedNotVerified =>
      devVerdict == DevVerdict.fixed && testerVerdict != TesterVerdict.accepted;

  bool get hasPin => tapX != null && tapY != null;

  /// Regions the platform composited and the screenshot could not record —
  /// maps, webviews, native chart SDKs, video.
  ///
  /// Nothing can capture these; Flutter draws around them. Surfacing them is
  /// the difference between a developer seeing a labelled hole and a developer
  /// seeing a black rectangle with no explanation.
  List<BlankRegion> get blankRegions {
    final raw = context['blank_regions'];
    if (raw is! List) return const [];
    return [
      for (final r in raw)
        if (r is Map) BlankRegion.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  /// What `GuidesterRedact` did to the screenshot, from SDK 0.6.0. Null when
  /// nothing on the screen was wrapped, or the SDK is older.
  Redaction? get redaction => Redaction.fromJson(context['redaction']);

  factory Comment.fromRow(Map<String, dynamic> row) {
    return Comment(
      id: row['id']?.toString() ?? '',
      body: row['body']?.toString() ?? '',
      screenName: row['screen_name']?.toString() ?? 'UNKNOWN',
      status: CommentStatus.fromWire(row['status']?.toString()),
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      tapX: _toDouble(row['tap_x']),
      tapY: _toDouble(row['tap_y']),
      screenshotPath: _nonEmpty(row['screenshot_path']),
      testerName: _nonEmpty(row['tester_name']),
      testerId: _nonEmpty(row['tester_id']),
      deviceModel: _nonEmpty(row['device_model']),
      osVersion: _nonEmpty(row['os_version']),
      appVersion: _nonEmpty(row['app_version']),
      issueType: IssueType.fromWire(_nonEmpty(row['issue_type'])),
      impact: Impact.fromWire(_nonEmpty(row['impact'])),
      testerVerdict: TesterVerdict.fromWire(_nonEmpty(row['tester_verdict'])),
      devVerdict: DevVerdict.fromWire(_nonEmpty(row['dev_verdict'])),
      blockedOn: BlockedOn.fromWire(_nonEmpty(row['blocked_on'])),
      assignee: _nonEmpty(row['assignee']),
      foundInBuild: _nonEmpty(row['found_in_build']),
      fixedInBuild: _nonEmpty(row['fixed_in_build']),
      verifiedInBuild: _nonEmpty(row['verified_in_build']),
      environment: _nonEmpty(row['environment']),
      errors: _errors(row['errors']),
      context: row['context'] is Map
          ? Map<String, dynamic>.from(row['context'] as Map)
          : const {},
    );
  }

  Comment copyWith({
    CommentStatus? status,
    TesterVerdict? testerVerdict,
    DevVerdict? devVerdict,
    String? blockedOn,
    bool clearBlockedOn = false,
    String? assignee,
    String? fixedInBuild,
    String? verifiedInBuild,
  }) => Comment(
    id: id,
    body: body,
    screenName: screenName,
    status: status ?? this.status,
    createdAt: createdAt,
    tapX: tapX,
    tapY: tapY,
    screenshotPath: screenshotPath,
    testerName: testerName,
    testerId: testerId,
    deviceModel: deviceModel,
    osVersion: osVersion,
    appVersion: appVersion,
    issueType: issueType,
    impact: impact,
    testerVerdict: testerVerdict ?? this.testerVerdict,
    devVerdict: devVerdict ?? this.devVerdict,
    blockedOn: clearBlockedOn ? null : (blockedOn ?? this.blockedOn),
    assignee: assignee ?? this.assignee,
    foundInBuild: foundInBuild,
    fixedInBuild: fixedInBuild ?? this.fixedInBuild,
    verifiedInBuild: verifiedInBuild ?? this.verifiedInBuild,
    environment: environment,
    errors: errors,
    context: context,
  );

  static List<CapturedError> _errors(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map) CapturedError.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  static double? _toDouble(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static String? _nonEmpty(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }
}
