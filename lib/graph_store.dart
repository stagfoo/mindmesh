/// Keeps the contexts, the placements and the counters between launches.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'context_graph.dart';
import 'usage.dart';

typedef StoredGraph = ({ContextGraph graph, UsageBook usage});

class GraphStore {
  static const _key = 'mindmesh.contexts.v1';

  /// The previous model: a tree of places, each holding apps.
  static const _legacyKey = 'mindmesh.map.v1';

  Future<StoredGraph> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw != null) {
      try {
        final json = jsonDecode(raw);
        if (json is Map) {
          final graph = ContextGraph.fromJson(json['graph']);
          if (graph != null) {
            final usage = UsageBook.fromJson(json['usage'])
                .keepingOnly(graph.edges.keys.toSet());
            return (graph: graph, usage: usage);
          }
        }
      } on FormatException {
        // A graph that will not parse is a graph you no longer have. Falling
        // through to the seed beats a launcher that refuses to draw.
      }
    }

    final carried = _carryOver(prefs.getString(_legacyKey));
    return (graph: carried ?? ContextGraph.seed(), usage: const UsageBook.empty());
  }

  Future<void> save(ContextGraph graph, UsageBook usage) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({'graph': graph.toJson(), 'usage': usage.toJson()}),
    );
  }

  /// Turns a map from the previous model into contexts and edges.
  ///
  /// Places become contexts and the apps they held become app edges, so the
  /// arrangement someone built survives the change. Positions do not carry: the
  /// old ones were world coordinates on a canvas that panned, and this view has
  /// no such thing — they are laid out fresh instead of landing somewhere
  /// arbitrary.
  static ContextGraph? _carryOver(String? raw) {
    if (raw == null) return null;
    Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! List) return null;

    final places = <String, Map<String, dynamic>>{};
    final appOf = <String, String>{};
    for (final entry in json) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String) continue;
      if (entry['kind'] == 'app') {
        final appId = entry['appId'];
        if (appId is String) appOf[id] = appId;
        continue;
      }
      places[id] = entry.cast<String, dynamic>();
    }
    if (!places.containsKey(ContextGraph.rootContextId)) return null;

    var graph = ContextGraph(
      contexts: {
        for (final entry in places.entries)
          entry.key: ContextNode(
            id: entry.key,
            label: (entry.value['label'] as String?) ?? entry.key,
            colorKey: (entry.value['colorKey'] as String?) ?? 'cyan',
          ),
      },
      edges: const {},
      rootId: ContextGraph.rootContextId,
    );

    for (final entry in places.entries) {
      final parentId = entry.key;
      var placed = 0;
      final children = [
        for (final child in (entry.value['childIds'] as List? ?? const []))
          if (child is String) child,
      ];
      // Apps that were nodes of their own, plus apps already folded into the
      // place — both were the same thing by the end, and both belong here.
      final apps = <String>[
        for (final child in children)
          if (appOf[child] != null) appOf[child]!,
        for (final app in (entry.value['apps'] as List? ?? const []))
          if (app is String) app,
      ];

      for (final childId in children) {
        if (appOf.containsKey(childId)) continue;
        if (!places.containsKey(childId)) continue;
        final spot = freeSpot(placed++);
        graph = graph.link(parentId, ChildRef.context(childId),
            x: spot.x, y: spot.y);
      }
      for (final appId in apps.toSet()) {
        final spot = freeSpot(placed++);
        graph = graph.link(parentId, ChildRef.app(appId), x: spot.x, y: spot.y);
      }
    }
    return graph;
  }
}
