# Canvas PoC

Branch `canvas-poc`. Goal: decide whether Metal + raw UIKit touches gives a stroke that feels good enough to build Calco on.

## What it does

- 1024×1024 RGBA canvas texture, aspect-fit on screen with a dark background.
- Apple Pencil input via `coalescedTouches` (240 Hz on recent iPads), pressure mapped to radius.
- Strokes rendered as instanced round stamps, premultiplied blending, 120 Hz redraw.
- A latency readout: time from the touch's hardware timestamp to the moment the stamp is enqueued.

## What to judge

1. Does the line keep up with the Pencil tip? Drag fast; the gap between tip and ink should be ~2 frames.
2. Pressure curve: light → thin, firm → thick, no steps.
3. Stamp spacing: no visible beads at any speed.

## Known gaps (on purpose)

- No predicted touches. If the lag feels bad, add a prediction overlay that is rewound each frame.
- No zoom/pan, no undo, no layers, no eraser.
- Straight-line stamping between samples. Catmull-Rom smoothing comes later if corners look polygonal.
