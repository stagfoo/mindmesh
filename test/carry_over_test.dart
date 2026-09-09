import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/context_graph.dart';
import 'package:mindmesh/graph_store.dart';
import 'package:mindmesh/usage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A map saved by the previous model: a tree of places holding apps, plus one
/// app that was still a node of its own from the model before that.
final legacy = jsonEncode([
  {
    'id': 'root',
    'label': 'now',
    'x': 0,
    'y': 0,
    'childIds': ['gym', 'home'],
    'colorKey': 'butter',
  },
  {
    'id': 'gym',
    'label': 'gym',
    'x': 200,
    'y': -100,
    'parentId': 'root',
    'childIds': ['oldnode'],
    'apps': ['com.strong/M'],
    'colorKey': 'green',
  },
  {
    'id': 'oldnode',
    'label': 'Music',
    'kind': 'app',
    'x': 0,
    'y': 0,
    'parentId': 'gym',
    'appId': 'com.spotify/M',
  },
  {
    'id': 'home',
    'label': 'at home',
    'x': -150,
    'y': 90,
    'parentId': 'root',
    'colorKey': 'periwinkle',
  },
]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('an arrangement built on the old model comes across', () {
    test('places become contexts, keeping their names and colours', () async {
      SharedPreferences.setMockInitialValues({'mindmesh.map.v1': legacy});

      final stored = await GraphStore().load();

      expect(stored.graph['gym']!.label, 'gym');
      expect(stored.graph['gym']!.colorKey, 'green');
      expect(stored.graph['home']!.label, 'at home');
      expect(stored.graph.root.id, ContextGraph.rootContextId);
    });

    test('what a place held becomes what a context holds', () async {
      SharedPreferences.setMockInitialValues({'mindmesh.map.v1': legacy});

      final stored = await GraphStore().load();
      final inRoot = stored.graph.childrenOf(ContextGraph.rootContextId);
      final inGym = stored.graph.childrenOf('gym');

      expect(inRoot.map((e) => e.child.id), containsAll(['gym', 'home']));
      expect(
        inGym.where((e) => e.child.isApp).map((e) => e.child.id),
        containsAll(['com.spotify/M', 'com.strong/M']),
        reason: 'both the app node and the folded-in app',
      );
    });

    test('everything carried over is placed somewhere on the screen', () async {
      // Old positions were world coordinates on a canvas that panned; this view
      // has no such thing, so they are laid out fresh rather than landing
      // somewhere arbitrary or off the edge.
      SharedPreferences.setMockInitialValues({'mindmesh.map.v1': legacy});

      final stored = await GraphStore().load();

      for (final edge in stored.graph.edges.values) {
        expect(edge.x, inInclusiveRange(0, 1), reason: edge.key);
        expect(edge.y, inInclusiveRange(0, 1), reason: edge.key);
      }
    });

    test('nothing lands exactly on top of anything else', () async {
      SharedPreferences.setMockInitialValues({'mindmesh.map.v1': legacy});

      final stored = await GraphStore().load();
      final inGym = stored.graph.childrenOf('gym');

      expect(inGym, hasLength(2));
      expect(inGym[0].x == inGym[1].x && inGym[0].y == inGym[1].y, isFalse);
    });

    test('a saved graph wins over the old map', () async {
      final graph = ContextGraph.seed();
      SharedPreferences.setMockInitialValues({
        'mindmesh.map.v1': legacy,
        'mindmesh.contexts.v1': jsonEncode({
          'graph': graph.toJson(),
          'usage': <String, dynamic>{},
        }),
      });

      final stored = await GraphStore().load();

      expect(stored.graph['gym'], isNull, reason: 'not the legacy map');
      expect(stored.graph.childrenOf(ContextGraph.rootContextId), hasLength(5));
    });

    test('no old map and no new one is the seed, not a blank screen', () async {
      final stored = await GraphStore().load();
      expect(stored.graph.childrenOf(ContextGraph.rootContextId), hasLength(5));
    });

    test('an unreadable old map falls back to the seed', () async {
      SharedPreferences.setMockInitialValues({'mindmesh.map.v1': '{oh dear'});
      final stored = await GraphStore().load();
      expect(stored.graph.childrenOf(ContextGraph.rootContextId), hasLength(5));
    });
  });

  group('saving and loading', () {
    test('a graph and its counters come back as they went in', () async {
      final store = GraphStore();
      final graph = ContextGraph.seed()
          .link(ContextGraph.rootContextId, const ChildRef.app('com.a/M'),
              x: 0.3, y: 0.4);
      final key = edgeKey(ContextGraph.rootContextId, const ChildRef.context('home'));
      final usage = const UsageBook.empty().opened(key, DateTime.now());

      await store.save(graph, usage);
      final stored = await store.load();

      expect(stored.graph.edges.length, graph.edges.length);
      expect(stored.usage.clicksAt(key, DateTime.now()), 1);
    });
  });
}
