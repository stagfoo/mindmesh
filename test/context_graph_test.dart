import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/context_graph.dart';

ContextNode ctx(String id) => ContextNode(id: id, label: id);

ContextGraph withContexts(List<String> ids) {
  var graph = ContextGraph.seed();
  for (final id in ids) {
    graph = graph.addContext(ctx(id));
  }
  return graph;
}

void main() {
  group('a context is one thing in several places', () {
    test('the same context sits in two parents without being copied', () {
      // The whole point of edges being stored apart from contexts: "gym" in
      // "morning" and "gym" in "health" is one gym.
      var graph = withContexts(['morning', 'health', 'gym'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link(ContextGraph.rootContextId, const ChildRef.context('health'))
          .link('morning', const ChildRef.context('gym'))
          .link('health', const ChildRef.context('gym'));

      expect(graph.contexts.values.where((c) => c.id == 'gym').length, 1);
      expect(graph.parentsOf('gym').map((p) => p.id),
          containsAll(['morning', 'health']));
    });

    test('renaming it renames it everywhere', () {
      var graph = withContexts(['morning', 'health', 'gym'])
          .link('morning', const ChildRef.context('gym'))
          .link('health', const ChildRef.context('gym'));

      graph = graph.replaceContext(graph['gym']!.copyWith(label: 'the gym'));

      expect(graph.childrenOf('morning').single.child.id, 'gym');
      expect(graph['gym']!.label, 'the gym');
      expect(graph.parentsOf('gym'), hasLength(2));
    });

    test('taking it out of one parent leaves the other alone', () {
      var graph = withContexts(['morning', 'health', 'gym'])
          .link('morning', const ChildRef.context('gym'))
          .link('health', const ChildRef.context('gym'));

      graph = graph.unlink('morning', const ChildRef.context('gym'));

      expect(graph.childrenOf('morning'), isEmpty);
      expect(graph.childrenOf('health'), hasLength(1));
      expect(graph['gym'], isNotNull);
    });

    test('linking the same child twice does not double it up', () {
      // Two circles for one thing in one place would be a lie about a model
      // whose whole claim is that there are no duplicates.
      final graph = withContexts(['gym'])
          .link(ContextGraph.rootContextId, const ChildRef.context('gym'))
          .link(ContextGraph.rootContextId, const ChildRef.context('gym'));

      expect(
        graph.childrenOf(ContextGraph.rootContextId)
            .where((e) => e.child.id == 'gym'),
        hasLength(1),
      );
    });

    test('a context and an app with the same id do not collide', () {
      final graph = withContexts(['spotify'])
          .link(ContextGraph.rootContextId, const ChildRef.context('spotify'))
          .link(ContextGraph.rootContextId, const ChildRef.app('spotify'));

      expect(graph.childrenOf(ContextGraph.rootContextId), hasLength(7));
    });
  });

  group('freeform means many parents, not circular ones', () {
    test('a context cannot be put inside itself', () {
      final graph = withContexts(['gym'])
          .link('gym', const ChildRef.context('gym'));
      expect(graph.childrenOf('gym'), isEmpty);
    });

    test('a context cannot be put inside its own descendant', () {
      // There would be no bottom: you could navigate in for ever and never
      // arrive anywhere.
      var graph = withContexts(['morning', 'gym', 'warmup'])
          .link('morning', const ChildRef.context('gym'))
          .link('gym', const ChildRef.context('warmup'));

      expect(graph.wouldLoop('warmup', 'morning'), isTrue);
      graph = graph.link('warmup', const ChildRef.context('morning'));
      expect(graph.childrenOf('warmup'), isEmpty);
    });

    test('a diamond is fine — it is not a loop', () {
      // "gym" under both "morning" and "health", both under root. Two paths to
      // the same place is exactly what freeform means.
      final graph = withContexts(['morning', 'health', 'gym'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link(ContextGraph.rootContextId, const ChildRef.context('health'))
          .link('morning', const ChildRef.context('gym'))
          .link('health', const ChildRef.context('gym'));

      expect(graph.wouldLoop('morning', 'gym'), isFalse);
      expect(graph.parentsOf('gym'), hasLength(2));
    });
  });

  group('position and size belong to the edge, not the context', () {
    test('the same context sits somewhere different in each parent', () {
      final graph = withContexts(['morning', 'health', 'gym'])
          .link('morning', const ChildRef.context('gym'), x: 0.2, y: 0.3)
          .link('health', const ChildRef.context('gym'), x: 0.8, y: 0.7);

      expect(graph.childrenOf('morning').single.x, 0.2);
      expect(graph.childrenOf('health').single.x, 0.8);
    });

    test('moving it in one parent does not move it in the other', () {
      var graph = withContexts(['morning', 'health', 'gym'])
          .link('morning', const ChildRef.context('gym'), x: 0.2, y: 0.3)
          .link('health', const ChildRef.context('gym'), x: 0.8, y: 0.7);

      graph = graph.moveChild(
          'morning', const ChildRef.context('gym'), 0.45, 0.55);

      expect(graph.childrenOf('morning').single.x, 0.45);
      expect(graph.childrenOf('health').single.x, 0.8);
    });

    test('a position is a fraction, and stays inside the view', () {
      // Stored as fractions because a launcher outlives the phone it was
      // arranged on, and a pixel position does not survive the move.
      final graph = withContexts(['gym'])
          .link('gym', const ChildRef.app('a/M'), x: 2.5, y: -3);
      final edge = graph.childrenOf('gym').single;

      expect(edge.x, 1.0);
      expect(edge.y, 0.0);
    });
  });

  group('deleting', () {
    test('deleting a context takes it out of every parent', () {
      var graph = withContexts(['morning', 'health', 'gym'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link(ContextGraph.rootContextId, const ChildRef.context('health'))
          .link('morning', const ChildRef.context('gym'))
          .link('health', const ChildRef.context('gym'));

      graph = graph.removeContext('gym');

      expect(graph['gym'], isNull);
      expect(graph.childrenOf('morning'), isEmpty);
      expect(graph.childrenOf('health'), isEmpty);
    });

    test('what it held survives if something else holds it too', () {
      var graph = withContexts(['morning', 'health', 'gym'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link(ContextGraph.rootContextId, const ChildRef.context('health'))
          .link('morning', const ChildRef.context('gym'))
          .link('health', const ChildRef.context('gym'));

      graph = graph.removeContext('morning');

      expect(graph['gym'], isNotNull, reason: 'health still holds it');
      expect(graph.childrenOf('health'), hasLength(1));
    });

    test('what it held is dropped if nothing else can reach it', () {
      // Not deleted out of spite — there would be no way to navigate to it
      // again, and an unreachable context is just weight in storage.
      var graph = withContexts(['morning', 'gym'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link('morning', const ChildRef.context('gym'));

      graph = graph.removeContext('morning');

      expect(graph['gym'], isNull);
    });

    test('the root cannot be deleted', () {
      final graph = ContextGraph.seed();
      expect(graph.removeContext(ContextGraph.rootContextId).root, isNotNull);
    });
  });

  group('storage', () {
    test('round-trips contexts, edges and placements', () {
      final graph = withContexts(['morning', 'gym'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'),
              x: 0.25, y: 0.75)
          .link('morning', const ChildRef.context('gym'))
          .link('morning', const ChildRef.app('com.a/M'), x: 0.1, y: 0.9);

      final restored = ContextGraph.fromJson(graph.toJson())!;

      expect(restored.contexts.length, graph.contexts.length);
      expect(restored.edges.length, graph.edges.length);
      final morning = restored.childrenOf(ContextGraph.rootContextId)
          .firstWhere((e) => e.child.id == 'morning');
      expect(morning.x, 0.25);
      expect(morning.y, 0.75);
      expect(restored.childrenOf('morning').where((e) => e.child.isApp),
          hasLength(1));
    });

    test('an edge to a context that no longer exists is dropped', () {
      final json = withContexts(['gym'])
          .link(ContextGraph.rootContextId, const ChildRef.context('gym'))
          .toJson();
      (json['contexts'] as List).removeWhere((c) => c['id'] == 'gym');

      final restored = ContextGraph.fromJson(json)!;

      expect(restored.childrenOf(ContextGraph.rootContextId)
          .where((e) => e.child.id == 'gym'), isEmpty);
    });

    test('a graph with no root is not a graph', () {
      expect(ContextGraph.fromJson({'contexts': [], 'edges': []}), isNull);
    });

    test('an unreachable context is not loaded back', () {
      final json = withContexts(['stray']).toJson();
      final restored = ContextGraph.fromJson(json)!;
      expect(restored['stray'], isNull);
    });
  });

  group('the seed', () {
    test('is contexts you could be in, already placed', () {
      final graph = ContextGraph.seed();
      final children = graph.childrenOf(ContextGraph.rootContextId);

      expect(children, hasLength(5));
      for (final edge in children) {
        expect(edge.x, inExclusiveRange(0, 1));
        expect(edge.y, inExclusiveRange(0, 1));
      }
    });
  });

  group('the trail is where you walked', () {
    test('a context with two parents has two ways in, both real', () {
      // Which is why the trail cannot be derived from the graph: there is no
      // single path to a shared context, only the one you took.
      final graph = withContexts(['morning', 'health', 'gym'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link(ContextGraph.rootContextId, const ChildRef.context('health'))
          .link('morning', const ChildRef.context('gym'))
          .link('health', const ChildRef.context('gym'));

      expect(graph.parentsOf('gym').map((p) => p.id).toSet(),
          {'morning', 'health'});
    });
  });

  group('a spot for something new', () {
    test('no two of the first dozen land on each other', () {
      final spots = [for (var i = 0; i < 12; i++) freeSpot(i)];
      for (var i = 0; i < spots.length; i++) {
        for (var j = i + 1; j < spots.length; j++) {
          final dx = spots[i].x - spots[j].x;
          final dy = spots[i].y - spots[j].y;
          expect(dx * dx + dy * dy, greaterThan(0.0004),
              reason: 'spots $i and $j');
        }
      }
    });

    test('every spot is inside the view', () {
      for (var i = 0; i < 60; i++) {
        final spot = freeSpot(i);
        expect(spot.x, inInclusiveRange(0, 1));
        expect(spot.y, inInclusiveRange(0, 1));
      }
    });
  });
}
