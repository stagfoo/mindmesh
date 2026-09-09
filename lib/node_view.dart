import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'models.dart';
import 'node.dart';
import 'theme.dart';

/// One place on the canvas.
///
/// Shows its colour and mark when it is empty, and a preview of the apps inside
/// once it holds some — the same way a folder shows what is in it. Only places
/// are drawn: apps live inside one, so the canvas stays a picture of your
/// situations rather than of your app drawer.
class NodeView extends StatelessWidget {
  const NodeView({
    super.key,
    required this.node,
    required this.onTap,
    required this.onLongPress,
    required this.onDragStart,
    required this.onDragBy,
    required this.onDragEnd,
    this.dragging = false,
    this.apps = const {},
    this.focused = false,
    this.childCount = 0,
  });

  final MapNode node;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Moving a node is a press-and-drag, not a plain drag: a plain one would
  /// compete with panning the canvas, and the canvas has to stay draggable
  /// from anywhere including on top of a node.
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragBy;
  final VoidCallback onDragEnd;

  final bool dragging;

  /// Installed apps by id, for drawing the preview of what is inside.
  final Map<String, LaunchableApp> apps;

  final bool focused;
  final int childCount;

  @override
  Widget build(BuildContext context) {
    final colour = colorOf(node.colorKey);
    final onNode = onNodeFor(colour);
    final inside = [
      for (final appId in node.apps)
        if (apps[appId] != null) apps[appId]!,
    ];

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressStart: (_) => onDragStart(),
      onLongPressMoveUpdate: (details) => onDragBy(details.offsetFromOrigin),
      onLongPressEnd: (_) => onDragEnd(),
      onLongPressCancel: onDragEnd,
      child: SizedBox(
        width: MeshMetrics.nodeSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: MeshMetrics.nodeSize * (dragging ? 0.82 : 0.72),
              height: MeshMetrics.nodeSize * (dragging ? 0.82 : 0.72),
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(MeshMetrics.nodeRadius),
                border: Border.all(
                  color: focused ? MeshColors.text : Colors.transparent,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colour.withValues(alpha: focused ? 0.5 : 0.3),
                    blurRadius: focused ? 20 : 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: inside.isEmpty
                  ? Icon(iconOf(node.iconKey),
                      size: MeshMetrics.nodeSize * 0.34, color: onNode)
                  : _Preview(apps: inside),
            ),
            const SizedBox(height: 6),
            Text(
              node.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: meshText(
                size: 11,
                weight: 600,
                height: 1.15,
                color: focused ? MeshColors.text : MeshColors.textDim,
              ),
            ),
            if (childCount > 0 || node.apps.isNotEmpty)
              Text(
                [
                  if (node.apps.isNotEmpty) '${node.apps.length}',
                  if (childCount > 0) '$childCount·',
                ].reversed.join(),
                style: meshText(size: 9, color: MeshColors.textDim),
              ),
          ],
        ),
      ),
    );
  }
}

/// The first few apps in a place, laid out like a folder's contents.
///
/// Four at most: past that they are too small to tell apart, and the count
/// under the label says how many there really are.
class _Preview extends StatelessWidget {
  const _Preview({required this.apps});

  final List<LaunchableApp> apps;

  @override
  Widget build(BuildContext context) {
    final shown = apps.take(4).toList();
    final cell = MeshMetrics.nodeSize * (shown.length > 1 ? 0.22 : 0.42);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          spacing: 3,
          runSpacing: 3,
          children: [
            for (final app in shown) AppIconImage(app: app, size: cell),
          ],
        ),
      ),
    );
  }
}

/// The lines between a node and its children.
///
/// Drawn under everything, and thin: they are there to say what belongs to
/// what, not to be looked at.
class EdgePainter extends CustomPainter {
  const EdgePainter({required this.edges, required this.colours});

  /// World-space pairs, parent to child.
  final List<({double x1, double y1, double x2, double y2, String colorKey})>
      edges;

  final Map<String, Color> colours;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final paint = Paint()
        ..color = (colours[edge.colorKey] ?? MeshColors.surfaceEdge)
            .withValues(alpha: 0.45)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(edge.x1, edge.y1),
        Offset(edge.x2, edge.y2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(EdgePainter oldDelegate) =>
      oldDelegate.edges != edges;
}
