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
