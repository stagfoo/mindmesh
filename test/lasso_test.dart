import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/lasso.dart';

Point at(double x, double y) => (x: x, y: y);

/// A square loop, drawn clockwise from the top left.
List<Point> square(double left, double top, double side) => [
      at(left, top),
      at(left + side, top),
      at(left + side, top + side),
      at(left, top + side),
    ];

void main() {
  group('what counts as a loop', () {
    test('a square catches what is inside it', () {
      expect(encloses(square(0, 0, 100), at(50, 50)), isTrue);
      expect(encloses(square(0, 0, 100), at(150, 50)), isFalse);
    });

    test('a tap that wobbled is not a selection', () {
      // Otherwise every slightly-imprecise tap on the ground would quietly
      // select whatever happened to be under it.
      final wobble = [at(100, 100), at(103, 101), at(102, 104), at(100, 102)];
      expect(isLoop(wobble), isFalse);
      expect(caughtBy(wobble, [(key: 'a', x: 101, y: 102)]), isEmpty);
    });

    test('a deliberate loop is', () {
      expect(isLoop(square(0, 0, 120)), isTrue);
    });

    test('a long thin loop still counts', () {
      // Sweeping along a row of apps is a normal way to pick them.
      final thin = [at(0, 100), at(300, 100), at(300, 118), at(0, 118)];
      expect(isLoop(thin), isTrue);
    });

    test('two points cannot enclose anything', () {
      expect(encloses([at(0, 0), at(100, 100)], at(50, 50)), isFalse);
    });
  });

  group('an unclosed path closes itself', () {
    test('because nobody finishes where they started', () {
      // Three corners of a square, never joined up: the fourth side is implied.
      final open = [at(0, 0), at(100, 0), at(100, 100), at(2, 98)];
      expect(encloses(open, at(50, 50)), isTrue);
    });
  });

  group('a loop that crosses itself', () {
    test('is handled without special-casing, because it happens', () {
      // A figure of eight. Even-odd says the two lobes are inside and the
      // crossing point region is not, which is at least consistent — the point
      // is that it answers rather than falling over.
      final eight = [
        at(0, 0), at(100, 0), at(0, 100), at(100, 100),
      ];
      expect(() => encloses(eight, at(50, 50)), returnsNormally);
    });
  });

  group('catching things', () {
    test('by centre, not by touching the line', () {
      // Judging by overlap would sweep up whatever the line was drawn past on
      // the way round, which is never what was meant.
      final loop = square(0, 0, 100);
      final caught = caughtBy(loop, [
        (key: 'inside', x: 50, y: 50),
        (key: 'just outside', x: 104, y: 50),
        (key: 'far', x: 300, y: 300),
      ]);
      expect(caught, ['inside']);
    });

    test('catches several at once', () {
      final caught = caughtBy(square(0, 0, 200), [
        (key: 'a', x: 30, y: 30),
        (key: 'b', x: 90, y: 120),
        (key: 'c', x: 400, y: 400),
      ]);
      expect(caught, ['a', 'b']);
    });

    test('an empty loop catches nothing rather than everything', () {
      expect(caughtBy(square(0, 0, 200), const []), isEmpty);
      expect(caughtBy(const [], [(key: 'a', x: 1, y: 1)]), isEmpty);
    });

    test('a ray straight through two vertices still answers sensibly', () {
      // The half-open y test earns its keep here: counted the other way, a ray
      // level with a pair of vertices crosses twice or not at all, and points
      // inside the shape come back outside. Which side of the boundary line
      // itself lands inside is arbitrary; being consistent across it is not.
      final diamond = [at(50, 0), at(100, 50), at(50, 100), at(0, 50)];

      expect(encloses(diamond, at(50, 50)), isTrue, reason: 'level, middle');
      expect(encloses(diamond, at(20, 50)), isTrue, reason: 'level, inside');
      expect(encloses(diamond, at(120, 50)), isFalse, reason: 'level, outside');
      expect(encloses(diamond, at(-20, 50)), isFalse, reason: 'level, before');
    });

    test('sweeping across the shape flips exactly twice', () {
      // One entry and one exit. More than that is double-counting an edge.
      final loop = square(0, 0, 100);
      var flips = 0;
      var was = encloses(loop, at(-10, 50));
      for (var x = -10.0; x <= 130; x += 0.5) {
        final now = encloses(loop, at(x, 50));
        if (now != was) flips++;
        was = now;
      }
      expect(flips, 2);
    });
  });
}
