/// Keeping apps out of each other's way.
///
/// An app icon is small and its label is smaller, so two of them overlapping is
/// not a look, it is a thing you cannot read or press. Contexts are different —
/// they are blurred clouds that are *meant* to bleed into each other — so this
/// only ever runs over a set someone hands it.
///
/// Positions are in pixels, not fractions of the view. A circle in fraction
/// space is an ellipse on a tall screen, and "these two do not touch" would
/// stop meaning anything.
///
/// Pure maths, so the awkward cases — a disc pinned under your finger, two
/// discs exactly on top of each other, more discs than the box can hold — are
/// testable without dragging anything.
library;

import 'dart:math' as math;

typedef Disc = ({String key, double x, double y, double r});

typedef Box = ({double width, double height});

class PackStyle {
  const PackStyle({this.gap = 6, this.rounds = 32, this.slack = 0.5});

  /// Clear space to leave between two discs, on top of their radii.
  final double gap;

  /// How many separation passes to make. Each pass fixes every overlapping
  /// pair once; a push can create a new overlap, so it takes a few.
  final int rounds;

  /// Overlap small enough to leave alone, in pixels. Without it a pair can
  /// jitter across rounds trading a fraction of a pixel back and forth.
  final double slack;

  static const standard = PackStyle();
}

/// Moves [discs] apart until none overlap, holding [pinned] exactly where it is.
///
/// The pinned disc is the one under your finger: it goes where you put it, and
/// everything it runs into gets out of the way. Without that, dragging would
/// feel like pushing against the thing you are dragging.
List<Disc> separate(
  List<Disc> discs, {
  Set<String> pinned = const {},
  Box? within,
  PackStyle style = PackStyle.standard,
}) {
  if (discs.length < 2) return _bounded(discs, within, pinned);

  final out = [...discs];
  for (var round = 0; round < style.rounds; round++) {
    var moved = false;

    for (var i = 0; i < out.length; i++) {
      for (var j = i + 1; j < out.length; j++) {
        final a = out[i];
        final b = out[j];
        final wanted = a.r + b.r + style.gap;

        var dx = b.x - a.x;
        var dy = b.y - a.y;
        var distance = math.sqrt(dx * dx + dy * dy);

        if (distance >= wanted - style.slack) continue;

        if (distance < 0.0001) {
          // Exactly on top of each other: any direction will do, but it has to
          // be the *same* direction every time or a re-render jumps them
          // somewhere new. Derived from the keys, so it is stable.
          final angle = (a.key.hashCode ^ b.key.hashCode) % 360 * math.pi / 180;
          dx = math.cos(angle);
          dy = math.sin(angle);
          distance = 1;
        }

        final push = wanted - distance;
        final ux = dx / distance;
        final uy = dy / distance;

        final aPinned = pinned.contains(a.key);
        final bPinned = pinned.contains(b.key);
        if (aPinned && bPinned) continue;

        // A pinned neighbour takes none of the push, so the other one takes
        // all of it.
        final aShare = aPinned ? 0.0 : (bPinned ? 1.0 : 0.5);
        final bShare = bPinned ? 0.0 : (aPinned ? 1.0 : 0.5);

        out[i] = (
          key: a.key,
          x: a.x - ux * push * aShare,
          y: a.y - uy * push * aShare,
          r: a.r,
        );
        out[j] = (
          key: b.key,
          x: b.x + ux * push * bShare,
          y: b.y + uy * push * bShare,
          r: b.r,
        );
        moved = true;
      }
    }

    if (within != null) {
      for (var i = 0; i < out.length; i++) {
        if (pinned.contains(out[i].key)) continue;
        out[i] = _clamp(out[i], within);
      }
    }

    if (!moved) break;
  }

  return out;
}

/// Whether any two of [discs] are closer than they should be.
bool anyOverlap(List<Disc> discs, {PackStyle style = PackStyle.standard}) {
  for (var i = 0; i < discs.length; i++) {
    for (var j = i + 1; j < discs.length; j++) {
      final dx = discs[j].x - discs[i].x;
      final dy = discs[j].y - discs[i].y;
      final wanted = discs[i].r + discs[j].r + style.gap;
      if (math.sqrt(dx * dx + dy * dy) < wanted - style.slack - 0.001) {
        return true;
      }
    }
  }
  return false;
}

List<Disc> _bounded(List<Disc> discs, Box? within, Set<String> pinned) {
  if (within == null) return discs;
  return [
    for (final disc in discs)
      if (pinned.contains(disc.key)) disc else _clamp(disc, within)
  ];
}

/// Keeps a disc whole inside the box.
///
/// When the box is narrower than the disc, centre it rather than pinning it to
/// an edge: half off one side is worse than a bit off both.
Disc _clamp(Disc disc, Box within) {
  final x = within.width < disc.r * 2
      ? within.width / 2
      : disc.x.clamp(disc.r, within.width - disc.r);
  final y = within.height < disc.r * 2
      ? within.height / 2
      : disc.y.clamp(disc.r, within.height - disc.r);
  return (key: disc.key, x: x, y: y, r: disc.r);
}
