/// Drawing a loop round things to pick them out.
///
/// A lasso rather than a tap-each-one mode: the apps in a context are placed
/// where they are for a reason, and "these ones, over here" is the shape that
/// reason usually has.
///
/// Pure geometry, in pixels, so the cases that decide whether a selection feels
/// right — a loop that crosses itself, one that was never closed, a stray tap —
/// can be checked exactly.
library;

import 'dart:math' as math;

typedef Point = ({double x, double y});

class LassoStyle {
  const LassoStyle({this.minSpan = 24, this.minPoints = 3});

  /// How far the loop has to reach before it counts as a loop at all. Below
  /// this it is a tap that wobbled, and a tap must not silently select things.
  final double minSpan;

  final int minPoints;

  static const standard = LassoStyle();
}

/// Whether the path is a real loop rather than a wobbled tap.
bool isLoop(List<Point> path, {LassoStyle style = LassoStyle.standard}) {
  if (path.length < style.minPoints) return false;
  var left = path.first.x, right = path.first.x;
  var top = path.first.y, bottom = path.first.y;
  for (final point in path) {
    left = math.min(left, point.x);
    right = math.max(right, point.x);
    top = math.min(top, point.y);
    bottom = math.max(bottom, point.y);
  }
  return (right - left) >= style.minSpan || (bottom - top) >= style.minSpan;
}

/// Whether [point] is inside the loop [path] encloses.
///
/// The path is closed by joining its last point back to its first, because
/// nobody finishes a lasso exactly where they started it.
///
/// Even-odd crossing: a ray going right from the point crosses the outline an
/// odd number of times if it started inside. It handles a path that crosses
/// itself without special-casing, which matters — a lasso drawn in a hurry
/// often does.
bool encloses(List<Point> path, Point point) {
  if (path.length < 3) return false;
  var inside = false;
  for (var i = 0, j = path.length - 1; i < path.length; j = i++) {
    final a = path[i];
    final b = path[j];
    // Half-open on y, so a vertex exactly level with the ray is counted once
    // rather than twice or not at all.
    final straddles = (a.y > point.y) != (b.y > point.y);
    if (!straddles) continue;
    final crossX = a.x + (point.y - a.y) / (b.y - a.y) * (b.x - a.x);
    if (point.x < crossX) inside = !inside;
  }
  return inside;
}

/// The keys of everything the loop caught.
///
/// A thing counts as caught when its centre is inside: judging by any overlap
/// would sweep up whatever the line was drawn *past* on the way round.
List<String> caughtBy(
  List<Point> path,
  List<({String key, double x, double y})> things, {
  LassoStyle style = LassoStyle.standard,
}) {
  if (!isLoop(path, style: style)) return const [];
  return [
    for (final thing in things)
      if (encloses(path, (x: thing.x, y: thing.y))) thing.key,
  ];
}
