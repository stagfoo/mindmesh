import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/camera.dart';
import 'package:mindmesh/node.dart';
import 'package:mindmesh/node_map.dart';
import 'package:mindmesh/world.dart';

/// Where the camera actually puts a node, all the way through: node
/// coordinates, to canvas coordinates, to the transform, to a screen pixel.
///
/// This is the join that was broken — the camera framed nodes at their own
/// coordinates while the canvas drew them half a world away, so a map full of
/// nodes rendered as an empty screen. Each half was right on its own, which is
/// exactly why only an end-to-end check catches it.
({double x, double y}) onScreen(
  MapNode node,
  CameraView view,
) {
  final canvas = toCanvas((x: node.x, y: node.y));
  return (x: canvas.x * view.scale + view.offsetX, y: canvas.y * view.scale + view.offsetY);
}

/// What the screen does when you travel to a place. Mirrors `_focusOn`.
CameraView focusOn(NodeMap map, String id, double width, double height) {
  final node = map[id]!;
  final here = toCanvas((x: node.x, y: node.y));
  return centreOn(
    x: here.x,
    y: here.y,
    viewportWidth: width,
    viewportHeight: height,
    scale: CameraStyle.standard.travelScale,
  );
}

void main() {
  const screens = [
    ('mind one', 360.0, 400.0),
    ('cmf 2 pro', 384.0, 790.0),
    ('tablet', 800.0, 1200.0),
  ];

  group('the map lands on the screen', () {
    for (final (name, width, height) in screens) {
      test('a fresh map is visible on a $name', () {
        final map = NodeMap.seed(aspect: width / height);
        final view = focusOn(map, NodeMap.rootNodeId, width, height);

        for (final node in map.nodes.values) {
          final at = onScreen(node, view);
          expect(at.x, inInclusiveRange(0, width), reason: '${node.label} x');
          expect(at.y, inInclusiveRange(0, height), reason: '${node.label} y');
        }
      });

      test('the place you travelled to is dead centre on a $name', () {
        final map = NodeMap.seed(aspect: width / height);
        for (final id in [NodeMap.rootNodeId, 'seed-0', 'seed-3']) {
          final view = focusOn(map, id, width, height);
          final at = onScreen(map[id]!, view);
          expect(at.x, closeTo(width / 2, 0.001), reason: id);
          expect(at.y, closeTo(height / 2, 0.001), reason: id);
        }
      });

      test('travelling does not zoom out as the map grows on a $name', () {
        // The complaint this fixes: framing a place and everything under it
        // pulls the camera further back the more you put in the map, until it
        // is showing the whole tree — and once you can see everything, going
        // somewhere is not going anywhere.
        final aspect = width / height;
        var map = NodeMap.seed(aspect: aspect);
        final first = focusOn(map, NodeMap.rootNodeId, width, height).scale;

        for (var i = 0; i < 10; i++) {
          map = map.addChild(
            NodeMap.rootNodeId,
            MapNode(id: 'more-$i', label: 'more $i', x: 0, y: 0),
            aspect: aspect,
          );
          map = map.addChild(
            'seed-2',
            MapNode(id: 'deeper-$i', label: 'deeper $i', x: 0, y: 0),
            aspect: aspect,
          );
          map = map.addApps('seed-2', ['app-$i/M']);
        }

        expect(focusOn(map, NodeMap.rootNodeId, width, height).scale, first);
        expect(focusOn(map, 'seed-2', width, height).scale, first);
      });

      test('walking into a situation brings it to the middle on a $name', () {
        var map = NodeMap.seed(aspect: width / height);
        map = map.addChild(
          'seed-2',
          const MapNode(id: 'weights', label: 'weights', x: 0, y: 0),
          aspect: width / height,
        );

        final view = focusOn(map, 'seed-2', width, height);
        final gym = onScreen(map['seed-2']!, view);
        final child = onScreen(map['weights']!, view);

        // The place you went to is centred, and what is under it is on screen
        // with you — near enough to reach, without the camera pulling back.
        expect(gym.x, closeTo(width / 2, 0.001));
        expect(gym.y, closeTo(height / 2, 0.001));
        expect(child.x, inInclusiveRange(0, width));
        expect(child.y, inInclusiveRange(0, height));
      });

      test('a leaf still centres on a $name', () {
        final map = NodeMap.seed(aspect: width / height);
        final view = focusOn(map, 'seed-0', width, height);
        final at = onScreen(map['seed-0']!, view);

        expect(at.x, closeTo(width / 2, 1));
        expect(at.y, closeTo(height / 2, 1));
      });
    }
  });

  group('the world is big enough to hold the map', () {
    test('a long chain of situations stays inside the canvas', () {
      // Branches fan outward rather than folding back, so a deep chain keeps
      // travelling. A node outside the canvas box is undrawable.
      var map = NodeMap.seed(aspect: 384 / 790);
      var parent = 'seed-2';
      for (var depth = 0; depth < 12; depth++) {
        final id = 'deep-$depth';
        map = map.addChild(
          parent,
          MapNode(id: id, label: id, x: 0, y: 0),
          aspect: 384 / 790,
        );
        parent = id;
      }

      for (final node in map.nodes.values) {
        final canvas = toCanvas((x: node.x, y: node.y));
        expect(canvas.x, inInclusiveRange(0, worldExtent), reason: node.id);
        expect(canvas.y, inInclusiveRange(0, worldExtent), reason: node.id);
      }
    });
  });
}
