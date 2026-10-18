using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace Calco
{
    /// <summary>
    /// Slices a texture into sprites when a Calco/Aseprite JSON sits next to it, then hands the
    /// imported sprites to <see cref="CalcoAnimationBuilder"/>. Everything else about the texture
    /// (filter, PPU, compression) is left to the user.
    /// </summary>
    public sealed class CalcoSheetPostprocessor : AssetPostprocessor
    {
        void OnPreprocessTexture()
        {
            var sheet = CalcoSheet.LoadFor(assetPath, out _);
            if (sheet == null) return;
            var importer = (TextureImporter)assetImporter;
            ApplySlicing(importer, sheet, Path.GetFileNameWithoutExtension(assetPath));
        }

        static void ApplySlicing(TextureImporter importer, CalcoSheet sheet, string sheetName)
        {
            importer.textureType = TextureImporterType.Sprite;
            importer.spriteImportMode = SpriteImportMode.Multiple;
            if (importer.mipmapEnabled) importer.mipmapEnabled = false;

            int texHeight = sheet.meta.size != null && sheet.meta.size.h > 0 ? sheet.meta.size.h : TextureHeight(importer);
            int texWidth = sheet.meta.size != null ? sheet.meta.size.w : 0;

            // Unity's default max size is 2048; a downscaled sheet would make every rect wrong.
            int needed = Mathf.NextPowerOfTwo(Mathf.Max(texWidth, texHeight));
            if (needed > importer.maxTextureSize) importer.maxTextureSize = Mathf.Min(needed, 16384);

            var metas = new List<SpriteMetaData>(sheet.frames.Length);
            for (int i = 0; i < sheet.frames.Length; i++)
            {
                var f = sheet.frames[i].frame;
                if (f == null) continue;
                var tag = sheet.TagForFrame(i);
                metas.Add(new SpriteMetaData
                {
                    name = sheet.SpriteName(sheetName, i),
                    // Aseprite rects are top-left; Unity's are bottom-left.
                    rect = new Rect(f.x, texHeight - f.y - f.h, f.w, f.h),
                    alignment = (int)SpriteAlignment.Custom,
                    pivot = sheet.PivotFor(tag, sheet.frames[i]),
                    border = Vector4.zero,
                });
            }

#pragma warning disable CS0618 // spritesheet is deprecated in favour of ISpriteEditorDataProvider; it still works and needs no extra package.
            importer.spritesheet = metas.ToArray();
#pragma warning restore CS0618
        }

        static int TextureHeight(TextureImporter importer)
        {
            // Only needed when the JSON has no meta.size; read the PNG header (IHDR height at byte 20, big-endian).
            try
            {
                using var stream = File.OpenRead(importer.assetPath);
                var header = new byte[24];
                if (stream.Read(header, 0, 24) == 24 && header[1] == (byte)'P' && header[2] == (byte)'N' && header[3] == (byte)'G')
                    return (header[20] << 24) | (header[21] << 16) | (header[22] << 8) | header[23];
            }
            catch { /* fall through */ }
            return 0;
        }

        static void OnPostprocessAllAssets(string[] imported, string[] deleted, string[] moved, string[] movedFrom)
        {
            var textures = new HashSet<string>();
            var reimport = new HashSet<string>();
            foreach (var path in imported)
            {
                var ext = Path.GetExtension(path).ToLowerInvariant();
                if (ext == ".png")
                {
                    if (CalcoSheet.LoadFor(path, out _) != null) textures.Add(path);
                }
                else if (ext == ".json")
                {
                    // JSON changed on its own (re-export over the same PNG): reimport the texture so slicing updates.
                    var png = Path.ChangeExtension(path, ".png");
                    if (File.Exists(png) && CalcoSheet.LoadFor(png, out _) != null) reimport.Add(png);
                }
            }
            reimport.ExceptWith(textures);
            if (textures.Count == 0 && reimport.Count == 0) return;

            // OnPostprocessAllAssets is the one postprocessor callback where creating assets is supported.
            // (EditorApplication.delayCall never fires in -batchmode -quit, so it can't be relied on here.)
            foreach (var png in reimport)
                AssetDatabase.ImportAsset(png, ImportAssetOptions.ForceUpdate);
            foreach (var texture in textures)
                CalcoAnimationBuilder.Build(texture);
        }

        // MARK: Menu

        const string MenuPath = "Assets/Calco/Reimport sprite sheet";

        [MenuItem(MenuPath, priority = 2000)]
        static void ReimportSelected()
        {
            foreach (var png in SelectedSheets())
                AssetDatabase.ImportAsset(png, ImportAssetOptions.ForceUpdate);
        }

        [MenuItem(MenuPath, validate = true)]
        static bool ValidateReimportSelected() => SelectedSheets().Count > 0;

        static List<string> SelectedSheets()
        {
            var result = new List<string>();
            foreach (var obj in Selection.objects)
            {
                var path = AssetDatabase.GetAssetPath(obj);
                if (string.IsNullOrEmpty(path)) continue;
                var png = Path.GetExtension(path).ToLowerInvariant() == ".json" ? Path.ChangeExtension(path, ".png") : path;
                if (Path.GetExtension(png).ToLowerInvariant() == ".png" && File.Exists(png)
                    && CalcoSheet.LoadFor(png, out _) != null && !result.Contains(png))
                    result.Add(png);
            }
            return result;
        }
    }
}
