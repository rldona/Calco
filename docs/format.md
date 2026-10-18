# The `.calco` project format

A Calco project is a **folder** (an iOS document package) named `<name>.calco`. Everything inside is plain files: one JSON manifest plus PNGs. You can open, diff and version it without Calco.

Status: draft for v0.1. Breaking changes are expected until 1.0; `version` in the manifest will be bumped on every incompatible change.

## Layout

```
Hero.calco/
├── project.json
├── clips/
│   ├── idle/
│   │   ├── 000/
│   │   │   ├── line.png
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
- The manifest is the source of truth for order, holds, layers and pivots. Folder contents alone are not enough to reconstruct the animation.
- Calco rewrites the whole package on every save and drops folders the manifest no longer refers to, so don't keep your own files inside `clips/`. `references/` is left alone.

## `project.json`

```json
{
  "version": 1,
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
        { "id": "002", "hold": 3 }
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
| `clips[].frames[].id` | Frame folder name. Order in the array is playback order. |
| `clips[].frames[].hold` | How many ticks at the clip's fps this frame stays on screen. Default `1`. |
| `references` | Optional guide images drawn under everything, never exported. |

## Export: sprite sheet

`Export → Sprite sheet` produces `<name>.png` + `<name>.json` in the [Aseprite JSON (array) format](https://www.aseprite.org/docs/cli/#data), which Unity, Godot and most engines already understand.

- Frames are packed in a near-square grid of canvas-sized cells, in project order (clip by clip), untrimmed.
- Visible layers are flattened per frame. `duration` is `hold * 1000 / fps` in ms, using the clip's fps override when set.
- `meta.frameTags` carries one tag per clip, named by clip **id**, with `direction: "forward"` and a non-standard `loop` boolean.
- `meta.slices` carries one full-frame slice per clip, named by clip id, keyed at the clip's first frame, with `pivot` in Aseprite's convention: pixels from the top-left. `{0.5, 0}` in `project.json` becomes `{w/2, h}`.
- Pivot per clip is the only thing that doesn't round-trip through Aseprite itself (Aseprite pivots are per slice key, not per tag); `calco-unity` reads the slice that shares the tag's name.

The Unity importer ([`calco-unity/`](../calco-unity/README.md)) reads the same JSON and generates `Sprite`s, `AnimationClip`s and an `AnimatorController`. Install it with `https://github.com/rldona/Calco.git?path=/calco-unity` in the Package Manager.

## Export: GIF

`Export → GIF` writes the current clip as `<name>-<clip>.gif`: one GIF frame per Calco frame, delay `hold / fps`
rounded to 1/100 s, looping forever when the clip loops and once otherwise, transparent background. It's a
preview format for sharing, not for engines; use the sprite sheet for those.
