import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/node.dart';
import 'package:mindmesh/node_map.dart';

MapNode appNode(String id, String appId, {String label = 'Music'}) => MapNode(
      id: id,
      label: label,
      kind: NodeKind.app,
      x: 0,
      y: 0,
      appId: appId,
    );

void main() {
  group('the seed is situations, not categories', () {
    test('it asks what you are doing', () {
      // A seed teaches the model: a categorical one would quietly turn this
      // back into a folder tree.
      final map = NodeMap.seed();
      final labels = map.childrenOf(NodeMap.rootNodeId).map((n) => n.label);
      expect(map.root.label, 'now');
      expect(labels, contains('gym'));
      expect(labels, isNot(contains('media')));
      expect(labels, isNot(contains('tools')));
    });
  });

  group('an app can belong to several situations', () {
    const music = 'com.spotify/com.spotify.Main';

    test('the same app sits in two places without either being a copy', () {
      // Music in the gym and music on the commute are the same app and two
      // different answers; a node is a placement, not the app itself.
      var map = NodeMap.seed();
      map = map.addChild('seed-2', appNode('gym-music', music));
      map = map.addChild('seed-1', appNode('out-music', music));

      expect(map['gym-music']!.appId, map['out-music']!.appId);
      expect(map['gym-music']!.parentId, 'seed-2');
      expect(map['out-music']!.parentId, 'seed-1');
      expect(map.reachable(), containsAll(['gym-music', 'out-music']));
    });

    test('removing it from one situation leaves the other alone', () {
      var map = NodeMap.seed();
      map = map.addChild('seed-2', appNode('gym-music', music));
      map = map.addChild('seed-1', appNode('out-music', music));

      map = map.remove('gym-music');
      expect(map['gym-music'], isNull);
      expect(map['out-music'], isNotNull);
    });

    test('each placement is positioned by its own situation', () {
      // They ring different parents, so the same app is in two places on the
      // canvas — which is the whole point of a spatial map.
      var map = NodeMap.seed();
      map = map.addChild('seed-2', appNode('gym-music', music));
      map = map.addChild('seed-1', appNode('out-music', music));

      final a = map['gym-music']!;
      final b = map['out-music']!;
      expect(a.x == b.x && a.y == b.y, isFalse);
    });
  });

  group('each situation gets its own territory', () {
    test('one branch does not fold back over its siblings', () {
      // Moving to a situation has to mean moving somewhere; children ringing
      // their parent completely put them straight back among its siblings.
      var map = NodeMap.seed();
      for (var i = 0; i < 4; i++) {
        map = map.addChild('seed-2', appNode('gym-\$i', 'com.g\$i/M'));
      }

      final siblings = map.childrenOf(NodeMap.rootNodeId)
          .where((n) => n.id != 'seed-2');
      final gymChildren = map.childrenOf('seed-2');

      for (final child in gymChildren) {
        for (final sibling in siblings) {
          expect(overlaps(child, sibling), isFalse,
              reason: '\${child.id} sits on \${sibling.label}');
        }
      }
    });

    test('a branch points away from where it was reached from', () {
      // Its children should be further from the root than it is, not nearer.
      var map = NodeMap.seed();
      map = map.addChild('seed-2', appNode('gym-a', 'com.a/M'));

      final root = map.root;
      final gym = map['seed-2']!;
      final child = map['gym-a']!;

      double from(MapNode node) {
        final dx = node.x - root.x;
        final dy = node.y - root.y;
        return dx * dx + dy * dy;
      }

      expect(from(child), greaterThan(from(gym)));
    });

    test('the root still rings, having nowhere it was reached from', () {
      final children = NodeMap.seed().childrenOf(NodeMap.rootNodeId);
      expect(children.any((n) => n.x > 1), isTrue);
      expect(children.any((n) => n.x < -1), isTrue);
    });
  });

  group('situations nest', () {
    test('a place inside a place is still one map', () {
      // "daily -> gym -> music" is a path, not three screens.
      var map = NodeMap.seed();
      map = map.addChild(
        'seed-2',
        const MapNode(
          id: 'warmup',
          label: 'warm up',
          kind: NodeKind.place,
          x: 0,
          y: 0,
        ),
      );
      map = map.addChild('warmup', appNode('warm-music', 'com.a/com.a.Main'));

      expect(
        map.pathTo('warm-music').map((n) => n.label),
        ['now', 'gym', 'warm up', 'Music'],
      );
    });
  });
}

/// Whether two nodes are far enough apart to read as separate on the canvas.
bool overlaps(MapNode a, MapNode b, {double size = 96}) {
  final dx = (a.x - b.x).abs();
  final dy = (a.y - b.y).abs();
  return dx < size && dy < size;
}
