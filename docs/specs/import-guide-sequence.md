# Spec: import an image sequence as a per-frame guide

Status: implemented. This is the spec as it was built; where the code differed from the first
draft, the code won and the difference is noted under **Adapted to the code**.

## Context

Target workflow: animate the motion as a stick figure in an outside tool (StykAnimate, Pivot, a
text-to-motion model, rotoscoped video…), export one PNG per frame with transparency, and trace
the character over it in Calco. Calco already had `guide: true` layers (shown in the editor, never
exported) and imported reference images, but no way to bring in **a different image per frame**
in one go.

The `.calco` format stays at version 3. Everything the import produces is expressed with what the
manifest already supports: a `guide` layer, one PNG per frame, `hold`. One optional field is added:
`clips[].layers[].tint`.

## Scope

In: N PNG images onto a clip's frames, in order, on a guide layer; adding frames when the clip is
too short; taking 1 in k images and a hold for the frames added; a fit (scale + offset) chosen once
and baked into the PNGs; the guide's opacity and tint; undo / redo as one step.

Out: video, animated GIF or APNG; sprite sheet + JSON; refitting a guide after importing (import
again instead); per-frame references outside the clip.

## UX

Entry points: the **+** over the layer names → **Sequence as guide…**, and a guide layer's menu
→ **Replace sequence…**.

1. The system file picker, several files at once, PNG only; a folder can be picked too, and its
   PNGs are used.
2. Natural order by file name (`frame_2.png` before `frame_10.png`), shown in the sheet.
3. One sheet with a live preview of the image over the frame it goes to, and a slider to look at
   any image with the same fit:
   - **Into:** a new guide layer ("Guide") or a guide already in the clip.
   - **Use one image in** k (default 1) and **New frames last** h (default 1).
   - **Start at:** the first frame (default) or the playhead.
   - **Add the frames that are missing** (default on). Off, only what fits, and the sheet says
     "6 of 12 fit" before importing.
   - **Fit:** Whole (fit, centred), Cover (fill, centred), 1:1 (centred), and an X / Y offset in
     canvas pixels.
   - **Opacity** (default 0.4) and **Tint** (none, red, blue, green; default none).
4. **Import**, with progress when N > 30. The guide ends up current and locked.

The options (k, hold, start, add frames, fit, offset, opacity, tint) are remembered in
`UserDefaults` (`guideSequence.options`).

## Mapping

Images `I[0..N-1]`, step `k`, hold `h`, start `s`:

- Images `I[0], I[k], I[2k]…` are used: M images.
- Used image `j` goes to frame `s + j`.
- Missing frames are added at the end with `hold: h` and nothing on the other layers. Frames that
  already existed keep their `hold`.
- A new guide goes under every layer (index 0 of `layers`), `guide: true`, `locked: true`, with the
  chosen opacity and tint.
- Replacing an existing guide removes its PNGs on every frame of the clip and writes the new ones;
  frames that get no image have no PNG on that layer (and don't hold the one before).
- Images are drawn at canvas size with the fit, premultiplied RGBA, and saved like any layer
  (`clips/<clip>/<frame>/<layer>.png`), with no `.strokes`. Any size or pixel format is converted.
- An unreadable image is skipped: its frame gets no guide, and a message says how many failed.

## Architecture

- `Calco/Model/GuideSequence.swift` (pure): `plan(count:step:start:existing:createMissing:)`, the
  fit `rect(for:in:fit:offset:)`, `rasterize`, `naturalOrder`, and the remembered `Options`.
- `EditorState.importGuideSequence(_:plan:hold:replacing:opacity:tint:name:)`: the one way the
  import changes the project. One undo step: it records the guide's drawing on every frame and
  every cell of the frames it adds before changing anything, so undo brings back the replaced PNGs
  and removes the added frames.
- `Calco/Timeline/GuideSequenceSheet.swift`: the picker and the sheet. The preview composes the
  frame and the image with SwiftUI, no Metal. Decoding and drawing the images at canvas size
  happen off the main thread; the sheet then hands the pixels to the editor.

## Adapted to the code

- **Undo:** Calco has no command objects; edits are `EditorState` methods that snapshot the
  project and the drawings they touch (`recordUndo`). The import is one such method.
- **Loading images:** the single-image import decodes inside the layers menu with ImageIO; the
  sequence uses the same ImageIO decoding (with orientation, up to 4096 px), shared in
  `GuideSequenceFiles.decode`.
- **Fit:** worked out from the first image, as specified, and applied unchanged to every image.
- **Onion skin:** it used to ghost guide layers too. With a guide on every frame that drew a second
  ghost figure, so guides are now left out of the onion skin (criterion 10).
- **Playback:** guides still show while playing in the editor, as before; they're never exported.
- **Pixel art projects:** images are drawn with nearest-neighbour sampling, like other imports.
- **Tint:** shown wherever the editor draws the guide; the onion skin's own tint, when it applies
  to a whole frame, takes over.

## Acceptance criteria and tests

1. Empty clip + 12 PNGs, k=1, h=1 → 12 frames, "Guide" at index 0, guide, locked, 0.4, one PNG
   per frame, hold 1; not in the export. (`GuideSequenceImportTests.testTwelveImagesIntoAnEmptyClipAndOutOfTheExport`)
2. 6 frames with varied holds + 24 PNGs, k=2, h=2 → the 6 keep their holds, 6 more with hold 2,
   12 images. (`testExistingFramesKeepTheirHold`, `GuideSequencePlanTests`)
3. The same with adding frames off → 6 images; the sheet says "6 of 12 fit". (`testWithoutNewFramesOnlyWhatFits`)
4. 1024 images on a 256 canvas: Whole fills the height, centred; 1:1 crops the centre.
   (`testFittingABigImageScalesItDownCentredAndActualSizeCropsIt`, `testTheThreeFits`)
5. Replacing a 10-frame guide with 4 images → frames 1-4 new, 5-10 empty, no other layer changes.
   (`testReplacingASequenceClearsTheRestAndUndoesBack`)
6. Undo after 1 empties the clip and removes the layer; redo brings it back; undo after 5 brings
   back the 10 old PNGs. (same tests)
7. Natural order. (`testNaturalOrder`)
8. One unreadable PNG in 12 → 11 imported, its frame empty, a message. (`testAnUnreadableImageLeavesItsFrameEmpty`)
9. Save, reopen: layer, PNGs, opacity and tint kept; a file without `tint` opens.
   (`testTheGuideSurvivesSavingAndOpening`, `testTintIsOptionalInTheFile`)
10. The onion skin doesn't show the guide. (`testTheOnionSkinLeavesGuidesOut`; guides already stay
    out of exports, `GuideLayerTests`)
