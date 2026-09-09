/// Where a node's children go when nobody has said.
///
/// Children ring their parent. A ring rather than a tree row because the map is
/// panned and zoomed rather than read top to bottom: from any node, its
/// children are simply "around it", which is the same shape whichever way you
/// arrived.
///
/// Pure geometry — no widgets, no canvas — so the arrangement can be checked
/// exactly rather than eyeballed.
library;

import 'dart:math' as math;

/// A point in world space.
typedef Place = ({double x, double y});

class RingStyle {
  const RingStyle({
    this.nodeSize = 96,
    this.minGap = 28,
    this.minRadius = 190,
    this.startAngle = -math.pi / 2,
  });

  /// How wide a node is, which is what decides whether a ring is crowded.
  final double nodeSize;

  /// Space to leave between neighbouring nodes on the ring.
  final double minGap;

  final double minRadius;

  /// Where the first child sits. Straight up, so a map with one child reads
  /// as a stalk rather than as something that drifted sideways.
  final double startAngle;

  static const standard = RingStyle();
}

/// The radius a ring of [count] nodes needs so they do not touch.
///
/// Grows with the number of children rather than being fixed: eight nodes on a
/// ring sized for three overlap, and pushing them outward is less destructive
/// than shrinking them.
double ringRadius(int count, {RingStyle style = RingStyle.standard}) {
  if (count <= 1) return style.minRadius;
  // Chord between neighbours must clear a node plus a gap:
  // 2 * r * sin(pi / count) >= nodeSize + minGap
  final needed =
      (style.nodeSize + style.minGap) / (2 * math.sin(math.pi / count));
  return math.max(style.minRadius, needed);
}

/// [count] places evenly around a centre.
List<Place> arrangeAround({
  required double centreX,
  required double centreY,
  required int count,
  RingStyle style = RingStyle.standard,
}) {
  if (count <= 0) return const [];
  final radius = ringRadius(count, style: style);
  return [
    for (var i = 0; i < count; i++)
      (
        x: centreX + radius * math.cos(style.startAngle + 2 * math.pi * i / count),
        y: centreY + radius * math.sin(style.startAngle + 2 * math.pi * i / count),
      ),
  ];
}

/// The box that contains a set of places, padded by a node's own size so
/// nothing sits half off the edge.
({double left, double top, double width, double height}) boundsOf(
  Iterable<Place> places, {
  RingStyle style = RingStyle.standard,
}) {
  if (places.isEmpty) {
    return (
      left: -style.nodeSize,
      top: -style.nodeSize,
      width: style.nodeSize * 2,
      height: style.nodeSize * 2,
    );
  }
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final place in places) {
    minX = math.min(minX, place.x);
    minY = math.min(minY, place.y);
    maxX = math.max(maxX, place.x);
    maxY = math.max(maxY, place.y);
  }
  final pad = style.nodeSize;
  return (
    left: minX - pad,
    top: minY - pad,
    width: (maxX - minX) + pad * 2,
    height: (maxY - minY) + pad * 2,
  );
}
