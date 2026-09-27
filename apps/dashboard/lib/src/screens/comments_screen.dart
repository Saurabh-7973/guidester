import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/env.dart';
import '../data/comment_repository.dart';
import '../models/comment.dart';
import '../models/comment_status.dart';
import '../models/impact.dart';
import '../models/issue_type.dart';
import '../models/workflow.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/comment_detail.dart';
import '../widgets/comment_row.dart';
import '../widgets/comment_strip.dart';
import '../widgets/controls.dart';
import '../widgets/project_header.dart';
import '../widgets/skeleton.dart';
import '../widgets/workflow_panel.dart';

/// Master-detail over one project's comments, split by status.
///
/// One screen rather than two routes: with a left rail and a right pane the
/// Prev/Next requirement is just moving the selection, and a status change
/// never loses your place in the list.
class CommentsScreen extends StatefulWidget {
  const CommentsScreen({
    super.key,
    required this.repository,
    this.projectId,
    this.projectName = 'Project',
    this.createdBy = 'You',
    this.onBackToProjects,
    this.projectTotal,
    this.commentId,
    this.status = CommentStatus.open,
    this.impact,
    this.screen,
    this.onChanged,
    this.linkFor,
    this.lastLaunch,
    this.onSetup,
    this.onOpenSettings,
  });

  final CommentRepository repository;

  /// Which project's board this is. Null falls back to the `PROJECT_ID`
  /// dart-define, which is how a single-project build was configured before
  /// the projects list became real.
  final String? projectId;

  /// §4's title and meta row. Passed in rather than fetched: v0 has one
  /// project and the shell already knows who is signed in.
  final String projectName;
  final String createdBy;
  final VoidCallback? onBackToProjects;

  /// Every comment in the project, across tabs and filters. Decides whether
  /// the new-project help card is still worth its space. Null when unknown,
  /// and then an active filter never brings the card back.
  final int? projectTotal;

  /// The comment, tab and filter the URL names. The screen follows them when
  /// they change, and reports its own changes through [onChanged] so the URL
  /// follows the screen.
  final String? commentId;
  final CommentStatus status;
  final Impact? impact;
  final String? screen;

  /// The shareable URL of one comment, for Copy link. Null hides the button.
  final String Function(String commentId)? linkFor;

  /// For an empty project: when the SDK last reached it (§5.6 row 9).
  final Future<LastLaunch?> Function()? lastLaunch;

  /// Where "Open setup" goes when no launch has been seen.
  final VoidCallback? onSetup;

  /// `g` then `s` (§5.6 row 7).
  final VoidCallback? onOpenSettings;

  /// A user moved the selection, the tab or a filter. [commentId] is null
  /// when the selection was made for them (first row, after a status change).
  final void Function(
    String? commentId,
    CommentStatus status,
    Impact? impact,
    String? screen,
  )?
  onChanged;

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: CommentStatus.values.length,
    vsync: this,
    initialIndex: CommentStatus.values.indexOf(widget.status),
  );

  /// Everything the tab and impact filter loaded.
  List<Comment> _all = const [];

  /// Null is every screen. Applied here rather than in Postgres: the picker
  /// lists every screen present with its count, which a server-side filter
  /// would hide.
  late String? _screenFilter = widget.screen;

  /// What the board shows: [_all], narrowed to [_screenFilter].
  List<Comment> get _comments => _screenFilter == null
      ? _all
      : _all.where((c) => c.screenName == _screenFilter).toList();

  /// Null is every impact.
  late Impact? _impactFilter = widget.impact;

  /// The URL named a comment that is not in this list.
  bool _missing = false;
  Comment? _selected;
  String? _signedUrl;
  List<CommentEvent> _events = const [];
  Board? _board;
  bool _loading = true;
  String? _error;

  CommentStatus get _status => CommentStatus.values[_tabs.index];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final id in List.of(_pendingDeletes.keys)) {
      unawaited(_commitDelete(id));
    }
    _retry?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  /// The URL moved: back, forward, or a link opened in this tab.
  @override
  void didUpdateWidget(CommentsScreen old) {
    super.didUpdateWidget(old);
    if (widget.screen != _screenFilter) {
      setState(() => _screenFilter = widget.screen);
      // Back or Forward to a narrower URL can hide the open comment. After
      // this build: choosing another one reports it, and reporting moves
      // the URL, which must not happen mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectFirst();
      });
    }
    if (widget.status != _status || widget.impact != _impactFilter) {
      _tabs.index = CommentStatus.values.indexOf(widget.status);
      _impactFilter = widget.impact;
      _load();
      return;
    }
    final id = widget.commentId;
    if (id != null && id != _selected?.id) _selectById(id);
  }

  /// An empty tab with no filter on. Open with comments elsewhere in the
  /// project is the goal reached (§5.6 row 11), not a new project, so the
  /// first-run help is only for a project that has never had a comment.
  Widget _emptyTab() {
    if (_status == CommentStatus.open && (widget.projectTotal ?? 0) > 0) {
      return _InboxZero(
        onSeeResolved: () {
          _tabs.index = CommentStatus.values.indexOf(CommentStatus.resolved);
          _announce();
          _load(keepComment: false);
        },
      );
    }
    if (_status != CommentStatus.open) {
      return Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Text(
          _status == CommentStatus.inProgress
              ? 'Nothing in progress.'
              : 'Nothing resolved yet.',
          style: T.body.copyWith(color: T.text3),
        ),
      );
    }
    return ProjectEmptyState(
      lastLaunch: widget.lastLaunch,
      onSetup: widget.onSetup,
    );
  }

  /// Every screen in what the tab and impact filter loaded, most comments
  /// first, so the busiest screen is the first choice.
  List<(String, int)> get _screenCounts {
    final counts = <String, int>{};
    for (final c in _all) {
      counts[c.screenName] = (counts[c.screenName] ?? 0) + 1;
    }
    return counts.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2 != a.$2 ? b.$2 - a.$2 : a.$1.compareTo(b.$1));
  }

  void _setScreen(String? screen) {
    setState(() => _screenFilter = screen);
    _selectFirst();
  }

  /// After the visible list changed under the selection: keep it if it is
  /// still shown, otherwise the first row.
  void _selectFirst() {
    final shown = _comments;
    if (_selected != null && shown.any((c) => c.id == _selected!.id)) {
      _announce(commentId: _selected!.id);
      return;
    }
    _announce();
    if (shown.isEmpty) {
      setState(() {
        _selected = null;
        _signedUrl = null;
      });
      return;
    }
    _select(shown.first);
  }

  void _announce({String? commentId}) =>
      widget.onChanged?.call(commentId, _status, _impactFilter, _screenFilter);

  void _selectById(String id) {
    final match = _comments.where((c) => c.id == id).firstOrNull;
    if (match == null) {
      setState(() {
        _missing = true;
        _selected = null;
        _signedUrl = null;
      });
      return;
    }
    _missing = false;
    _select(match);
  }

  /// [keepComment] false when the user changed the tab or filter: the comment
  /// the URL named belongs to the old view, and looking for it in the new one
  /// reports it missing (found in Chrome, 26 Sep).
  Future<void> _load({bool keepComment = true}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final comments = await widget.repository.fetch(
        projectId: widget.projectId ?? Env.projectId,
        status: _status,
        impact: _impactFilter,
      );
      if (!mounted) return;
      final wanted = keepComment ? widget.commentId : null;
      final match = wanted == null
          ? null
          : comments.where((c) => c.id == wanted).firstOrNull;
      setState(() {
        _offline = false;
        _all = comments;
        _loading = false;
        _missing = wanted != null && match == null;
        final shown = _comments;
        _selected = _missing
            ? null
            : (match ?? (shown.isEmpty ? null : shown.first));
      });
      await _loadScreenshot();
      await _loadEvents();
    } on RepositoryException catch (e) {
      if (!mounted) return;
      if (e.offline) {
        // §5.6 row 15: the network, not the database. Keep what is on
        // screen, say so, and try again on our own.
        setState(() => _offline = true);
        _retry?.cancel();
        _retry = Timer(_retryEvery, () {
          if (mounted) _load(keepComment: keepComment);
        });
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  static const Duration _retryEvery = Duration(seconds: 5);
  bool _offline = false;
  Timer? _retry;

  /// The history of the selected comment. Loaded beside the screenshot: both
  /// are per-selection, and both are allowed to fail without emptying the pane.
  Future<void> _loadEvents() async {
    final id = _selected?.id;
    if (id == null) {
      if (mounted) setState(() => _events = const []);
      return;
    }
    try {
      final events = await widget.repository.events(id);
      if (mounted && _selected?.id == id) setState(() => _events = events);
    } on RepositoryException {
      if (mounted) setState(() => _events = const []);
    }
  }

  /// The counts, refreshed whenever the list is. Cheap at v0 volumes and the
  /// only way to see "fixed but not verified" without reading every row.
  Future<void> _loadBoard() async {
    try {
      final board = await widget.repository.board(
        projectId: widget.projectId ?? Env.projectId,
      );
      if (mounted) setState(() => _board = board);
    } on RepositoryException {
      // A missing count must never take the list down with it.
    }
  }

  Future<void> _loadScreenshot({bool retry = false}) async {
    if (!retry) {
      _resignedFor = null;
      _shotExpired = false;
    }
    final path = _selected?.screenshotPath;
    if (path == null) {
      if (mounted) setState(() => _signedUrl = null);
      return;
    }
    final url = await widget.repository.signedScreenshotUrl(path);
    if (mounted) setState(() => _signedUrl = url);
  }

  /// G7: signed URLs last an hour, so a tab left open over lunch holds dead
  /// links. The first failure mints a fresh one; a second means the object is
  /// really gone or unreachable, and the pane says so instead of retrying.
  String? _resignedFor;
  bool _shotExpired = false;

  void _onScreenshotFailed() {
    final id = _selected?.id;
    if (id == null || _shotExpired) return;
    if (_resignedFor != id) {
      _resignedFor = id;
      _loadScreenshot(retry: true);
      return;
    }
    setState(() => _shotExpired = true);
  }

  Future<void> _select(Comment comment) async {
    setState(() {
      _selected = comment;
      _signedUrl = null;
    });
    await _loadScreenshot();
    await _loadEvents();
  }

  /// Moves the selection by [delta] within the current list.
  void _step(int delta) {
    if (_selected == null || _comments.isEmpty) return;
    final i = _comments.indexWhere((c) => c.id == _selected!.id);
    final next = i + delta;
    if (next < 0 || next >= _comments.length) return;
    _select(_comments[next]);
    _announce(commentId: _comments[next].id);
  }

  Future<void> _setStatus(Comment comment, CommentStatus status) async {
    try {
      await widget.repository.updateStatus(
        commentId: comment.id,
        status: status,
      );
      if (!mounted) return;
      // The comment no longer belongs in this tab, so drop it and keep a
      // sensible selection rather than reloading and losing the scroll.
      final at = _comments.indexWhere((c) => c.id == comment.id);
      final wasSelected = _selected?.id == comment.id;
      setState(() {
        _all = _all.where((c) => c.id != comment.id).toList(growable: false);
        final remaining = _comments;
        if (wasSelected) {
          // The one that took its place: triage moves forward.
          _selected = remaining.isEmpty
              ? null
              : remaining[at.clamp(0, remaining.length - 1)];
          _signedUrl = null;
        }
      });
      // The URL named the comment that just left this tab.
      if (wasSelected) _announce();
      await _loadScreenshot();
      await _loadEvents();
      _toast('Marked ${status.label}');
    } on RepositoryException catch (e) {
      _toast(e.message, isError: true);
    }
  }

  void _toast(String message, {bool isError = false, VoidCallback? retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        action: retry == null
            ? null
            : SnackBarAction(
                label: 'Retry',
                textColor: T.accentText,
                onPressed: retry,
              ),
        content: Text(message),
        backgroundColor: isError ? T.surface3 : T.surface2,
        behavior: SnackBarBehavior.floating,
        width: 340,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No AppBar and no Scaffold: this now lives inside AppShell, which owns
    // the page, the nav tabs and the user chip. §4's header replaces them.
    if (_error != null) return _ErrorState(message: _error!, onRetry: _load);
    final board = _boardBody(context);
    if (!_offline) return board;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OfflineBanner(),
        Expanded(child: board),
      ],
    );
  }

  Widget _boardBody(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 516,
            child: BoardSkeleton(key: ValueKey('board-skeleton')),
          ),
        ),
      );
    }

    final header = ProjectHeader(
      projectName: widget.projectName,
      createdBy: widget.createdBy,
      // Collaborators do not exist yet, and §4 says the count renders only
      // when it is above zero rather than advertising an empty feature.
      collaborators: 0,
      commentCount:
          widget.projectTotal ??
          (_impactFilter == null && _status == CommentStatus.open
              ? _all.length
              : 3),
      status: _status,
      counts: _counts,
      board: _board,
      onStatusSelected: (s) {
        // Reload on tap rather than from a TabController listener. A
        // TabController is an Animation: its listeners fire on animation
        // ticks, and the usual `if (indexIsChanging) return;` idiom can
        // skip the whole animation without ever seeing a final tick where
        // the flag is false — so the list silently never reloads. Only the
        // browser showed that; pumpAndSettle hides it.
        _tabs.index = CommentStatus.values.indexOf(s);
        _announce();
        _load(keepComment: false);
      },
    );
    final filters = _ImpactFilterBar(
      selected: _impactFilter,
      onChanged: (impact) {
        setState(() => _impactFilter = impact);
        _announce();
        _load(keepComment: false);
      },
      trailing: _ScreenPicker(
        key: const ValueKey('screen-filter'),
        counts: _screenCounts,
        selected: _screenFilter,
        onChanged: _setScreen,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Home (8): with comments to show on a wide screen, the header, tabs,
        // filters and list are one left panel and the comment takes the rest
        // at full height. Stacked above the pane, the header pushed the
        // screenshot and triage controls into a scroll.
        if (constraints.maxWidth >= _railBreakpoint && _comments.isNotEmpty) {
          return _withShortcuts(
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  // About a third of the board, within what a row reads at.
                  width: (constraints.maxWidth * 0.32).clamp(380.0, _railWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      const SizedBox(height: 16),
                      filters,
                      Expanded(child: _rail()),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 20),
                    child: _pane(),
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 16),
            filters,
            Expanded(
              child: _comments.isEmpty
                  ? (_impactFilter == null && _screenFilter == null
                        ? _emptyTab()
                        : _NoMatch(
                            onClear: () {
                              final reload = _impactFilter != null;
                              setState(() {
                                _impactFilter = null;
                                _screenFilter = null;
                              });
                              _announce();
                              if (reload) {
                                _load(keepComment: false);
                              } else {
                                _selectFirst();
                              }
                            },
                          ))
                  : _body(),
            ),
          ],
        );
      },
    );
  }

  /// Counts per tab. Only the loaded tab is known, so the others render
  /// without a number rather than with a wrong one.
  Map<CommentStatus, int> get _counts => {_status: _comments.length};

  /// Open comments sharing a screen AND an impact. Computed once per build
  /// rather than per row: the twelve-testers-one-bug case is a property of the
  /// list, and asking each row to scan the list would be quadratic.
  Map<String, int> get _duplicates {
    final counts = <String, int>{};
    for (final c in _comments) {
      final key = '${c.screenName}|${c.impact.wire}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  /// Where the rail goes as the window narrows.
  ///
  /// Ruled after §6, which only defines 1440. At 1280 you are reading one
  /// comment — screenshot, pin, context — not scanning a rail, so the pane
  /// wins the width. Stacking was rejected: it pushes the screenshot below the
  /// fold at exactly the width where there is least vertical room.
  static const double _railBreakpoint = 1100;
  static const double _railWidth = 480;
  static const double _stripBreakpoint = 720;

  /// The full rail, shown over the pane when the strip is expanded.
  bool _railOverlay = false;

  /// Moves the selection without touching the rail, so navigation never
  /// depends on the rail being open. `j`/`k`, and Prev/Next in the pane.
  ///
  /// Letter keys are ignored while a text field has focus: a note that
  /// contains a "j" must not move the selection.
  Map<ShortcutActivator, VoidCallback> get _bindings => {
    const SingleActivator(LogicalKeyboardKey.keyJ): _unlessTyping(
      () => _step(1),
    ),
    const SingleActivator(LogicalKeyboardKey.keyK): _unlessTyping(
      () => _step(-1),
    ),
    const SingleActivator(LogicalKeyboardKey.arrowDown): _unlessTyping(
      () => _step(1),
    ),
    const SingleActivator(LogicalKeyboardKey.arrowUp): _unlessTyping(
      () => _step(-1),
    ),
    const SingleActivator(LogicalKeyboardKey.keyR): _unlessTyping(
      () => _onSelected(CommentStatus.resolved),
    ),
    const SingleActivator(LogicalKeyboardKey.keyP): _unlessTyping(
      () => _onSelected(CommentStatus.inProgress),
    ),
    const CharacterActivator('?'): _unlessTyping(_showShortcuts),
    // `g` then `s`, within a second: go to settings (§5.6 row 7).
    const SingleActivator(LogicalKeyboardKey.keyG): _unlessTyping(
      () => _gAt = DateTime.now(),
    ),
    const SingleActivator(LogicalKeyboardKey.keyS): _unlessTyping(() {
      final g = _gAt;
      _gAt = null;
      if (g != null && DateTime.now().difference(g) < _chord) {
        widget.onOpenSettings?.call();
      }
    }),
    const SingleActivator(LogicalKeyboardKey.slash, shift: true): _unlessTyping(
      _showShortcuts,
    ),
  };

  DateTime? _gAt;
  static const Duration _chord = Duration(seconds: 1);

  VoidCallback _unlessTyping(VoidCallback action) => () {
    final focused = FocusManager.instance.primaryFocus?.context;
    final typing =
        focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null);
    if (!typing) action();
  };

  void _onSelected(CommentStatus status) {
    final c = _selected;
    if (c == null || c.status == status) return;
    _setStatus(c, status);
  }

  void _showShortcuts() {
    showDialog<void>(context: context, builder: (_) => const ShortcutsSheet());
  }

  Widget _rail() {
    final duplicates = _duplicates;
    // The first row of each group keeps its meta; the ones below it collapse.
    final seen = <String>{};
    return ListView.builder(
      key: const ValueKey('rail'),
      itemCount: _comments.length,
      itemBuilder: (context, i) {
        final c = _comments[i];
        final key = '${c.screenName}|${c.impact.wire}';
        final collapsed = !seen.add(key);
        return CommentRow(
          comment: c,
          selected: c.id == _selected?.id,
          duplicateCount: duplicates[key] ?? 0,
          collapsed: collapsed,
          onTap: () {
            _missing = false;
            _select(c);
            _announce(commentId: c.id);
            // Picking from the overlay closes it: you opened it to choose.
            if (_railOverlay) setState(() => _railOverlay = false);
          },
          onMarkInProgress: c.status == CommentStatus.inProgress
              ? null
              : () => _setStatus(c, CommentStatus.inProgress),
          onResolve: c.status == CommentStatus.resolved
              ? null
              : () => _setStatus(c, CommentStatus.resolved),
        );
      },
    );
  }

  Widget _pane({VoidCallback? onBack}) => _selected == null
      ? (_missing ? const _NoSuchComment() : const SizedBox.shrink())
      : CommentDetail(
          comment: _selected!,
          signedUrl: _signedUrl,
          screenshotExpired: _shotExpired,
          onScreenshotFailed: _onScreenshotFailed,
          link: widget.linkFor?.call(_selected!.id),
          onPrev: () => _step(-1),
          onNext: () => _step(1),
          onBack: onBack,
          workflow: WorkflowPanel(
            comment: _selected!,
            events: _events,
            blockedOnOptions: BlockedOn.defaults,
            onDevVerdict: (v, {String? build}) => _move(dev: v),
            onTesterVerdict: (v, {String? build}) => _move(tester: v),
            onBlockedOn: (v) => _move(blockedOn: v, clearBlockedOn: v == null),
            onAssign: (who) => _move(assignee: who),
            onNote: (note) => _move(note: note),
          ),
          onDelete: () => _delete(_selected!),
          onDeleteTester: _selected!.testerId == null
              ? null
              : () => _deleteTester(_selected!),
        );

  /// Moves a verdict and records it. One call: the row and its history are
  /// written together, which is the whole reason the events table exists.
  Future<void> _move({
    TesterVerdict? tester,
    DevVerdict? dev,
    String? blockedOn,
    bool clearBlockedOn = false,
    String? assignee,
    String? note,
  }) async {
    final current = _selected;
    if (current == null) return;
    // §5.6 row 19: the chip moves at once. A failed save puts the comment
    // back as it was and offers Retry, rather than leaving the screen
    // claiming a verdict the database never took.
    void show(Comment c) => setState(() {
      if (_selected?.id == c.id) _selected = c;
      _all = [
        for (final x in _all)
          if (x.id == c.id) c else x,
      ];
    });
    if (tester != null ||
        dev != null ||
        blockedOn != null ||
        clearBlockedOn ||
        assignee != null) {
      show(
        current.copyWith(
          testerVerdict: tester,
          devVerdict: dev,
          blockedOn: blockedOn,
          clearBlockedOn: clearBlockedOn,
          assignee: assignee,
        ),
      );
    }
    try {
      final updated = await widget.repository.setVerdict(
        comment: current,
        tester: tester,
        dev: dev,
        blockedOn: blockedOn,
        clearBlockedOn: clearBlockedOn,
        assignee: assignee,
        // The build a fix lands in is the build the report came from until a
        // developer says otherwise — and for a verification it is the build the
        // tester retested on. Both default to what the SDK already captured.
        build: current.foundInBuild,
        note: note,
      );
      if (!mounted) return;
      show(updated);
      await _loadEvents();
      await _loadBoard();
    } on RepositoryException catch (e) {
      if (!mounted) return;
      show(current);
      _toast(
        e.message,
        isError: true,
        retry: () => _move(
          tester: tester,
          dev: dev,
          blockedOn: blockedOn,
          clearBlockedOn: clearBlockedOn,
          assignee: assignee,
          note: note,
        ),
      );
    }
  }

  /// G4: the row and its screenshot, gone. Under the DPDP Act this request is
  /// not optional and the project owner is the data fiduciary.
  /// §5.6 row 20: confirm, then Undo for 5 s. The comment leaves the board
  /// at once and the delete waits out the window; Undo puts it back where it
  /// was. Leaving the board inside the window deletes straight away: that is
  /// what was asked for.
  static const Duration _undoWindow = Duration(seconds: 5);
  final Map<String, (Timer, Comment)> _pendingDeletes = {};

  void _delete(Comment comment) {
    final at = _all.indexWhere((c) => c.id == comment.id);
    _dropFromList([comment.id]);
    _pendingDeletes[comment.id] = (
      Timer(_undoWindow, () => _commitDelete(comment.id)),
      comment,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Comment deleted'),
        duration: _undoWindow,
        backgroundColor: T.surface2,
        behavior: SnackBarBehavior.floating,
        width: 340,
        action: SnackBarAction(
          label: 'Undo',
          textColor: T.accentText,
          onPressed: () => _undoDelete(comment.id, at),
        ),
      ),
    );
  }

  void _undoDelete(String id, int at) {
    final pending = _pendingDeletes.remove(id);
    if (pending == null) return;
    pending.$1.cancel();
    final comment = pending.$2;
    setState(() {
      final list = List.of(_all);
      list.insert(at.clamp(0, list.length), comment);
      _all = list;
    });
    _select(comment);
    _announce(commentId: comment.id);
  }

  Future<void> _commitDelete(String id) async {
    final pending = _pendingDeletes.remove(id);
    if (pending == null) return;
    pending.$1.cancel();
    try {
      await widget.repository.deleteComment(pending.$2);
    } on RepositoryException catch (e) {
      // It never left the database: put it back and say why.
      if (!mounted) return;
      setState(() => _all = [..._all, pending.$2]);
      // "Comment deleted" is no longer true; the error replaces it rather
      // than queueing behind it.
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _toast(e.message, isError: true);
    }
  }

  Future<void> _deleteTester(Comment comment) async {
    final testerId = comment.testerId;
    if (testerId == null) return;
    try {
      final n = await widget.repository.deleteTester(
        projectId: widget.projectId ?? Env.projectId,
        testerId: testerId,
      );
      if (!mounted) return;
      // Everything of theirs went, not just what this tab was showing, so
      // reload rather than pruning in Dart and guessing at the rest.
      _toast(n == 1 ? '1 comment deleted' : '$n comments deleted');
      await _load();
    } on RepositoryException catch (e) {
      if (mounted) _toast(e.message, isError: true);
    }
  }

  void _dropFromList(List<String> ids) {
    final wasSelected = _selected != null && ids.contains(_selected!.id);
    if (wasSelected) _announce();
    setState(() {
      _all = _all.where((c) => !ids.contains(c.id)).toList(growable: false);
      final remaining = _comments;
      if (_selected != null && ids.contains(_selected!.id)) {
        _selected = remaining.isEmpty ? null : remaining.first;
        _signedUrl = null;
      }
    });
    if (_selected != null) _loadScreenshot();
  }

  /// j/k and the rest, for whichever layout is showing.
  Widget _withShortcuts(Widget child) => CallbackShortcuts(
    bindings: _bindings,
    child: Focus(autofocus: true, child: child),
  );

  Widget _body() {
    return _withShortcuts(
      LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;

          // >= 1100: §6 as drawn. 516 rail, 24 gap, pane.
          if (w >= _railBreakpoint) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: _railWidth, child: _rail()),
                  const SizedBox(width: 24),
                  Expanded(child: _pane()),
                ],
              ),
            );
          }

          // 720-1099: the rail collapses to a strip, the pane takes the
          // rest, and the strip expands back to 516 as an overlay.
          if (w >= _stripBreakpoint) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CommentStrip(
                        comments: _comments,
                        selected: _selected,
                        onSelect: (c) {
                          _missing = false;
                          _select(c);
                          _announce(commentId: c.id);
                        },
                        onExpand: () => setState(() => _railOverlay = true),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: _pane()),
                    ],
                  ),
                  if (_railOverlay)
                    _RailOverlay(
                      width: 516,
                      onDismiss: () => setState(() => _railOverlay = false),
                      child: _rail(),
                    ),
                ],
              ),
            );
          }

          // < 720: the pane only. The rail becomes a back control.
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                _pane(onBack: () => setState(() => _railOverlay = true)),
                if (_railOverlay)
                  _RailOverlay(
                    width: w,
                    onDismiss: () => setState(() => _railOverlay = false),
                    child: _rail(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The full rail, over the pane, at the widths where it does not fit beside it.
class _RailOverlay extends StatelessWidget {
  const _RailOverlay({
    required this.width,
    required this.onDismiss,
    required this.child,
  });

  final double width;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Tapping the pane behind it dismisses, the way a drawer does.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: width,
            child: Material(
              color: T.page,
              elevation: 8,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 18, color: T.text3),
                      onPressed: onDismiss,
                      tooltip: 'Close list',
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpactFilterBar extends StatelessWidget {
  const _ImpactFilterBar({
    required this.selected,
    required this.onChanged,
    this.trailing,
  });

  final Impact? selected;
  final ValueChanged<Impact?> onChanged;

  /// Drawn after the impact chips, in the same wrap: the screen picker.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // Wrapped, not scrolled, for the same reason as the overlay's chips: a
    // filter the user cannot see is a filter they will not use.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          // Keyed: the same labels appear on the rows below, so a finder by
          // text alone cannot tell a filter from a comment's own label.
          _FilterChip(
            key: const ValueKey('impact-filter-all'),
            label: 'All',
            isSelected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final impact in Impact.values)
            _FilterChip(
              key: ValueKey('impact-filter-${impact.wire}'),
              label: _title(impact.wire),
              isSelected: impact == selected,
              // Tap the active filter to clear it, as in the overlay.
              onTap: () => onChanged(impact == selected ? null : impact),
            ),
          ?trailing,
        ],
      ),
    );
  }

  static String _title(String wire) =>
      wire[0].toUpperCase() + wire.substring(1);
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Material(
        color: isSelected
            ? AppTheme.accent.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? AppTheme.accent
                    : AppTheme.muted.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppTheme.accent : AppTheme.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The type as it appears on a list row and in the detail header.
class IssueTypeChip extends StatelessWidget {
  const IssueTypeChip({super.key, required this.issueType});

  final IssueType issueType;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.muted.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        issueType.label,
        style: const TextStyle(
          color: AppTheme.muted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The URL named a comment this list does not hold: deleted, in another
/// project, or never shared with this account. The board stays usable.
class _NoSuchComment extends StatelessWidget {
  const _NoSuchComment();

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      "This comment doesn't exist or you don't have access.",
      style: TextStyle(color: AppTheme.muted),
    ),
  );
}

/// An active filter with nothing under it. Says so, and offers the way back:
/// on 25 Sep an empty filter showed the new-project help instead, which reads
/// as "this project has no comments".
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'No comments match these filters.',
          style: TextStyle(color: AppTheme.muted),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onClear, child: const Text('Clear filters')),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: const TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

/// The `?` sheet: every triage key, in one place.
class ShortcutsSheet extends StatelessWidget {
  const ShortcutsSheet({super.key});

  static const List<(String, String)> keys = [
    ('j  or  ↓', 'Next comment'),
    ('k  or  ↑', 'Previous comment'),
    ('r', 'Resolve'),
    ('p', 'Mark in progress'),
    ('g  s', 'Settings'),
    ('?', 'This list'),
    ('Esc', 'Close'),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: T.surface1,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Keyboard shortcuts', style: T.heading),
              const SizedBox(height: 16),
              for (final (key, what) in keys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(width: 96, child: Text(key, style: T.code)),
                      Expanded(
                        child: Text(
                          what,
                          style: T.supporting.copyWith(color: T.text2),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "All screens ▾" beside the impact chips. Lists every screen in the tab
/// with its count.
class _ScreenPicker extends StatelessWidget {
  const _ScreenPicker({
    super.key,
    required this.counts,
    required this.selected,
    required this.onChanged,
  });

  final List<(String, int)> counts;
  final String? selected;
  final ValueChanged<String?> onChanged;

  /// PopupMenuButton treats a null value as "dismissed", so "every screen"
  /// travels as the empty string.
  static const String _all = '';

  @override
  Widget build(BuildContext context) {
    final active = selected != null;
    return PopupMenuButton<String>(
      tooltip: 'Filter by screen',
      color: T.surface2,
      position: PopupMenuPosition.under,
      onSelected: (v) => onChanged(v == _all ? null : v),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _all,
          child: Text('All screens', style: T.supporting),
        ),
        for (final (name, n) in counts)
          PopupMenuItem(
            value: name,
            child: Text('$name  $n', style: T.supporting),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? T.accent.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? T.accent : T.text2.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected ?? 'All screens',
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? T.accentText : T.text2,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more,
              size: 14,
              color: active ? T.accentText : T.text2,
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxZero extends StatelessWidget {
  const _InboxZero({required this.onSeeResolved});

  final VoidCallback onSeeResolved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: T.green),
              SizedBox(width: 8),
              Text('Inbox zero', style: T.body),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Nothing open. Every comment has been dealt with.',
            style: T.supporting.copyWith(color: T.text3),
          ),
          const SizedBox(height: 14),
          GButton(
            label: 'See resolved',
            kind: GButtonKind.secondary,
            onPressed: onSeeResolved,
          ),
        ],
      ),
    );
  }
}

/// §5.6 row 15. Over the board, not instead of it.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: T.amberGround,
          borderRadius: BorderRadius.circular(T.rControl),
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, size: 16, color: T.amber),
            const SizedBox(width: 10),
            Text(
              "Can't reach the server. Retrying…",
              style: T.supporting.copyWith(color: T.amber),
            ),
          ],
        ),
      ),
    );
  }
}
