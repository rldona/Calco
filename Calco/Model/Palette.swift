import Foundation
import simd

/// The project palette's pixel work: changing one colour into another in a drawing, and finding
/// the colours a drawing is made of. Pure, on RGBA8 premultiplied buffers, so it can be tested
/// without Metal.
enum Palette {

    static func hex(_ c: SIMD3<Float>) -> String {
        let v = simd_clamp(c, .zero, .one) * 255
        return String(format: "#%02X%02X%02X", Int(v.x.rounded()), Int(v.y.rounded()), Int(v.z.rounded()))
    }

    static func rgb(_ hex: String) -> SIMD3<Float>? {
        guard hex.count == 7, hex.first == "#", let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
    }

    /// How far, per channel out of 255, a pixel may be from the colour and still count as it:
    /// soft edges and the rounding of premultiplied alpha. Pixel art: exact.
    static func tolerance(hard: Bool) -> Int { hard ? 0 : 10 }

    /// `pixels` (`width` wide) with every pixel of colour `from` turned into `to`, keeping its
    /// opacity (so a soft edge against nothing stays soft). Where `from` meets another colour, the
    /// edge pixels are a mix of the two: each is worked out against a solid neighbour of the other
    /// colour and gets the same mix with `to`, so no ring of the old colour is left. Pixel art:
    /// exact pixels only. Returns nil when nothing changed.
    static func recolor(_ pixels: [UInt8], width: Int, from: SIMD3<Float>, to: SIMD3<Float>, hard: Bool) -> [UInt8]? {
        let n = pixels.count / 4
        guard n > 0, width > 0 else { return nil }
        let height = n / width
        let f = from * 255, delta = (to - from) * 255
        let tol = Float(tolerance(hard: hard))
        // Straight (unpremultiplied) colour of pixel i.
        func color(_ i: Int) -> SIMD3<Float> {
            let a = Float(pixels[i * 4 + 3])
            return SIMD3(Float(pixels[i * 4]), Float(pixels[i * 4 + 1]), Float(pixels[i * 4 + 2])) * (255 / max(a, 1))
        }
        var isFrom = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let a = Int(pixels[i * 4 + 3])
            guard a > 0 else { continue }
            let slack = tol + (hard ? 0 : 255 / Float(max(a, 1)))
            isFrom[i] = simd_reduce_max(simd_abs(color(i) - f)) <= slack
        }
        var out = pixels
        var changed = false
        func put(_ i: Int, _ c: SIMD3<Float>) {
            let a = Float(pixels[i * 4 + 3])
            let v = simd_clamp(c, .zero, SIMD3(repeating: 255)) * (a / 255)
            out[i * 4] = UInt8(v.x.rounded()); out[i * 4 + 1] = UInt8(v.y.rounded()); out[i * 4 + 2] = UInt8(v.z.rounded())
            changed = true
        }
        for i in 0..<n where isFrom[i] { put(i, color(i) + delta) }
        guard !hard else { return changed ? out : nil }
        // Edges between `from` and another colour: next to a pixel of `from`, a mix of it and a
        // solid neighbour of some other colour.
        for i in 0..<n where !isFrom[i] && pixels[i * 4 + 3] > 0 {
            let x = i % width, y = i / width
            // Cheap check first: most pixels aren't next to the colour at all.
            var nextToFrom = false
            for dy in -1...1 where !nextToFrom {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, ny >= 0, nx < width, ny < height, isFrom[ny * width + nx] { nextToFrom = true; break }
                }
            }
            guard nextToFrom else { continue }
            var others: [SIMD3<Float>] = []
            for dy in -2...2 {
                for dx in -2...2 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let j = ny * width + nx
                    if !isFrom[j] && pixels[j * 4 + 3] >= 250 { others.append(color(j)) }
                }
            }
            guard !others.isEmpty else { continue }
            let p = color(i)
            // The other colour that explains this pixel best as a mix with `from`.
            var best: (t: Float, err: Float)?
            for c2 in others {
                let axis = f - c2
                let len2 = simd_dot(axis, axis)
                guard len2 > 1 else { continue }
                let t = simd_dot(p - c2, axis) / len2
                guard t > 0.02, t < 0.98 else { continue }
                let err = simd_length(p - (c2 + axis * t))
                if best == nil || err < best!.err { best = (t, err) }
            }
            if let best, best.err <= 18 { put(i, p + delta * best.t) }
        }
        return changed ? out : nil
    }

    /// The colours a set of drawings is mostly made of, most used first: solid pixels only (soft
    /// edges are mixes), colours closer than `merge` per channel counted as one, and none that
    /// covers less than `share` of the solid pixels.
    static func dominantColors(_ drawings: [[UInt8]], limit: Int = 8, merge: Int = 24, share: Double = 0.005) -> [SIMD3<Float>] {
        var counts: [UInt32: Int] = [:]
        var total = 0
        for px in drawings {
            for p in stride(from: 0, to: px.count, by: 4) where px[p + 3] >= 250 {
                let key = UInt32(px[p]) << 16 | UInt32(px[p + 1]) << 8 | UInt32(px[p + 2])
                counts[key, default: 0] += 1
                total += 1
            }
        }
        guard total > 0 else { return [] }
        var picked: [(SIMD3<Int>, Int)] = []
        for (key, n) in counts.sorted(by: { $0.value > $1.value }) {
            let c = SIMD3<Int>(Int(key >> 16), Int((key >> 8) & 0xFF), Int(key & 0xFF))
            if let i = picked.firstIndex(where: { abs($0.0.x - c.x) <= merge && abs($0.0.y - c.y) <= merge && abs($0.0.z - c.z) <= merge }) {
                picked[i].1 += n
            } else {
                picked.append((c, n))
            }
        }
        return picked.sorted { $0.1 > $1.1 }
            .filter { Double($0.1) / Double(total) >= share }
            .prefix(limit)
            .map { SIMD3(Float($0.0.x), Float($0.0.y), Float($0.0.z)) / 255 }
    }
}
