# Architecture

Three layers, dependencies point downward only.

```
App/        SwiftUI views + EditorState (selection, onion settings, playback)
Timeline/   Frame strip UI
Canvas/     CanvasUIView (Pencil input)  ->  FrameStore (textures)  ->  CanvasRenderer (Metal)
Model/      Project: Codable mirror of docs/format.md. No UI, no Metal.
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
