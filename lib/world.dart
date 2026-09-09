/// The canvas the map is drawn on.
///
/// InteractiveViewer needs a real box to pan over, so the map lives in the
/// middle of a fixed, generous one rather than in a box sized to its contents —
/// sizing it to the content would move every node whenever the map grew.
///
/// It has to be generous because branches fan outward rather than ringing their
/// parent, so a long chain of situations keeps travelling in one direction —
/// roughly 260px a level — instead of folding back near the middle. A node
/// placed outside this box would be undrawable and unhittable.
library;

import 'radial_layout.dart';

const double worldExtent = 12000;

/// Half the world: where node coordinate zero sits on the canvas.
const double worldOrigin = worldExtent / 2;

/// Nodes are stored centred on zero; the canvas is not.
///
/// Every place that turns one into the other has to agree, and the camera did
/// not — it framed nodes at their own coordinates while the canvas drew them
/// half a world away, which is why the map was always just off screen. One
/// function now, so there is nothing left to disagree with.
Place toCanvas(Place place) =>
    (x: place.x + worldOrigin, y: place.y + worldOrigin);
