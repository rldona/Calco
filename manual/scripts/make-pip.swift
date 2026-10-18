// Generates "Pip.calco": a round character with line + colour layers and idle / walk / jump clips,
// for the user manual's screenshots. Run: swift scripts/make-pip.swift <folder>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 256
let out = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Pip.calco")
try? FileManager.default.removeItem(at: out)

func context() -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Top-left origin, y down, like the canvas.
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    return ctx
}

func save(_ ctx: CGContext, _ path: URL) {
    try! FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

struct Pose {
    var bodyY: CGFloat = 0          // bob
    var squash: CGFloat = 1         // >1 wider
    var leftLeg: CGFloat = 0        // foot x offset
    var rightLeg: CGFloat = 0
    var legLift: (CGFloat, CGFloat) = (0, 0)
    var arms: CGFloat = 0           // arm swing
    var blink = false
    var lift: CGFloat = 0           // whole body off the ground (jump)
}

let ink = CGColor(red: 0.13, green: 0.11, blue: 0.16, alpha: 1)
let body = CGColor(red: 0.98, green: 0.62, blue: 0.24, alpha: 1)
let belly = CGColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1)
let boots = CGColor(red: 0.36, green: 0.27, blue: 0.55, alpha: 1)

func draw(_ p: Pose, line: Bool) -> CGContext {
    let ctx = context()
    let ground: CGFloat = 236 - p.lift
    let cx: CGFloat = 128
    let rx: CGFloat = 54 * p.squash, ry: CGFloat = 50 / p.squash
    let cy = ground - 34 - ry + p.bodyY
    let bodyRect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)

    // Legs and boots
    for (i, dx) in [p.leftLeg, p.rightLeg].enumerated() {
        let hip = CGPoint(x: cx + (i == 0 ? -20 : 20), y: cy + ry - 8)
        let lift = i == 0 ? p.legLift.0 : p.legLift.1
        let foot = CGPoint(x: hip.x + dx, y: ground - 8 - lift)
        if line {
            ctx.setStrokeColor(ink); ctx.setLineWidth(5)
            ctx.move(to: hip); ctx.addLine(to: foot); ctx.strokePath()
        }
        let boot = CGRect(x: foot.x - 13, y: foot.y - 8, width: 28, height: 16)
        if line { ctx.setStrokeColor(ink); ctx.setLineWidth(4); ctx.strokeEllipse(in: boot) }
        else { ctx.setFillColor(boots); ctx.fillEllipse(in: boot) }
    }
    // Arms
    for side in [-1.0, 1.0] as [CGFloat] {
        let shoulder = CGPoint(x: cx + side * (rx - 6), y: cy + 4)
        let hand = CGPoint(x: shoulder.x + side * 18, y: shoulder.y + 22 + side * p.arms)
        if line { ctx.setStrokeColor(ink); ctx.setLineWidth(5); ctx.move(to: shoulder); ctx.addLine(to: hand); ctx.strokePath() }
    }
    // Body, belly
    if line {
        ctx.setStrokeColor(ink); ctx.setLineWidth(5); ctx.strokeEllipse(in: bodyRect)
    } else {
        ctx.setFillColor(body); ctx.fillEllipse(in: bodyRect)
        ctx.setFillColor(belly); ctx.fillEllipse(in: bodyRect.insetBy(dx: rx * 0.42, dy: ry * 0.38).offsetBy(dx: 0, dy: ry * 0.3))
    }
    // Face
    if line {
        ctx.setFillColor(ink)
        for side in [-1.0, 1.0] as [CGFloat] {
            let eye = CGPoint(x: cx + side * 17, y: cy - 10)
            if p.blink {
                ctx.setStrokeColor(ink); ctx.setLineWidth(4)
                ctx.move(to: CGPoint(x: eye.x - 6, y: eye.y)); ctx.addLine(to: CGPoint(x: eye.x + 6, y: eye.y)); ctx.strokePath()
            } else {
                ctx.fillEllipse(in: CGRect(x: eye.x - 5, y: eye.y - 7, width: 10, height: 14))
            }
        }
        ctx.setStrokeColor(ink); ctx.setLineWidth(4)
        ctx.addArc(center: CGPoint(x: cx, y: cy + 4), radius: 10, startAngle: 0.25 * .pi, endAngle: 0.75 * .pi, clockwise: false)
        ctx.strokePath()
        // Little sprout on top
        ctx.setLineWidth(4)
        ctx.move(to: CGPoint(x: cx, y: cy - ry)); ctx.addQuadCurve(to: CGPoint(x: cx + 14, y: cy - ry - 18), control: CGPoint(x: cx - 2, y: cy - ry - 18))
        ctx.strokePath()
    }
    return ctx
}

struct F { var pose: Pose; var hold: Int; var label: String? = nil }

let clips: [(id: String, name: String, fps: Int, frames: [F])] = [
    ("idle", "Idle", 8, [
        F(pose: Pose(), hold: 3),
        F(pose: Pose(bodyY: 3, squash: 1.04), hold: 2),
        F(pose: Pose(bodyY: 4, squash: 1.06, blink: true), hold: 1),
        F(pose: Pose(bodyY: 2, squash: 1.03), hold: 2),
    ]),
    ("walk", "Walk", 12, [
        F(pose: Pose(bodyY: 2, leftLeg: -22, rightLeg: 22, arms: 8), hold: 1, label: "step"),
        F(pose: Pose(bodyY: -4, leftLeg: -8, rightLeg: 8, legLift: (0, 10), arms: 3), hold: 1),
        F(pose: Pose(bodyY: -6, leftLeg: 4, rightLeg: -4, legLift: (0, 6), arms: -3), hold: 1),
        F(pose: Pose(bodyY: 2, leftLeg: 22, rightLeg: -22, arms: -8), hold: 1, label: "step"),
        F(pose: Pose(bodyY: -4, leftLeg: 8, rightLeg: -8, legLift: (10, 0), arms: -3), hold: 1),
        F(pose: Pose(bodyY: -6, leftLeg: -4, rightLeg: 4, legLift: (6, 0), arms: 3), hold: 1),
    ]),
    ("jump", "Jump", 12, [
        F(pose: Pose(bodyY: 8, squash: 1.18), hold: 2, label: "takeoff"),
        F(pose: Pose(squash: 0.88, legLift: (12, 12), arms: -12, lift: 60), hold: 3),
        F(pose: Pose(squash: 0.95, legLift: (4, 4), arms: -4, lift: 26), hold: 2),
        F(pose: Pose(bodyY: 6, squash: 1.14), hold: 2, label: "land"),
    ]),
]

var clipJSON: [[String: Any]] = []
var n = 0
for clip in clips {
    var frames: [[String: Any]] = []
    for f in clip.frames {
        let id = String(format: "%03d", n); n += 1
        let dir = out.appendingPathComponent("clips/\(clip.id)/\(id)")
        save(draw(f.pose, line: true), dir.appendingPathComponent("line.png"))
        save(draw(f.pose, line: false), dir.appendingPathComponent("color.png"))
        var fr: [String: Any] = ["id": id, "hold": f.hold]
        if let l = f.label { fr["labels"] = ["line": l] }
        frames.append(fr)
    }
    clipJSON.append(["id": clip.id, "name": clip.name, "fps": clip.fps, "loop": clip.id != "jump",
                     "pivot": ["x": 0.5, "y": 0.0],
                     "layers": [["id": "color", "name": "Color", "opacity": 1.0, "visible": true, "locked": false],
                                ["id": "line", "name": "Line", "opacity": 1.0, "visible": true, "locked": false]],
                     "frames": frames])
}
let project: [String: Any] = ["version": 3, "name": "Pip", "canvas": ["width": size, "height": size], "fps": 12,
                              "clips": clipJSON, "references": []]
let data = try JSONSerialization.data(withJSONObject: project, options: [.prettyPrinted, .sortedKeys])
try data.write(to: out.appendingPathComponent("project.json"))
print("wrote", out.path)
