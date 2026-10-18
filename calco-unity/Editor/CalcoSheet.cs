using System;
using System.IO;
using UnityEngine;

namespace Calco
{
    /// <summary>
    /// The Aseprite JSON "array" format as Calco writes it (docs/format.md), shaped for JsonUtility.
    /// Fields JsonUtility doesn't find keep their defaults, so plain Aseprite exports parse too.
    /// </summary>
    [Serializable]
    public sealed class CalcoSheet
    {
        [Serializable] public sealed class Rect { public int x, y, w, h; }
        [Serializable] public sealed class Size { public int w, h; }
        [Serializable] public sealed class Point { public int x, y; }

        [Serializable]
        public sealed class Frame
        {
            public string filename;
            public Rect frame;
            public bool rotated;
            public bool trimmed;
            public Rect spriteSourceSize;
            public Size sourceSize;
            /// <summary>Milliseconds.</summary>
            public int duration = 100;
            /// <summary>Calco extension: drawing labels starting on this frame, comma-separated. Become animation events.</summary>
            public string label;
        }

        [Serializable]
        public sealed class Tag
        {
            public string name;
            public int from;
            public int to;
            public string direction = "forward";
            /// <summary>Calco extension. Absent in plain Aseprite files, which then loop.</summary>
            public bool loop = true;
        }

        [Serializable]
        public sealed class SliceKey
        {
            public int frame;
            public Rect bounds;
            /// <summary>Pixels from the top-left of <see cref="bounds"/>, Aseprite's convention.</summary>
            public Point pivot;
        }

        [Serializable]
        public sealed class Slice
        {
            public string name;
            public string color;
            public SliceKey[] keys;
        }

        [Serializable]
        public sealed class Meta
        {
            public string app;
            public string version;
            public string image;
            public string format;
            public Size size;
            public string scale;
            public Tag[] frameTags;
            public Slice[] slices;
            /// <summary>Calco extension. 0 (absent) leaves the texture's pixels per unit alone.</summary>
            public int pixelsPerUnit;
        }

        public Frame[] frames;
        public Meta meta;

        public bool IsValid => frames != null && frames.Length > 0 && meta != null;

        /// <summary>The JSON next to a texture, or null when there is none worth importing.</summary>
        public static CalcoSheet LoadFor(string texturePath, out string jsonPath)
        {
            jsonPath = Path.ChangeExtension(texturePath, ".json");
            if (!File.Exists(jsonPath)) return null;
            try
            {
                var sheet = JsonUtility.FromJson<CalcoSheet>(File.ReadAllText(jsonPath));
                return sheet != null && sheet.IsValid ? sheet : null;
            }
            catch (Exception e)
            {
                Debug.LogWarning($"[Calco] Ignoring {jsonPath}: {e.Message}");
                return null;
            }
        }

        /// <summary>Normalized pivot, origin bottom-left (Unity), for a tag. Falls back to bottom-center.</summary>
        public Vector2 PivotFor(Tag tag)
        {
            if (meta.slices != null)
            {
                foreach (var slice in meta.slices)
                {
                    if (slice.name != tag.name || slice.keys == null || slice.keys.Length == 0) continue;
                    var key = slice.keys[0];
                    if (key.bounds == null || key.pivot == null || key.bounds.w == 0 || key.bounds.h == 0) continue;
                    return new Vector2(
                        (float)key.pivot.x / key.bounds.w,
                        1f - (float)key.pivot.y / key.bounds.h);
                }
            }
            return new Vector2(0.5f, 0f);
        }

        /// <summary>
        /// Pivot for one sprite. Same as <see cref="PivotFor(Tag)"/> for full-canvas frames; for trimmed
        /// frames the canvas pivot is moved onto the trimmed box, so the character stays put in the scene.
        /// </summary>
        public Vector2 PivotFor(Tag tag, Frame frame)
        {
            var canvasPivot = tag != null ? PivotFor(tag) : new Vector2(0.5f, 0f);
            var box = frame.spriteSourceSize;
            var canvas = frame.sourceSize;
            if (!frame.trimmed || box == null || canvas == null || box.w == 0 || box.h == 0 || canvas.w == 0 || canvas.h == 0)
                return canvasPivot;
            // Canvas pivot in pixels from the top-left, then relative to the box, back to bottom-left normalized.
            float px = canvasPivot.x * canvas.w;
            float py = (1f - canvasPivot.y) * canvas.h;
            return new Vector2((px - box.x) / box.w, 1f - (py - box.y) / box.h);
        }

        /// <summary>Tag that owns frame <paramref name="index"/>, or null.</summary>
        public Tag TagForFrame(int index)
        {
            if (meta.frameTags == null) return null;
            foreach (var tag in meta.frameTags)
                if (index >= tag.from && index <= tag.to) return tag;
            return null;
        }

        /// <summary>Sprite name for frame i: "<sheet>_<tag>_<n>" or "<sheet>_<i>" for untagged frames.</summary>
        public string SpriteName(string sheetName, int index)
        {
            var tag = TagForFrame(index);
            return tag == null
                ? $"{sheetName}_{index}"
                : $"{sheetName}_{tag.name}_{index - tag.from}";
        }
    }
}
