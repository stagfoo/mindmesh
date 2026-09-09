/// Contexts and the edges between them.
///
/// Not a tree. The same context is one object that several parents point at —
/// "gym" inside both "morning" and "health" is the same gym, so renaming it in
/// one place renames it in both. That is why contexts and edges are stored
/// apart: a tree would have to copy the child, and two copies drift.
///
/// Everything that varies per parent lives on the *edge*, not on the context:
/// where the circle sits, and how big use has made it. A context's size in
/// "morning" says nothing about its size in "health".
///
/// Pure Dart, so the rules — no cycles, no orphans, one edge per parent-child
/// pair — are testable without a screen.
library;

import 'dart:math' as math;

enum ChildKind { context, app }

/// What an edge points at: another context, or an app to launch.
class ChildRef {
  const ChildRef(this.kind, this.id);

  const ChildRef.context(this.id) : kind = ChildKind.context;
  const ChildRef.app(this.id) : kind = ChildKind.app;

  final ChildKind kind;

  /// A context id, or an app id (`package/activity`).
  final String id;

  bool get isApp => kind == ChildKind.app;

  /// Unique within a parent, so a context and an app can never collide.
  String get key => '${kind.name}:$id';

  @override
  bool operator ==(Object other) =>
      other is ChildRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => key;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'id': id};

  static ChildRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return ChildRef(
      json['kind'] == 'app' ? ChildKind.app : ChildKind.context,
      id,
    );
  }
}

class ContextNode {
  const ContextNode({
    required this.id,
    required this.label,
    this.colorKey = 'cyan',
  });

  final String id;
  final String label;

  /// Base hue for the blurred circle.
  final String colorKey;

  ContextNode copyWith({String? label, String? colorKey}) => ContextNode(
        id: id,
        label: label ?? this.label,
        colorKey: colorKey ?? this.colorKey,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'label': label, 'colorKey': colorKey};

  static ContextNode? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return ContextNode(
      id: id,
      label: (json['label'] as String?) ?? id,
      colorKey: (json['colorKey'] as String?) ?? 'cyan',
    );
  }
}

/// One child, placed inside one parent.
///
/// [x] and [y] are fractions of the view, not pixels: the same placement has to
/// mean the same thing on a square panel and on a tall phone, and a launcher
/// outlives the phone it was arranged on.
class Edge {
  const Edge({
    required this.parentId,
    required this.child,
    required this.x,
    required this.y,
  });

  final String parentId;
  final ChildRef child;
  final double x;
  final double y;

  String get key => edgeKey(parentId, child);

  Edge movedTo(double x, double y) => Edge(
        parentId: parentId,
        child: child,
        x: x.clamp(0.0, 1.0),
        y: y.clamp(0.0, 1.0),
      );

  Map<String, dynamic> toJson() =>
      {'parentId': parentId, 'child': child.toJson(), 'x': x, 'y': y};

  static Edge? fromJson(Object? json) {
    if (json is! Map) return null;
    final parentId = json['parentId'];
    final child = ChildRef.fromJson(json['child']);
    if (parentId is! String || child == null) return null;
    return Edge(
      parentId: parentId,
      child: child,
      x: ((json['x'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
      y: ((json['y'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
    );
  }
}

/// The key a placement and its usage counter are both filed under.
///
/// Parent *and* child, because both size and position are scoped to the parent
/// you are looking at them from.
String edgeKey(String parentId, ChildRef child) => '$parentId|${child.key}';

class ContextGraph {
  const ContextGraph({
    required this.contexts,
    required this.edges,
    required this.rootId,
  });

  final Map<String, ContextNode> contexts;

  /// Keyed by [edgeKey]; one placement per parent-child pair.
  final Map<String, Edge> edges;

  final String rootId;

  static const rootContextId = 'root';

  ContextNode? operator [](String id) => contexts[id];

  ContextNode get root => contexts[rootId]!;

  /// What is inside [parentId], in insertion order so the view is stable.
  List<Edge> childrenOf(String parentId) => [
        for (final edge in edges.values)
          if (edge.parentId == parentId &&
              (edge.child.isApp || contexts.containsKey(edge.child.id)))
            edge,
      ];

  /// Every context that holds [contextId] — what makes a shared context worth
  /// showing as shared rather than as a duplicate.
  List<ContextNode> parentsOf(String contextId) => [
        for (final edge in edges.values)
          if (!edge.child.isApp &&
              edge.child.id == contextId &&
              contexts.containsKey(edge.parentId))
            contexts[edge.parentId]!,
      ];

  /// The places holding [appId], for the same reason.
  List<ContextNode> holdersOf(String appId) => [
        for (final edge in edges.values)
          if (edge.child.isApp &&
              edge.child.id == appId &&
              contexts.containsKey(edge.parentId))
            contexts[edge.parentId]!,
      ];

  ContextGraph _with({
    Map<String, ContextNode>? contexts,
    Map<String, Edge>? edges,
  }) =>
      ContextGraph(
        contexts: contexts ?? this.contexts,
        edges: edges ?? this.edges,
        rootId: rootId,
      );

  /// Every context reachable from [id], following edges downward.
  Set<String> descendantsOf(String id) {
    final seen = <String>{};
    final queue = <String>[id];
    while (queue.isNotEmpty) {
      final next = queue.removeLast();
      if (!seen.add(next)) continue;
      for (final edge in childrenOf(next)) {
        if (!edge.child.isApp) queue.add(edge.child.id);
      }
    }
    return seen;
  }

  /// Whether putting [contextId] inside [parentId] would make a loop.
  ///
  /// A context inside its own descendant has no bottom: you could navigate
  /// into it for ever and never arrive anywhere. Being freeform means many
  /// parents, not circular ones.
  bool wouldLoop(String parentId, String contextId) =>
      parentId == contextId || descendantsOf(contextId).contains(parentId);

  ContextGraph addContext(ContextNode node) =>
      _with(contexts: {...contexts, node.id: node});

  ContextGraph replaceContext(ContextNode node) => contexts.containsKey(node.id)
      ? _with(contexts: {...contexts, node.id: node})
      : this;

  /// Puts [child] inside [parentId] at a fraction of the view.
  ///
  /// Linking something already there is a no-op rather than a second copy —
  /// two circles for one thing in one place would be a lie about the model.
  ContextGraph link(
    String parentId,
    ChildRef child, {
    double x = 0.5,
    double y = 0.5,
  }) {
    if (!contexts.containsKey(parentId)) return this;
    if (!child.isApp) {
      if (!contexts.containsKey(child.id)) return this;
      if (wouldLoop(parentId, child.id)) return this;
    }
    final key = edgeKey(parentId, child);
    if (edges.containsKey(key)) return this;
    return _with(edges: {
      ...edges,
      key: Edge(
        parentId: parentId,
        child: child,
        x: x.clamp(0.0, 1.0),
        y: y.clamp(0.0, 1.0),
      ),
    });
  }

  /// Takes [child] out of [parentId] only. Other parents keep it, and the
  /// context itself still exists.
  ContextGraph unlink(String parentId, ChildRef child) {
    final key = edgeKey(parentId, child);
    if (!edges.containsKey(key)) return this;
    return _with(edges: {
      for (final entry in edges.entries)
        if (entry.key != key) entry.key: entry.value,
    });
  }

  ContextGraph moveChild(
    String parentId,
    ChildRef child,
    double x,
    double y,
  ) {
    final edge = edges[edgeKey(parentId, child)];
    if (edge == null) return this;
    return _with(edges: {...edges, edge.key: edge.movedTo(x, y)});
  }

  /// Deletes a context everywhere, and everything that only it held.
  ///
  /// Its children are not deleted — they may well live in other contexts too.
  /// Anything left with no parent at all is dropped, since there would be no
  /// way to reach it again.
  ContextGraph removeContext(String id) {
    if (id == rootId) return this;
    final remaining = {
      for (final entry in contexts.entries)
        if (entry.key != id) entry.key: entry.value,
    };
    final kept = {
      for (final entry in edges.entries)
        if (entry.value.parentId != id &&
            !(!entry.value.child.isApp && entry.value.child.id == id))
          entry.key: entry.value,
    };
    return ContextGraph(contexts: remaining, edges: kept, rootId: rootId)
        ._pruned();
  }

  /// Drops anything the root can no longer reach.
  ContextGraph _pruned() {
    final live = descendantsOf(rootId);
    return ContextGraph(
      contexts: {
        for (final entry in contexts.entries)
          if (live.contains(entry.key)) entry.key: entry.value,
      },
      edges: {
        for (final entry in edges.entries)
          if (live.contains(entry.value.parentId) &&
              (entry.value.child.isApp || live.contains(entry.value.child.id)))
            entry.key: entry.value,
      },
      rootId: rootId,
    );
  }

  Map<String, dynamic> toJson() => {
        'contexts': [for (final node in contexts.values) node.toJson()],
        'edges': [for (final edge in edges.values) edge.toJson()],
      };

  static ContextGraph? fromJson(Object? json) {
    if (json is! Map) return null;
    final contexts = <String, ContextNode>{};
    for (final entry in (json['contexts'] as List? ?? const [])) {
      final node = ContextNode.fromJson(entry);
      if (node != null) contexts[node.id] = node;
    }
    if (!contexts.containsKey(rootContextId)) return null;

    final edges = <String, Edge>{};
    for (final entry in (json['edges'] as List? ?? const [])) {
      final edge = Edge.fromJson(entry);
      if (edge == null) continue;
      if (!contexts.containsKey(edge.parentId)) continue;
      if (!edge.child.isApp && !contexts.containsKey(edge.child.id)) continue;
      edges[edge.key] = edge;
    }

    return ContextGraph(
      contexts: contexts,
      edges: edges,
      rootId: rootContextId,
    )._pruned();
  }

  /// A first graph, so the launcher is never a blank screen.
  ///
  /// Situations rather than categories — "morning", not "media" — because the
  /// question a context answers is what you are doing, not what kind of thing
  /// an app is.
  static ContextGraph seed() {
    const starters = [
      ('home', 'home', 'periwinkle', 0.34, 0.74),
      ('musings', 'musings', 'blue', 0.66, 0.55),
      ('journaling', 'journaling', 'butter', 0.55, 0.44),
      ('writing', 'improving writing', 'orange', 0.30, 0.32),
      ('poi', 'poi', 'red', 0.52, 0.18),
    ];
    var graph = ContextGraph(
      contexts: {
        rootContextId: const ContextNode(
          id: rootContextId,
          label: 'contexts',
          colorKey: 'butter',
        ),
      },
      edges: const {},
      rootId: rootContextId,
    );
    for (final (id, label, colour, x, y) in starters) {
      graph = graph
          .addContext(ContextNode(id: id, label: label, colorKey: colour))
          .link(rootContextId, ChildRef.context(id), x: x, y: y);
    }
    return graph;
  }
}

/// A spot inside a parent for something new, spiralling outward from the
/// middle so a run of additions does not stack on one point.
({double x, double y}) freeSpot(int existing) {
  const turn = 2.399963; // the golden angle, which never repeats a direction
  final angle = turn * existing;
  final radius = 0.30 * math.sqrt(existing / 8).clamp(0.0, 1.0);
  return (
    x: (0.5 + radius * math.cos(angle)).clamp(0.08, 0.92),
    y: (0.5 + radius * math.sin(angle)).clamp(0.10, 0.90),
  );
}
