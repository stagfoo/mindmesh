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
import 'place_apps.dart';
import 'world.dart';
import 'radial_layout.dart';
import 'theme.dart';

/// The map.
///
/// One canvas the whole way down: tapping a place flies the camera to it and
/// opens what it holds, rather than pushing a screen — so zooming out always
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

  /// The place whose apps are open over the canvas, if any.
  String? _openId;

  MapNode? get _openPlace {
    final id = _openId;
    return id == null ? null : _map[id];
  }
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

  /// Flies the camera to [id], keeping the same scale it always travels at.
  ///
  /// Deliberately not a fit-to-contents frame. Framing a place and everything
  /// under it means the camera pulls further back the more you put in the map,
  /// until it is showing the whole tree at once — and once you can see
  /// everything, going somewhere is not going anywhere. A fixed scale keeps
  /// moving feeling like moving; what does not fit is off screen, which is
  /// what being somewhere means.
  void _focusOn(String id, {bool animate = true}) {
    final node = _map[id];
    if (node == null || _viewport.isEmpty) return;

    // Centred in canvas coordinates, because that is where the nodes are
    // actually drawn — aiming at their own coordinates aims the camera half a
    // world away from the map.
    final here = toCanvas((x: node.x, y: node.y));
    final view = centreOn(
      x: here.x,
      y: here.y,
      viewportWidth: _viewport.width,
      viewportHeight: _viewport.height,
      scale: CameraStyle.standard.travelScale,
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

  /// Arriving at a place: move to it, and open what it holds.
  ///
  /// Tapping the place you are already at closes the panel again, so the map
  /// underneath is never something you have to hunt for a way back to.
  void _onNodeTapped(MapNode node) {
    if (node.id == _focusId && _openId == node.id) {
      setState(() => _openId = null);
      return;
    }
    setState(() => _openId = node.apps.isEmpty ? null : node.id);
    _focusOn(node.id);
  }

  void _launch(String appId) {
    final app = _apps[appId];
    if (app == null) {
      _toast('Not installed any more');
      return;
    }
    LauncherBridge.instance.open(app);
  }

  Future<void> _appHeld(MapNode place, String appId) async {
    final app = _apps[appId];
    final elsewhere = _map.placesWith(appId).where((p) => p.id != place.id);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MeshColors.strip,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(app?.label ?? appId,
                  style: meshText(size: 15, weight: 600)),
              subtitle: Text(
                elsewhere.isEmpty
                    ? 'Only in ${place.label}'
                    : 'Also in ${elsewhere.map((p) => p.label).join(', ')}',
                style: meshText(size: 11, color: MeshColors.textDim),
              ),
            ),
            const Divider(height: 1, color: MeshColors.surfaceEdge),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline_rounded,
                  color: Color(0xFFFF6B5A)),
              title: Text('Take out of ${place.label}',
                  style: meshText(size: 14)),
              subtitle: Text(
                elsewhere.isEmpty
                    ? 'From the map, not from the phone'
                    : 'It stays in the other places',
                style: meshText(size: 11, color: MeshColors.textDim),
              ),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice != 'remove') return;
    await _update(_map.removeApp(place.id, appId));
  }

  /// What a place holds, for the line under its name in the menu.
  static String _inside(MapNode node) {
    final parts = [
      if (node.apps.isNotEmpty)
        '${node.apps.length} app${node.apps.length == 1 ? '' : 's'}',
      if (node.childIds.isNotEmpty) '${node.childIds.length} inside',
    ];
    return parts.isEmpty ? 'Empty' : parts.join(' · ');
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
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(child: _canvas()),
                          // Over the canvas at a fixed size, not on it: the
                          // apps are what you came here to press, so they stay
                          // readable however far out the map is zoomed.
                          if (_openPlace != null)
                            Positioned.fill(
                              child: _AppsOverlay(
                                onDismiss: () =>
                                    setState(() => _openId = null),
                                child: PlaceApps(
                                  place: _openPlace!,
                                  apps: _apps,
                                  onLaunch: _launch,
                                  onHold: (appId) =>
                                      _appHeld(_openPlace!, appId),
                                  onAdd: () => _addApps(_openPlace!),
                                  onClose: () =>
                                      setState(() => _openId = null),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
                      apps: _apps,
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
  ///
  /// The only thing that zooms out, deliberately: pulling back is something you
  /// ask for, not something that happens to you because the map grew.
  void _showEverything() {
    if (_viewport.isEmpty) return;
    final region = boundsOf(
      [for (final node in _map.nodes.values) toCanvas((x: node.x, y: node.y))],
    );
    final view = frame(
      region: region,
      viewportWidth: _viewport.width,
      viewportHeight: _viewport.height,
    );
    setState(() {
      _focusId = NodeMap.rootNodeId;
      _openId = null;
    });
    _controller.value = Matrix4.identity()
      ..translateByDouble(view.offsetX, view.offsetY, 0, 1)
      ..scaleByDouble(view.scale, view.scale, 1, 1);
  }

  Future<void> _addTo(String parentId) async {
    final parent = _map[parentId];
    if (parent == null) return;

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
              subtitle: Text('Put them in ${parent.label}',
                  style: meshText(size: 11, color: MeshColors.textDim)),
              onTap: () => Navigator.pop(context, 'apps'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.hub_rounded, color: MeshColors.textDim),
              title: Text('Add a place', style: meshText(size: 14)),
              subtitle: Text('Somewhere else to go from ${parent.label}',
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
    final chosen = await showAppPicker(
      context,
      placeName: parent.label,
      accent: colorOf(parent.colorKey),
      installed: _apps.values.toList(),
      alreadyHere: parent.apps.toSet(),
      alsoIn: _placesByApp(exclude: parent.id),
    );
    if (chosen == null || chosen.isEmpty) return;

    await _update(_map.addApps(parent.id, chosen));
    if (!mounted) return;
    setState(() => _openId = parent.id);
    _focusOn(parent.id);
  }

  /// Which places each app already sits in.
  ///
  /// The same app belonging to several situations is the point, so this is
  /// shown when picking rather than used to rule anything out.
  Map<String, List<String>> _placesByApp({required String exclude}) {
    final byApp = <String, List<String>>{};
    for (final node in _map.nodes.values) {
      if (node.id == exclude) continue;
      for (final appId in node.apps) {
        byApp.putIfAbsent(appId, () => []).add(node.label);
      }
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
                _inside(node),
                style: meshText(size: 11, color: MeshColors.textDim),
              ),
            ),
            const Divider(height: 1, color: MeshColors.surfaceEdge),
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
                  node.isEmpty
                      ? 'From the map, not from the phone'
                      : 'And everything inside it',
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

/// The dimmed ground behind an open place, so tapping away closes it.
///
/// Aligned to the bottom rather than centred: it is a launcher, and the row you
/// are reaching for should be near the thumb, not in the middle of the screen.
class _AppsOverlay extends StatelessWidget {
  const _AppsOverlay({required this.child, required this.onDismiss});

  final Widget child;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Color(0x99000000)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: child,
          ),
        ),
      ],
    );
  }
}
