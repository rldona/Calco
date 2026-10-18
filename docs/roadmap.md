# Roadmap

Calco is for **indie game developers who animate on iPad**: tablet ergonomics (Pencil, gestures,
Zen) are the base of every screen, and the game pipeline is what sets it apart from RoughAnimator.
A Mac version can come later on the same core.

## v0.1 — "it moves in Unity"

- [x] Metal canvas PoC: Pencil input, pressure, one brush, acceptable latency (~9 ms on iPad Pro 11)
- [x] Layers per frame with opacity/visibility
- [x] Frame strip: add / duplicate / delete / reorder / hold
- [x] Onion skin (configurable before/after)
- [x] Clips (idle, run…) with pivot
- [x] Loop playback
- [x] `.calco` save/load (see `format.md`)
- [x] Export sprite sheet PNG + Aseprite JSON
- [x] Export GIF (current clip)
- [x] `calco-unity` importer: JSON → Sprites + AnimationClips + AnimatorController (`calco-unity/`, verified with Unity 6000.6 in batch mode)

## v0.2 — "usable"

The v0.1 UI grew one control per feature. This pass makes it a tool you can work in.

- [x] Frame strip: drag to reorder (long-press a thumbnail; arrows stay for single steps)
- [x] Layers panel: add / delete / rename / drag to reorder / opacity / visibility / lock, all undoable
- [x] Tool panel: brush / eraser with their own sizes (1–64 px), 16-colour palette + system picker, remembered across launches; B, E, [ and ] on a keyboard
- [x] Gestures: two-finger tap undo, three-finger redo, pinch zoom / pan / rotate (fingers only; Pencil always draws; ⌘0 or the fit button resets the view)
- [x] Undo / redo stack (50 steps; strokes, clear, frames, clips, layer visibility, clip settings; ⌘Z / ⇧⌘Z)
- [x] Keyboard shortcuts for hardware keyboards: all in app menus (`CalcoCommands`), so holding ⌘ lists them — frames, layers, playback, zoom, onion skin, tools, file
- [x] Layout pass: top bar in three groups (document · drawing · view) that fits an 11" iPad in portrait, compact steppers, onion skin in a popover, clear layer moved to the layers panel. Landscape not yet looked at on a device

## v0.3 — "Estudio"

Calco's own look, aimed squarely at being better to work in than RoughAnimator.

- [x] Dark Estudio theme (`Theme.swift`): neutral chrome, one amber accent for whatever is active
- [x] Tool rail on the left (brush, eraser, colour, vertical size slider, undo / redo); layers as a fixed panel on the right
- [x] Canvas gets only the space the panels leave, so chrome never covers the drawing
- [x] Timeline with one track per clip: the active clip as thumbnails sized by hold, the rest as exposure bars on the same time scale; tap a track to edit it
- [x] Zen mode: hides everything but the canvas and a small floating bar (Zen button or ⌃⌘F)
- [x] Project gallery as the start screen: "Continue" with the last project, cards that play their first clip, rename / duplicate / delete on long press; everything saves into it on its own
- [x] New project sheet: sprite-size presets (64–1024 or custom), fps explained in game terms (8 / 12 / 24), starting clips (Idle, Run, Jump, Attack, Hurt or your own)
- [x] App icon
- [ ] Custom icon set (brush, eraser, onion skin, pivot) instead of SF Symbols
- [ ] Landscape and Stage Manager sizes checked on a device

## v0.4 — "draw and colour"

What RoughAnimator users reach for most, done the Calco way (from its tutorial chapters and user comments).

- [x] Fill bucket (G): fills the region under the finger using all visible layers as the outline, slides under anti-aliased edges; undoable
- [x] Eyedropper (I): picks the colour from what's on screen, then hands you back the tool you had
- [x] Close gaps for the fill (Off / Small / Medium / Large, scaled to the canvas; tap the bucket again), remembered
- [x] Lasso (L): lift, move, scale (corner), rotate (knob), flip, with an anchor you drag by finger without moving the drawing; one undo step; ✓ / Return applies, ✕ / Esc cancels, tapping outside applies
- [x] Stroke smoothing (stabiliser) and a pressure on/off switch (tap the brush again; remembered)
- [x] Canvas shows real pixels when magnified (no more blurry strokes)
- [ ] Brush opacity (needs strokes rendered to their own buffer first, so overlaps don't build up)
- [ ] Resize the canvas after creating the project
- [ ] Draw behind (paint under what's already on the layer, for colouring under lines)

## v0.5 — "exposure sheet"

Where RoughAnimator is still ahead: every layer has its own timeline. A background can be one
drawing held for the whole clip while the character changes every 2 frames. Changes `.calco`
(format version 2, with a migration from 1).

- [x] Per-layer exposures as held cells: a layer can keep showing the previous drawing (format 2). New frames hold every layer but the one being drawn; add / duplicate / delete / move keep every frame looking the same; painting a held cell edits the held drawing
- [x] Timeline rows are the layers: name, eye, lock and opacity inline, long-press for rename / order / delete; a held drawing is one long cell; tap a cell to go there; clips as tabs
- [x] Hold previous / new drawing / copy drawing per cell
- [x] Extend or shorten a drawing by dragging its end; hold a frame number and drag to reorder; long-press a cell for hold / new / copy / label / clear
- [x] Onion skin in the timeline (on/off, before / after), current layer only option; held layers no longer ghost over themselves
- [x] Onion skin colours
- [x] Playback range (in / out) from the footer menu
- [x] Drawing labels, shown in the cell
- [ ] Export and Unity importer flatten per-layer exposures (no change for Unity)

## v0.6 — "pipeline"

- [x] Export profiles: saved, app-wide combinations (target, clips, scale, trim, padding, power-of-two); presets Unity, Unity · trimmed, Pixel art 4×, GIF to share, PNG frames; "Export again" (⇧⌘E)
- [x] Export only some clips; GIF per clip; PNG sequence per clip (holds expanded)
- [x] Trim transparent borders, one box per clip, with the pivot kept right in Unity (checked in Unity 6000.6 batch mode); scale ½× / 1× / 2× / 4×
- [ ] Godot target (SpriteFrames .tres)
- [ ] Unity: pixels per unit, animation events from drawing labels; importer checked against held cells
- [ ] Consistency checks before export: pivot / feet drifting, size changing, cycles that don't close, empty frames, hidden layers

## v0.7 — "assist"

Helps without drawing for you: guides on their own layer, never final art.

- [ ] Reference images to trace over (`references/` in the format already)
- [ ] Recolour a colour across a clip; apply a palette
- [ ] Mirror or ping-pong a clip
- [ ] Inbetween suggestions as a translucent guide

## Later

- Pixel-art mode
- Custom brushes
- iCloud sync
- Audio track with waveform and scrubbing (lip sync)
- Textured brushes (grain, flow, spacing)
- iPhone

## Never (on purpose)

- Camera, tweening, vectors, rigging. That's a different product.
