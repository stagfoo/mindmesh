import 'dart:async';

import 'package:flutter/material.dart';

import 'app_cache.dart';
import 'app_icon.dart';
import 'app_picker_screen.dart';
import 'blob.dart';
import 'card_style.dart';
import 'context_graph.dart';
import 'graph_store.dart';
import 'launcher_bridge.dart';
import 'models.dart';
import 'theme.dart';
import 'usage.dart';

/// The launcher.
///
/// One context at a time: the view is whatever is inside where you are, and
/// going somewhere replaces it rather than zooming out to show the whole graph.
/// The trail along the bottom is how you get back — and because a context can
/// sit in several parents, the trail is where you walked, not a path the graph
/// could work out for you.
class ContextsScreen extends StatefulWidget {
  const ContextsScreen({super.key});

  @override
  State<ContextsScreen> createState() => _ContextsScreenState();
}

class _ContextsScreenState extends State<ContextsScreen>
    with WidgetsBindingObserver {
  final _store = GraphStore();
  final _appCache = AppCache();

  ContextGraph _graph = ContextGraph.seed();
  UsageBook _usage = const UsageBook.empty();
  Map<String, LaunchableApp> _apps = const {};

  /// Where you walked to get here. Never empty; the first entry is the root.
  List<String> _trail = [ContextGraph.rootContextId];

  bool _loading = true;
  String? _draggingKey;

  String get _hereId => _trail.last;
  ContextNode get _here =>
      _graph[_hereId] ?? _graph.root;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshApps());
  }

  Future<void> _load() async {
    try {
      final stored = await _store.load();
      final cached = await _appCache.load();
      if (!mounted) return;
      setState(() {
        _graph = stored.graph;
        _usage = stored.usage;
        _apps = _index(cached?.apps ?? const []);
        _loading = false;
      });
      await _refreshApps();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshApps() async {
    try {
      final apps = await LauncherBridge.instance.listApps();
      if (!mounted) return;
      setState(() => _apps = _index(apps));
      await _appCache.save(apps);
    } catch (_) {
      // A refresh that fails leaves the last list in place, which beats an
      // empty launcher.
    }
  }

  static Map<String, LaunchableApp> _index(List<LaunchableApp> apps) =>
      {for (final app in apps) app.id: app};

  Future<void> _save() => _store.save(_graph, _usage);

  Future<void> _update(ContextGraph graph, {UsageBook? usage}) async {
    setState(() {
      _graph = graph;
      if (usage != null) _usage = usage;
      _trail = _walkable(_trail, graph);
    });
    await _save();
  }

  /// The trail, minus anything that has since been deleted.
  ///
  /// Cut at the first missing step rather than closing the gap: the steps after
  /// it were reached *through* it, and a trail that quietly re-links them would
  /// claim a route that no longer exists.
  static List<String> _walkable(List<String> trail, ContextGraph graph) {
    final kept = <String>[ContextGraph.rootContextId];
    for (final id in trail.skip(1)) {
      if (graph[id] == null) break;
      kept.add(id);
    }
    return kept;
  }

  // ---------------------------------------------------------------- navigate

  /// Steps into a context, counting the open against this parent's edge.
  void _enter(Edge edge) {
    final id = edge.child.id;
    if (_graph[id] == null) return;
    setState(() {
      _usage = _usage.opened(edge.key, DateTime.now());
      _trail = [..._trail, id];
    });
    unawaited(_save());
  }

  void _goBack() {
    if (_trail.length <= 1) return;
    setState(() => _trail = _trail.sublist(0, _trail.length - 1));
  }

  /// Jumps to a point on the trail, keeping the walk that got you there.
  void _goTo(int index) {
    if (index < 0 || index >= _trail.length - 1) return;
    setState(() => _trail = _trail.sublist(0, index + 1));
  }

  void _launch(String appId) {
    final app = _apps[appId];
    if (app == null) {
      _toast('Not installed any more');
      return;
    }
    LauncherBridge.instance.open(app);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: MeshColors.text,
        content: Text(message,
            style: meshText(size: 12, color: MeshColors.strip)),
      ),
    );
  }

  // ------------------------------------------------------------------ edits

  Future<void> _addContext() async {
    final name = await _askForName('New context', '');
    if (name == null || name.isEmpty) return;
    final existing = _graph.childrenOf(_hereId).length;
    final spot = freeSpot(existing);
    final id = 'ctx-${DateTime.now().microsecondsSinceEpoch}';
    await _update(
      _graph
          .addContext(ContextNode(
            id: id,
            label: name,
            colorKey: paletteAt(existing).key,
          ))
          .link(_hereId, ChildRef.context(id), x: spot.x, y: spot.y),
    );
  }

  Future<void> _addApps() async {
    final here = _hereId;
    final chosen = await showAppPicker(
      context,
      placeName: _here.label,
      accent: colorOf(_here.colorKey),
      installed: _apps.values.toList(),
      alreadyHere: {
        for (final edge in _graph.childrenOf(here))
          if (edge.child.isApp) edge.child.id,
      },
      alsoIn: _appsElsewhere(exclude: here),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    var graph = _graph;
    var placed = graph.childrenOf(here).length;
    for (final appId in chosen) {
      final spot = freeSpot(placed++);
      graph = graph.link(here, ChildRef.app(appId), x: spot.x, y: spot.y);
    }
    await _update(graph);
  }

  /// Contexts a context could be put into, other than the ones it is in.
  Future<void> _addExisting() async {
    final here = _hereId;
    final already = {
      for (final edge in _graph.childrenOf(here))
        if (!edge.child.isApp) edge.child.id,
    };
    final options = [
      for (final node in _graph.contexts.values)
        if (node.id != here &&
            !already.contains(node.id) &&
            !_graph.wouldLoop(here, node.id))
          node,
    ];
    if (options.isEmpty) {
      _toast('Nothing else to put here yet');
      return;
    }

    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MeshColors.strip,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'The same context, not a copy — edits show up everywhere it is.',
                style: meshText(size: 11, color: MeshColors.textDim),
              ),
            ),
            for (final node in options)
              ListTile(
                leading: _Swatch(colour: colorOf(node.colorKey)),
                title: Text(node.label, style: meshText(size: 14)),
                subtitle: Text(
                  _whereElse(_graph.parentsOf(node.id)),
                  style: meshText(size: 11, color: MeshColors.textDim),
                ),
                onTap: () => Navigator.pop(context, node.id),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    final spot = freeSpot(_graph.childrenOf(here).length);
    await _update(
      _graph.link(here, ChildRef.context(chosen), x: spot.x, y: spot.y),
    );
  }

  Map<String, List<String>> _appsElsewhere({required String exclude}) {
    final byApp = <String, List<String>>{};
    for (final edge in _graph.edges.values) {
      if (!edge.child.isApp || edge.parentId == exclude) continue;
      final parent = _graph[edge.parentId];
      if (parent == null) continue;
      byApp.putIfAbsent(edge.child.id, () => []).add(parent.label);
    }
    return byApp;
  }

  static String _whereElse(List<ContextNode> parents) => parents.isEmpty
      ? 'Not in anything yet'
      : 'In ${parents.map((p) => p.label).join(', ')}';

  Future<void> _showAddSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MeshColors.strip,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.blur_on_rounded,
                  color: MeshColors.textDim),
              title: Text('New context', style: meshText(size: 14)),
              subtitle: Text('Somewhere else to go from ${_here.label}',
                  style: meshText(size: 11, color: MeshColors.textDim)),
              onTap: () => Navigator.pop(context, 'context'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.apps_rounded, color: MeshColors.textDim),
              title: Text('Add apps', style: meshText(size: 14)),
              subtitle: Text('Put them in ${_here.label}',
                  style: meshText(size: 11, color: MeshColors.textDim)),
              onTap: () => Navigator.pop(context, 'apps'),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded,
                  color: MeshColors.textDim),
              title: Text('Put an existing context here',
                  style: meshText(size: 14)),
              subtitle: Text('The same one, in two places at once',
                  style: meshText(size: 11, color: MeshColors.textDim)),
              onTap: () => Navigator.pop(context, 'existing'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'context':
        await _addContext();
      case 'apps':
        await _addApps();
      case 'existing':
        await _addExisting();
    }
  }

  Future<void> _held(Edge edge) async {
    final node = edge.child.isApp ? null : _graph[edge.child.id];
    final app = edge.child.isApp ? _apps[edge.child.id] : null;
    final elsewhere = edge.child.isApp
        ? _graph.holdersOf(edge.child.id)
        : _graph.parentsOf(edge.child.id);
    final others = elsewhere.where((p) => p.id != edge.parentId).toList();

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MeshColors.strip,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(node?.label ?? app?.label ?? edge.child.id,
                  style: meshText(size: 15, weight: 600)),
              subtitle: Text(
                others.isEmpty
                    ? 'Only in ${_here.label}'
                    : 'Also in ${others.map((p) => p.label).join(', ')}',
                style: meshText(size: 11, color: MeshColors.textDim),
              ),
            ),
            const Divider(height: 1, color: MeshColors.surfaceEdge),
            if (node != null) ...[
              ListTile(
                leading: const Icon(Icons.edit_rounded,
                    color: MeshColors.textDim),
                title: Text('Rename', style: meshText(size: 14)),
                subtitle: Text('Everywhere it appears',
                    style: meshText(size: 11, color: MeshColors.textDim)),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              ListTile(
                leading: const Icon(Icons.palette_rounded,
                    color: MeshColors.textDim),
                title: Text('Colour', style: meshText(size: 14)),
                onTap: () => Navigator.pop(context, 'colour'),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.remove_circle_outline_rounded,
                  color: Color(0xFFC7503F)),
              title: Text('Take out of ${_here.label}',
                  style: meshText(size: 14)),
              subtitle: Text(
                others.isEmpty
                    ? 'From the launcher, not from the phone'
                    : 'It stays in the other contexts',
                style: meshText(size: 11, color: MeshColors.textDim),
              ),
              onTap: () => Navigator.pop(context, 'unlink'),
            ),
            if (node != null && others.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFC7503F)),
                title: Text('Delete everywhere', style: meshText(size: 14)),
                subtitle: Text(
                  'From all ${others.length + 1} contexts it is in',
                  style: meshText(size: 11, color: MeshColors.textDim),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case 'rename':
        final name = await _askForName('Rename', node!.label);
        if (name == null || name.isEmpty || !mounted) return;
        await _update(_graph.replaceContext(node.copyWith(label: name)));
      case 'colour':
        final key = await _askForColour(node!.colorKey);
        if (key == null || !mounted) return;
        await _update(_graph.replaceContext(node.copyWith(colorKey: key)));
      case 'unlink':
        await _update(_graph.unlink(edge.parentId, edge.child));
      case 'delete':
        await _update(_graph.removeContext(edge.child.id));
    }
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
          style: meshText(size: 15),
          decoration: InputDecoration(
            hintText: 'gym, morning, wind down',
            hintStyle: meshText(size: 14, color: MeshColors.textDim),
          ),
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
            child: Text('Save', style: meshText(size: 13, weight: 600)),
          ),
        ],
      ),
    );
  }

  Future<String?> _askForColour(String current) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: MeshColors.strip,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final colour in cardPalette)
                GestureDetector(
                  onTap: () => Navigator.pop(context, colour.key),
                  child: _Swatch(
                    colour: Color(colour.value),
                    selected: colour.key == current,
                    size: 44,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: MeshColors.ground,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF4F00)),
                )
              : Column(
                  children: [
                    _header(),
                    Expanded(child: _field()),
                    _trailBar(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: _trail.length > 1
                ? IconButton(
                    onPressed: _goBack,
                    icon: const Icon(Icons.arrow_back_rounded,
                        size: 20, color: MeshColors.text),
                  )
                : null,
          ),
          Expanded(
            child: Text(
              _here.label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: meshText(size: 15, weight: 600, letterSpacing: 0.4),
            ),
          ),
          SizedBox(
            width: 48,
            child: IconButton(
              onPressed: _showAddSheet,
              icon: const Icon(Icons.add_rounded,
                  size: 22, color: MeshColors.text),
            ),
          ),
        ],
      ),
    );
  }

  /// Everything inside where you are, where you put it.
  Widget _field() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final children = _graph.childrenOf(_hereId);
        if (children.isEmpty) return _empty();

        final now = DateTime.now();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final edge in children)
              _placed(edge, constraints.biggest, now),
          ],
        );
      },
    );
  }

  Widget _placed(Edge edge, Size field, DateTime now) {
    final isApp = edge.child.isApp;
    final size = isApp
        ? UsageStyle.standard.baseSize * 0.72
        : _usage.sizeAt(edge.key, now);
    final node = isApp ? null : _graph[edge.child.id];
    final shared = isApp
        ? _graph.holdersOf(edge.child.id).length > 1
        : _graph.parentsOf(edge.child.id).length > 1;

    // Kept inside the view by its own half-width, so a circle can be dropped
    // near an edge without half of it becoming unreachable.
    final half = size / 2;
    final left = (edge.x * field.width).clamp(half, field.width - half) - half;
    final top = (edge.y * field.height).clamp(half, field.height - half) - half;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => isApp ? _launch(edge.child.id) : _enter(edge),
        onLongPress: () => _held(edge),
        onPanStart: (_) => setState(() => _draggingKey = edge.key),
        onPanUpdate: (details) =>
            _drag(edge.parentId, edge.child, details.delta, field),
        onPanEnd: (_) => _endDrag(),
        onPanCancel: _endDrag,
        child: isApp
            ? _AppDot(
                appId: edge.child.id,
                app: _apps[edge.child.id],
                size: size,
                shared: shared,
              )
            : Blob(
                label: node?.label ?? '',
                colour: colorOf(node?.colorKey ?? 'cyan'),
                size: size,
                shared: shared,
                dragging: _draggingKey == edge.key,
              ),
      ),
    );
  }

  /// Reads the live position rather than the one captured when the frame was
  /// built, so a drag accumulates instead of snapping back to where it started.
  void _drag(String parentId, ChildRef child, Offset delta, Size field) {
    if (field.isEmpty) return;
    final edge = _graph.edges[edgeKey(parentId, child)];
    if (edge == null) return;
    setState(() {
      _graph = _graph.moveChild(
        parentId,
        child,
        edge.x + delta.dx / field.width,
        edge.y + delta.dy / field.height,
      );
    });
  }

  void _endDrag() {
    if (_draggingKey == null) return;
    setState(() => _draggingKey = null);
    unawaited(_save());
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nothing in ${_here.label} yet',
              textAlign: TextAlign.center,
              style: meshText(size: 13, color: MeshColors.textDim),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: _showAddSheet,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text('Put something here', style: meshText(size: 13)),
            ),
          ],
        ),
      ),
    );
  }

  /// Where you walked, not a path the graph could work out.
  ///
  /// A context with several parents has several paths to it, so the only
  /// honest trail is the one you actually took.
  Widget _trailBar() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.centerLeft,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        children: [
          for (var i = _trail.length - 1; i >= 0; i--) ...[
            GestureDetector(
              onTap: () => _goTo(i),
              child: Center(
                child: Text(
                  _graph[_trail[i]]?.label ?? '—',
                  style: meshText(
                    size: 12,
                    weight: i == _trail.length - 1 ? 600 : 400,
                    letterSpacing: 0.6,
                    color: i == _trail.length - 1
                        ? MeshColors.text
                        : MeshColors.textDim,
                  ),
                ),
              ),
            ),
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Center(
                  child: Text('>',
                      style:
                          meshText(size: 11, color: MeshColors.textDim)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// An app, inside a context. A plain icon: apps are the bottom of the model,
/// and drawing one as a cloud would say it holds things when it does not.
class _AppDot extends StatelessWidget {
  const _AppDot({
    required this.appId,
    required this.app,
    required this.size,
    this.shared = false,
  });

  final String appId;
  final LaunchableApp? app;
  final double size;
  final bool shared;

  @override
  Widget build(BuildContext context) {
    final installed = app;
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (installed == null)
            Container(
              width: size * 0.62,
              height: size * 0.62,
              decoration: BoxDecoration(
                color: MeshColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.help_outline_rounded,
                  size: 20, color: MeshColors.textDim),
            )
          else
            AppIconImage(app: installed, size: size * 0.62),
          const SizedBox(height: 5),
          Text(
            installed?.label ?? appId.split('/').first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: meshText(
              size: 9,
              letterSpacing: 0.3,
              color: MeshColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colour,
    this.selected = false,
    this.size = 26,
  });

  final Color colour;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.75),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? MeshColors.text : Colors.transparent,
          width: 2,
        ),
      ),
    );
  }
}
