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

1. In Calco, **File → Export sprite sheet…** and share the PNG + JSON to your Unity project's `Assets/`.
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

Pixels per unit default to **100**, Unity's default. Change it on the texture if your canvas isn't that scale;
it's preserved across reimports.

## Force a rebuild

Right-click the PNG or JSON → **Calco → Reimport sprite sheet**.
