import 'dart:async';

import 'package:flutter/material.dart';

import 'app_cache.dart';
import 'app_icon.dart';
import 'app_picker_screen.dart';
import 'blob.dart';
import 'card_style.dart';
import 'context_graph.dart';
import 'grain.dart';
import 'graph_store.dart';
import 'launcher_bridge.dart';
import 'models.dart';
import 'saved_shortcuts.dart';
import 'theme.dart';
import 'usage.dart';
import 'widget_view.dart';

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
  final _shortcuts = SavedShortcutStore();

  ContextGraph _graph = ContextGraph.seed();
  UsageBook _usage = const UsageBook.empty();
  Map<String, LaunchableApp> _apps = const {};

  /// Where you walked to get here. Never empty; the first entry is the root.
  List<String> _trail = [ContextGraph.rootContextId];

  bool _loading = true;
  String? _draggingKey;

  /// What each placed widget currently is, by appWidgetId. Re-read on resume:
  /// the app behind a widget can be uninstalled while the launcher is away.
  Map<int, PlacedWidget> _widgets = const {};

  Size _viewport = Size.zero;

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
    if (state != AppLifecycleState.resumed) return;
    // Both on resume, because "add to home screen" hands the shortcut over
    // while another app is in front and this one may have been destroyed
    // behind it — the result is written down on the Android side and collected
    // here whenever the launcher comes back, however long that took.
    unawaited(_collectShortcuts());
    unawaited(_refreshWidgets());
    unawaited(_refreshApps());
  }

  Future<void> _load() async {
    try {
      final stored = await _store.load();
      final cached = await _appCache.load();
      if (!mounted) return;
      final saved = await _shortcuts.load();
      if (!mounted) return;
      setState(() {
        _graph = stored.graph;
        _usage = stored.usage;
        _apps = {
          ..._index(cached?.apps ?? const []),
          for (final shortcut in saved) shortcut.app.id: shortcut.app,
        };
        _loading = false;
      });
      await _collectShortcuts();
      await _refreshWidgets();
      await _refreshApps();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Picks up shortcuts pinned since the last look and puts them where you
  /// were when you asked for them.
  ///
  /// Landing them in the context you were in is the whole difference between a
  /// shortcut arriving somewhere and a shortcut disappearing into a drawer.
  Future<void> _collectShortcuts() async {
    List<StoredShortcutRecord> pending;
    try {
      pending = await LauncherBridge.instance.takePendingShortcuts();
    } catch (_) {
      return;
    }
    if (pending.isEmpty || !mounted) return;

    final arrived = <LaunchableApp>[];
    for (final record in pending) {
      final app = record.toApp();
      if (app == null) continue;
      await _shortcuts.add(StoredShortcut(app: app, icon: record.icon));
      arrived.add(app);
    }
    if (arrived.isEmpty || !mounted) return;

    final here = _hereId;
    var graph = _graph;
    var placed = graph.childrenOf(here).length;
    for (final app in arrived) {
      final spot = freeSpot(placed++);
      graph = graph.link(here, ChildRef.app(app.id), x: spot.x, y: spot.y);
    }

    setState(() {
      _apps = {..._apps, for (final app in arrived) app.id: app};
    });
    await _update(graph);
    if (!mounted) return;
    _toast(arrived.length == 1
        ? '${arrived.single.label} added to ${_here.label}'
        : '${arrived.length} shortcuts added to ${_here.label}');
  }

  Future<void> _refreshWidgets() async {
    final ids = _graph.widgetIds;
    if (ids.isEmpty) {
      if (_widgets.isNotEmpty && mounted) setState(() => _widgets = const {});
      return;
    }
    final found = <int, PlacedWidget>{};
    for (final id in ids) {
      try {
        final info = await LauncherBridge.instance.widgetInfo(id);
        if (info != null) found[id] = info;
      } catch (_) {
        // One widget that will not answer must not cost the others.
      }
    }
    if (!mounted) return;
    setState(() => _widgets = found);
  }

  Future<void> _addWidget() async {
    final here = _hereId;
    List<WidgetProvider> providers;
    try {
      providers = await LauncherBridge.instance.widgetProviders();
    } catch (_) {
      _toast('Could not read the widget list');
      return;
    }
    if (!mounted) return;

    final chosen = await showWidgetPicker(context, providers);
    if (chosen == null || !mounted) return;

    PlacedWidget? placed;
    try {
      placed = await LauncherBridge.instance.addWidget(chosen.provider);
    } catch (_) {
      placed = null;
    }
    if (!mounted) return;
    if (placed == null) {
      // Said no to the permission, or backed out of the widget's own setup.
      // The Android side released the id, so there is nothing to clean up.
      return;
    }

    final spot = freeSpot(_graph.childrenOf(here).length);
    final size = _viewport;
    await _update(
      _graph.link(
        here,
        ChildRef.widget('${placed.appWidgetId}'),
        x: spot.x,
        y: spot.y,
      ).resizeChild(
        here,
        ChildRef.widget('${placed.appWidgetId}'),
        size.isEmpty ? 0.86 : (placed.minWidth + 16) / size.width,
        size.isEmpty ? 0.22 : (placed.minHeight + HostedWidgetView.stripHeight) /
            size.height,
      ),
    );
    if (!mounted) return;
    setState(() => _widgets = {..._widgets, placed!.appWidgetId: placed});
  }

  Future<void> _refreshApps() async {
    try {
      final apps = await LauncherBridge.instance.listApps();
      final saved = await _shortcuts.load();
      if (!mounted) return;
      setState(() => _apps = {
            ..._index(apps),
            // After, not before: a shortcut is not in the installed list, so a
            // plain replace would blank every shortcut on every resume.
            for (final shortcut in saved) shortcut.app.id: shortcut.app,
          });
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
    // Compared before the swap, because deleting a context takes its whole
    // subtree with it — every widget in there stops being placed, and an id
    // that stops being placed without being released leaks a live widget
    // nothing can see and nobody can remove. One funnel, so no edit can
    // forget.
    final released = _graph.widgetIds.difference(graph.widgetIds);
    final droppedShortcuts = _shortcutsNoLongerPlaced(graph);

    setState(() {
      _graph = graph;
      if (usage != null) _usage = usage;
      _trail = _walkable(_trail, graph);
      if (released.isNotEmpty) {
        _widgets = {
          for (final entry in _widgets.entries)
            if (!released.contains(entry.key)) entry.key: entry.value,
        };
      }
    });
    await _save();

    for (final id in released) {
      try {
        await LauncherBridge.instance.removeWidget(id);
      } catch (_) {
        // Already gone, which is the state we were asking for.
      }
    }
    for (final id in droppedShortcuts) {
      await _shortcuts.remove(id);
    }
  }

  /// Pinned shortcuts that no context holds any more.
  ///
  /// Only shortcuts: an app the launcher stops showing is still installed, but
  /// a pinned shortcut exists nowhere else, so keeping it would leave a dead
  /// entry in the picker for ever.
  Set<String> _shortcutsNoLongerPlaced(ContextGraph after) {
    final still = {
      for (final edge in after.edges.values)
        if (edge.child.isApp) edge.child.id,
    };
    return {
      for (final edge in _graph.edges.values)
        if (edge.child.isApp &&
            !still.contains(edge.child.id) &&
            (_apps[edge.child.id]?.isShortcut ?? false))
          edge.child.id,
    };
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
              leading: const Icon(Icons.widgets_rounded,
                  color: MeshColors.textDim),
              title: Text('Add a widget', style: meshText(size: 14)),
              subtitle: Text('Lives in ${_here.label}, running',
                  style: meshText(size: 11, color: MeshColors.textDim)),
              onTap: () => Navigator.pop(context, 'widget'),
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
      case 'widget':
        await _addWidget();
      case 'existing':
        await _addExisting();
    }
  }

  Future<void> _held(Edge edge) async {
    if (edge.child.isWidget) return _widgetHeld(edge);

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

  /// A widget's menu: how big, and whether to keep it.
  ///
  /// No "take out of here, keep elsewhere" — a widget placement *is* the
  /// widget, so removing it is removing it, and its id has to go back to the
  /// system rather than being quietly forgotten.
  Future<void> _widgetHeld(Edge edge) async {
    final id = edge.child.appWidgetId;
    if (id == null) return;
    final placed = _widgets[id];

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MeshColors.strip,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(placed?.label ?? 'Widget',
                  style: meshText(size: 15, weight: 600)),
              subtitle: Text(
                placed?.missing == true
                    ? 'The app behind it is gone'
                    : 'In ${_here.label}',
                style: meshText(size: 11, color: MeshColors.textDim),
              ),
            ),
            const Divider(height: 1, color: MeshColors.surfaceEdge),
            for (final size in _widgetSizes)
              ListTile(
                leading: const Icon(Icons.aspect_ratio_rounded,
                    color: MeshColors.textDim),
                title: Text(size.name, style: meshText(size: 14)),
                trailing: (edge.h ?? 0.22) == size.h
                    ? const Icon(Icons.check_rounded,
                        size: 18, color: MeshColors.text)
                    : null,
                onTap: () => Navigator.pop(context, 'size:${size.name}'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFC7503F)),
              title: Text('Remove widget', style: meshText(size: 14)),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == 'remove') {
      await _removeWidget(edge, id);
      return;
    }
    final wanted = _widgetSizes.firstWhere(
      (size) => 'size:${size.name}' == choice,
      orElse: () => _widgetSizes.first,
    );
    await _update(
      _graph.resizeChild(edge.parentId, edge.child, wanted.w, wanted.h),
    );
  }

  Future<void> _removeWidget(Edge edge, int id) async {
    // Unlinked first, so a failure to hand the id back still gets the widget
    // off the screen; the id is the system's problem after that, and it will
    // not be handed out twice.
    await _update(_graph.unlink(edge.parentId, edge.child));
    try {
      await LauncherBridge.instance.removeWidget(id);
    } catch (_) {
      // Already gone, which is the state we were asking for.
    }
    if (!mounted) return;
    setState(() => _widgets = {
          for (final entry in _widgets.entries)
            if (entry.key != id) entry.key: entry.value,
        });
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
        body: Stack(
          children: [
            const Positioned.fill(child: Grain()),
            SafeArea(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFFF4F00)),
                    )
                  : Column(
                      children: [
                        _header(),
                        Expanded(child: _field()),
                        _trailBar(),
                      ],
                    ),
            ),
          ],
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
        _viewport = constraints.biggest;
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
    if (edge.child.isWidget) return _placedWidget(edge, field);

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

  /// A widget is a box, not a circle, and it is sized by what it needs rather
  /// than by how often it is opened — you do not open a widget, you read it.
  Widget _placedWidget(Edge edge, Size field) {
    final id = edge.child.appWidgetId;
    if (id == null) return const SizedBox.shrink();
    final placed = _widgets[id];

    final width = (edge.w ?? 0.86) * field.width;
    final height = (edge.h ?? 0.22) * field.height;
    final left = (edge.x * field.width - width / 2)
        .clamp(0.0, (field.width - width).clamp(0.0, field.width));
    final top = (edge.y * field.height - height / 2)
        .clamp(0.0, (field.height - height).clamp(0.0, field.height));

    return Positioned(
      left: left,
      top: top,
      child: HostedWidgetView(
        // Keyed by id and size: a platform view is a real Android view, and
        // reusing one across a resize leaves it drawing at the old size.
        key: ValueKey('widget-$id-${width.round()}x${height.round()}'),
        appWidgetId: id,
        label: placed?.label ?? 'Widget',
        width: width,
        height: height,
        missing: placed?.missing ?? false,
        dragging: _draggingKey == edge.key,
        onMoveBy: (delta) {
          if (_draggingKey != edge.key) {
            setState(() => _draggingKey = edge.key);
          }
          _drag(edge.parentId, edge.child, delta, field);
        },
        onMoveEnd: _endDrag,
        onHold: () => _held(edge),
      ),
    );
  }

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
          if (shared) const SharedMark(),
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


/// The three sizes a widget can be, as fractions of the view.
///
/// Presets rather than a free resize: a widget is another app's layout, and
/// dragging one to an arbitrary size mostly produces something that app never
/// drew for.
const _widgetSizes = [
  (name: 'Small', w: 0.62, h: 0.16),
  (name: 'Medium', w: 0.86, h: 0.24),
  (name: 'Large', w: 0.92, h: 0.42),
];
