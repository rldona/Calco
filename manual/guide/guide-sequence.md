# Tracing a motion

Animate the motion somewhere else first, as a stick figure in StykAnimate or Pivot, from a text-to-motion model or from rotoscoped video, export one PNG per frame, and trace your character over it in Calco. The images come in as a **guide**: one per frame, faint, never exported.

## In five steps

1. Export the motion as **PNG images, one per frame**, with a transparent background if you can. Name them in order: `walk_1.png`, `walk_2.png`… (Calco sorts `walk_2` before `walk_10`).
2. In Calco, open the clip and tap **+** over the layer names → **Sequence as guide…**.
3. Pick the images, or the folder that holds them.
4. Check the options (below) with the preview: it shows each image over the frame it goes to. Drag the slider under it to look at any of them.
5. Tap **Import**. The guide goes under every layer, locked, so your first stroke doesn't land on it. Pick the layer you draw on and trace.

## The options

| Option | What it does |
|---|---|
| **Into** | A new guide layer (called **Guide**), or a guide that's already in the clip, whose images are replaced. |
| **Use one image in** | 1 uses them all; 2 every other one, for animating on twos from a 24 fps export. |
| **New frames last** | How long the frames the import adds last. The frames already in the clip keep their length. |
| **Start at** | The first frame, or the frame at the playhead. |
| **Add the frames that are missing** | When there are more images than frames, add frames at the end. Off, only the images that fit come in, and the sheet tells you how many. |
| **Fit** | **Whole**: the whole image, as big as fits. **Cover**: fills the canvas, cutting the edges. **1:1**: its own size, centred. **Offset X / Y** move it, in canvas pixels. The first image decides the fit and every other one gets the same, so the figure doesn't jump. |
| **Opacity** and **Tint** | How faint it is (40 % to start), and a colour for its lines (red, blue or green) so they don't read as drawing. |

Calco remembers these for next time.

## Afterwards

- The guide is a layer like the others: hide it, change its opacity, unlock it.
- To use another take, long-press the guide's name → **Replace sequence…**. Every image it had goes, and the new ones come in with the same options.
- It's never exported, the fill ignores it, and the onion skin doesn't ghost it.
- One **undo** takes the whole import back, frames included.
- An image that can't be read leaves its frame without a guide; Calco says how many when it finishes.
