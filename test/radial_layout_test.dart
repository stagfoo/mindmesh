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
