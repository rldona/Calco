import CoreGraphics
import Foundation

/// A Godot 4 `SpriteFrames` resource (.tres, text) for a sprite sheet: one animation per clip,
/// one AtlasTexture per frame. Holds become frame durations (Godot's duration is relative: a
/// frame lasts `duration / speed` seconds, so duration = hold and speed = the clip's fps).
/// Trimmed frames get an AtlasTexture margin, so they still line up as full-canvas frames.
///
/// Godot has no per-animation pivot: centre or offset the AnimatedSprite2D yourself.
enum GodotExport {

    static func spriteFrames(_ sheet: SpriteSheet, project: Project, imageName: String) -> String {
        let scale = sheet.scale
        let canvasW = Int((Double(project.canvas.width) * scale).rounded())
        let canvasH = Int((Double(project.canvas.height) * scale).rounded())
        func s(_ v: CGFloat) -> Int { Int((Double(v) * scale).rounded()) }

        var out = "[gd_resource type=\"SpriteFrames\" load_steps=\(sheet.cells.count + 2) format=3]\n\n"
        out += "[ext_resource type=\"Texture2D\" path=\"\(escape(imageName))\" id=\"1_sheet\"]\n\n"

        for (i, cell) in sheet.cells.enumerated() {
            let r = cell.rect
            out += "[sub_resource type=\"AtlasTexture\" id=\"AtlasTexture_\(i)\"]\n"
            out += "atlas = ExtResource(\"1_sheet\")\n"
            out += "region = Rect2(\(Int(r.minX)), \(Int(r.minY)), \(Int(r.width)), \(Int(r.height)))\n"
            if sheet.trimmed {
                // Margin: left / top offset, then the extra width / height to reach the full canvas.
                let left = s(cell.source.minX), top = s(cell.source.minY)
                out += "margin = Rect2(\(left), \(top), \(canvasW - Int(r.width)), \(canvasH - Int(r.height)))\n"
            }
            out += "\n"
        }

        var animations: [String] = []
        for clip in project.clips {
            let cells = sheet.cells.enumerated().filter { $0.element.clip.id == clip.id }
            guard !cells.isEmpty else { continue }
            let frames = cells.map { (i, cell) in
                "{\n\"duration\": \(Double(max(cell.frame.hold, 1))),\n\"texture\": SubResource(\"AtlasTexture_\(i)\")\n}"
            }
            animations.append("""
            {
            "frames": [\(frames.joined(separator: ", "))],
            "loop": \(clip.loop),
            "name": &"\(escape(clip.id))",
            "speed": \(Double(max(clip.fps ?? project.fps, 1)))
            }
            """)
        }
        out += "[resource]\nanimations = [\(animations.joined(separator: ", "))]\n"
        return out
    }

    /// Writes `<baseName>.png` and `<baseName>.tres` into `folder` (PNG first). Keep them together
    /// in the Godot project: the resource points at the PNG by a path relative to itself.
    @discardableResult
    static func write(_ sheet: SpriteSheet, project: Project, to folder: URL, baseName: String) throws -> [URL] {
        let png = try sheet.writePNG(to: folder, baseName: baseName)
        let tres = folder.appendingPathComponent("\(baseName).tres")
        try spriteFrames(sheet, project: project, imageName: png.lastPathComponent)
            .write(to: tres, atomically: true, encoding: .utf8)
        return [png, tres]
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
