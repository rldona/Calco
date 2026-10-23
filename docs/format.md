# The `.calco` project format

A Calco project is a **folder** (an iOS document package) named `<name>.calco`. Everything inside is plain files: one JSON manifest plus PNGs. You can open, diff and version it without Calco.

Status: draft (format 2 since v0.5). Breaking changes are expected until 1.0; `version` in the manifest will be bumped on every incompatible change.

## Layout

```
Hero.calco/
├── project.json
├── clips/
│   ├── idle/
│   │   ├── 000/
│   │   │   ├── line.png
│   │   │   ├── line.strokes
│   │   │   └── color.png
│   │   ├── 001/
│   │   │   ├── line.png
│   │   │   └── color.png
│   │   └── ...
│   └── run/
│       └── ...
└── references/
    └── silhouette.png
```

- One folder per clip, one folder per frame (zero-padded index), one PNG per layer.
- PNGs are RGBA, premultiplied alpha, canvas-sized. Empty layers may be omitted.
- `<layer>.strokes` (optional) keeps the drawing's pencil strokes apart, so the Move tool can pick them one by one. The PNG stays the truth: a reader can ignore these files, and Calco ignores one that no longer adds up to its PNG and splits the drawing into its shapes instead. Binary, little-endian: `CSTK`, `UInt32` version (2), `UInt32` piece count, then per piece, bottom to top, `UInt32` x, y, width, height, the byte count, and the piece's RGBA premultiplied pixels (cropped to its rectangle) compressed with LZFSE; then the byte count of its recipe (0 when it has none) and the recipe compressed with LZFSE. A recipe is how a pencil stroke was painted, so Move can paint it again sharp at any size: `Float32` colour (r, g, b), hardness, grain, grain scale, `UInt32` builds up (0/1), `Float32` opacity, `UInt32` pixel art (0/1), `UInt32` stamp count, then each stamp's `Float32` x, y, radius and alpha in canvas pixels, and, for a filled shape or a Pen path, `UInt32` the number of corners of its inside (0 when it has none) and each one's `Float32` x and y; then, for a Pen path, `UInt32` the byte count of a JSON object with its points (`path`: `nodes` with `point`, `handleIn`, `handleOut` and `smooth`, and `closed`) and its `style`, and the JSON itself, padded with zeros to whole words. Version 1 files have no recipes.
- The manifest is the source of truth for order, holds, layers and pivots. Folder contents alone are not enough to reconstruct the animation.
- Calco rewrites the whole package on every save and drops folders the manifest no longer refers to, so don't keep your own files inside `clips/`. `references/` is left alone.

## `project.json`

```json
{
  "version": 3,
  "name": "Hero",
  "canvas": { "width": 512, "height": 512 },
  "fps": 12,
  "clips": [
    {
      "id": "idle",
      "name": "Idle",
      "fps": 12,
      "loop": true,
      "pivot": { "x": 0.5, "y": 0.0 },
      "layers": [
        { "id": "line",  "name": "Line",  "opacity": 1.0, "visible": true, "locked": false },
        { "id": "color", "name": "Color", "opacity": 1.0, "visible": true, "locked": false }
      ],
      "frames": [
        { "id": "000", "hold": 2 },
        { "id": "001", "hold": 2 },
        { "id": "002", "hold": 3, "held": ["color"] }
      ]
    }
  ],
  "references": [
    { "id": "silhouette", "file": "references/silhouette.png", "opacity": 0.3 }
  ]
}
```

### Fields

| Field | Notes |
|---|---|
| `version` | Integer. Format version, not app version. |
| `canvas` | Pixels. All frames in the project share it. |
| `fps` | Project default. A clip may override it. |
| `clips[].pivot` | Normalized `0..1`, origin bottom-left (Unity convention). `{0.5, 0}` = bottom center. |
| `clips[].layers` | Ordered bottom to top. Layer `id` is the PNG basename inside each frame folder. |
| `clips[].layers[].maskBelow` | Optional, default `false`. The layer only shows where the nearest unmasked layer below it has paint (a clipping mask); exports flatten it that way. |
| `clips[].layers[].guide` | Optional, default `false`. A guide to draw over, such as an imported reference image: shown in the editor, left out of every export and of the fill's outline. |
| `clips[].layers[].tint` | Optional, absent by default. `"#RRGGBB"`: a guide layer's lines shown in that colour in the editor (only guides use it). Readers that don't know it can ignore it. |
| `clips[].frames[].id` | Frame folder name. Order in the array is playback order. |
| `clips[].frames[].hold` | How many ticks at the clip's fps this frame stays on screen. Default `1`. |
| `clips[].frames[].labels` | Optional (format 2). Names for this frame's own drawings, by layer id, e.g. `{"line": "contact"}`. |
| `clips[].frames[].held` | Optional (format 2). Layer ids that keep showing the previous frame's drawing here, like a hold on an exposure sheet; those layers have no PNG in this frame's folder. Ignored on a clip's first frame. |
| `clips[].frames[].links` | Optional (format 3). Layer id → frame id: that layer shows the other frame's drawing here, linked, as in a cycle (editing one edits all). No PNG in this frame's folder for those layers. A link to a frame that doesn't exist shows nothing. |
| `references` | Optional guide images drawn under everything, never exported. |
| `symmetry` | Optional, absent when off. Drawing with a mirror: `{ "mode": "vertical" \| "horizontal" \| "both", "x", "y" }`, the axes in canvas pixels (on a half pixel). Only the editor uses it. |
| `palette` | Optional, absent when empty. The project's named colours, in order: `[{ "id", "name", "color": "#RRGGBB" }]`. Only the editor uses it; drawings stay plain pixels. |
| `pixelArt` | Optional, default `false`. When `true` the editor draws, erases, fills and moves selections with hard edges (no antialiasing). Doesn't change how the file is read. |

## Export: sprite sheet

`Export → Sprite sheet` produces `<name>.png` + `<name>.json` in the [Aseprite JSON (array) format](https://www.aseprite.org/docs/cli/#data), which Unity, Godot and most engines already understand.

- Frames are packed in a near-square grid of canvas-sized cells, in project order (clip by clip), untrimmed.
- Cells are separated by a transparent **2 px margin**, also applied around the outer edge, so an engine's bilinear filtering never samples the neighbouring frame. Cell `i` of an `n`-column grid sits at `x = 2 + (i % n) * (w + 2)`, `y = 2 + (i / n) * (h + 2)`; `frames[].frame` carries those positions, while `spriteSourceSize` / `sourceSize` stay the bare canvas size. Slice `bounds` are relative to the sprite (`0,0,w,h`), so the margin doesn't affect them.
- Visible layers are flattened per frame. `duration` is `hold * 1000 / fps` in ms, using the clip's fps override when set.
- `meta.frameTags` carries one tag per clip, named by clip **id**, with `direction: "forward"` and a non-standard `loop` boolean.
- `meta.slices` carries one full-frame slice per clip, named by clip id, keyed at the clip's first frame, with `pivot` in Aseprite's convention: pixels from the top-left. `{0.5, 0}` in `project.json` becomes `{w/2, h}`.
- Pivot per clip is the only thing that doesn't round-trip through Aseprite itself (Aseprite pivots are per slice key, not per tag); `calco-unity` reads the slice that shares the tag's name.

The Unity importer ([`calco-unity/`](../calco-unity/README.md)) reads the same JSON and generates `Sprite`s, `AnimationClip`s and an `AnimatorController`. Install it with `https://github.com/rldona/Calco.git?path=/calco-unity` in the Package Manager.

## Export: GIF

`Export → GIF` writes the current clip as `<name>-<clip>.gif`: one GIF frame per Calco frame, delay `hold / fps`
rounded to 1/100 s, looping forever when the clip loops and once otherwise, transparent background. It's a
preview format for sharing, not for engines; use the sprite sheet for those.
