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

`Export → Sprite sheet` produces `<name>.png` + `<name>.json` in the [Aseprite JSON (array) format](https://www.aseprite.org/docs/cli/#data), which Unity, Godot and most engines already understand. Layers are flattened per frame; `frameTags` carry the clips; `meta.slices` carries the pivot as a `pivot` on a full-frame slice.

The Unity importer (`calco-unity`) reads the same JSON and generates `Sprite`s, `AnimationClip`s and an `AnimatorController`.
