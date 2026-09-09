/// The map: places, what they hold, and where they sit.
///
/// A node is a place — a situation you can be in. Apps are not nodes; they are
/// what a place *holds*. That distinction is the model: "gym" is somewhere you
/// go, and the apps in it are what you do once you are there. Giving every app
/// its own node made the canvas a picture of your app drawer rather than a
/// picture of your day, and it grew until the whole thing had to be zoomed out
/// to fit.
///
/// Pure Dart, so the graph rules and the geometry can be tested without a
/// device or a canvas.
library;

class MapNode {
  const MapNode({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
    this.parentId,
    this.childIds = const [],
    this.apps = const [],
    this.colorKey = 'cyan',
    this.iconKey = 'folder',
    this.placed = false,
  });

  final String id;
  final String label;

  /// Position in world space — the canvas's own coordinates, not the screen's.
  final double x;
  final double y;

  final String? parentId;

  /// Places nested inside this one, which are drawn on the canvas.
  final List<String> childIds;

  /// The apps this place holds, in the order they were added. Not nodes: they
  /// live inside the place and are shown when you arrive at it.
  final List<String> apps;

  final String colorKey;
  final String iconKey;

  /// Whether a person put this node here.
  ///
  /// An unplaced node is arranged automatically and re-arranged when its
  /// siblings change; a placed one is left exactly where it was dropped. The
  /// distinction is the whole of "auto-placed, then draggable".
  final bool placed;

  bool get hasChildren => childIds.isNotEmpty;

  bool get isEmpty => childIds.isEmpty && apps.isEmpty;

  MapNode copyWith({
    String? label,
    double? x,
    double? y,
    List<String>? childIds,
    List<String>? apps,
    String? colorKey,
    String? iconKey,
    bool? placed,
    String? parentId,
  }) {
    return MapNode(
      id: id,
      label: label ?? this.label,
      x: x ?? this.x,
      y: y ?? this.y,
      parentId: parentId ?? this.parentId,
      childIds: childIds ?? this.childIds,
      apps: apps ?? this.apps,
      colorKey: colorKey ?? this.colorKey,
      iconKey: iconKey ?? this.iconKey,
      placed: placed ?? this.placed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'x': x,
        'y': y,
        if (parentId != null) 'parentId': parentId,
        'childIds': childIds,
        if (apps.isNotEmpty) 'apps': apps,
        'colorKey': colorKey,
        'iconKey': iconKey,
        if (placed) 'placed': true,
      };

  /// Reads a place. Returns null for an app entry from an older map — those are
  /// folded into their parent by [NodeMap.fromJson] rather than kept as nodes.
  static MapNode? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = json.cast<String, dynamic>();
    final id = map['id'];
    if (id is! String) return null;
    if (map['kind'] == 'app') return null;
    return MapNode(
      id: id,
      label: (map['label'] as String?) ?? id,
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
      parentId: map['parentId'] as String?,
      childIds: [
        for (final child in (map['childIds'] as List? ?? const []))
          if (child is String) child,
      ],
      apps: [
        for (final app in (map['apps'] as List? ?? const []))
          if (app is String) app,
      ],
      colorKey: (map['colorKey'] as String?) ?? 'cyan',
      iconKey: (map['iconKey'] as String?) ?? 'folder',
      placed: map['placed'] as bool? ?? false,
    );
  }

  /// The app an older map's node stood for, as (node id, parent id, app id).
  ///
  /// Kept only long enough to move it into its parent's [apps] on load.
  static ({String id, String? parentId, String appId})? appEntryFromJson(
    Object? json,
  ) {
    if (json is! Map) return null;
    final map = json.cast<String, dynamic>();
    if (map['kind'] != 'app') return null;
    final id = map['id'];
    final appId = map['appId'];
    if (id is! String || appId is! String) return null;
    return (id: id, parentId: map['parentId'] as String?, appId: appId);
  }
}
