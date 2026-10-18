# Changelog

All notable changes to Calco. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

A release is made by pushing a tag `vX.Y.Z`: the release workflow builds the app, uploads it to TestFlight and publishes a GitHub release whose notes are that version's section below. Add your changes under **Unreleased** as you go, then rename it to the new version before tagging.

## [Unreleased]

### Added

- **Resizable timeline**: drag the grip above it to make the layer grid taller (rows grow up to 36 pt); the height is remembered, and a double tap returns to the automatic height.
- **Import an image as a layer** (New layer → Image from Photos / Files): it goes under every layer, fitted to the canvas and held through the whole clip, at 40 %, locked and marked as a **guide**, which is shown in the editor but never exported and isn't an outline for the fill. Any layer can be made a guide, or a guide part of the sprite, from its menu.

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
