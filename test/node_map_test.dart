import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/node.dart';
import 'package:mindmesh/node_map.dart';
import 'package:mindmesh/radial_layout.dart';

MapNode place(String id, {String? parentId}) => MapNode(
      id: id,
      label: id,
      kind: NodeKind.place,
      x: 0,
      y: 0,
      parentId: parentId,
    );

MapNode app(String id) => MapNode(
      id: id,
      label: id,
      kind: NodeKind.app,
      x: 0,
      y: 0,
      appId: 'com.$id/com.$id.Main',
    );

void main() {
  group('the seed map', () {
    test('is a root with somewhere to go', () {
      final map = NodeMap.seed();
      expect(map.root.label, 'now');
      expect(map.childrenOf(NodeMap.rootNodeId), hasLength(5));
    });

    test('arranges its children around the root rather than on top of it', () {
      // All at 0,0 would be one node with four hidden behind it.
      final children = NodeMap.seed().childrenOf(NodeMap.rootNodeId);
      final places = {for (final child in children) '${child.x},${child.y}'};
      expect(places, hasLength(children.length));
    });
  });

  group('adding', () {
    test('a child is reachable from the root and knows its parent', () {
      final map = NodeMap.seed().addChild('seed-0', app('spotify'));
      expect(map['spotify']!.parentId, 'seed-0');
      expect(map.childrenOf('seed-0').single.id, 'spotify');
      expect(map.reachable(), contains('spotify'));
    });

    test('under a node that does not exist changes nothing', () {
      final map = NodeMap.seed();
      expect(map.addChild('nowhere', app('a')).length, map.length);
    });
  });

  group('placing', () {
    test('a dropped node stays where it was dropped', () {
      // The only decision anyone makes about the map's shape; rearranging over
      // it would undo that.
      var map = NodeMap.seed().addChild('seed-0', app('a'));
      map = map.moveTo('a', 500, -300);
      expect(map['a']!.placed, isTrue);

      map = map.addChild('seed-0', app('b'));
      expect(map['a']!.x, 500);
      expect(map['a']!.y, -300);
    });

    test('unplaced siblings share a ring; a placed one does not', () {
      var map = NodeMap.seed();
      for (var i = 0; i < 6; i++) {
        map = map.addChild('seed-0', app('a$i'));
      }
      map = map.moveTo('a0', 900, 900);

      final parent = map['seed-0']!;
      double distance(MapNode node) {
        final dx = node.x - parent.x;
        final dy = node.y - parent.y;
        return (dx * dx + dy * dy);
      }

      final unplaced = [
        for (var i = 1; i < 6; i++) distance(map['a$i']!),
      ];
      // All on one circle around the parent.
      for (final d in unplaced) {
        expect(d, closeTo(unplaced.first, 1));
      }
      expect(distance(map['a0']!), isNot(closeTo(unplaced.first, 1)));
    });

    test('a crowded ring pushes outward rather than overlapping', () {
      var few = NodeMap.seed();
      var many = NodeMap.seed();
      for (var i = 0; i < 2; i++) {
        few = few.addChild('seed-0', app('f$i'));
      }
      for (var i = 0; i < 10; i++) {
        many = many.addChild('seed-0', app('m$i'));
      }
      double radius(NodeMap map, String id) {
        final parent = map['seed-0']!;
        final node = map[id]!;
        final dx = node.x - parent.x;
        final dy = node.y - parent.y;
        return dx * dx + dy * dy;
      }

      expect(radius(many, 'm0'), greaterThan(radius(few, 'f0')));
    });
  });

  group('removing', () {
    test('takes the whole subtree with it', () {
      var map = NodeMap.seed().addChild('seed-0', place('inner'));
      map = map.addChild('inner', app('deep'));
      map = map.remove('seed-0');

      expect(map['seed-0'], isNull);
      expect(map['inner'], isNull);
      expect(map['deep'], isNull);
      expect(map.childrenOf(NodeMap.rootNodeId).map((n) => n.id),
          isNot(contains('seed-0')));
    });

    test('the root cannot be removed', () {
      // There would be nothing to draw and nowhere to add to.
      final map = NodeMap.seed();
      expect(map.remove(NodeMap.rootNodeId).root.id, NodeMap.rootNodeId);
    });
  });

  group('pathTo', () {
    test('runs from the root down to the node', () {
      var map = NodeMap.seed().addChild('seed-1', place('inner'));
      map = map.addChild('inner', app('deep'));
      expect(map.pathTo('deep').map((n) => n.id),
          [NodeMap.rootNodeId, 'seed-1', 'inner', 'deep']);
    });

    test('a cycle in stored data does not walk forever', () {
      // Storage is not to be trusted with the shape of a graph.
      final looped = NodeMap(
        rootId: NodeMap.rootNodeId,
        nodes: {
          NodeMap.rootNodeId: place(NodeMap.rootNodeId, parentId: 'a'),
          'a': place('a', parentId: NodeMap.rootNodeId),
        },
      );
      expect(looped.pathTo('a').length, lessThanOrEqualTo(3));
    });
  });

  group('laid out for the screen it is on', () {
    test('a seed on a tall phone is a tall map', () {
      final tall = NodeMap.seed(aspect: 384 / 790);
      final box = boundsOf([
        for (final n in tall.childrenOf(NodeMap.rootNodeId)) (x: n.x, y: n.y),
      ]);
      expect(box.height, greaterThan(box.width));
    });

    test('adding to a place shapes that ring too', () {
      // The map converges on the screen it is used on: every ring is laid out
      // again as it grows, so an old square map does not stay square forever.
      var map = NodeMap.seed(aspect: 384 / 790);
      for (var i = 0; i < 4; i++) {
        map = map.addChild(
          NodeMap.rootNodeId,
          place('extra-$i'),
          aspect: 384 / 790,
        );
      }
      final box = boundsOf([
        for (final n in map.childrenOf(NodeMap.rootNodeId)) (x: n.x, y: n.y),
      ]);
      expect(box.height, greaterThan(box.width));
    });
  });

  group('storage', () {
    test('round-trips a map, positions and all', () {
      var map = NodeMap.seed().addChild('seed-0', app('a'));
      map = map.moveTo('a', 120, -80);

      final restored = NodeMap.fromJson(map.toJson());
      expect(restored.length, map.length);
      expect(restored['a']!.x, 120);
      expect(restored['a']!.placed, isTrue);
      expect(restored['a']!.isApp, isTrue);
      expect(restored.childrenOf('seed-0').single.id, 'a');
    });

    test('an orphaned subtree is dropped rather than half-loaded', () {
      // Half a map is harder to reason about than a smaller whole one.
      final json = NodeMap.seed().toJson()
        ..add(place('stray').toJson())
        ..add(app('stray-app').toJson());
      final restored = NodeMap.fromJson(json);
      expect(restored['stray'], isNull);
      expect(restored['stray-app'], isNull);
    });

    test('a child id pointing at nothing is dropped', () {
      final map = NodeMap.seed();
      final json = [
        for (final node in map.toJson())
          if (node['id'] == NodeMap.rootNodeId)
            {...node, 'childIds': [...node['childIds'] as List, 'ghost']}
          else
            node,
      ];
      expect(NodeMap.fromJson(json).root.childIds, isNot(contains('ghost')));
    });

    test('nonsense falls back to a seed rather than an empty canvas', () {
      expect(NodeMap.fromJson(null).root.label, 'now');
      expect(NodeMap.fromJson([1, 2]).root.label, 'now');
      expect(NodeMap.fromJson([app('a').toJson()]).root.label, 'now');
    });

    test('an app node with nothing to launch is not kept', () {
      final broken = {...app('a').toJson()}..remove('appId');
      expect(MapNode.fromJson(broken), isNull);
    });
  });
}
