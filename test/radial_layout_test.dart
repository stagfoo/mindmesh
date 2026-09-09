import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/radial_layout.dart';

double distance(Place a, Place b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

void main() {
  group('arranging children around a parent', () {
    test('puts them all the same distance out', () {
      const centre = (x: 100.0, y: -50.0);
      final places = arrangeAround(centreX: centre.x, centreY: centre.y, count: 6);
      final radii = [for (final place in places) distance(centre, place)];
      for (final r in radii) {
        expect(r, closeTo(radii.first, 0.01));
      }
    });

    test('a single child sits straight above, not off to one side', () {
      // One child should read as a stalk rather than as something that drifted.
      final place = arrangeAround(centreX: 0, centreY: 0, count: 1).single;
      expect(place.x, closeTo(0, 0.0001));
      expect(place.y, lessThan(0));
    });

    test('none of them land on top of each other', () {
      final places = arrangeAround(centreX: 0, centreY: 0, count: 8);
      for (var i = 0; i < places.length; i++) {
        for (var j = i + 1; j < places.length; j++) {
          expect(distance(places[i], places[j]), greaterThan(1));
        }
      }
    });

    test('no children is no places, not a crash', () {
      expect(arrangeAround(centreX: 0, centreY: 0, count: 0), isEmpty);
    });
  });

  group('the ring grows with the family', () {
    test('neighbours never come closer than a node plus its gap', () {
      // The whole reason the radius is computed rather than fixed: a ring
      // sized for three has eight overlapping.
      const style = RingStyle.standard;
      for (final count in [2, 3, 5, 8, 12, 20]) {
        final places = arrangeAround(centreX: 0, centreY: 0, count: count);
        final gap = distance(places[0], places[1]);
        expect(
          gap,
          greaterThanOrEqualTo(style.nodeSize + style.minGap - 0.5),
          reason: '$count children',
        );
      }
    });

    test('a big family sits further out than a small one', () {
      expect(ringRadius(12), greaterThan(ringRadius(3)));
    });

    test('a small family still gets a sensible ring', () {
      // Packing two children tight against their parent would look like a
      // mistake rather than a choice.
      expect(ringRadius(1), RingStyle.standard.minRadius);
      expect(ringRadius(2), RingStyle.standard.minRadius);
    });
  });

  group('facing a direction', () {
    test('a fan stays on the side it was pointed', () {
      // A branch has to occupy its own direction; a full ring would send its
      // children back over its parent's siblings.
      const facing = 0.0; // straight right
      final places = arrangeAround(
        centreX: 0,
        centreY: 0,
        count: 5,
        facing: facing,
      );
      for (final place in places) {
        expect(place.x, greaterThan(0), reason: 'should be to the right');
      }
    });

    test('one child goes straight out along the facing', () {
      final place = arrangeAround(
        centreX: 0,
        centreY: 0,
        count: 1,
        facing: math.pi / 2,
      ).single;
      expect(place.x, closeTo(0, 0.0001));
      expect(place.y, greaterThan(0));
    });

    test('a fan still keeps its neighbours apart', () {
      // Squeezed into an arc, the same children sit closer than on a ring, so
      // the radius has to account for which it is.
      const style = RingStyle.standard;
      for (final count in [2, 4, 7, 11]) {
        final places =
            arrangeAround(centreX: 0, centreY: 0, count: count, facing: 0);
        final gap = distance(places[0], places[1]);
        expect(gap, greaterThanOrEqualTo(style.nodeSize + style.minGap - 0.5),
            reason: '\$count children');
      }
    });

    test('the fan is narrower than a half turn', () {
      // Wider and the outermost children curl back alongside the parent's own
      // siblings, which is the overlap this avoids.
      expect(RingStyle.standard.spread, lessThan(math.pi));
    });

    test('with no facing it still rings the centre', () {
      final places = arrangeAround(centreX: 0, centreY: 0, count: 4);
      expect(places.any((p) => p.x > 1), isTrue);
      expect(places.any((p) => p.x < -1), isTrue);
    });
  });

  group('shaped to the screen', () {
    test('a tall screen gets a tall ring', () {
      // A circle runs out of width on a phone long before it runs out of
      // height, so the map has to be zoomed down to fit and half the screen
      // holds nothing.
      final tall = boundsOf(
        arrangeAround(centreX: 0, centreY: 0, count: 5, aspect: 384 / 790),
      );
      expect(tall.height, greaterThan(tall.width));

      final circle =
          boundsOf(arrangeAround(centreX: 0, centreY: 0, count: 5));
      expect(tall.width, lessThan(circle.width));
    });

    test('a wide screen gets a wide ring', () {
      final wide = boundsOf(
        arrangeAround(centreX: 0, centreY: 0, count: 5, aspect: 790 / 384),
      );
      expect(wide.width, greaterThan(wide.height));
    });

    test('squashing never pushes neighbours together', () {
      // Evenly spaced angles are not evenly spaced points on an ellipse, so
      // the size has to come from the tightest pair, not from the angle.
      const style = RingStyle.standard;
      for (final aspect in [0.3, 0.45, 0.5, 1.0, 1.8, 3.0]) {
        for (final count in [2, 3, 5, 8, 13]) {
          final places = arrangeAround(
              centreX: 0, centreY: 0, count: count, aspect: aspect);
          for (var i = 0; i < count; i++) {
            final gap = distance(places[i], places[(i + 1) % count]);
            expect(gap, greaterThanOrEqualTo(style.nodeSize + style.minGap - 0.5),
                reason: 'aspect \$aspect, \$count children');
          }
        }
      }
    });

    test('an extreme screen still reads as a ring, not a line', () {
      final places = arrangeAround(
          centreX: 0, centreY: 0, count: 6, aspect: 0.05);
      final box = boundsOf(places);
      expect(box.width / box.height, greaterThan(0.25));
    });

    test('the default is still a circle', () {
      // Not the bounding box — six points sampled off a circle box up
      // 1.73r by 2r. What makes it a circle is that every one is the same
      // distance out.
      final places = arrangeAround(centreX: 0, centreY: 0, count: 6);
      final first = distance((x: 0, y: 0), places.first);
      for (final place in places) {
        expect(distance((x: 0, y: 0), place), closeTo(first, 0.0001));
      }
    });

    test('a fan ignores the screen shape', () {
      // A fan already points somewhere; squashing it would bend that
      // direction into something other than what it means.
      final plain =
          arrangeAround(centreX: 0, centreY: 0, count: 4, facing: 0);
      final squashed = arrangeAround(
          centreX: 0, centreY: 0, count: 4, facing: 0, aspect: 0.5);
      for (var i = 0; i < plain.length; i++) {
        expect(squashed[i].x, closeTo(plain[i].x, 0.0001));
        expect(squashed[i].y, closeTo(plain[i].y, 0.0001));
      }
    });
  });

  group('directionTo', () {
    test('points from one place to another', () {
      expect(directionTo(fromX: 0, fromY: 0, toX: 10, toY: 0), closeTo(0, 0.001));
      expect(directionTo(fromX: 0, fromY: 0, toX: 0, toY: 10),
          closeTo(math.pi / 2, 0.001));
    });
  });

  group('bounds', () {
    test('contain every place, with room for the nodes themselves', () {
      final places = arrangeAround(centreX: 0, centreY: 0, count: 5);
      final box = boundsOf(places);
      for (final place in places) {
        expect(place.x, greaterThan(box.left));
        expect(place.x, lessThan(box.left + box.width));
        expect(place.y, greaterThan(box.top));
        expect(place.y, lessThan(box.top + box.height));
      }
    });

    test('an empty set still has a box, so framing it does not divide by zero',
        () {
      final box = boundsOf(const []);
      expect(box.width, greaterThan(0));
      expect(box.height, greaterThan(0));
    });

    test('a single place gets a box around it rather than a point', () {
      final box = boundsOf([(x: 40.0, y: 40.0)]);
      expect(box.width, greaterThan(0));
      expect(box.left, lessThan(40));
    });
  });
}
