using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Animations;
using UnityEngine;

namespace Calco
{
    /// <summary>
    /// Turns an imported sheet into one AnimationClip per tag and an AnimatorController with one
    /// state per clip. Assets are updated in place so existing references keep working.
    /// </summary>
    public static class CalcoAnimationBuilder
    {
        public static void Build(string texturePath)
        {
            var sheet = CalcoSheet.LoadFor(texturePath, out _);
            if (sheet == null || sheet.meta.frameTags == null || sheet.meta.frameTags.Length == 0) return;

            var sprites = AssetDatabase.LoadAllAssetRepresentationsAtPath(texturePath).OfType<Sprite>().ToArray();
            if (sprites.Length == 0)
            {
                Debug.LogWarning($"[Calco] {texturePath} has no sprites yet; skipping animation build.");
                return;
            }

            // AssetDatabase paths always use '/', also on Windows.
            string folder = Path.GetDirectoryName(texturePath).Replace('\\', '/');
            string sheetName = Path.GetFileNameWithoutExtension(texturePath);
            var byName = sprites.ToDictionary(s => s.name, s => s);

            var clips = new List<(CalcoSheet.Tag tag, AnimationClip clip)>();
            foreach (var tag in sheet.meta.frameTags)
            {
                var clip = BuildClip(sheet, tag, sheetName, byName, $"{folder}/{sheetName}_{tag.name}.anim");
                if (clip != null) clips.Add((tag, clip));
            }
            if (clips.Count == 0) return;

            BuildController($"{folder}/{sheetName}.controller", clips);
            AssetDatabase.SaveAssets();
        }

        static AnimationClip BuildClip(CalcoSheet sheet, CalcoSheet.Tag tag, string sheetName,
                                       Dictionary<string, Sprite> byName, string path)
        {
            var keys = new List<ObjectReferenceKeyframe>();
            float time = 0f;
            Sprite last = null;
            for (int i = tag.from; i <= tag.to && i < sheet.frames.Length; i++)
            {
                if (!byName.TryGetValue(sheet.SpriteName(sheetName, i), out var sprite)) continue;
                keys.Add(new ObjectReferenceKeyframe { time = time, value = sprite });
                time += Mathf.Max(sheet.frames[i].duration, 1) / 1000f;
                last = sprite;
            }
            if (keys.Count == 0) return null;
            // Repeat the last sprite at the end so the final frame holds for its full duration.
            keys.Add(new ObjectReferenceKeyframe { time = time, value = last });

            var clip = AssetDatabase.LoadAssetAtPath<AnimationClip>(path);
            bool isNew = clip == null;
            if (isNew) clip = new AnimationClip();

            clip.ClearCurves();
            clip.frameRate = FrameRate(sheet, tag);
            var binding = EditorCurveBinding.PPtrCurve("", typeof(SpriteRenderer), "m_Sprite");
            AnimationUtility.SetObjectReferenceCurve(clip, binding, keys.ToArray());

            var settings = AnimationUtility.GetAnimationClipSettings(clip);
            settings.loopTime = tag.loop;
            settings.stopTime = time;
            AnimationUtility.SetAnimationClipSettings(clip, settings);

            if (isNew) AssetDatabase.CreateAsset(clip, path);
            else EditorUtility.SetDirty(clip);
            return clip;
        }

        /// <summary>Editor display rate: the clip's fps when every frame shares a duration, else 60.</summary>
        static float FrameRate(CalcoSheet sheet, CalcoSheet.Tag tag)
        {
            int first = -1;
            for (int i = tag.from; i <= tag.to && i < sheet.frames.Length; i++)
            {
                int d = sheet.frames[i].duration;
                if (first < 0) first = d;
                else if (d != first) return 60f;
            }
            return first > 0 ? Mathf.Round(1000f / first) : 12f;
        }

        static void BuildController(string path, List<(CalcoSheet.Tag tag, AnimationClip clip)> clips)
        {
            var controller = AssetDatabase.LoadAssetAtPath<AnimatorController>(path)
                             ?? AnimatorController.CreateAnimatorControllerAtPath(path);
            if (controller.layers.Length == 0) controller.AddLayer("Base Layer");
            var machine = controller.layers[0].stateMachine;

            var wanted = new HashSet<string>(clips.Select(c => c.tag.name));
            var existing = machine.states.ToDictionary(s => s.state.name, s => s.state);

            // Drop states for clips that no longer exist in the sheet.
            foreach (var kv in existing.Where(kv => !wanted.Contains(kv.Key)).ToList())
            {
                machine.RemoveState(kv.Value);
                existing.Remove(kv.Key);
            }

            AnimatorState first = null;
            for (int i = 0; i < clips.Count; i++)
            {
                var (tag, clip) = clips[i];
                if (!existing.TryGetValue(tag.name, out var state))
                {
                    state = machine.AddState(tag.name, new Vector3(300, 60 + 70 * i, 0));
                    existing[tag.name] = state;
                }
                state.motion = clip;
                if (first == null) first = state;
            }
            if (first != null && machine.defaultState != first) machine.defaultState = first;
            EditorUtility.SetDirty(controller);
        }
    }
}
