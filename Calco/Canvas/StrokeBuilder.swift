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
    /// Stabiliser, 0 (raw input) to 1 (heavy): the drawn point trails the pen, which irons out
    /// wobble. `finish()` draws the rest of the way to where the pen lifted.
    var smoothing: Float = 0

    // Spelled out: with private state the synthesized initializer isn't visible outside this file
    // on every compiler (Xcode 26 hides it from the tests).
    init(baseRadius: Float = 6, minRadiusFactor: Float = 0.15, spacing: Float = 0.25, smoothing: Float = 0) {
        self.baseRadius = baseRadius
        self.minRadiusFactor = minRadiusFactor
        self.spacing = spacing
        self.smoothing = smoothing
    }

    private var last: Sample?
    private var leftover: Float = 0
    /// Last raw input, so `finish()` can close the gap the stabiliser leaves.
    private var target: Sample?

    mutating func begin() {
        last = nil
        leftover = 0
        target = nil
    }

    /// Append a raw input sample, returning the stamps to render.
    mutating func add(_ sample: Sample) -> [CanvasRenderer.Stamp] {
        target = sample
        guard smoothing > 0, let prev = last else { return place(sample) }
        // How far the drawn point moves toward the pen each sample: all the way at 0, 4% at 1.
        let follow = 1 - min(max(smoothing, 0), 1) * 0.96
        return place(Sample(position: prev.position + (sample.position - prev.position) * follow,
                            force: prev.force + (sample.force - prev.force) * follow))
    }

    /// End of stroke: catch up with the pen so the line ends where it lifted.
    mutating func finish() -> [CanvasRenderer.Stamp] {
        guard smoothing > 0, let target, let last, simd_distance(target.position, last.position) > 0.5
        else { return [] }
        return place(target)
    }

    private mutating func place(_ sample: Sample) -> [CanvasRenderer.Stamp] {
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
