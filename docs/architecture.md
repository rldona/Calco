# Architecture

Three layers, dependencies point downward only.

```
App/        SwiftUI views + EditorState (selection, onion settings, playback, document)
Timeline/   Frame strip UI + ClipBar (clip picker, loop, fps override, pivot toggle)
Canvas/     CanvasUIView (Pencil input)  ->  FrameStore (textures)  ->  CanvasRenderer (Metal)
Model/      Project: Codable mirror of docs/format.md. ProjectDocument: package I/O. No UI, no Metal.
Export/     SpriteSheet (grid + Aseprite JSON) and GIFExport (ImageIO). CoreGraphics only; get flattened CGImages.
```

## Pixel storage

`FrameStore` keeps one `MTLTexture` per `(clip, frame, layer)`, allocated lazily on first stroke.
Nothing is downsampled or cached on the CPU; the whole project lives on the GPU while editing.
A 512×512 RGBA8 layer is 1 MB, so a 3-layer, 48-frame clip is ~150 MB. Fine for v0.1; paging to
disk is a later problem and the `.calco` format already stores one PNG per layer.

## Frame draw

Every display refresh `CanvasUIView.draw` asks `EditorState.visibleLayers()` for an ordered list
of `(texture, opacity, tint)` and hands it to `CanvasRenderer.present`, which draws a checkerboard
and composites each entry with premultiplied "over" blending. Onion skin is nothing special: it is
just previous/next frames in that list with a tint and a lower opacity.

## Strokes

`StrokeBuilder` (pure Swift) turns Pencil samples into evenly spaced round stamps; the renderer draws
them as instanced quads straight into the target layer texture. Brush and eraser share the vertex
path and differ only in blend factors.

## Thumbnails

After each stroke the current frame is composited into a 160 px texture, read back, and published
as a `CGImage` for the timeline. Cheap enough to do per stroke; no need to debounce yet.

## Save / load

`ProjectDocument` owns the package layout and knows nothing about Metal: `save` takes a closure
`(LayerKey) -> CGImage?` and `loadLayerImages` returns `[LayerKey: CGImage]`. `EditorState` wires
those to `FrameStore.image` / `FrameStore.load`, which go through `CanvasRenderer.readback` (blit
private texture → shared staging → `CGImage`, blocking) and `CanvasRenderer.upload` (draw the
`CGImage` into an RGBA8 premultiplied `CGContext` → staging → blit). Both sides use the same memory
layout as the layer textures, so a save/load round trip is lossless.

A save assembles the whole package in a temp folder and swaps it in with `replaceItemAt`, so a crash
mid-save can't corrupt the project and frames deleted since the last save don't leave orphan folders.
Layers that were never drawn on have no texture and no PNG. Opening a project with a different canvas
size replaces the renderer and the store.

`EditorState.isDirty` flips on every edit; the app saves on its own only when going to the background,
and only for a project that already has a file. New projects are written to `Documents/<name>.calco`,
which Files shows under *On My iPad › Calco*; opened projects are written back where they came from.

## Clips and pivot

A clip is a folder on disk, so its `id` is a slug of the name (`Run Fast!` → `run-fast`), unique
within the project and never renamed afterwards; only `name` changes. Frame ids come from one
project-wide counter, so a frame id is unique across clips and the thumbnail cache can be keyed by
frame alone. A new clip copies the current clip's layer list and starts with one blank frame.

The pivot is stored normalized with origin bottom-left (Unity convention) and edited through
`PivotOverlay`, a SwiftUI layer above the Metal canvas that maps the handle through the same
`CanvasRenderer.fitRect` the renderer uses, so it stays glued to the canvas in any orientation.
Only the handle takes touches; everything else falls through to the Pencil.

## Export

`EditorState.exportSpriteSheet` flattens every frame of every clip on the GPU
(`CanvasRenderer.flatten`: visible layers composited over transparent, no checkerboard, read back) and
hands the images to `SpriteSheet.build`, which packs them into a near-square grid of canvas-sized cells
and renders the sheet with CoreGraphics. `SpriteSheet.aseprite` describes it in the Aseprite JSON
array format: one `frames[]` entry per frame with `duration = hold * 1000 / fps`, one `frameTags[]`
entry per clip (`name` is the clip id, plus a non-standard `loop` flag for `calco-unity`), and one
`slices[]` entry per clip carrying the pivot in Aseprite's convention (pixels from the top-left of a
full-frame bounds). Output goes to `Documents/Exports/<name>/<name>.png|json` and to a share sheet.
Hidden layers are left out, the same way Aseprite exports.

`EditorState.exportGIF` writes the *current clip* as `Documents/Exports/<name>/<name>-<clip>.gif`
through ImageIO: one frame per Calco frame, delay `hold / fps`, NETSCAPE loop count 0 (forever) or 1
(once) from `clip.loop`, transparency preserved. GIF timing is in 1/100 s and viewers clamp short
delays, so very fast clips play slower than in the app; that's the format.
