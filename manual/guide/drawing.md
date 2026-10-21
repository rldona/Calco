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
- **Shapes** (U)
- **Pen** (P)
- **Node** (A)
- **Smudge** (S)
- **Colour**: tap for the palette and the colour picker.
- **Size**: drag the slider, or tap the number for exact values. `[` and `]` on a keyboard.
- **Undo / Redo**: also two-finger and three-finger taps on the canvas.

<div class="clear"></div>

::: tip In portrait
Turn the iPad upright and the tools lie across the top, under the document's name, with the size slider running sideways. The canvas gets the whole width.
:::

## Brush

Tap the brush again to open the **brush library**: every brush with a sample of how it paints.

![Brush library](/crops/en/brush-library.jpg)

| Brush | What it's for |
|---|---|
| **Inker** | Clean line art: thins with light pressure. |
| **Ballpoint** | Fine, steady lines and small details. |
| **Marker** | Bold and even, at 70 %: it doesn't get darker where the stroke crosses itself. |
| **Pencil** | Sketching on paper grain; light pressure is lighter, and tilting the Pencil shades with the side of the lead. |
| **Blue pencil** | The same pencil, always light blue, for roughing out motion under the clean line. |
| **Charcoal** | Rough and grainy, for quick masses. |
| **Paintbrush** | Soft edge and a tip that tapers in. |
| **Airbrush** | Very soft; builds up as you go over it, for gradients and glows. |
| **Flat** | A hard, even fill with no pressure: colouring. |

Each brush remembers **its own size and opacity**: the size slider on the rail shows the current brush's, and **Opacity** sits under the library. The rail's brush icon changes to the brush you chose.

The **Settings** tab has the options for every brush:

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

The eraser has its own size, remembered separately from the brushes. Tap it again to choose its **tip**: any brush's edge, like a soft airbrush or a grainy pencil. In pixel art mode it erases whole pixels.

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
- **Corner handle**: scale. **Side handles**: stretch it wider or taller, for squash and stretch. **Round handle**: rotate. **Centre dot**: the point it scales, stretches and rotates around; drag it to move it (to the feet, say, so a squash keeps them on the ground).
- While you scale or stretch, a chip shows the width and height as a percentage. Each one **clicks** back to 100 %, or to the other's proportions, with a light haptic tap.
- **Uniform | Free**, under the canvas, is what the corner does: keep the proportions, or stretch width and height apart.
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

Scaled, stretched or turned, a stroke **stays sharp**: Calco paints it again where it lands, with its brush, instead of resampling its pixels. Strokes that were erased, filled or lassoed, and imported images, are resampled.

Where several strokes cross, **tap the same spot again** to go to the one underneath; the hint under the canvas says which one you have. **Add strokes** makes each tap add a stroke to what you're moving, or take it out, to move a few together.

![Picking the stroke underneath](/crops/en/move-crossing.jpg)

Moving, rotating and scaling **click back** into the starting place, upright (or a quarter turn) and the original size, with a light tap you can feel; the pivot clicks back to the middle. So you can always return to where you began. Tap outside, change tool or change frame to drop it; the whole move is one undo step.

- Moved strokes stay strokes: you can pick them again later.
- The **eraser** trims the strokes it crosses. A **fill**, the **lasso** or a paste merge the drawing, which then splits into its separate shapes.
- On a **locked** layer, such as an [imported image](./layers#reference-images), Move offers **Unlock and move**, and locks it again when you're done.

## Shapes

**Shapes** draws lines, arrows, rectangles, ellipses, triangles, polygons, stars and rounded rectangles. Its icon in the bar shows the shape chosen; tap it again for its options:

- **Shape**, and the polygon's **sides** or the star's **points**.
- **Outline**: solid, dashed or dotted.
- **Thickness**: also with the size slider while Shapes is chosen.
- **Fill**: no fill, filled, or fill only. With a fill, pick **Line's colour** or **Its own** to give the inside a colour of its own, apart from the outline (the bar's colour).
- **Brush**: the inker, for a clean line, or the brush you have chosen (a pencil square, with grain).

Drag from corner to corner on the canvas; the shape comes out in the bar's colour when you lift. Near 1:1 it **clicks** into a perfect square or circle, and lines and arrows every 45°, with a light haptic tap; the chip under it gives the size.

Each shape is one undo, and a piece of its drawing: with **Move**, one tap picks it all up, and it stays sharp when scaled, stretched or turned.

## Pen

The **Pen** draws by joining points:

- **Tap** to place a point; a straight line joins it to the one before.
- **Drag as you place a point**, or pull it afterwards, to curve it: two handles come out that shape the curve on each side. Pull a handle to change it; on a curved point both turn together.
- **Tap the line** to add a point there and curve from that spot.
- **Tap the first point** to close the path.

While the path is open, the bar under the canvas turns the picked point into a **Corner** or a **Curve**, closes or opens the path, **deletes the point**, opens its **Style**, cancels (✕) or finishes it (✓, **Done**). Changing tool, frame or layer finishes it too.

**Style** (or tapping the Pen again) changes the open path's outline (solid, dashed or dotted), thickness, fill (on closed paths) and brush; they're the same settings as **Shapes**. The colour is the bar's: opening a path puts its colour in the bar, and a new colour goes to it.

A path **can be edited again**: with the Pen, tap it and its points come back. It's a piece of the drawing, so **Move** picks it up whole and it stays sharp when scaled or turned.

## Node

**Node** edits paths and shapes point by point, and never draws:

- **Tap a Pen path or a shape** to see its nodes. Shapes (rectangles, ellipses, polygons…) edit like paths: an ellipse is four curved nodes. Arrows can't be edited this way.
- **Drag a node** or its handles to change the shape. Node never adds nodes: that's the Pen's job.
- **Drag on an empty spot** to draw a box: it picks every node inside, and dragging one moves them all together.
- **Tap a node twice** to switch it between corner and curve.
- **Tap an empty spot** to let go of the picked nodes; again, to finish.

The bar under the canvas is the Pen's: how many nodes you have, **Corner** or **Curve** for all of them, delete them, cancel or finish. You can switch between the Pen and Node without closing the path.

## Smudge

**Smudge** works the paint already on the layer:

- **Smear** drags it along with your finger.
- **Blur** softens it where you go over it.
- **Motion** blurs it along the way you move, like a trail.

Tap Smudge again for the mode, the **strength** and the **tip** (soft, or the chosen brush's). The size is the bar's, and pressing harder with the Pencil works the paint more. Whatever Smudge goes over is no longer a stroke Move remembers: it stays as pixels.

## Pixel art

With **Pixel art** on, every tool works on whole pixels: no soft edges on the brush, eraser, fill or lasso, and moved selections stay crisp. Turn it on when creating the project or in the brush options.

## View

- **Flip view** (the mirror icon in the top bar, or H) shows the drawing mirrored without changing it, to spot mistakes with fresh eyes.
- **Fit** returns to the fitted, upright canvas (⌘0); a flipped view stays flipped.
- **Zen mode** hides everything but the canvas and a small floating bar with undo, redo, every tool and the colour. Swipe **three fingers down** to go in and **up** to come out, like the timeline's grip (or ⌃⌘F).

![Zen mode](/screens/en/zen.jpg)
