/// The map: nodes, what they hold, and where they sit.
///
/// A node is either a place that holds other nodes, or an app. Both are the
/// same shape on the canvas, which is the point — you navigate by remembering
/// where a thing is, not by reading a list of names.
///
/// Pure Dart, so the graph rules and the geometry can be tested without a
/// device or a canvas.
library;


enum NodeKind {
  /// Holds other nodes.
  place,

  /// Launches something.
  app,
}

class MapNode {
  const MapNode({
    required this.id,
    required this.label,
    required this.kind,
    required this.x,
    required this.y,
    this.parentId,
    this.childIds = const [],
    this.colorKey = 'cyan',
    this.iconKey = 'folder',
    this.appId,
    this.placed = false,
  });

  final String id;
  final String label;
  final NodeKind kind;

  /// Position in world space — the canvas's own coordinates, not the screen's.
  final double x;
  final double y;

  final String? parentId;
  final List<String> childIds;

  final String colorKey;
  final String iconKey;

  /// For [NodeKind.app]: the launchable it stands for.
  final String? appId;

  /// Whether a person put this node here.
  ///
  /// An unplaced node is arranged automatically and re-arranged when its
  /// siblings change; a placed one is left exactly where it was dropped. The
  /// distinction is the whole of "auto-placed, then draggable".
  final bool placed;

  bool get isApp => kind == NodeKind.app;

  bool get hasChildren => childIds.isNotEmpty;

  MapNode copyWith({
    String? label,
    double? x,
    double? y,
    List<String>? childIds,
    String? colorKey,
    String? iconKey,
    bool? placed,
    String? parentId,
  }) {
    return MapNode(
      id: id,
      label: label ?? this.label,
      kind: kind,
      x: x ?? this.x,
      y: y ?? this.y,
      parentId: parentId ?? this.parentId,
      childIds: childIds ?? this.childIds,
      colorKey: colorKey ?? this.colorKey,
      iconKey: iconKey ?? this.iconKey,
      appId: appId,
      placed: placed ?? this.placed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'x': x,
        'y': y,
        if (parentId != null) 'parentId': parentId,
        'childIds': childIds,
        'colorKey': colorKey,
        'iconKey': iconKey,
        if (appId != null) 'appId': appId,
        if (placed) 'placed': true,
      };

  static MapNode? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = json.cast<String, dynamic>();
    final id = map['id'];
    if (id is! String) return null;
    final kind = map['kind'] == 'app' ? NodeKind.app : NodeKind.place;
    // An app node with nothing to launch is not a node, it is a hole.
    if (kind == NodeKind.app && map['appId'] is! String) return null;
    return MapNode(
      id: id,
      label: (map['label'] as String?) ?? id,
      kind: kind,
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
      parentId: map['parentId'] as String?,
      childIds: [
        for (final child in (map['childIds'] as List? ?? const []))
          if (child is String) child,
      ],
      colorKey: (map['colorKey'] as String?) ?? 'cyan',
      iconKey: (map['iconKey'] as String?) ?? 'folder',
      appId: map['appId'] as String?,
      placed: map['placed'] as bool? ?? false,
    );
  }
}
