import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'launcher_bridge.dart';
import 'theme.dart';

/// A hosted widget, with a strip along the top to move it by.
///
/// The widget's own view fills the rest and stays live — the whole point of
/// hosting one rather than showing a picture of it. That is also why it needs
/// the strip: every touch inside the widget belongs to the widget, so there is
/// nowhere left to grab it by.
class HostedWidgetView extends StatelessWidget {
  const HostedWidgetView({
    super.key,
    required this.appWidgetId,
    required this.label,
    required this.width,
    required this.height,
    required this.onMoveBy,
    required this.onMoveEnd,
    required this.onHold,
    this.missing = false,
    this.dragging = false,
  });

  final int appWidgetId;
  final String label;
  final double width;
  final double height;

  final ValueChanged<Offset> onMoveBy;
  final VoidCallback onMoveEnd;
  final VoidCallback onHold;

  final bool missing;
  final bool dragging;

  static const stripHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => onMoveBy(details.delta),
            onPanEnd: (_) => onMoveEnd(),
            onPanCancel: onMoveEnd,
            onLongPress: onHold,
            onTap: onHold,
            child: Container(
              height: stripHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: dragging
                    ? MeshColors.surfaceEdge
                    : MeshColors.surface.withValues(alpha: 0.9),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.drag_indicator_rounded,
                      size: 13, color: MeshColors.textDim),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: meshText(
                          size: 9,
                          letterSpacing: 0.5,
                          color: MeshColors.textDim),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(14)),
              child: missing
                  ? _Gone(label: label)
                  : _hosted(),
            ),
          ),
        ],
      ),
    );
  }

  /// Hybrid composition, not a plain [AndroidView].
  ///
  /// The default route renders the view into a virtual display, which gets
  /// touch and focus wrong for anything with real controls — and a widget is
  /// mostly buttons. Hybrid composition puts the actual view in the hierarchy,
  /// so a play button in a music widget is a play button.
  Widget _hosted() {
    return PlatformViewLink(
      viewType: 'mindmesh/widget',
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const {},
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (params) {
        return PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: 'mindmesh/widget',
          layoutDirection: TextDirection.ltr,
          creationParams: {
            'appWidgetId': appWidgetId,
            'width': width.round(),
            'height': (height - stripHeight).round(),
          },
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
      },
    );
  }
}

/// The app behind a widget is gone.
///
/// Shown rather than silently dropped: the placement is something the user put
/// there, and a hole where it was explains itself where a gap does not.
class _Gone extends StatelessWidget {
  const _Gone({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MeshColors.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      child: Text(
        '$label is gone\nhold to remove',
        textAlign: TextAlign.center,
        style: meshText(size: 10, color: MeshColors.textDim, height: 1.4),
      ),
    );
  }
}

/// Picks a widget from everything installed.
///
/// The launcher's own list rather than the system picker: the system one hands
/// back a bare id with no label and no preview, and this needs both to show
/// what a widget will look like before it takes up half a context.
Future<WidgetProvider?> showWidgetPicker(
  BuildContext context,
  List<WidgetProvider> providers,
) {
  return showModalBottomSheet<WidgetProvider>(
    context: context,
    backgroundColor: MeshColors.strip,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, controller) => providers.isEmpty
          ? Center(
              child: Text('No widgets installed',
                  style: meshText(size: 13, color: MeshColors.textDim)),
            )
          : ListView.builder(
              controller: controller,
              itemCount: providers.length,
              itemBuilder: (context, index) {
                final provider = providers[index];
                return ListTile(
                  leading: SizedBox(
                    width: 52,
                    height: 44,
                    child: provider.preview == null
                        ? const Icon(Icons.widgets_rounded,
                            color: MeshColors.textDim)
                        : Image.memory(provider.preview!, fit: BoxFit.contain),
                  ),
                  title: Text(provider.label, style: meshText(size: 14)),
                  subtitle: Text(
                    '${provider.minWidth}×${provider.minHeight}'
                    '${provider.configurable ? ' · sets itself up' : ''}',
                    style: meshText(size: 11, color: MeshColors.textDim),
                  ),
                  onTap: () => Navigator.pop(context, provider),
                );
              },
            ),
    ),
  );
}
