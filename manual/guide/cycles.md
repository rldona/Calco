# Cycles and inbetweens

## Repeat as a cycle

A walk, a run or an idle breath repeats the same few drawings. Instead of copying them, **repeat** them linked: change one and every repeat changes with it.

![Repeat as a cycle](/crops/en/repeat-popover.jpg)

1. Go to the last drawing of the cycle.
2. Tap **More → Repeat drawings…** on the animation rail and choose how many of the last drawings to repeat.
3. Tap **Repeat N drawings**. They're added after the playhead, with the same timing.

Repeats show a **link icon** and the number of the drawing they repeat. Drawing on a repeat edits the original. Labels carry over too, so a *step* event fires on every loop in Unity.

- **Unlink** (on the rail, or long-press the cell) turns a repeat into its own drawing, keeping a copy.
- Deleting a repeat never deletes the original.
- With **All** on the rail, the frames repeat on every layer.

## Inbetween halfway

To add a pose between two drawings, split the time of the first one in two: **More → Split drawing halfway**.

![Split drawing halfway](/crops/en/split-menu.jpg)

- **Blank inbetween halfway**: the second half becomes a new, empty drawing to draw the inbetween. The onion skin shows the drawings on both sides.
- **Duplicate split halfway**: the second half becomes a copy, to adjust from there.

The clip's total length doesn't change, and other layers are untouched. The drawing must last at least 2 frames; with an odd length, the first half keeps the extra frame.
