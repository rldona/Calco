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

## Later

- Pixel-art mode
- Custom brushes
- iCloud sync
- Audio scrubbing
- iPhone

## Never (on purpose)

- Camera, tweening, vectors, rigging. That's a different product.
