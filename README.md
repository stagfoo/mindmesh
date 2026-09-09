# MindMesh

A spatial launcher for Android: one canvas of connected nodes, where a node is
a place you remember rather than a name you read.

Tapping a **place** flies the camera to it and frames what it holds. Tapping an
**app** launches it. You never leave the canvas — zooming out always shows where
you have been, which is the whole reason it is a map and not nested folders.

## How it works

- **Tap a place** — the camera flies there and frames it with its children. The
  parent stays in frame, because a view of only the children loses the thing
  they belong to.
- **Tap an app** — it launches.
- **Press and hold, then drag** — moves a node, and it stays there.
- **Long-press** — add, rename, remove, or put a moved node back into the
  automatic arrangement.
- **The breadcrumb** along the bottom says where you are; tapping any step flies
  back to it. The button beside it frames the whole map.

## Placement

New nodes ring their parent automatically, and the ring grows with the family:
neighbours are never closer than a node plus a gap, because a ring sized for
three has eight overlapping. Drag a node and it is *placed* — left exactly where
it was dropped, and no longer rearranged when its siblings change. That
distinction is the whole of "auto-placed, then draggable", and "put it back" in
the long-press menu undoes it.

Dragging divides the gesture by the current zoom, or a node would race away from
your finger when zoomed out and crawl when zoomed in. Moving is a press-and-drag
rather than a plain drag, so the canvas stays pannable from anywhere — including
from on top of a node.

## Layout

The parts worth being sure about are plain Dart with no Flutter imports, so the
graph rules and the geometry are tested without a canvas:

| File | Does |
| --- | --- |
| `lib/node.dart`, `lib/node_map.dart` | Nodes, the tree, and the rules that keep it one |
| `lib/radial_layout.dart` | Where children go when nobody has said |
| `lib/camera.dart` | What transform frames a region, and screen↔world |
| `lib/launcher_bridge.dart` | The only platform-channel code |
| `android/…/MainActivity.kt` | The only Android code |

The Android side is carried over from [Rolidecks](https://github.com/stagfoo/rolidecks)
— app listing, icons, launching, pinned shortcuts, package-change broadcasts —
rather than re-derived. It is the part that took the longest to get right there,
including profile handling that a locked work profile otherwise breaks.

A map that will not parse falls back to a seed rather than an empty canvas, and
an orphaned subtree is dropped on load: half a map is harder to reason about
than a smaller whole one, and the launcher has to draw something either way.

## Building

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

`scripts/release.sh` bumps the version, builds, verifies the APK really is that
version, and publishes it. Publish only from there — finishing by hand skips
that check, which is how a release ends up carrying the previous version's APK.
