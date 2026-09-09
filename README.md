# MindMesh

A spatial launcher for Android: one canvas of connected nodes that answers the
question *what am I doing*, rather than *what kind of thing is this app*.

`now → gym → music, gym app, food app`. The nodes are situations, not
categories. Tapping a **place** flies the camera to it and frames what it holds;
tapping an **app** launches it. You never leave the canvas — zooming out always
shows where you have been, which is the whole reason it is a map and not nested
folders.

**The same app belongs in as many situations as it is useful in.** A node is a
placement, not the app itself, so music can sit in the gym *and* in the commute
without either being a copy: each has its own position on the canvas, and
removing one leaves the other alone. When you add apps to a place, anything
already placed elsewhere says where — as context for the choice, never to rule
it out.

The seed map is situations for that reason too. A categorical one would quietly
turn this back into a folder tree.

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

## Installing with Obtainium

[Add it](obtainium://app/%7B%22id%22%3A%22com.mindmesh.mindmesh%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fstagfoo%2Fmindmesh%22%2C%22author%22%3A%22stagfoo%22%2C%22name%22%3A%22MindMesh%22%7D) — or paste `https://github.com/stagfoo/mindmesh` into
Obtainium's Add App screen. Tags are exactly the version and every release bumps
it, so no extra settings are needed.

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
