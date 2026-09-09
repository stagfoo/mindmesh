import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/camera.dart';

void main() {
  const viewport = (width: 400.0, height: 800.0);

  CameraView framing(Rect region) => frame(
        region: region,
        viewportWidth: viewport.width,
        viewportHeight: viewport.height,
      );

  group('framing a region', () {
    test('puts its centre in the middle of the screen', () {
      final view = framing((left: 100, top: 100, width: 200, height: 200));
      final centre = view.worldToScreen(200, 200);
      expect(centre.x, closeTo(viewport.width / 2, 0.01));
      expect(centre.y, closeTo(viewport.height / 2, 0.01));
    });

    test('a region off in the corner still comes to the middle', () {
      final view = framing((left: -900, top: -900, width: 100, height: 100));
      final centre = view.worldToScreen(-850, -850);
      expect(centre.x, closeTo(viewport.width / 2, 0.01));
      expect(centre.y, closeTo(viewport.height / 2, 0.01));
    });

    test('fits the region on screen with room to spare', () {
      final view = framing((left: 0, top: 0, width: 800, height: 800));
      final topLeft = view.worldToScreen(0, 0);
      final bottomRight = view.worldToScreen(800, 800);
      expect(topLeft.x, greaterThanOrEqualTo(0));
      expect(bottomRight.x, lessThanOrEqualTo(viewport.width));
    });

    test('a bigger region is shown smaller', () {
      final small = framing((left: 0, top: 0, width: 200, height: 200));
      final large = framing((left: 0, top: 0, width: 1000, height: 1000));
      expect(large.scale, lessThan(small.scale));
    });
  });

  group('scale is clamped', () {
    test('a sprawling map does not zoom out past legibility', () {
      // Fitting everything would eventually make every node a dot.
      final view = framing((left: -50000, top: -50000, width: 100000, height: 100000));
      expect(view.scale, CameraStyle.standard.minScale);
    });

    test('a tiny region does not fill the screen with one node', () {
      // Where a node sits is the whole point; filling the screen loses it.
      final view = framing((left: 0, top: 0, width: 4, height: 4));
      expect(view.scale, CameraStyle.standard.maxScale);
    });

    test('a clamped region is still centred, not stuck against an edge', () {
      final view = framing((left: 1000, top: 1000, width: 2, height: 2));
      final centre = view.worldToScreen(1001, 1001);
      expect(centre.x, closeTo(viewport.width / 2, 0.01));
      expect(centre.y, closeTo(viewport.height / 2, 0.01));
    });
  });

  group('centreOn', () {
    test('places a point in the middle at the scale asked for', () {
      final view = centreOn(
        x: 300,
        y: -200,
        viewportWidth: viewport.width,
        viewportHeight: viewport.height,
        scale: 1.5,
      );
      expect(view.scale, 1.5);
      final centre = view.worldToScreen(300, -200);
      expect(centre.x, closeTo(viewport.width / 2, 0.01));
      expect(centre.y, closeTo(viewport.height / 2, 0.01));
    });

    test('clamps a silly scale', () {
      final view = centreOn(
        x: 0,
        y: 0,
        viewportWidth: viewport.width,
        viewportHeight: viewport.height,
        scale: 99,
      );
      expect(view.scale, CameraStyle.standard.maxScale);
    });
  });

  group('screen and world agree', () {
    test('converting one way and back returns the same point', () {
      // A tap arrives in screen coordinates and has to find a node in world
      // ones; if these disagree, taps land on the wrong node.
      final view = framing((left: -300, top: 40, width: 700, height: 400));
      for (final point in [(1.0, 2.0), (-500.0, 250.0), (0.0, 0.0)]) {
        final screen = view.worldToScreen(point.$1, point.$2);
        final back = view.screenToWorld(screen.x, screen.y);
        expect(back.x, closeTo(point.$1, 0.0001));
        expect(back.y, closeTo(point.$2, 0.0001));
      }
    });
  });
}
