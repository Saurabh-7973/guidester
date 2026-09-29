import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'capture_context.dart';
import 'capture_warnings.dart';
import 'guidester.dart';
import 'impact.dart';

/// Outcome of a send attempt. Never throws at the call site.
class SendResult {
  const SendResult.ok()
      : success = true,
        error = null,
        retryable = false,
        status = 200;
  const SendResult.failure(this.error, {this.retryable = false, this.status})
      : success = false;

  final bool success;
  final String? error;

  /// The same request could succeed later: the network was not there, or the
  /// server had a bad minute. What the offline queue keeps. False for every
  /// answer that says this request is wrong, which a retry cannot change.
  final bool retryable;

  /// The HTTP status, when there was a response at all.
  final int? status;
}

/// One report a developer has marked fixed and this tester has not accepted.
///
/// The column list is the `pending_retests` view's, and deliberately short:
/// no screenshot, no other tester, no project total. See migration 0008.
class PendingRetest {
  const PendingRetest({
    required this.id,
    required this.excerpt,
    this.screenName,
    this.fixedInBuild,
    this.createdAt,
  });

  final String id;

  /// The first 120 characters of what the tester wrote, enough to recognise
  /// which report this is. Not the body.
  final String excerpt;
  final String? screenName;

  /// The build that contains the fix, so a tester on an older one can be told
  /// to update rather than told they are wrong.
  final String? fixedInBuild;
  final DateTime? createdAt;

  /// Null for anything that is not a usable row.
  ///
  /// This runs on a tester's phone inside the launch path. One malformed row
  /// must cost them that row and nothing else.
  static PendingRetest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final excerpt = raw['excerpt'];
    return PendingRetest(
      id: id,
      excerpt: excerpt is String ? excerpt : '',
      screenName:
          raw['screen_name'] is String ? raw['screen_name'] as String : null,
      fixedInBuild: raw['fixed_in_build'] is String
          ? raw['fixed_in_build'] as String
          : null,
      createdAt: raw['created_at'] is String
          ? DateTime.tryParse(raw['created_at'] as String)
          : null,
    );
  }
}

/// A ping's outcome, plus whatever the response carried back.
///
/// The return leg rides this request rather than an endpoint of its own —
/// D60. A ping that failed carries no retests, and a ping that succeeded
/// against an older backend carries none either.
class PingResult {
  const PingResult({
    required this.success,
    this.error,
    this.retests = const [],
  });

  final bool success;
  final String? error;
  final List<PendingRetest> retests;
}

/// The SDK's entire network surface: one POST to the ingest edge function.
///
/// The SDK never bundles a backend client. It holds a project api_key, not
/// database credentials, and it cannot reach the database directly.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _pingTimeout = Duration(seconds: 8);

  Future<SendResult> send({
    required String body,
    required String screenName,
    double? tapX,
    double? tapY,
    Uint8List? screenshot,
    String? testerName,
    String? testerId,
    Impact impact = Impact.fallback,
    List<BlankRegion> blankRegions = const [],
    List<Map<String, dynamic>> errors = const [],
    CaptureContext? context,
    RedactionReport? redaction,
    String? clientId,
  }) =>
      sendPayload(
        commentPayload(
          body: body,
          screenName: screenName,
          tapX: tapX,
          tapY: tapY,
          screenshot: screenshot,
          testerName: testerName,
          testerId: testerId,
          impact: impact,
          blankRegions: blankRegions,
          errors: errors,
          context: context,
          redaction: redaction,
          clientId: clientId,
        ),
      );

  /// A comment's request body, without the api key.
  ///
  /// Separate from [sendPayload] so the offline queue can keep exactly what
  /// was going to be sent and send it again later.
  static Map<String, dynamic> commentPayload({
    required String body,
    required String screenName,
    double? tapX,
    double? tapY,
    Uint8List? screenshot,
    String? testerName,
    String? testerId,
    Impact impact = Impact.fallback,
    List<BlankRegion> blankRegions = const [],
    List<Map<String, dynamic>> errors = const [],
    CaptureContext? context,
    RedactionReport? redaction,
    String? clientId,
  }) {
    return <String, dynamic>{
      'body': body,
      'screen_name': screenName,
      if (tapX != null) 'tap_x': tapX,
      if (tapY != null) 'tap_y': tapY,
      if (screenshot != null) 'screenshot_b64': base64Encode(screenshot),
      if (testerName != null) 'tester_name': testerName,
      if (testerId != null) 'tester_id': testerId,
      // Always sent. The column has a default, but relying on it would make
      // an older SDK build and a tester who chose 'annoying' indistinguishable
      // in the data — and the whole point of tracking the default rate is
      // telling those two apart.
      'impact': impact.wire,
      // Which backend this build points at. Omitted when the host has not set
      // it, so an older build is distinguishable from a deliberate blank.
      if (Guidester.environment.isNotEmpty)
        'environment': Guidester.environment,
      // Where the screenshot is blank and why. Sent even though the picture
      // still uploads: a developer looking at a black rectangle otherwise has
      // to work out for themselves that the platform composited over it.
      if (blankRegions.isNotEmpty)
        'blank_regions': [for (final r in blankRegions) r.toJson()],
      // What the app threw before the tester wrote this. Sent with every
      // comment, not only a crash report: "the list is empty" and "the button
      // does nothing" are both what a caught exception looks like from the
      // outside, and the stack is the only part of that a developer can act
      // on. Not cleared after a send — the errors happened in this session and
      // the second comment about them is as entitled to the cause as the
      // first.
      if (errors.isNotEmpty) 'errors': errors,
      if (context != null) ...{
        'device_model': context.deviceModel,
        'os_version': context.osVersion,
        'app_version': context.appVersion,
      },
      // What redaction did, inside `context` because ingest stores that object
      // as sent: the dashboard reads it with no backend change, and an older
      // backend keeps it too. Sent even when the device context timed out —
      // a withheld screenshot must never arrive unexplained.
      if (context != null || redaction != null)
        'context': <String, dynamic>{
          ...?context?.extra,
          if (redaction != null) 'redaction': redaction.toJson(),
        },
      // Made once per comment and resent with every retry, so a retry of a
      // request that did arrive is recognised rather than stored twice.
      if (clientId != null) 'client_id': clientId,
    };
  }

  /// POSTs a comment built by [commentPayload], with this build's key.
  Future<SendResult> sendPayload(Map<String, dynamic> payload) async {
    if (!Guidester.isEnabled) {
      return const SendResult.failure('Guidester is not enabled');
    }
    try {
      final response = await _client
          .post(
            Uri.parse(Guidester.endpoint),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({...payload, 'api_key': Guidester.apiKey}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) return const SendResult.ok();
      return SendResult.failure(
        _describe(response.statusCode, response.body),
        retryable: _retryable(response.statusCode, response.body),
        status: response.statusCode,
      );
    } catch (e) {
      // No response: offline, a timeout, a connection dropped mid-upload.
      // Every one of those can go through later.
      return SendResult.failure(_friendly(e), retryable: true);
    }
  }

  /// A 5xx is a server having a bad minute, and a 429 is one asking to be
  /// asked later. Every other answer is about the request itself.
  static bool _retryable(int status, String rawBody) =>
      status >= 500 || status == 429;

  /// Tell the backend this build launched. Product spec §3.2.
  ///
  /// Writes nothing but the key's own last-used columns — no comment, no
  /// screenshot, no upload — and exists so the onboarding screen can state
  /// that the SDK reached the backend instead of asking the developer whether
  /// it did. Self-reported success is the weakest check in that flow.
  ///
  /// The device model and OS go with it because the answer a developer needs
  /// at minute one is "the phone in my hand reported", not "something did".
  ///
  /// Never throws, never retries, and is not worth a millisecond of the
  /// tester's time: a shorter timeout than [send] because nothing is lost when
  /// a ping is dropped.
  Future<PingResult> ping({
    String? deviceModel,
    String? osVersion,
    String? appVersion,
    String? testerId,
  }) async {
    if (!Guidester.isEnabled) {
      return const PingResult(
        success: false,
        error: 'Guidester is not enabled',
      );
    }

    final payload = <String, dynamic>{
      'api_key': Guidester.apiKey,
      'ping': true,
      if (deviceModel != null) 'device_model': deviceModel,
      if (osVersion != null) 'os_version': osVersion,
      if (appVersion != null) 'app_version': appVersion,
      // The return leg. Without this the response can only say `ok`: the
      // backend scopes the list to one tester inside one project, and a
      // missing id answers with an empty list rather than an error.
      if (testerId != null && testerId.isNotEmpty) 'tester_id': testerId,
    };

    try {
      final response = await _client
          .post(
            Uri.parse(Guidester.endpoint),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_pingTimeout);
      if (response.statusCode == 200) {
        return PingResult(success: true, retests: _retestsIn(response.body));
      }
      return PingResult(
        success: false,
        error: _describe(response.statusCode, response.body),
      );
    } catch (e) {
      return PingResult(success: false, error: _friendly(e));
    }
  }

  /// What a tester says about their own report. The only write in the system
  /// that is not a new comment.
  ///
  /// Ownership is checked at the backend twice over — the row must belong to
  /// the key's project AND carry this tester_id — and "no such report" and
  /// "not yours" come back as the same 404 on purpose, so this does not
  /// invent a distinction between them either.
  Future<SendResult> sendVerdict({
    required String commentId,
    required String testerId,
    required bool accepted,
  }) async {
    if (!Guidester.isEnabled) {
      return const SendResult.failure('Guidester is not enabled');
    }

    final payload = <String, dynamic>{
      'api_key': Guidester.apiKey,
      'verdict': accepted ? 'accepted' : 'rejected',
      'comment_id': commentId,
      'tester_id': testerId,
    };

    try {
      final response = await _client
          .post(
            Uri.parse(Guidester.endpoint),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) return const SendResult.ok();
      return SendResult.failure(_describe(response.statusCode, response.body));
    } catch (e) {
      return SendResult.failure(_friendly(e), retryable: true);
    }
  }

  /// The retests in a ping's 200, or none.
  ///
  /// Anything unreadable is none. A launch must never fail because the return
  /// leg could not be understood — the same rule the edge function applies at
  /// the other end.
  static List<PendingRetest> _retestsIn(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map) return const [];
      final raw = decoded['retests'];
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (PendingRetest.tryParse(item) case final r?) r,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Map the edge function's error codes onto something a tester can act on.
  /// Diagnostic 4 of 6. A rejected key produces a failure the tester sees as
  /// "could not send", and a developer never sees at all unless they are
  /// watching the console when it happens. Printing it names the two cases
  /// apart: a key that was never valid, and one that was turned off.
  static void _warnOnRejection(int status, String rawBody) {
    if (status != 401) return;
    final revoked = rawBody.contains('key_revoked');
    debugPrint(
      '[guidester] key rejected (401 ${revoked ? 'key_revoked' : 'invalid_key'}). '
      '${revoked ? 'This build\'s key was rotated or revoked — install a newer build.' : 'Check --dart-define=GUIDESTER_KEY against the key in Settings.'}',
    );
  }

  /// Stage B 10 of the 25 Sep field test: a wrong endpoint printed nothing.
  /// Every other misconfiguration ends in one `[guidester]` line, and the
  /// launch ping goes through here too, so the developer reads this at launch
  /// rather than in the first failed tester report.
  static void _warnOnEndpoint(String what, {bool ifOnline = false}) {
    debugPrint(
      '[guidester] ${Guidester.endpoint} $what. '
      '${ifOnline ? 'If this device is online, check' : 'Check'} the endpoint '
      'passed to Guidester.init '
      '(--dart-define=GUIDESTER_ENDPOINT): it should be your deployment of '
      'the ingest function.',
    );
  }

  static String _describe(int status, String rawBody) {
    _warnOnRejection(status, rawBody);
    String? code;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map && decoded['error'] is String) {
        code = decoded['error'] as String;
      }
    } catch (_) {
      // Non-JSON error body; fall through to the status code.
    }
    switch (code) {
      case 'invalid_key':
        return 'This build is not configured correctly (invalid key).';
      case 'key_revoked':
        // Distinct from invalid_key: the build was configured correctly once
        // and its key has since been turned off, which is fixed by installing
        // a newer build rather than by retrying.
        return 'This build\'s key was revoked. Ask for a newer build.';
      case 'missing_fields':
        return 'Please write something before sending.';
      case 'body_too_long':
        return 'That comment is too long (2000 characters max).';
      case 'screenshot_too_large':
        return 'The screenshot was too large to send.';
      case 'bad_json':
        return 'Could not send that comment.';
      case 'invalid_issue_type':
      case 'invalid_impact':
      case 'invalid_blank_regions':
      case 'too_many_blank_regions':
      case 'invalid_context':
      case 'context_too_large':
        // Only reachable if the SDK and the server disagree on the accepted
        // values, which is a bug in us, not something the tester can fix by
        // retrying. `invalid_issue_type` is kept because an older SDK build in
        // a tester's hands still sends that field.
        return 'Could not send that comment.';
      case 'not_found':
        // "No such report" and "not yours" are the same answer from the
        // server, so they are the same sentence here.
        return 'That report is no longer available on this build.';
      case 'invalid_verdict':
        return 'Could not send that answer.';
      case 'rate_limited':
        // A 429, so the offline queue keeps it and retries after a pause.
        // Only seen when the queue could not keep it either.
        return 'Too many comments at once. Wait a moment and try again.';
      case 'upload_failed':
      case 'insert_failed':
      case 'lookup_failed':
        return 'The server could not save that comment. Try again.';
    }
    // No code this function sends: whatever answered is not the ingest
    // function. A 5xx can still be ours having a bad minute (the gateway in
    // front of it answers with no body of its own), so only a 4xx is blamed on
    // the build.
    if (status >= 500) {
      _warnOnEndpoint('answered HTTP $status with no Guidester error code');
      return 'The server had a problem. Your comment is still here — try again.';
    }
    _warnOnEndpoint(
      'answered HTTP $status, which is not a Guidester response',
    );
    return 'This build is not configured correctly (wrong server address).';
  }

  static String _friendly(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('timeout')) {
      return 'That took too long. Check your connection and try again.';
    }
    if (text.contains('socket') ||
        text.contains('failed host lookup') ||
        text.contains('connection')) {
      // Offline and a host that does not exist fail identically on the
      // device, so the tester is told only what is known. The developer is
      // told which of the two to rule out.
      _warnOnEndpoint(
        'could not be reached '
        '(${text.contains('failed host lookup') ? 'host lookup failed' : 'connection failed'})',
        ifOnline: true,
      );
      // Found recording the demo, 27 Sep: a release build of an app whose
      // main manifest lacks INTERNET fails exactly like this on a device
      // that is online, and the line above sends the developer to check a
      // correct endpoint. Debug and profile builds get the permission from
      // Flutter's own manifests, so it only ever shows up in release.
      if (defaultTargetPlatform == TargetPlatform.android &&
          text.contains('failed host lookup')) {
        debugPrint(
          '[guidester] On Android, a release build also needs '
          '<uses-permission android:name="android.permission.INTERNET"/> in '
          'android/app/src/main/AndroidManifest.xml. Debug builds get it '
          'automatically, so a build that sends in debug and not in release '
          'is missing it.',
        );
      }
      return 'Could not reach the server. Your comment is still here — try '
          'again.';
    }
    return 'Could not send that comment. Try again.';
  }

  void dispose() => _client.close();
}
