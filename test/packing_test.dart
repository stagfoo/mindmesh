import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/packing.dart';

Disc disc(String key, double x, double y, [double r = 33]) =>
    (key: key, x: x, y: y, r: r);

double gap(Disc a, Disc b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  return math.sqrt(dx * dx + dy * dy) - a.r - b.r;
}

Disc find(List<Disc> discs, String key) =>
    discs.firstWhere((d) => d.key == key);

void main() {
  group('two apps cannot sit on top of each other', () {
    test('overlapping discs end up apart', () {
      final out = separate([disc('a', 100, 100), disc('b', 110, 100)]);
      expect(anyOverlap(out), isFalse);
      expect(gap(find(out, 'a'), find(out, 'b')),
          greaterThanOrEqualTo(PackStyle.standard.gap - 0.5));
    });

    test('discs that already clear each other are left alone', () {
      // Nothing should twitch when a drag passes nowhere near it.
      final before = [disc('a', 40, 40), disc('b', 300, 300)];
      final after = separate(before);
      expect(after, before);
    });

    test('they push apart along the line between them', () {
      final out = separate([disc('a', 100, 100), disc('b', 120, 100)]);
      expect(find(out, 'a').y, closeTo(100, 0.001));
      expect(find(out, 'b').y, closeTo(100, 0.001));
      expect(find(out, 'a').x, lessThan(100));
      expect(find(out, 'b').x, greaterThan(120));
    });

    test('two exactly on top of each other still come apart', () {
      final out = separate([disc('a', 100, 100), disc('b', 100, 100)]);
      expect(anyOverlap(out), isFalse);
    });

    test('and they come apart the same way every time', () {
      // A direction picked at random would move them somewhere new on every
      // rebuild, which reads as the launcher twitching on its own.
      final first = separate([disc('a', 100, 100), disc('b', 100, 100)]);
      final again = separate([disc('a', 100, 100), disc('b', 100, 100)]);
      expect(find(again, 'a').x, find(first, 'a').x);
      expect(find(again, 'a').y, find(first, 'a').y);
    });
  });

  group('the one under your finger does not move', () {
    test('a pinned disc stays exactly where it was put', () {
      final out = separate(
        [disc('finger', 100, 100), disc('other', 108, 100)],
        pinned: {'finger'},
      );
      expect(find(out, 'finger').x, 100);
      expect(find(out, 'finger').y, 100);
    });

    test('the other one takes the whole push', () {
      // Otherwise dragging feels like shoving against the thing you are
      // dragging, which is the bug this rule exists to avoid.
      final out = separate(
        [disc('finger', 100, 100), disc('other', 108, 100)],
        pinned: {'finger'},
      );
      expect(anyOverlap(out), isFalse);
      expect(find(out, 'other').x, greaterThan(108));
    });

    test('a push carries on down a row', () {
      // Shoving one app into a line of them has to move the whole line, not
      // just jam the first two together.
      final out = separate(
        [
          disc('finger', 100, 100),
          disc('b', 120, 100),
          disc('c', 150, 100),
          disc('d', 180, 100),
        ],
        pinned: {'finger'},
      );
      expect(anyOverlap(out), isFalse);
      expect(find(out, 'd').x, greaterThan(180));
    });

    test('two pinned discs are left to overlap', () {
      // Dragging a whole selection: the ones moving together keep their own
      // arrangement rather than exploding apart mid-drag.
      final out = separate(
        [disc('a', 100, 100), disc('b', 104, 100)],
        pinned: {'a', 'b'},
      );
      expect(find(out, 'a').x, 100);
      expect(find(out, 'b').x, 104);
    });
  });

  group('staying on the screen', () {
    test('a disc pushed at the edge stays whole inside the box', () {
      final out = separate(
        [disc('finger', 30, 100), disc('other', 40, 100)],
        pinned: {'finger'},
        within: (width: 400, height: 800),
      );
      for (final d in out) {
        if (d.key == 'finger') continue;
        expect(d.x, greaterThanOrEqualTo(d.r - 0.001));
        expect(d.x, lessThanOrEqualTo(400 - d.r + 0.001));
      }
    });

    test('a box narrower than the disc centres it rather than half-hiding it', () {
      final out = separate(
        [disc('a', 5, 100), disc('b', 300, 400)],
        within: (width: 40, height: 800),
      );
      expect(find(out, 'a').x, 20);
    });

    test('more apps than the box can hold does not hang', () {
      // It cannot be solved; it must still finish and still be sane.
      final crowded = [
        for (var i = 0; i < 40; i++) disc('d$i', 100 + i % 3, 100 + i % 5),
      ];
      final out = separate(crowded, within: (width: 380, height: 700));

      expect(out, hasLength(40));
      for (final d in out) {
        expect(d.x.isFinite, isTrue);
        expect(d.y.isFinite, isTrue);
      }
    });

    test('a normal screenful does come apart completely', () {
      final some = [
        for (var i = 0; i < 8; i++) disc('d$i', 150 + i * 4, 300 + i * 3),
      ];
      final out = separate(some, within: (width: 380, height: 700));
      expect(anyOverlap(out), isFalse);
    });
  });

  group('trivial cases', () {
    test('one disc is already arranged', () {
      expect(separate([disc('a', 10, 10)]), hasLength(1));
    });

    test('no discs is not an error', () {
      expect(separate(const []), isEmpty);
    });

    test('one disc is still kept inside the box', () {
      final out = separate([disc('a', -50, -50)], within: (width: 400, height: 800));
      expect(find(out, 'a').x, 33);
      expect(find(out, 'a').y, 33);
    });
  });
}
