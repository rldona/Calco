# Calco Importer for Unity

Drop a sprite sheet exported by [Calco](https://github.com/rldona/Calco) (`Hero.png` + `Hero.json`) into
your project and get, next to it:

- `Hero.png` sliced into Sprites, one per frame, pivots from each clip
- `Hero_idle.anim`, `Hero_run.anim`… one `AnimationClip` per clip, frame timing from the sheet, loop from the clip
- `Hero.controller`, an `AnimatorController` with one state per clip (first clip is the default)

Re-export from Calco and re-import: sprites, clips and controller are regenerated in place, so references
from your scenes and prefabs survive.

## Install

Unity 2021.3 or newer. In **Window → Package Manager → + → Add package from git URL…**:

```
https://github.com/rldona/Calco.git?path=/calco-unity
```

## Use

1. In Calco, **File → Export…**, pick a sprite sheet profile ("Unity", "Unity · trimmed"…) and share the
   PNG + JSON to your Unity project's `Assets/`.
   Keep them in the same folder with the same base name.
2. Unity imports the PNG; the importer sees the JSON and does the rest.
3. Put `Hero.controller` on an `Animator` next to a `SpriteRenderer`.

Nothing to configure. If you change import settings on the texture (filter mode, pixels per unit, compression)
they're kept; only sprite rects and pivots are rewritten from the JSON on each import.

### What's read from the JSON

The JSON is the [Aseprite array format](https://www.aseprite.org/docs/cli/#data), so sheets exported from
Aseprite itself also work:

| JSON | Unity |
|---|---|
| `frames[].frame` | Sprite rect (y flipped, Unity's origin is bottom-left) |
| `frames[].duration` | Keyframe timing in the clip (ms) |
| `meta.frameTags[]` | One `AnimationClip` per tag, named `<sheet>_<tag>` |
| `meta.frameTags[].loop` | Clip `loopTime`. Calco writes it; absent (plain Aseprite) means loop |
| `meta.slices[]` named like a tag | That tag's sprite pivot, converted from top-left pixels to normalized bottom-left |
| `frames[].label` (Calco) | An `AnimationEvent` calling `OnCalcoLabel(string)` with the label, at that frame's time. Export with "Labels as animation events" |
| `meta.pixelsPerUnit` (Calco) | Texture pixels per unit, when the export profile sets it; otherwise your setting is kept |
| `frames[].trimmed`, `spriteSourceSize`, `sourceSize` | For trimmed frames the canvas pivot is moved onto the trimmed box, so the character stands in the same place as untrimmed (the pivot may fall outside the box, e.g. feet below a trimmed shadow) |

Pixels per unit default to **100**, Unity's default. Set it in the Calco export profile, or change it on the
texture yourself (kept across reimports unless the profile sets it).

To react to labels, put a script with `void OnCalcoLabel(string label)` next to the `Animator` (footsteps,
hit frames…). Unity warns at runtime when an event has no receiver, so only turn events on when you use them.

## Force a rebuild

Right-click the PNG or JSON → **Calco → Reimport sprite sheet**.

## Development

There are no Unity tests yet; the package is checked by importing a sheet into a throwaway project from the
command line. Create a project with `Packages/manifest.json` pointing at this folder
(`"dev.plazoleta.calco-unity": "file:/path/to/Calco/calco-unity"`), drop a `Hero.png` + `Hero.json` into
`Assets/`, then:

```sh
/Applications/Unity/Hub/Editor/<version>/Unity.app/Contents/MacOS/Unity \
  -batchmode -nographics -quit -projectPath <project> -logFile import.log
```

`Hero.png.meta` should list one sprite per frame with rect and pivot, and `Hero_<tag>.anim` +
`Hero.controller` should appear next to the PNG. Everything runs synchronously inside
`OnPostprocessAllAssets`; `EditorApplication.delayCall` is avoided on purpose because it never fires in
`-batchmode -quit`.
