import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/usage.dart';

final start = DateTime.utc(2026, 1, 1, 9);

void main() {
  group('opening a context counts against that edge', () {
    test('the first open shows', () {
      // clicks + 1 in the curve exists so it does; a first open that changed
      // nothing would make the whole mechanism look broken.
      final book = const UsageBook.empty().opened('a|b', start);

      expect(book.clicksAt('a|b', start), 1);
      expect(circleSize(1), greaterThan(circleSize(0)));
    });

    test('the same context in two parents is counted apart', () {
      // A context's weight is only meaningful inside the one you are looking
      // at it from: the gym you open every morning is big in "morning" and
      // small in "health", and both are true.
      var book = const UsageBook.empty();
      for (var i = 0; i < 5; i++) {
        book = book.opened('morning|context:gym', start);
      }
      book = book.opened('health|context:gym', start);

      expect(book.clicksAt('morning|context:gym', start), 5);
      expect(book.clicksAt('health|context:gym', start), 1);
    });

    test('an edge nobody has opened is zero, not missing', () {
      expect(const UsageBook.empty().clicksAt('a|b', start), 0);
      expect(const UsageBook.empty().sizeAt('a|b', start),
          UsageStyle.standard.baseSize);
    });
  });

  group('decay is worked out on the way past, not by a timer', () {
    test('one click falls off every thirty minutes', () {
      var book = const UsageBook.empty();
      for (var i = 0; i < 10; i++) {
        book = book.opened('a|b', start);
      }

      expect(book.clicksAt('a|b', start), 10);
      expect(book.clicksAt('a|b', start.add(const Duration(minutes: 29))), 10);
      expect(book.clicksAt('a|b', start.add(const Duration(minutes: 30))), 9);
      expect(book.clicksAt('a|b', start.add(const Duration(hours: 2))), 6);
    });

    test('it never goes below zero, however long you leave it', () {
      final book = const UsageBook.empty().opened('a|b', start);
      final later = start.add(const Duration(days: 400));

      expect(book.clicksAt('a|b', later), 0);
      expect(book.sizeAt('a|b', later), UsageStyle.standard.baseSize);
    });

    test('reading the count does not change it', () {
      // The whole reason decay can be lazy: asking is free and repeatable, so
      // there is never a moment when disk and screen disagree.
      var book = const UsageBook.empty();
      for (var i = 0; i < 4; i++) {
        book = book.opened('a|b', start);
      }
      final later = start.add(const Duration(hours: 1));

      expect(book.clicksAt('a|b', later), 2);
      expect(book.clicksAt('a|b', later), 2);
      expect(book.entries['a|b']!.clicks, 4, reason: 'stored count untouched');
    });

    test('opening catches decay up first, then adds one', () {
      var book = const UsageBook.empty();
      for (var i = 0; i < 6; i++) {
        book = book.opened('a|b', start);
      }
      final later = start.add(const Duration(hours: 1)); // two steps of decay

      book = book.opened('a|b', later);

      expect(book.clicksAt('a|b', later), 5, reason: '6 - 2 + 1');
      expect(book.entries['a|b']!.lastUpdated, later);
    });

    test('a clock that goes backwards does not hand out free clicks', () {
      // Time zones, NTP corrections, a user changing the date. Negative
      // elapsed time must decay nothing rather than a negative amount.
      var book = const UsageBook.empty();
      for (var i = 0; i < 3; i++) {
        book = book.opened('a|b', start);
      }
      final earlier = start.subtract(const Duration(days: 1));

      expect(book.clicksAt('a|b', earlier), 3);
    });
  });

  group('size grows with use, but not without limit', () {
    test('each further open is worth less than the one before it', () {
      // Logarithmic per click, not per decade: 1 to 10 spans a wider ratio
      // than 10 to 11, so compare single clicks rather than round numbers.
      final early = circleSize(2) - circleSize(1);
      final later = circleSize(11) - circleSize(10);
      final much = circleSize(51) - circleSize(50);

      expect(early, greaterThan(later));
      expect(later, greaterThan(much));
      expect(much, greaterThan(0), reason: 'still growing, just slowly');
    });

    test('a heavily used context is bigger but not absurdly so', () {
      expect(circleSize(50) / circleSize(1), lessThan(3));
      expect(circleSize(50), greaterThan(circleSize(5)));
    });

    test('it matches the curve it claims to be', () {
      const style = UsageStyle.standard;
      for (final clicks in [0, 1, 5, 23]) {
        expect(
          circleSize(clicks),
          closeTo(style.baseSize + math.log(clicks + 1) * style.scaleFactor,
              0.0001),
        );
      }
    });

    test('an unused context is still big enough to press', () {
      expect(circleSize(0), UsageStyle.standard.baseSize);
      expect(circleSize(0), greaterThan(44), reason: 'a real touch target');
    });

    test('one runaway context cannot swallow the view', () {
      expect(circleSize(100000), UsageStyle.standard.maxSize);
    });

    test('a negative count is treated as none', () {
      expect(circleSize(-5), circleSize(0));
    });
  });

  group('storage', () {
    test('round-trips counts and their timestamps', () {
      var book = const UsageBook.empty();
      for (var i = 0; i < 3; i++) {
        book = book.opened('a|context:b', start);
      }

      final restored = UsageBook.fromJson(book.toJson());

      expect(restored.entries['a|context:b']!.clicks, 3);
      expect(restored.clicksAt('a|context:b', start), 3);
      expect(
        restored.clicksAt('a|context:b', start.add(const Duration(hours: 1))),
        1,
      );
    });

    test('counters for edges that no longer exist are forgotten', () {
      var book = const UsageBook.empty()
          .opened('a|context:b', start)
          .opened('gone|context:x', start);

      book = book.keepingOnly({'a|context:b'});

      expect(book.entries.keys, ['a|context:b']);
    });

    test('nonsense in storage reads as no usage rather than throwing', () {
      expect(UsageBook.fromJson('not a map').entries, isEmpty);
      expect(UsageBook.fromJson({'a|b': 'junk'}).entries, isEmpty);
    });
  });
}
