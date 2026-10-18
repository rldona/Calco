/// Bucket fill on CPU pixels (RGBA8 premultiplied, row 0 at the top, tightly packed).
/// Pure Swift so it's testable without Metal.
enum FloodFill {

    /// Pixels 4-connected to `seed` whose colour is within `tolerance` (0–255, per channel,
    /// alpha included) of the seed pixel's. Returns one flag per pixel; empty if the seed is outside.
    static func region(in rgba: [UInt8], width: Int, height: Int, seed: (x: Int, y: Int), tolerance: Int) -> [Bool] {
        guard width > 0, height > 0, rgba.count == width * height * 4,
              (0..<width).contains(seed.x), (0..<height).contains(seed.y) else { return [] }
        let s = (seed.y * width + seed.x) * 4
        let target = (Int(rgba[s]), Int(rgba[s + 1]), Int(rgba[s + 2]), Int(rgba[s + 3]))

        func matches(_ i: Int) -> Bool {
            let p = i * 4
            return abs(Int(rgba[p]) - target.0) <= tolerance
                && abs(Int(rgba[p + 1]) - target.1) <= tolerance
                && abs(Int(rgba[p + 2]) - target.2) <= tolerance
                && abs(Int(rgba[p + 3]) - target.3) <= tolerance
        }

        // Scanline fill: fill a whole run, queue the rows above and below it.
        var mask = [Bool](repeating: false, count: width * height)
        var stack = [seed.y * width + seed.x]
        while let start = stack.popLast() {
            if mask[start] { continue }
            let y = start / width
            var left = start, right = start
            let rowStart = y * width, rowEnd = rowStart + width - 1
            while left > rowStart, !mask[left - 1], matches(left - 1) { left -= 1 }
            while right < rowEnd, !mask[right + 1], matches(right + 1) { right += 1 }
            for i in left...right { mask[i] = true }
            for neighbourRow in [y - 1, y + 1] where (0..<height).contains(neighbourRow) {
                var inRun = false
                for x in (left - rowStart)...(right - rowStart) {
                    let i = neighbourRow * width + x
                    if !mask[i] && matches(i) {
                        if !inRun { stack.append(i); inRun = true }
                    } else {
                        inRun = false
                    }
                }
            }
        }
        return mask
    }

    /// Grows the mask by `radius` pixels (square neighbourhood), so a fill slides under the
    /// anti-aliased edge of a line instead of leaving a light halo against it.
    static func grow(_ mask: [Bool], width: Int, height: Int, by radius: Int) -> [Bool] {
        guard radius > 0, mask.count == width * height else { return mask }
        // Separable: dilate rows, then columns.
        var rows = mask
        for y in 0..<height {
            let r = y * width
            var lastOn = Int.min / 2
            for x in 0..<width { if mask[r + x] { lastOn = x }; if x - lastOn <= radius { rows[r + x] = true } }
            lastOn = Int.max / 2
            for x in stride(from: width - 1, through: 0, by: -1) {
                if mask[r + x] { lastOn = x }; if lastOn - x <= radius { rows[r + x] = true }
            }
        }
        var out = rows
        for x in 0..<width {
            var lastOn = Int.min / 2
            for y in 0..<height { if rows[y * width + x] { lastOn = y }; if y - lastOn <= radius { out[y * width + x] = true } }
            lastOn = Int.max / 2
            for y in stride(from: height - 1, through: 0, by: -1) {
                if rows[y * width + x] { lastOn = y }; if lastOn - y <= radius { out[y * width + x] = true }
            }
        }
        return out
    }

    /// Writes an opaque `color` (0–1 RGB) into every masked pixel of `rgba`.
    static func paint(_ mask: [Bool], color: SIMD3<Float>, into rgba: inout [UInt8]) {
        guard rgba.count == mask.count * 4 else { return }
        let r = UInt8((min(max(color.x, 0), 1) * 255).rounded())
        let g = UInt8((min(max(color.y, 0), 1) * 255).rounded())
        let b = UInt8((min(max(color.z, 0), 1) * 255).rounded())
        for (i, on) in mask.enumerated() where on {
            rgba[i * 4] = r; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = b; rgba[i * 4 + 3] = 255
        }
    }

    /// Straight (un-premultiplied) colour at a pixel, or nil if it's (almost) transparent.
    static func color(in rgba: [UInt8], width: Int, height: Int, at p: (x: Int, y: Int)) -> SIMD3<Float>? {
        guard rgba.count == width * height * 4, (0..<width).contains(p.x), (0..<height).contains(p.y) else { return nil }
        let i = (p.y * width + p.x) * 4
        let a = Float(rgba[i + 3]) / 255
        guard a > 0.05 else { return nil }
        return SIMD3(Float(rgba[i]) / 255 / a, Float(rgba[i + 1]) / 255 / a, Float(rgba[i + 2]) / 255 / a)
            .clamped(lowerBound: .zero, upperBound: .one)
    }
}
