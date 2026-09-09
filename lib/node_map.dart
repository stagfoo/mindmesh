/// The whole map, and the rules that keep it a map.
///
/// Pure Dart: every rule here — a node has one parent, a place cannot be
/// inside itself, the root cannot be removed — is testable without a canvas.
library;

import 'node.dart';
import 'radial_layout.dart';

class NodeMap {
  const NodeMap({required this.nodes, required this.rootId});

  final Map<String, MapNode> nodes;
  final String rootId;

  static const rootNodeId = 'root';

  MapNode? operator [](String id) => nodes[id];

  MapNode get root => nodes[rootId]!;

  int get length => nodes.length;

  List<MapNode> childrenOf(String id) => [
        for (final childId in nodes[id]?.childIds ?? const <String>[])
          if (nodes.containsKey(childId)) nodes[childId]!,
      ];

  /// Every node reachable from the root, which is every node a map is allowed
  /// to have. Anything else is an orphan and is dropped on load.
  Set<String> reachable() {
    final seen = <String>{};
    final queue = <String>[rootId];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      if (!seen.add(id)) continue;
      queue.addAll(nodes[id]?.childIds ?? const []);
    }
    return seen;
  }

  /// The path from the root down to [id], for saying where you are.
  List<MapNode> pathTo(String id) {
    final path = <MapNode>[];
    var current = nodes[id];
    // Bounded by the node count: a cycle would otherwise walk forever, and
    // storage is not to be trusted with that.
    var guard = nodes.length + 1;
    while (current != null && guard-- > 0) {
      path.insert(0, current);
      final parentId = current.parentId;
      if (parentId == null || parentId == current.id) break;
      current = nodes[parentId];
    }
    return path;
  }

  NodeMap _with(Map<String, MapNode> updated) =>
      NodeMap(nodes: updated, rootId: rootId);

  NodeMap replace(MapNode node) =>
      _with({...nodes, node.id: node});

  /// Adds a child *place* under [parentId] and lays the parent's children out
  /// again, leaving anything hand-placed where it is.
  ///
  /// Only places go on the canvas. Apps go inside one, via [addApps].
  ///
  /// [aspect] is the shape of the screen the map is being laid out for, so a
  /// ring fills a tall phone instead of sitting in a small circle in the
  /// middle of it.
  NodeMap addChild(String parentId, MapNode node, {double aspect = 1}) {
    final parent = nodes[parentId];
    if (parent == null) return this;
    final updated = {
      ...nodes,
      node.id: node.copyWith(parentId: parentId),
      parentId: parent.copyWith(childIds: [...parent.childIds, node.id]),
    };
    return NodeMap(nodes: updated, rootId: rootId)
        .arrangeChildrenOf(parentId, aspect: aspect);
  }

  /// Puts [appIds] in [placeId], skipping any already there.
  ///
  /// An app can be in as many places as you like — the same music app belongs
  /// in "gym" and in "wind down", and having to choose one would be the folder
  /// model this is trying not to be.
  NodeMap addApps(String placeId, Iterable<String> appIds) {
    final place = nodes[placeId];
    if (place == null) return this;
    final here = [...place.apps];
    for (final appId in appIds) {
      if (!here.contains(appId)) here.add(appId);
    }
    return replace(place.copyWith(apps: here));
  }

  /// Takes [appId] out of [placeId] only. Other places keep it.
  NodeMap removeApp(String placeId, String appId) {
    final place = nodes[placeId];
    if (place == null) return this;
    return replace(
      place.copyWith(apps: [
        for (final id in place.apps)
          if (id != appId) id,
      ]),
    );
  }

  /// Moves [appId] within [placeId] to sit at [index].
  NodeMap reorderApp(String placeId, String appId, int index) {
    final place = nodes[placeId];
    if (place == null || !place.apps.contains(appId)) return this;
    final apps = [
      for (final id in place.apps)
        if (id != appId) id,
    ];
    apps.insert(index.clamp(0, apps.length), appId);
    return replace(place.copyWith(apps: apps));
  }

  /// The places holding [appId], for showing where else an app already lives.
  List<MapNode> placesWith(String appId) => [
        for (final node in nodes.values)
          if (node.apps.contains(appId)) node,
      ];

  /// Removes [id] and everything under it. The root cannot go.
  NodeMap remove(String id) {
    if (id == rootId) return this;
    final doomed = <String>{};
    final queue = <String>[id];
    while (queue.isNotEmpty) {
      final next = queue.removeLast();
      if (!doomed.add(next)) continue;
      queue.addAll(nodes[next]?.childIds ?? const []);
    }

    final updated = <String, MapNode>{
      for (final entry in nodes.entries)
        if (!doomed.contains(entry.key))
          entry.key: entry.value.copyWith(
            childIds: [
              for (final child in entry.value.childIds)
                if (!doomed.contains(child)) child,
            ],
          ),
    };
    return _with(updated);
  }

  /// Drops [id] at a point, and remembers that it was put there.
  NodeMap moveTo(String id, double x, double y) {
    final node = nodes[id];
    if (node == null) return this;
    return replace(node.copyWith(x: x, y: y, placed: true));
  }

  /// Positions the children of [parentId] that nobody has placed by hand.
  NodeMap arrangeChildrenOf(String parentId, {double aspect = 1}) {
    final parent = nodes[parentId];
    if (parent == null) return this;

    final children = childrenOf(parentId);

    // Children fan away from where their parent was reached from, so a branch
    // occupies its own direction instead of folding back over its siblings.
    // The root has nowhere it was reached from, so its children ring it.
    final grandparent =
        parent.parentId == null ? null : nodes[parent.parentId];
    final facing = grandparent == null
        ? null
        : directionTo(
            fromX: grandparent.x,
            fromY: grandparent.y,
            toX: parent.x,
            toY: parent.y,
          );

    final places = arrangeAround(
      centreX: parent.x,
      centreY: parent.y,
      count: children.length,
      facing: facing,
      aspect: aspect,
    );

    final updated = {...nodes};
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      // A node someone dropped somewhere stays dropped; rearranging around it
      // would undo the only decision they made about the map's shape.
      if (child.placed) continue;
      updated[child.id] = child.copyWith(x: places[i].x, y: places[i].y);
    }
    return _with(updated);
  }

  List<Map<String, dynamic>> toJson() =>
      [for (final node in nodes.values) node.toJson()];

  /// Rebuilds a map from storage, keeping only what hangs off the root.
  ///
  /// A dangling child id or an orphaned subtree is dropped rather than carried:
  /// half a map is harder to reason about than a smaller whole one, and the
  /// launcher has to draw something either way.
  static NodeMap fromJson(Object? json, {double aspect = 1}) {
    if (json is! List) return seed(aspect: aspect);
    final parsed = <String, MapNode>{};
    // Apps used to be nodes of their own. A map saved that way is folded back
    // into its places rather than dropped — the arrangement someone built is
    // the thing worth keeping, and the model change is not their problem.
    final wasNode = <String, ({String? parentId, String appId})>{};
    for (final entry in json) {
      final node = MapNode.fromJson(entry);
      if (node != null) {
        parsed[node.id] = node;
        continue;
      }
      final app = MapNode.appEntryFromJson(entry);
      if (app != null) wasNode[app.id] = (parentId: app.parentId, appId: app.appId);
    }
    if (!parsed.containsKey(rootNodeId)) return seed(aspect: aspect);

    if (wasNode.isNotEmpty) {
      // Taken in each parent's own child order, so apps keep the order they
      // were arranged in rather than whatever order storage happened to list.
      for (final entry in parsed.entries.toList()) {
        final moved = [
          for (final childId in entry.value.childIds)
            if (wasNode[childId]?.parentId == entry.key) wasNode[childId]!.appId,
        ];
        if (moved.isEmpty) continue;
        parsed[entry.key] = entry.value.copyWith(
          apps: [
            ...entry.value.apps,
            for (final appId in moved)
              if (!entry.value.apps.contains(appId)) appId,
          ],
        );
      }
    }

    final map = NodeMap(nodes: parsed, rootId: rootNodeId);
    final live = map.reachable();
    return NodeMap(
      nodes: {
        for (final entry in parsed.entries)
          if (live.contains(entry.key))
            entry.key: entry.value.copyWith(
              childIds: [
                for (final child in entry.value.childIds)
                  if (parsed.containsKey(child)) child,
              ],
            ),
      },
      rootId: rootNodeId,
    );
  }

  /// A first map, so the canvas is never a blank sheet.
  ///
  /// Seeded with situations rather than categories — "gym", not "media" —
  /// because that is the question the map answers: not what kind of thing an
  /// app is, but what you are doing. The same app belongs in as many of these
  /// as it is useful in, which the map allows: a node is a placement, so music
  /// can sit in the gym and in the commute without either being a copy of the
  /// other.
  ///
  /// A seed teaches the model, so a categorical one would quietly turn this
  /// back into a folder tree.
  static NodeMap seed({double aspect = 1}) {
    const root = MapNode(
      id: rootNodeId,
      label: 'now',
      x: 0,
      y: 0,
      colorKey: 'butter',
      iconKey: 'schedule',
    );
    var map = NodeMap(nodes: {rootNodeId: root}, rootId: rootNodeId);
    const starters = [
      ('morning', 'wb_sunny', 'butter'),
      ('out', 'directions_walk', 'cyan'),
      ('gym', 'fitness_center', 'green'),
      ('at home', 'weekend', 'periwinkle'),
      ('wind down', 'nightlight', 'violet'),
    ];
    for (var i = 0; i < starters.length; i++) {
      final (label, icon, colour) = starters[i];
      map = map.addChild(
        rootNodeId,
        MapNode(
          id: 'seed-$i',
          label: label,

          x: 0,
          y: 0,
          colorKey: colour,
          iconKey: icon,
        ),
        aspect: aspect,
      );
    }
    return map;
  }
}
