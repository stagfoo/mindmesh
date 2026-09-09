import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/camera.dart';
import 'package:mindmesh/node.dart';
import 'package:mindmesh/node_map.dart';
import 'package:mindmesh/radial_layout.dart';
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

CameraView focusOn(NodeMap map, String id, double width, double height) {
  final node = map[id]!;
  final children = map.childrenOf(id);
  final here = toCanvas((x: node.x, y: node.y));
  if (children.isEmpty) {
    return centreOn(
      x: here.x,
      y: here.y,
      viewportWidth: width,
      viewportHeight: height,
      scale: 1.1,
    );
  }
  return frame(
    region: boundsOf([
      here,
      for (final child in children) toCanvas((x: child.x, y: child.y)),
    ]),
    viewportWidth: width,
    viewportHeight: height,
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

      test('the map is centred, not shoved into a corner, on a $name', () {
        // The *group* is centred, not the root: five nodes on a ring are not
        // symmetric about their centre, so the root sits slightly off middle
        // by design. What matters is that the framed content is centred.
        final map = NodeMap.seed(aspect: width / height);
        final view = focusOn(map, NodeMap.rootNodeId, width, height);

        final xs = [for (final n in map.nodes.values) onScreen(n, view).x];
        final ys = [for (final n in map.nodes.values) onScreen(n, view).y];
        final midX = (xs.reduce((a, b) => a < b ? a : b) +
                xs.reduce((a, b) => a > b ? a : b)) /
            2;
        final midY = (ys.reduce((a, b) => a < b ? a : b) +
                ys.reduce((a, b) => a > b ? a : b)) /
            2;

        expect(midX, closeTo(width / 2, 1));
        expect(midY, closeTo(height / 2, 1));
      });

      test('walking into a situation brings it to the middle on a $name', () {
        var map = NodeMap.seed(aspect: width / height);
        map = map.addChild(
          'seed-2',
          const MapNode(
            id: 'weights',
            label: 'weights',
            kind: NodeKind.app,
            x: 0,
            y: 0,
            appId: 'com.example/M',
          ),
          aspect: width / height,
        );

        final view = focusOn(map, 'seed-2', width, height);
        final gym = onScreen(map['seed-2']!, view);
        final child = onScreen(map['weights']!, view);

        // Both on screen, and the pair centred between them.
        for (final at in [gym, child]) {
          expect(at.x, inInclusiveRange(0, width));
          expect(at.y, inInclusiveRange(0, height));
        }
        expect((gym.x + child.x) / 2, closeTo(width / 2, 1));
        expect((gym.y + child.y) / 2, closeTo(height / 2, 1));
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
          MapNode(id: id, label: id, kind: NodeKind.place, x: 0, y: 0),
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
