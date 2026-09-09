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
    this.spread = math.pi * 0.62,
  });

  /// How wide a node is, which is what decides whether a ring is crowded.
  final double nodeSize;

  /// Space to leave between neighbouring nodes on the ring.
  final double minGap;

  final double minRadius;

  /// Where the first child sits when there is no direction to face. Straight
  /// up, so a map with one child reads as a stalk rather than as something
  /// that drifted sideways.
  final double startAngle;

  /// How wide a fan of children is when there *is* a direction to face.
  ///
  /// Well under a half turn: wider and the outermost children curl back
  /// alongside their parent's siblings, which is the overlap this exists to
  /// avoid.
  final double spread;

  static const standard = RingStyle();
}

/// The radius a ring of [count] nodes needs so they do not touch.
///
/// Grows with the number of children rather than being fixed: eight nodes on a
/// ring sized for three overlap, and pushing them outward is less destructive
/// than shrinking them.
/// The radius [count] nodes need so neighbours do not touch.
///
/// [spread] is the arc they are sharing; a full turn when they ring the centre.
/// A fan crowds sooner than a ring does — the same children squeezed into two
/// thirds of a turn sit closer together — so the radius has to know which it is.
double ringRadius(
  int count, {
  RingStyle style = RingStyle.standard,
  double? spread,
}) {
  if (count <= 1) return style.minRadius;
  final arc = spread ?? 2 * math.pi;
  // Angle between neighbours, and the chord across it must clear a node plus a
  // gap: 2 * r * sin(step / 2) >= nodeSize + minGap
  final step = spread == null ? arc / count : arc / (count - 1);
  final needed =
      (style.nodeSize + style.minGap) / (2 * math.sin(step / 2).abs());
  return math.max(style.minRadius, needed);
}

/// [count] places around a centre.
///
/// With no [facing] the places ring the centre completely, which is right for
/// the root: it has no direction to come from.
///
/// With one, they fan into an arc pointing that way instead. A situation's
/// children have to occupy their own territory — a full ring around a node that
/// is itself on a ring sends its children back over its siblings, and the map
/// stops being somewhere you can move *to*. Facing outward gives each branch a
/// direction of its own, which is what makes a position worth remembering.
List<Place> arrangeAround({
  required double centreX,
  required double centreY,
  required int count,
  double? facing,
  RingStyle style = RingStyle.standard,
}) {
  if (count <= 0) return const [];
  final radius = ringRadius(count, style: style, spread: facing == null ? null : style.spread);

  if (facing == null) {
    return [
      for (var i = 0; i < count; i++)
        (
          x: centreX +
              radius * math.cos(style.startAngle + 2 * math.pi * i / count),
          y: centreY +
              radius * math.sin(style.startAngle + 2 * math.pi * i / count),
        ),
    ];
  }

  // One child goes straight out along the facing; more share the arc evenly,
  // with the ends inset so a fan of two does not sit on the arc's edges.
  final start = facing - style.spread / 2;
  final step = count == 1 ? 0.0 : style.spread / (count - 1);
  return [
    for (var i = 0; i < count; i++)
      (
        x: centreX + radius * math.cos(count == 1 ? facing : start + step * i),
        y: centreY + radius * math.sin(count == 1 ? facing : start + step * i),
      ),
  ];
}

/// The direction from [fromX], [fromY] towards [toX], [toY].
double directionTo({
  required double fromX,
  required double fromY,
  required double toX,
  required double toY,
}) =>
    math.atan2(toY - fromY, toX - fromX);

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
