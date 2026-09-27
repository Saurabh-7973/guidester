import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme/tokens.dart';

/// The count on the bubble. The system's only push channel.
///
/// A tester opens the build, the ping answers, and this appears. It costs no
/// notification permission, no login and no link, because the request it rides
/// on was already being made.
class GuidesterRetestBadge extends StatelessWidget {
  const GuidesterRetestBadge({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = count > 9 ? '9+' : '$count';
    return Semantics(
      button: true,
      label: '$count waiting on you',
      hint: 'Opens the reports a developer says are fixed',
      child: Material(
        color: GT.accent,
        shape:
            const CircleBorder(side: BorderSide(color: GT.surface1, width: 2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 22,
            height: 22,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: GT.text1,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What is waiting on this tester, and the two answers they can give.
///
/// Everything here is information the tester does not have and cannot get any
/// other way — which is what separates it from the in-app comment list that
/// was ruled out. No other tester's reports, no totals, no screenshots.
class GuidesterRetestList extends StatelessWidget {
  const GuidesterRetestList({
    super.key,
    required this.items,
    required this.busyId,
    required this.error,
    required this.onAnswer,
    required this.onClose,
  });

  final List<PendingRetest> items;

  /// The item whose answer is in flight, so two taps cannot send two verdicts.
  final String? busyId;
  final String? error;
  final void Function(PendingRetest item, {required bool accepted}) onAnswer;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Waiting on you',
                  style: TextStyle(
                    color: GT.text1,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, color: GT.text2, size: 20),
                tooltip: 'Close',
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error!,
                style: const TextStyle(color: GT.red, fontSize: 13),
              ),
            ),
          // Bounded by the backend at 20, and by the screen here: the list
          // scrolls rather than pushing the buttons off the bottom.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    _RetestItem(
                      item: item,
                      busy: busyId == item.id,
                      onAnswer: onAnswer,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetestItem extends StatelessWidget {
  const _RetestItem({
    required this.item,
    required this.busy,
    required this.onAnswer,
  });

  final PendingRetest item;
  final bool busy;
  final void Function(PendingRetest item, {required bool accepted}) onAnswer;

  @override
  Widget build(BuildContext context) {
    // Plain words, never internal vocabulary: a tester reads "fixed in", not
    // `dev_verdict`.
    final parts = <String>[
      if (item.screenName != null && item.screenName!.isNotEmpty)
        item.screenName!,
      if (item.fixedInBuild != null && item.fixedInBuild!.isNotEmpty)
        'fixed in ${item.fixedInBuild}'
      else
        'fixed in a newer build',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.excerpt,
            style: const TextStyle(color: GT.text1, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            parts.join(' · '),
            style: const TextStyle(color: GT.text2, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      busy ? null : () => onAnswer(item, accepted: false),
                  child: const Text('Still broken'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : () => onAnswer(item, accepted: true),
                  child: const Text('Works now'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
