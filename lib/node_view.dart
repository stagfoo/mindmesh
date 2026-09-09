import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'models.dart';
import 'node.dart';
import 'theme.dart';

/// One node on the canvas.
///
/// A place shows its colour and mark; an app shows its own icon. Same size and
/// same shape either way, because on a map the thing you navigate by is where
/// something is, and a node that changed shape by kind would make the map
/// harder to read rather than easier.
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
    this.app,
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

  /// Set for an app node whose app is installed.
  final LaunchableApp? app;

  final bool focused;
  final int childCount;

  @override
  Widget build(BuildContext context) {
    final colour = colorOf(node.colorKey);
    final onNode = onNodeFor(colour);
    final missing = node.isApp && app == null;

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
                color: node.isApp ? MeshColors.surface : colour,
                borderRadius: BorderRadius.circular(MeshMetrics.nodeRadius),
                border: Border.all(
                  color: focused ? MeshColors.text : Colors.transparent,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (node.isApp ? Colors.black : colour)
                        .withValues(alpha: focused ? 0.5 : 0.3),
                    blurRadius: focused ? 20 : 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: node.isApp
                  ? (missing
                      // Kept rather than hidden: the node is where you put it,
                      // and a gap there is more confusing than a greyed one.
                      ? const Icon(Icons.help_outline_rounded,
                          color: MeshColors.textDim)
                      : Center(
                          child: AppIconImage(
                            app: app!,
                            size: MeshMetrics.nodeSize * 0.72,
                          ),
                        ))
                  : Icon(iconOf(node.iconKey),
                      size: MeshMetrics.nodeSize * 0.34, color: onNode),
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
            if (!node.isApp && childCount > 0)
              Text(
                '$childCount',
                style: meshText(size: 9, color: MeshColors.textDim),
              ),
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
