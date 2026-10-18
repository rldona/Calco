# Roadmap

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

- [ ] Per-layer exposures: each layer is a row of drawings with their own holds, inside each clip
- [ ] Timeline rows are the layers: name, eye, lock and opacity inline; tap a cell to go there
- [ ] Hold, insert, duplicate and delete per cell; extend a drawing by dragging its end
- [ ] Onion skin in the timeline: before / after range, quick prev / next toggles, colours, current layer only
- [ ] Playback range (in / out) inside a clip
- [ ] Drawing labels
- [ ] Export and Unity importer flatten per-layer exposures (no change for Unity)

## Later

- Pixel-art mode
- Custom brushes
- iCloud sync
- Audio track with waveform and scrubbing (lip sync)
- Textured brushes (grain, flow, spacing)
- iPhone

## Never (on purpose)

- Camera, tweening, vectors, rigging. That's a different product.
