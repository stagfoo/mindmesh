import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/node.dart';
import 'package:mindmesh/node_map.dart';

MapNode place(String id, {String? label}) =>
    MapNode(id: id, label: label ?? id, x: 0, y: 0);

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

  group('apps are what a place holds, not more places', () {
    const music = 'com.spotify/com.spotify.Main';

    test('adding apps does not add anything to the canvas', () {
      // The whole point: the canvas is a picture of your situations. Giving
      // every app a node of its own made it a picture of the app drawer, and
      // it grew until the map had to be zoomed out to fit.
      final before = NodeMap.seed();
      final after = before.addApps('seed-2', [music, 'com.a/com.a.Main']);

      expect(after.length, before.length);
      expect(after.childrenOf('seed-2'), isEmpty);
      expect(after['seed-2']!.apps, [music, 'com.a/com.a.Main']);
    });

    test('the same app sits in two situations at once', () {
      // Music in the gym and music on the commute are the same app and two
      // different answers; neither is a copy of the other.
      var map = NodeMap.seed();
      map = map.addApps('seed-2', [music]);
      map = map.addApps('seed-1', [music]);

      expect(map.placesWith(music).map((p) => p.label), ['out', 'gym']);
    });

    test('taking it out of one situation leaves the other alone', () {
      var map = NodeMap.seed()
          .addApps('seed-2', [music])
          .addApps('seed-1', [music]);

      map = map.removeApp('seed-2', music);

      expect(map['seed-2']!.apps, isEmpty);
      expect(map['seed-1']!.apps, [music]);
    });

    test('adding the same app twice does not double it up', () {
      final map = NodeMap.seed()
          .addApps('seed-2', [music])
          .addApps('seed-2', [music, 'com.a/com.a.Main']);

      expect(map['seed-2']!.apps, [music, 'com.a/com.a.Main']);
    });

    test('apps keep the order they were put in', () {
      // Order is a decision someone made about what they reach for first.
      final map = NodeMap.seed().addApps('seed-2', ['c/M', 'a/M', 'b/M']);
      expect(map['seed-2']!.apps, ['c/M', 'a/M', 'b/M']);

      final moved = map.reorderApp('seed-2', 'b/M', 0);
      expect(moved['seed-2']!.apps, ['b/M', 'c/M', 'a/M']);
    });

    test('removing a place takes its apps with it, not the phone\'s', () {
      var map = NodeMap.seed().addApps('seed-2', [music]);
      map = map.remove('seed-2');

      expect(map['seed-2'], isNull);
      expect(map.placesWith(music), isEmpty);
    });
  });

  group('a map saved when apps were nodes still loads', () {
    test('an app node is folded into the place it was under', () {
      // The arrangement someone built is the thing worth keeping; the model
      // change is not their problem.
      final old = [
        {
          'id': 'root',
          'label': 'now',
          'x': 0,
          'y': 0,
          'childIds': ['gym'],
          'colorKey': 'butter',
          'iconKey': 'schedule',
        },
        {
          'id': 'gym',
          'label': 'gym',
          'x': 100,
          'y': 0,
          'parentId': 'root',
          'childIds': ['n1', 'n2'],
        },
        {
          'id': 'n1',
          'label': 'Music',
          'kind': 'app',
          'x': 0,
          'y': 0,
          'parentId': 'gym',
          'appId': 'com.spotify/M',
        },
        {
          'id': 'n2',
          'label': 'Strong',
          'kind': 'app',
          'x': 0,
          'y': 0,
          'parentId': 'gym',
          'appId': 'com.strong/M',
        },
      ];

      final map = NodeMap.fromJson(old);

      expect(map['n1'], isNull, reason: 'no longer a node');
      expect(map['gym']!.apps, ['com.spotify/M', 'com.strong/M']);
      expect(map.childrenOf('gym'), isEmpty);
      expect(map['gym']!.x, 100, reason: 'the place stays where it was');
    });

    test('a map with no app nodes is untouched', () {
      final map = NodeMap.seed().addApps('seed-2', ['a/M']);
      final restored = NodeMap.fromJson(map.toJson());

      expect(restored.length, map.length);
      expect(restored['seed-2']!.apps, ['a/M']);
    });
  });

  group('each situation gets its own territory', () {
    test('one branch does not fold back over its siblings', () {
      // Moving to a situation has to mean moving somewhere; children ringing
      // their parent completely put them straight back among its siblings.
      var map = NodeMap.seed();
      for (var i = 0; i < 4; i++) {
        map = map.addChild('seed-2', place('gym-\$i'));
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
      map = map.addChild('seed-2', place('gym-a'));

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
          x: 0,
          y: 0,
        ),
      );
      map = map.addApps('warmup', ['com.a/com.a.Main']);

      expect(
        map.pathTo('warmup').map((n) => n.label),
        ['now', 'gym', 'warm up'],
      );
      expect(map['warmup']!.apps, ['com.a/com.a.Main']);
    });
  });
}

/// Whether two nodes are far enough apart to read as separate on the canvas.
bool overlaps(MapNode a, MapNode b, {double size = 96}) {
  final dx = (a.x - b.x).abs();
  final dy = (a.y - b.y).abs();
  return dx < size && dy < size;
}
