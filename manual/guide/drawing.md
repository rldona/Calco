# Drawing tools

The rail on the left holds the tools. Tap a tool once to pick it; tap it again to open its options.

![Tool rail](/crops/en/tool-rail.jpg){.rail}

From top to bottom:

- **Brush** (B)
- **Eraser** (E)
- **Fill** (G)
- **Eyedropper** (I)
- **Lasso** (L)
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

## Pixel art

With **Pixel art** on, every tool works on whole pixels: no soft edges on the brush, eraser, fill or lasso, and moved selections stay crisp. Turn it on when creating the project or in the brush options.

## View

- **Flip view** (the mirror icon in the top bar, or H) shows the drawing mirrored without changing it, to spot mistakes with fresh eyes.
- **Fit** returns to the fitted, upright canvas (⌘0); a flipped view stays flipped.
- **Zen mode** hides everything but the canvas and a small floating bar (⌃⌘F).

![Zen mode](/screens/en/zen.jpg)
