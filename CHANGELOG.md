# Changelog

All notable changes to Calco. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

A release is made by pushing a tag `vX.Y.Z`: the release workflow tests and builds the app (unsigned) and publishes a GitHub release whose notes are that version's section below. Add your changes under **Unreleased** as you go, then rename it to the new version before tagging.

## [Unreleased]

### Added

- The inside of a shape or a path can have **its own colour**, apart from its outline.
- **Node** (A): edit the points of paths and shapes without ever drawing or adding points (that's the Pen). Shapes turn into points (an ellipse is four curves), a box picks several nodes to move together, and a double tap switches a node between corner and curve.
- **Scrub** the frames: drag along the frame numbers, with a finger or the Pencil, and the frames flip by as fast or as slow as you go, with a haptic tick on each.
- **Pen** (P): points joined by straight lines, or curves with handles; tap the line to add a point, the first point to close the path, and turn any point into a corner or a curve. Outline, fill and brush as with Shapes. A path stays editable (tap it with the Pen) and sharp with Move; its points are saved in the `.strokes` file.
- **Smudge** (S): smear the paint along, blur it, or blur it along the way you move (motion), with a strength, a soft tip or the brush's, and pressure.
- **Shapes** (U): lines, arrows, rectangles, ellipses, triangles, polygons, stars and rounded rectangles, solid, dashed or dotted, with or without a fill, in the inker's clean line or the chosen brush. Dragging clicks into a perfect square or circle, and lines every 45°, with a haptic tap. Each shape is one undo and a piece Move picks with one tap and keeps sharp.
- **Resizable timeline**: drag the grip above it to make the layer grid taller (rows grow up to 36 pt); the height is remembered, and a double tap returns to the automatic height.
- **Import an image as a layer** (New layer → Image from Photos / Files): it goes under every layer, fitted to the canvas and held through the whole clip, at 40 %, locked and marked as a **guide**, which is shown in the editor but never exported and isn't an outline for the fill. Any layer can be made a guide, or a guide part of the sprite, from its menu.

- **Floating panels**: the canvas and its grid fill the whole screen; the tool and animation rails float centred on each side and a narrower timeline floats at the bottom. The drawing fits in the space they leave free and glides into place when a panel hides or comes back.
- **Hide the timeline** by pushing its grip all the way down: the canvas gets the screen and the rails sit centred; a slim bar brings it back.
- **Previews in the timeline**: each cell shows its drawing, on white paper, and the cells are bigger.
- A faint **grid around the canvas**, which can be turned off in Preferences.
- The **status bar is hidden**: the whole screen is the studio.
- **Brush library**: Inker, Ballpoint, Marker, Pencil, Blue pencil, Charcoal, Paintbrush, Airbrush and Flat, each with a sample stroke. Pressure can change size or opacity, the pencils have paper grain and shade when you tilt the Pencil, the marker stays even where it crosses itself, the airbrush builds up. Each brush remembers its size and opacity; the eraser can use any brush's tip.
- **Strokes you can pick one by one**: each drawing remembers its pencil strokes. With Move, a tap picks the exact stroke under it even where it crosses others; tap the same spot again for the one underneath, and **Add strokes** to pick several. Dragging a stroke moves it straight away. The eraser trims strokes; a fill or the lasso merges a drawing into shapes. Saved in the project as optional `<layer>.strokes` files.
- **Stretch** with Move or the lasso: the handles in the middle of each side stretch the drawing wider or taller (squash and stretch), and **Uniform | Free** under the canvas makes the corner keep the proportions or stretch both ways. A chip shows the width and height while you drag, and each clicks back to 100 % or to the other's proportions. Pencil strokes **stay sharp** however much you scale or stretch them: each remembers how it was painted (saved as version 2 of the `.strokes` file) and is painted again where it lands instead of being resampled.
- **Move tool** (V): picks up the current layer's whole drawing, boxed tight, to move, scale or rotate; tap a shape (an eye, a hand) to move just that one. On a locked layer, such as an imported image, **Unlock and move** unlocks it for the move and locks it again after. Moving, rotating or scaling **clicks back** into its starting place, upright (or a quarter turn) and its own size, and the pivot clicks back to the middle, with a light haptic tap.

### Changed

- **Animation rail** on the right: a big **New**, Duplicate, Hold, Delete and **More** (label, split, repeat, frame actions), the onion skin, and **Layer | All**, which replaces Sync layers. In portrait it sits above the timeline.
- The timeline is cleaner: a bigger Play, one **clip settings** button (fps, loop, pivot), taller rows, a **+** over the layer names and a **+** cell after the last drawing.
- The **canvas clicks into place** while you move it with two fingers: upright and every quarter turn, its fitted size and the middle, with a light haptic tap.
- In **portrait** the tools lie across the top instead of down the left, so the canvas gets the whole width.
- **Swipe three fingers down** for Zen mode, and up to leave it.
- **Zen mode**'s bar has every tool now (fill, eyedropper, lasso, move) and redo.
- **Snappier controls**: the canvas redraws only when something changes (continuously only while you draw or move it), and the latency readout no longer redraws the editor on every Pencil sample. `scripts/install-ipad.sh` installs an optimised Release build.
- **Smoother playback and gestures**: the editor uses Swift Observation, so each part of the screen is redrawn only when what it shows changes. Playing redraws just the canvas, the playhead and its counter (the timeline marks the frame where playback started until it stops); pinching, panning and dragging a selection no longer redraw the panels.
- The latency readout is off unless you turn it on in Preferences.
- Releases are built **unsigned**, with no Apple Developer Program: the GitHub release has `Calco-X.Y.Z-unsigned.ipa` and the Unity package. TestFlight is gone.

## [0.7.0] - 2026-10-18

The "animator" release: what RoughAnimator users reach for first, plus the game pipeline and a second language.

### Added

- **Pixel art mode** per project: hard-edged brush, eraser, fill and lasso; the brush size is a width in pixels.
- **Draw in front, behind or inside** for the brush and the fill, and **mask a layer to the one below** (clipping mask, exported flattened).
- **Cycles**: repeat the last drawings after the playhead, linked, with their timing and labels; unlink a repeat to make it its own drawing. Project format 3 (`frames[].links`).
- **Inbetween halfway** and **duplicate split halfway**, keeping the clip's length.
- **Copy, cut, paste and delete** with the lasso, across frames and layers; **select all** (⌘C ⌘X ⌘V ⌘A).
- **Flip the view** horizontally without changing the drawing (H).
- **Pencil only** drawing, and Apple Pencil **double tap / squeeze** actions from the system settings.
- The drawing bar acts on the **current layer's drawing**; **Sync layers** makes it act on whole frames; a **Frame** menu for whole-frame actions.
- **New layer** with the same timing (blank), as a duplicate, or empty.
- **Lasts N frames** control; dragging a drawing's end pushes what follows instead of covering it.
- **Godot** export (SpriteFrames `.tres`).
- **Unity**: pixels per unit, and drawing labels as animation events (`OnCalcoLabel`).
- **Checks before exporting**: empty frames, hidden layers with drawings, sliding feet, loops that repeat their first frame.
- **Preferences** (⌘,) with the app's **language**: English by default, Spanish available, switching without relaunching.
- **User manual** in English and Spanish: <https://rldona.github.io/Calco/>.

### Changed

- The onion skin counts **drawings, not frames**, and its controls are labelled (Onion skin, Before, After).

## [0.6.0] - 2026-10-18

The "pipeline" release.

### Added

- **Export profiles**: saved, app-wide combinations of target, clips, scale, trim, padding and power of two; presets for Unity, Unity trimmed, Pixel art 4×, GIF and PNG frames; **Export again** (⇧⌘E).
- Export only some clips; a GIF per clip; a PNG sequence per clip.
- Trim transparent borders per clip with the pivot kept in place in Unity; scale ½× to 4×.

## [0.5.0] - 2026-10-18

The "exposure sheet" release.

### Added

- Per-layer exposures: a layer can keep showing the previous drawing (project format 2).
- Timeline rows are the layers, with name, visibility, lock and opacity; a held drawing is one long cell.
- Hold previous, new drawing and copy drawing per cell; drag a drawing's end to change its length.
- Onion skin colours, current-layer-only onion skin, playback range and drawing labels.

## [0.4.0] - 2026-10-18

The "draw and colour" release.

### Added

- Fill bucket with gap closing, eyedropper, and lasso to lift, move, scale, rotate and flip.
- Stroke smoothing and a pressure switch; crisp pixels when zoomed in.

## [0.3.0] - 2026-10-18

The "Estudio" release.

### Added

- Dark theme, tool rail, layers panel and clip tracks; Zen mode.
- Project gallery as the start screen and a new project sheet with sprite-size presets.
- App icon.

## [0.2.0] - 2026-10-18

The "usable" release.

### Added

- Drag to reorder frames; full layers panel; brush and eraser sizes, palette and colour picker.
- Finger gestures (undo, redo, zoom, pan, rotate), 50-step undo and keyboard shortcuts.

## [0.1.0] - 2026-10-18

First version: "it moves in Unity".

### Added

- Metal canvas with Apple Pencil input and pressure.
- Layers, frames, onion skin, clips with pivot and loop playback.
- `.calco` project format; sprite sheet PNG + Aseprite JSON and GIF export.
- `calco-unity` importer: sprites, animation clips and an Animator Controller.

[Unreleased]: https://github.com/rldona/Calco/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/rldona/Calco/releases/tag/v0.7.0
