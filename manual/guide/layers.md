# Layers

Each clip has a stack of layers, top to bottom in the timeline. New clips start with **Line** on top and **Color** under it, the usual way to animate: lines first, colour after.

Every layer has **its own drawings and its own timing**. Line can change every frame while Color holds the same fill for three, or a background layer can stay still for the whole clip.

## In the timeline

On the left of each row:

- **Eye**: show or hide the layer. Hidden layers aren't exported (Calco warns you before exporting).
- **Name**: tap to draw on that layer. It's highlighted in orange.
- **Lock**: protects the layer from the pencil, eraser, fill and lasso.

Long-press the name for **Rename…**, **Opacity…**, **Mask to layer below**, **Move up**, **Move down** and **Delete layer…**.

## The layers panel

**Layers** in the bottom bar opens the full panel: drag the handle to reorder, an opacity slider for the selected layer, and buttons to add, rename, clear, mask and delete.

![Layers panel](/crops/en/layers-panel.jpg)

## New layer

**New layer** in the bottom bar offers three kinds:

![New layer menu](/crops/en/new-layer-menu.jpg)

- **Empty layer**: a blank layer above the current one.
- **Same timing as Line, blank**: a layer *under* the current one with the same drawings and holds, all empty. Perfect for a colour pass: one empty drawing waiting under each line drawing.
- **Duplicate Line**: a copy with all its drawings.

## Mask to layer below

A masked layer only shows where the layer under it has paint, like a clipping mask. Put a **Shadows** layer above **Color**, mask it, and paint freely: the shadows never spill outside the colour. Several masked layers in a row share the same base. Masked layers export flattened, exactly as you see them.

::: tip Colour and line, step by step
1. Draw the animation on **Line**.
2. **New layer → Same timing as Line, blank** creates a colour layer under it.
3. Select it and use the **fill**: the lines on Line are the outline, and the paint goes on the colour layer.
:::
