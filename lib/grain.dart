import 'package:flutter/material.dart';

import 'theme.dart';

/// Paper grain over the whole screen.
///
/// A flat fill of one colour is the thing that makes a light UI look like a
/// browser page. The circles are already soft and blurred, so the ground under
/// them needs some tooth or the whole screen reads as unrendered.
///
/// One small tileable bitmap repeated rather than anything procedural: noise
/// generated per frame costs real time on a launcher's first paint, and the
/// texture never changes, so there is nothing to compute twice.
class Grain extends StatelessWidget {
  const Grain({super.key, this.opacity = 0.055});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Image.asset(
          'assets/grain.png',
          repeat: ImageRepeat.repeat,
          // Nearest, not the default filtering: a grain that gets smoothed
          // when the tile lands on a fractional device pixel turns into a soft
          // blur, which is the opposite of the point.
          filterQuality: FilterQuality.none,
          isAntiAlias: false,
          color: MeshColors.text,
          colorBlendMode: BlendMode.srcIn,
        ),
      ),
    );
  }
}
