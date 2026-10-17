import CoreGraphics
import simd

/// Turns a sequence of input samples into evenly spaced stamps.
/// Pure Swift, no UIKit, so it can be unit-tested.
struct StrokeBuilder {

    struct Sample {
        var position: SIMD2<Float>   // canvas pixels
        var force: Float             // 0...1 (0.5 for finger)
    }

    var baseRadius: Float = 6
    /// Minimum radius as a fraction of baseRadius at zero pressure.
    var minRadiusFactor: Float = 0.15
    /// Distance between stamps as a fraction of radius. Lower = smoother, more stamps.
    var spacing: Float = 0.25

    private var last: Sample?
    private var leftover: Float = 0

    mutating func begin() {
        last = nil
        leftover = 0
    }

    /// Append a sample, returning the stamps to render.
    mutating func add(_ sample: Sample) -> [CanvasRenderer.Stamp] {
        defer { last = sample }
        guard let prev = last else {
            return [stamp(at: sample.position, force: sample.force)]
        }
        let delta = sample.position - prev.position
        let dist = simd_length(delta)
        if dist < 0.001 { return [] }

        var stamps: [CanvasRenderer.Stamp] = []
        let dir = delta / dist
        var t = leftover
        while t <= dist {
            let f = t / dist
            let force = prev.force + (sample.force - prev.force) * f
            let pos = prev.position + dir * t
            stamps.append(stamp(at: pos, force: force))
            t += radius(for: force) * spacing
        }
        leftover = t - dist
        return stamps
    }

    private func radius(for force: Float) -> Float {
        let f = min(max(force, 0), 1)
        return baseRadius * (minRadiusFactor + (1 - minRadiusFactor) * f)
    }

    private func stamp(at p: SIMD2<Float>, force: Float) -> CanvasRenderer.Stamp {
        CanvasRenderer.Stamp(position: p, radius: radius(for: force), alpha: 1)
    }
}
