import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Grey bars in the shape of what is loading, so the page does not jump when
/// it arrives and nobody stares at a lone spinner wondering if it is stuck.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({super.key, required this.width, this.height = 12});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: T.surface2,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// The comment list, loading: rows of title and meta bars.
class BoardSkeleton extends StatelessWidget {
  const BoardSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading comments',
      liveRegion: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 516.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rows; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: T.line)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Varied widths read as text, not as a grid.
                        SkeletonBar(width: w * (i.isEven ? 0.72 : 0.55)),
                        const SizedBox(height: 10),
                        SkeletonBar(width: w * 0.4, height: 9),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
