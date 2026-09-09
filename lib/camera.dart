/// Where the canvas is looking.
///
/// The map is one surface; navigating it means moving a camera over it rather
/// than pushing screens. This works out the transform that frames a given
/// region, which is what "tap a node and it comes to you" actually is.
///
/// Pure maths on a viewport — no widgets — so the framing can be checked
/// exactly instead of by watching it move.
library;

import 'dart:math' as math;

typedef Rect = ({double left, double top, double width, double height});

class CameraStyle {
  const CameraStyle({
    this.minScale = 0.35,
    this.maxScale = 2.2,
    this.padding = 32,
    this.travelScale = 1,
  });

  final double minScale;
  final double maxScale;

  /// The scale the camera settles at when you move somewhere.
  ///
  /// Fixed, rather than whatever fits the place and its children: a map that
  /// zooms out as it grows ends up showing the whole tree at once, and then
  /// arriving somewhere stops being arriving anywhere. Moving should feel like
  /// walking across a room, not like being shown a diagram of the house.
  final double travelScale;

  /// Breathing room left around whatever is being framed, in screen pixels, so
  /// a framed group never touches the edges.
  final double padding;

  static const standard = CameraStyle();
}

/// How a region of the map maps onto the screen.
class CameraView {
  const CameraView({
    required this.scale,
    required this.offsetX,
    required this.offsetY,
  });

  final double scale;

  /// Screen position of the world origin.
  final double offsetX;
  final double offsetY;

  ({double x, double y}) worldToScreen(double x, double y) =>
      (x: x * scale + offsetX, y: y * scale + offsetY);

  ({double x, double y}) screenToWorld(double x, double y) =>
      (x: (x - offsetX) / scale, y: (y - offsetY) / scale);
}

/// The view that fits [region] into a [viewportWidth] x [viewportHeight] screen.
///
/// Scale is clamped: zooming far enough out to fit a sprawling map would make
/// its nodes unreadable, and far enough in to fill the screen with one node
/// would lose all sense of where it sits.
CameraView frame({
  required Rect region,
  required double viewportWidth,
  required double viewportHeight,
  CameraStyle style = CameraStyle.standard,
}) {
  final usableWidth = math.max(1.0, viewportWidth - style.padding * 2);
  final usableHeight = math.max(1.0, viewportHeight - style.padding * 2);

  final fitScale = math.min(
    usableWidth / math.max(1.0, region.width),
    usableHeight / math.max(1.0, region.height),
  );
  final scale = fitScale.clamp(style.minScale, style.maxScale);

  // Centre the region, whatever the scale ended up being — a clamped scale
  // must not also mean a region stuck against one edge.
  final centreX = region.left + region.width / 2;
  final centreY = region.top + region.height / 2;
  return CameraView(
    scale: scale,
    offsetX: viewportWidth / 2 - centreX * scale,
    offsetY: viewportHeight / 2 - centreY * scale,
  );
}

/// The view that puts a single point in the middle, at a given scale.
CameraView centreOn({
  required double x,
  required double y,
  required double viewportWidth,
  required double viewportHeight,
  double scale = 1,
  CameraStyle style = CameraStyle.standard,
}) {
  final clamped = scale.clamp(style.minScale, style.maxScale);
  return CameraView(
    scale: clamped,
    offsetX: viewportWidth / 2 - x * clamped,
    offsetY: viewportHeight / 2 - y * clamped,
  );
}
