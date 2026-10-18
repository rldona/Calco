# Timeline and drawings

The timeline is the bottom part of the editor: the clips and playback on top, a row per layer, and the bar with the drawing actions.

![The timeline](/crops/en/timeline.jpg)

## Make it taller

Drag the **grip** at the top of the timeline (the short bar in the middle) upwards to make room for more layers: the rows grow up to a comfortable height and the canvas gets smaller. Calco remembers the height. **Double-tap** the grip to go back to the automatic height, which fits the layers you have.

## Top row

- **▶** plays the clip (Space). The counter shows frame / total.
- **Clips** (Idle, Walk, Jump): tap to switch. The **…** button has more; see [Clips and pivot](./clips).
- **Loop** turns looping on or off for this clip.
- **fps − +** is the clip's speed. The arrow resets it to the project's fps.
- **Pivot** shows the pivot point; see [Clips and pivot](./clips).
- On the right, the [onion skin](./onion-skin).

## Cells

Each layer row is a strip of **cells**. A cell is one drawing, and its width is how long it lasts.

- Tap a cell to go there and draw on that layer.
- A dashed cell has nothing drawn yet.
- An arrow → means the drawing keeps showing in the following frames (a hold).
- A label (for example *step*) replaces the number when the drawing has one.
- A link icon means a [linked repeat](./cycles).

**Drag a cell's right edge** with the Pencil or a finger to make that drawing last longer or shorter. What comes after moves along: lengthening a drawing pushes the next one instead of covering it.

Long-press a cell for its menu:

![Cell menu](/crops/en/cell-menu.jpg)

- **Hold previous drawing**: this layer keeps showing the drawing before.
- **New drawing here** / **Copy drawing here**: give a held cell its own drawing, blank or as a copy.
- **Label…**: a name shown in the cell (contact, passing…). Labels can become Unity animation events.
- **Clear drawing**.

## The bar

![The bar](/crops/en/bottom-bar.jpg)

**Lasts N frames − +** sets how long the frame at the playhead stays on screen. It lights up orange when it lasts more than one.

The orange box acts on **the current layer's drawing**; its caption says which one (*Line · drawing 3*):

| Button | What it does |
|---|---|
| Hold previous / New drawing / Copy drawing | Same as the cell menu, for the current cell. |
| Label | Name the drawing. |
| Split drawing halfway | An inbetween; see [Cycles and inbetweens](./cycles). |
| Repeat drawings | A cycle; see [Cycles and inbetweens](./cycles). |
| Duplicate | Copies the drawing into a new frame after it. |
| Trash | Deletes the drawing. The one before keeps showing; a frame left with nothing of its own goes away. |
| **+** | A new blank drawing after the playhead, on this layer. The other layers keep showing what they had. |

### Sync layers

With **Sync layers** on, the same buttons act on **whole frames**, every layer at once.

![Sync layers on](/crops/en/sync-layers-bar.jpg)

### The Frame menu

**Frame** groups the actions that always affect every layer:

![Frame menu](/crops/en/frame-menu.jpg)

Add, duplicate, move earlier or later, set the **playback range** (play from or up to this frame), and delete the frame.
