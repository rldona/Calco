# Drawing tools

The rail on the left holds the tools. Tap a tool once to pick it; tap it again to open its options.

![Tool rail](/crops/en/tool-rail.jpg){.rail}

From top to bottom:

- **Brush** (B)
- **Eraser** (E)
- **Fill** (G)
- **Eyedropper** (I)
- **Lasso** (L)
- **Move** (V)
- **Colour**: tap for the palette and the colour picker.
- **Size**: drag the slider, or tap the number for exact values. `[` and `]` on a keyboard.
- **Undo / Redo**: also two-finger and three-finger taps on the canvas.

<div class="clear"></div>

## Brush

![Brush options](/crops/en/brush-options.jpg)

- **Draws**: where the paint goes on the layer.
  - **In front**: over what's already there.
  - **Behind**: under what's there. Colour under line art without touching the lines.
  - **Inside**: only on what's already drawn, keeping its edges. Shading and recolouring.
- **Smoothing**: steadies the line. Higher is calmer, with a little more lag.
- **Pencil pressure changes size**: turn it off for an even line.
- **Only Apple Pencil draws**: fingers never draw; they still zoom, pan and undo. See [Apple Pencil and gestures](./pencil).
- **Pixel art**: hard edges for this project. The brush size becomes a width in pixels: size 1 paints exactly one pixel.

## Eraser

The eraser has its own size, remembered separately from the brush. In pixel art mode it erases whole pixels.

## Fill

![Fill options](/crops/en/fill-options.jpg)

Tap inside an outline to fill it with the current colour. The outline is everything visible, on every layer, but the paint goes only on the current layer. Draw lines on **Line**, select **Color**, and fill there: the colour stays under the lines.

- **Draws**: in front, behind or inside, as with the brush.
- **Close gaps**: bridges small breaks in the line so the paint doesn't leak out. Try **Small** first.

## Eyedropper

Tap anywhere on the canvas to take that colour. Calco then switches back to the tool you had.

## Lasso

Draw around something to lift it into a selection.

![A lasso selection](/crops/en/lasso-selection.jpg)

- **Drag inside** to move it.
- **Corner handle**: scale. **Round handle**: rotate. **Centre dot**: the point it scales and rotates around; drag it to move it.
- The bar above it: **Copy**, **Cut**, **Delete**, **Flip horizontally**, **Cancel** (✕, Esc) and **Apply** (✓, Return). Tapping outside also applies.

Tap the lasso again for **Select all** and **Paste**:

![Lasso options](/crops/en/lasso-options.jpg)

Paste lands where you copied, on whichever frame and layer you're on: handy to carry a pose to another drawing and adjust it.

## Move

**Move** picks up the drawing on the current layer, at the playhead, to move, scale or rotate it, with the same handles as the lasso.

![Move: the whole drawing](/crops/en/move-all.jpg)

- Choosing **Move** picks up the **whole drawing**, in a box that hugs the paint.
- **Tap a stroke** to pick just that one: an eye, a hand, an antenna. Calco remembers every stroke you draw with the brush, so it picks the exact stroke even where it crosses others.
- **Drag a stroke** to pick it up and move it in one go.
- Tap a blank spot to go back to the whole drawing.

![Move: one stroke](/crops/en/move-stroke.jpg)

Where several strokes cross, **tap the same spot again** to go to the one underneath; the hint under the canvas says which one you have. **Add strokes** makes each tap add a stroke to what you're moving, or take it out, to move a few together.

![Picking the stroke underneath](/crops/en/move-crossing.jpg)

Moving, rotating and scaling **click back** into the starting place, upright (or a quarter turn) and the original size, with a light tap you can feel; the pivot clicks back to the middle. So you can always return to where you began. Tap outside, change tool or change frame to drop it; the whole move is one undo step.

- Moved strokes stay strokes: you can pick them again later.
- The **eraser** trims the strokes it crosses. A **fill**, the **lasso** or a paste merge the drawing, which then splits into its separate shapes.
- On a **locked** layer, such as an [imported image](./layers#reference-images), Move offers **Unlock and move**, and locks it again when you're done.

## Pixel art

With **Pixel art** on, every tool works on whole pixels: no soft edges on the brush, eraser, fill or lasso, and moved selections stay crisp. Turn it on when creating the project or in the brush options.

## View

- **Flip view** (the mirror icon in the top bar, or H) shows the drawing mirrored without changing it, to spot mistakes with fresh eyes.
- **Fit** returns to the fitted, upright canvas (⌘0); a flipped view stays flipped.
- **Zen mode** hides everything but the canvas and a small floating bar with undo, redo, every tool and the colour (⌃⌘F).

![Zen mode](/screens/en/zen.jpg)
