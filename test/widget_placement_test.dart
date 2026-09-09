import 'package:flutter_test/flutter_test.dart';
import 'package:mindmesh/context_graph.dart';

ContextGraph graphWith(List<String> ids) {
  var graph = ContextGraph.seed();
  for (final id in ids) {
    graph = graph.addContext(ContextNode(id: id, label: id));
  }
  return graph;
}

void main() {
  group('a widget is a placement, not a thing that gets shared', () {
    test('it goes in a context alongside apps and sub-contexts', () {
      final graph = graphWith(['morning'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link('morning', const ChildRef.widget('17'))
          .link('morning', const ChildRef.app('com.a/M'));

      final kinds =
          graph.childrenOf('morning').map((e) => e.child.kind).toSet();
      expect(kinds, {ChildKind.widget, ChildKind.app});
    });

    test('you cannot navigate into one', () {
      // Only a context is somewhere to go; a widget is something to read.
      final graph = graphWith(['morning'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link('morning', const ChildRef.widget('17'));

      expect(graph.descendantsOf(ContextGraph.rootContextId), isNot(contains('17')));
      expect(graph.childrenOf('17'), isEmpty);
    });

    test('a widget and a context with the same id do not collide', () {
      final graph = graphWith(['17'])
          .link(ContextGraph.rootContextId, const ChildRef.context('17'))
          .link(ContextGraph.rootContextId, const ChildRef.widget('17'));

      expect(
        graph.childrenOf(ContextGraph.rootContextId)
            .where((e) => e.child.id == '17'),
        hasLength(2),
      );
    });

    test('the appWidgetId is the number Android gave out', () {
      expect(const ChildRef.widget('17').appWidgetId, 17);
      expect(const ChildRef.app('com.a/M').appWidgetId, isNull);
      expect(const ChildRef.widget('not a number').appWidgetId, isNull);
    });
  });

  group('every placed widget id can be found again', () {
    test('so a removed one can be handed back to the system', () {
      // An id dropped without being released leaves a widget running that
      // nothing can see and nobody can remove.
      final graph = graphWith(['morning', 'evening'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link(ContextGraph.rootContextId, const ChildRef.context('evening'))
          .link('morning', const ChildRef.widget('17'))
          .link('evening', const ChildRef.widget('23'));

      expect(graph.widgetIds, {17, 23});
    });

    test('deleting a context surfaces the widgets that were inside it', () {
      var graph = graphWith(['morning', 'gym'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link('morning', const ChildRef.context('gym'))
          .link('morning', const ChildRef.widget('17'))
          .link('gym', const ChildRef.widget('23'));

      final before = graph.widgetIds;
      graph = graph.removeContext('morning');

      // Both: the one directly inside, and the one inside the sub-context that
      // went with it. Comparing before and after is what makes a delete deep
      // enough without every call site having to remember.
      expect(before.difference(graph.widgetIds), {17, 23});
      expect(graph.widgetIds, isEmpty);
    });

    test('unlinking one surfaces exactly that one', () {
      var graph = graphWith(['morning'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link('morning', const ChildRef.widget('17'))
          .link('morning', const ChildRef.widget('23'));

      final before = graph.widgetIds;
      graph = graph.unlink('morning', const ChildRef.widget('17'));

      expect(before.difference(graph.widgetIds), {17});
    });

    test('a widget in a context that survives is not released', () {
      var graph = graphWith(['morning', 'gym'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link(ContextGraph.rootContextId, const ChildRef.context('gym'))
          .link('morning', const ChildRef.context('gym'))
          .link('gym', const ChildRef.widget('23'));

      final before = graph.widgetIds;
      // "gym" is also under the root, so it and its widget survive.
      graph = graph.removeContext('morning');

      expect(before.difference(graph.widgetIds), isEmpty);
      expect(graph.widgetIds, {23});
    });
  });

  group('size belongs to the placement', () {
    test('a widget has one, a circle does not', () {
      final graph = graphWith(['morning'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link('morning', const ChildRef.widget('17'))
          .resizeChild('morning', const ChildRef.widget('17'), 0.86, 0.24);

      final widget = graph.childrenOf('morning').single;
      final circle = graph.childrenOf(ContextGraph.rootContextId)
          .firstWhere((e) => e.child.id == 'morning');

      expect(widget.w, 0.86);
      expect(widget.h, 0.24);
      expect(circle.w, isNull, reason: 'a context is sized by use');
    });

    test('a size cannot be set to nothing or to more than the view', () {
      final graph = graphWith(['morning'])
          .link('morning', const ChildRef.widget('17'))
          .resizeChild('morning', const ChildRef.widget('17'), 9, -4);
      final edge = graph.childrenOf('morning').single;

      expect(edge.w, 1.0);
      expect(edge.h, 0.08);
    });

    test('moving a widget keeps its size', () {
      final graph = graphWith(['morning'])
          .link('morning', const ChildRef.widget('17'))
          .resizeChild('morning', const ChildRef.widget('17'), 0.86, 0.24)
          .moveChild('morning', const ChildRef.widget('17'), 0.2, 0.3);
      final edge = graph.childrenOf('morning').single;

      expect(edge.x, 0.2);
      expect(edge.w, 0.86);
      expect(edge.h, 0.24);
    });

    test('size and position survive storage', () {
      final graph = graphWith(['morning'])
          .link(ContextGraph.rootContextId, const ChildRef.context('morning'))
          .link('morning', const ChildRef.widget('17'), x: 0.4, y: 0.6)
          .resizeChild('morning', const ChildRef.widget('17'), 0.86, 0.24);

      final restored = ContextGraph.fromJson(graph.toJson())!;
      final edge = restored.childrenOf('morning').single;

      expect(edge.child.kind, ChildKind.widget);
      expect(edge.child.appWidgetId, 17);
      expect(edge.x, 0.4);
      expect(edge.w, 0.86);
      expect(edge.h, 0.24);
    });
  });
}
