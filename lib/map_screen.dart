import 'dart:async';

import 'package:flutter/material.dart';

import 'app_cache.dart';
import 'camera.dart';
import 'launcher_bridge.dart';
import 'map_store.dart';
import 'models.dart';
import 'node.dart';
import 'node_map.dart';
import 'app_picker_screen.dart';
import 'card_style.dart';
import 'node_view.dart';
import 'world.dart';
import 'radial_layout.dart';
import 'theme.dart';

/// The map.
///
/// One canvas the whole way down: tapping a place flies the camera to it and
/// frames its children rather than pushing a screen, so zooming out always
/// shows where you have been.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _store = MapStore();
  final _appCache = AppCache();
  final _controller = TransformationController();

  NodeMap _map = NodeMap.seed();
  Map<String, LaunchableApp> _apps = const {};
  String _focusId = NodeMap.rootNodeId;
  bool _loading = true;
  Size _viewport = Size.zero;

  /// The shape of the screen the map is being laid out on, so a ring of
  /// children fills a tall phone rather than sitting in a small circle in the
  /// middle of it. Falls back to the device's own view before first layout,
  /// which is when a fresh map gets seeded.
  double get _aspect {
    if (!_viewport.isEmpty) return _viewport.width / _viewport.height;
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null || view.physicalSize.height <= 0) return 1;
    return view.physicalSize.width / view.physicalSize.height;
  }
  String? _draggingId;
  ({double x, double y})? _dragOrigin;
  Animation<Matrix4>? _flight;
  AnimationController? _flightController;
  StreamSubscription<String>? _packageSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _packageSub =
        LauncherBridge.instance.packageChanges.listen((_) => _refreshApps());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _packageSub?.cancel();
    _flightController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshApps();
  }

  Future<void> _load() async {
    final map = await _store.load(aspect: _aspect);
    final cached = await _appCache.load();
    if (!mounted) return;
    setState(() {
      _map = map;
      if (cached != null) _apps = _index(cached.apps);
      _loading = false;
    });

    try {
      final apps = await LauncherBridge.instance.listEverything();
      if (!mounted) return;
      setState(() => _apps = _index(apps));
      await _appCache.save(apps);
    } catch (e) {
      if (mounted) _toast('Could not read the app list: $e');
    }
  }

  Future<void> _refreshApps() async {
    try {
      final apps = await LauncherBridge.instance.listEverything();
      if (!mounted) return;
      setState(() => _apps = _index(apps));
      await _appCache.save(apps);
    } catch (_) {
      // A refresh that fails leaves the last list in place, which is better
      // than an empty map.
    }
  }

  static Map<String, LaunchableApp> _index(List<LaunchableApp> apps) =>
      {for (final app in apps) app.id: app};

  Future<void> _update(NodeMap map) async {
    setState(() => _map = map);
    await _store.save(map);
  }

  /// Flies the camera so [id] and its children fill the screen.
  void _focusOn(String id, {bool animate = true}) {
    final node = _map[id];
    if (node == null || _viewport.isEmpty) return;

    final children = _map.childrenOf(id);
    // Framed in canvas coordinates, because that is where the nodes are
    // actually drawn — framing them at their own coordinates aims the camera
    // half a world away from the map.
    final here = toCanvas((x: node.x, y: node.y));
    final view = children.isEmpty
        ? centreOn(
            x: here.x,
            y: here.y,
            viewportWidth: _viewport.width,
            viewportHeight: _viewport.height,
            scale: 1.1,
          )
        : frame(
            // The parent is included so you can see what you came from — a
            // frame of only the children loses the thing they belong to.
            region: boundsOf([
              here,
              for (final child in children)
                toCanvas((x: child.x, y: child.y)),
            ]),
            viewportWidth: _viewport.width,
            viewportHeight: _viewport.height,
          );

    final target = Matrix4.identity()
      ..translateByDouble(view.offsetX, view.offsetY, 0, 1)
      ..scaleByDouble(view.scale, view.scale, 1, 1);

    setState(() => _focusId = id);
    if (!animate) {
      _controller.value = target;
      return;
    }

    _flightController?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _flightController = controller;
    _flight = Matrix4Tween(begin: _controller.value, end: target)
        .animate(CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic));
    _flight!.addListener(() => _controller.value = _flight!.value);
    controller.forward();
  }

  /// Moves a node under the finger.
  ///
  /// The drag arrives in screen pixels and the map is in world ones, so it is
  /// divided by the current zoom — without that a node would race away from
  /// the finger when zoomed out and crawl when zoomed in.
  void _dragNode(String id, Offset offset) {
    final origin = _dragOrigin;
    if (origin == null) return;
    final scale = _controller.value.getMaxScaleOnAxis();
    setState(() {
      _map = _map.moveTo(
        id,
        origin.x + offset.dx / scale,
        origin.y + offset.dy / scale,
      );
    });
  }

  void _endDrag() {
    if (_draggingId == null) return;
    final map = _map;
    setState(() {
      _draggingId = null;
      _dragOrigin = null;
    });
    unawaited(_store.save(map));
  }

  void _onNodeTapped(MapNode node) {
    if (node.isApp) {
      final app = _apps[node.appId];
      if (app == null) {
        _toast('${node.label} is not installed');
        return;
      }
      LauncherBridge.instance.open(app);
      return;
    }
    _focusOn(node.id);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: MeshColors.surface,
        content: Text(message, style: meshText(size: 12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: MeshColors.ground,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF4F00)),
                )
              : Column(
                  children: [
                    Expanded(child: _canvas()),
                    _breadcrumb(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _canvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size != _viewport) {
          _viewport = size;
          // First real layout: frame the root rather than leaving the map at
          // whatever the identity transform happens to show.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focusOn(_focusId, animate: false);
          });
        }

        final nodes = _map.nodes.values.toList();
        final edges = [
          for (final node in nodes)
            for (final child in _map.childrenOf(node.id))
              (
                x1: node.x,
                y1: node.y,
                x2: child.x,
                y2: child.y,
                colorKey: node.colorKey,
              ),
        ];

        return InteractiveViewer(
          transformationController: _controller,
          minScale: CameraStyle.standard.minScale,
          maxScale: CameraStyle.standard.maxScale,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(worldExtent),
          child: SizedBox(
            width: worldExtent,
            height: worldExtent,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: EdgePainter(
                      edges: [
                        for (final edge in edges)
                          (
                            x1: edge.x1 + worldOrigin,
                            y1: edge.y1 + worldOrigin,
                            x2: edge.x2 + worldOrigin,
                            y2: edge.y2 + worldOrigin,
                            colorKey: edge.colorKey,
                          ),
                      ],
                      colours: {
                        for (final node in nodes)
                          node.colorKey: colorOf(node.colorKey),
                      },
                    ),
                  ),
                ),
                for (final node in nodes)
                  Positioned(
                    left: node.x + worldOrigin - MeshMetrics.nodeSize / 2,
                    top: node.y + worldOrigin - MeshMetrics.nodeSize / 2,
                    child: NodeView(
                      key: ValueKey(node.id),
                      node: node,
                      app: node.appId == null ? null : _apps[node.appId],
                      focused: node.id == _focusId,
                      childCount: node.childIds.length,
                      dragging: node.id == _draggingId,
                      onTap: () => _onNodeTapped(node),
                      onLongPress: () => _showNodeMenu(node),
                      onDragStart: () => setState(() {
                        _draggingId = node.id;
                        _dragOrigin = (x: node.x, y: node.y);
                      }),
                      onDragBy: (offset) => _dragNode(node.id, offset),
                      onDragEnd: () => _endDrag(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Where you are, and the way back up.
  Widget _breadcrumb() {
    final path = _map.pathTo(_focusId);
    return SizedBox(
      height: MeshMetrics.actionsHeight,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (var i = 0; i < path.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(Icons.chevron_right_rounded,
                          size: 14, color: MeshColors.textDim),
                    ),
                  GestureDetector(
                    onTap: () => _focusOn(path[i].id),
                    child: Center(
                      child: Text(
                        path[i].label,
                        style: meshText(
                          size: 12,
                          weight: i == path.length - 1 ? 600 : 400,
                          color: i == path.length - 1
                              ? colorOf(path[i].colorKey)
                              : MeshColors.textDim,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Add here',
            onPressed: () => _addTo(_focusId),
            icon: const Icon(Icons.add_rounded,
                size: 20, color: MeshColors.textDim),
          ),
          IconButton(
            tooltip: 'Whole map',
            onPressed: _showEverything,
            icon: const Icon(Icons.fullscreen_rounded,
                size: 20, color: MeshColors.textDim),
          ),
        ],
      ),
    );
  }

  /// Frames every node at once, which is the answer to "where am I".
  void _showEverything() {
    if (_viewport.isEmpty) return;
    final region = boundsOf(
      [for (final node in _map.nodes.values) (x: node.x, y: node.y)],
    );
    final view = frame(
      region: region,
      viewportWidth: _viewport.width,
      viewportHeight: _viewport.height,
    );
    setState(() => _focusId = NodeMap.rootNodeId);
    _controller.value = Matrix4.identity()
      ..translateByDouble(view.offsetX, view.offsetY, 0, 1)
      ..scaleByDouble(view.scale, view.scale, 1, 1);
  }

  Future<void> _addTo(String parentId) async {
    final parent = _map[parentId];
    if (parent == null || parent.isApp) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MeshColors.strip,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.apps_rounded, color: MeshColors.textDim),
              title: Text('Add apps', style: meshText(size: 14)),
              subtitle: Text('They become nodes around ${parent.label}',
                  style: meshText(size: 11, color: MeshColors.textDim)),
              onTap: () => Navigator.pop(context, 'apps'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.hub_rounded, color: MeshColors.textDim),
              title: Text('Add a place', style: meshText(size: 14)),
              subtitle: Text('A node that holds more nodes',
                  style: meshText(size: 11, color: MeshColors.textDim)),
              onTap: () => Navigator.pop(context, 'place'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == 'place') {
      await _addPlace(parent);
    } else {
      await _addApps(parent);
    }
  }

  Future<void> _addApps(MapNode parent) async {
    final here = {
      for (final child in _map.childrenOf(parent.id))
        if (child.appId != null) child.appId!,
    };
    final chosen = await showAppPicker(
      context,
      placeName: parent.label,
      accent: colorOf(parent.colorKey),
      installed: _apps.values.toList(),
      alreadyHere: here,
      alsoIn: _placesByApp(exclude: parent.id),
    );
    if (chosen == null || chosen.isEmpty) return;

    var map = _map;
    for (final appId in chosen) {
      final app = _apps[appId];
      if (app == null) continue;
      map = map.addChild(
        parent.id,
        MapNode(
          id: 'node-${DateTime.now().microsecondsSinceEpoch}-$appId',
          label: app.label,
          kind: NodeKind.app,
          x: parent.x,
          y: parent.y,
          appId: appId,
          colorKey: parent.colorKey,
        ),
        aspect: _aspect,
      );
    }
    await _update(map);
    _focusOn(parent.id);
  }

  /// Which places each app already sits in.
  ///
  /// The same app belonging to several situations is the point, so this is
  /// shown when picking rather than used to rule anything out.
  Map<String, List<String>> _placesByApp({required String exclude}) {
    final byApp = <String, List<String>>{};
    for (final node in _map.nodes.values) {
      final appId = node.appId;
      final parentId = node.parentId;
      if (appId == null || parentId == null || parentId == exclude) continue;
      final place = _map[parentId];
      if (place == null) continue;
      byApp.putIfAbsent(appId, () => []).add(place.label);
    }
    return byApp;
  }

  Future<void> _addPlace(MapNode parent) async {
    final name = await _askForName('New place', '');
    if (name == null || name.isEmpty) return;
    final index = _map.childrenOf(parent.id).length;
    final map = _map.addChild(
      parent.id,
      MapNode(
        id: 'place-${DateTime.now().microsecondsSinceEpoch}',
        label: name,
        kind: NodeKind.place,
        x: parent.x,
        y: parent.y,
        colorKey: paletteAt(index).key,
        iconKey: 'folder',
      ),
      aspect: _aspect,
    );
    await _update(map);
    _focusOn(parent.id);
  }

  Future<String?> _askForName(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MeshColors.strip,
        title: Text(title, style: meshText(size: 16, weight: 600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: meshText(size: 14),
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: meshText(size: 13, color: MeshColors.textDim)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: Text('Done', style: meshText(size: 13, weight: 600)),
          ),
        ],
      ),
    );
  }

  Future<void> _showNodeMenu(MapNode node) async {
    final isRoot = node.id == NodeMap.rootNodeId;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MeshColors.strip,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(node.label, style: meshText(size: 15, weight: 600)),
              subtitle: Text(
                node.isApp ? 'App' : '${node.childIds.length} inside',
                style: meshText(size: 11, color: MeshColors.textDim),
              ),
            ),
            const Divider(height: 1, color: MeshColors.surfaceEdge),
            if (!node.isApp)
              ListTile(
                leading:
                    const Icon(Icons.add_rounded, color: MeshColors.textDim),
                title: Text('Add here', style: meshText(size: 14)),
                onTap: () => Navigator.pop(context, 'add'),
              ),
            ListTile(
              leading:
                  const Icon(Icons.edit_rounded, color: MeshColors.textDim),
              title: Text('Rename', style: meshText(size: 14)),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            if (node.placed)
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded,
                    color: MeshColors.textDim),
                title: Text('Put it back', style: meshText(size: 14)),
                subtitle: Text('Let it arrange itself again',
                    style: meshText(size: 11, color: MeshColors.textDim)),
                onTap: () => Navigator.pop(context, 'unplace'),
              ),
            if (!isRoot)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF6B5A)),
                title: Text('Remove', style: meshText(size: 14)),
                subtitle: Text(
                  node.hasChildren
                      ? 'And everything inside it'
                      : 'From the map, not from the phone',
                  style: meshText(size: 11, color: MeshColors.textDim),
                ),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'add':
        await _addTo(node.id);
      case 'rename':
        final name = await _askForName('Rename', node.label);
        if (name != null && name.isNotEmpty) {
          await _update(_map.replace(node.copyWith(label: name)));
        }
      case 'unplace':
        final parentId = node.parentId;
        await _update(
          _map
              .replace(node.copyWith(placed: false))
              .arrangeChildrenOf(
                parentId ?? NodeMap.rootNodeId,
                aspect: _aspect,
              ),
        );
      case 'remove':
        final parentId = node.parentId ?? NodeMap.rootNodeId;
        await _update(_map.remove(node.id));
        _focusOn(parentId);
    }
  }
}
