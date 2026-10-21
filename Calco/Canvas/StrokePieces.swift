import CoreGraphics
import Foundation
import simd

/// One piece of a drawing that Move can pick up on its own: a pencil stroke, or a shape of
/// pixels that are no longer separable (filled, lassoed, from an older project). Its pixels are
/// cropped to its bounds, RGBA8 premultiplied, row 0 at the top. A drawing is its pieces
/// composited bottom to top.
struct StrokePiece: Equatable {
    var x: Int, y: Int, width: Int, height: Int
    var pixels: [UInt8]
    /// How a pencil stroke was painted, so Move can paint it again, sharp, wherever it goes;
    /// nil for shapes of pixels, which can only be resampled.
    var recipe: StrokeRecipe?

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// The painted part of a canvas-sized buffer, or nil if it's all clear.
    init?(canvas rgba: [UInt8], width w: Int, height h: Int) {
        guard let b = SelectionPixels.contentBounds(rgba, width: w, height: h) else { return nil }
        x = Int(b.minX); y = Int(b.minY); width = Int(b.width); height = Int(b.height)
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let src = ((y + row) * w + x) * 4, dst = row * width * 4
            pixels.replaceSubrange(dst..<(dst + width * 4), with: rgba[src..<(src + width * 4)])
        }
    }

    init(x: Int, y: Int, width: Int, height: Int, pixels: [UInt8], recipe: StrokeRecipe? = nil) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.pixels = pixels
        self.recipe = recipe
    }

    /// Back to a canvas-sized buffer, clear around it.
    func canvas(width w: Int, height h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for row in 0..<height {
            let src = row * width * 4, dst = ((y + row) * w + x) * 4
            out.replaceSubrange(dst..<(dst + width * 4), with: pixels[src..<(src + width * 4)])
        }
        return out
    }

    /// Whether there's paint at canvas pixel (px, py) or within `reach` of it.
    func hits(_ px: Int, _ py: Int, reach: Int) -> Bool {
        guard px >= x - reach, py >= y - reach, px < x + width + reach, py < y + height + reach else { return false }
        for dy in -reach...reach {
            for dx in -reach...reach where dx * dx + dy * dy <= reach * reach {
                let lx = px + dx - x, ly = py + dy - y
                guard lx >= 0, ly >= 0, lx < width, ly < height else { continue }
                if pixels[(ly * width + lx) * 4 + 3] != 0 { return true }
            }
        }
        return false
    }

    /// What's left after the eraser: every pixel scaled by (1 − coverage), like the eraser does.
    /// `coverage` is one byte per canvas pixel. Nil when nothing is left.
    func erased(by coverage: [UInt8], canvasWidth w: Int) -> StrokePiece? {
        var out = self
        out.recipe = nil                        // part of it is gone: only its pixels are true now
        var any = false
        for row in 0..<height {
            for col in 0..<width {
                let i = (row * width + col) * 4
                let c = Int(coverage[(y + row) * w + x + col])
                if c > 0 {
                    for k in 0..<4 { out.pixels[i + k] = UInt8((Int(out.pixels[i + k]) * (255 - c) + 127) / 255) }
                }
                if out.pixels[i + 3] != 0 { any = true }
            }
        }
        return any ? out : nil
    }

    /// Moved, scaled, rotated and flipped by `transform` (canvas space), by resampling its pixels;
    /// nil if it left the canvas. A piece with a recipe is better painted again (EditorState).
    func transformed(_ transform: CGAffineTransform, canvasWidth w: Int, height h: Int, hard: Bool) -> StrokePiece? {
        let placed = SelectionPixels.render(canvas(width: w, height: h), width: w, height: h, transform: transform, hard: hard)
        return StrokePiece(canvas: placed, width: w, height: h)
    }
}

/// A pencil stroke as it was painted: its stamps and how they were laid. Painting it again gives
/// the same pixels; painting it transformed gives a sharp line where resampling would blur it.
struct StrokeRecipe: Equatable {
    var stamps: [CanvasRenderer.Stamp]
    var color: SIMD3<Float>
    var tip: CanvasRenderer.BrushTip
    var opacity: Float
    var hard: Bool
    /// A shape's inside, painted under its outline in the same colour (canvas pixels).
    var fill: [SIMD2<Float>]? = nil
    /// A Pen path: its points and style, so it can be edited again.
    var pen: PenDrawing? = nil

    /// The stamps moved by `t` (canvas space). The line keeps its weight under a stretch: each
    /// stamp's radius scales by how much `t` scales area, the geometric mean of the two axes.
    func transformed(_ t: CGAffineTransform) -> StrokeRecipe {
        var out = self
        let k = Float(sqrt(abs(t.a * t.d - t.b * t.c)))
        out.stamps = stamps.map { s in
            let p = CGPoint(x: CGFloat(s.position.x), y: CGFloat(s.position.y)).applying(t)
            return CanvasRenderer.Stamp(position: SIMD2(Float(p.x), Float(p.y)), radius: s.radius * k, alpha: s.alpha)
        }
        out.fill = fill?.map { v in
            let p = CGPoint(x: CGFloat(v.x), y: CGFloat(v.y)).applying(t)
            return SIMD2(Float(p.x), Float(p.y))
        }
        if var pen {
            pen.path = pen.path.applying(t)
            pen.style.size *= k
            out.pen = pen
        }
        return out
    }
}

enum StrokePieces {

    /// Pieces composited bottom to top (premultiplied source-over) into a canvas-sized buffer.
    static func composite(_ pieces: [StrokePiece], width w: Int, height h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for p in pieces {
            for row in 0..<p.height {
                for col in 0..<p.width {
                    let s = (row * p.width + col) * 4
                    let sa = Int(p.pixels[s + 3])
                    guard sa != 0 else { continue }
                    let d = ((p.y + row) * w + p.x + col) * 4
                    if sa == 255 {
                        for k in 0..<4 { out[d + k] = p.pixels[s + k] }
                    } else {
                        for k in 0..<4 {
                            out[d + k] = UInt8(min(255, Int(p.pixels[s + k]) + (Int(out[d + k]) * (255 - sa) + 127) / 255))
                        }
                    }
                }
            }
        }
        return out
    }

    /// A drawing whose strokes aren't known, split into its separate shapes (pixels touching,
    /// diagonals included). Shapes don't overlap, so their order doesn't matter. Past `limit`
    /// shapes (noise, dithering) it stays one piece.
    static func shapes(of rgba: [UInt8], width w: Int, height h: Int, limit: Int = 400) -> [StrokePiece] {
        var label = [Int32](repeating: 0, count: w * h)
        var pieces: [StrokePiece] = []
        var next: Int32 = 0
        for start in 0..<(w * h) where label[start] == 0 && rgba[start * 4 + 3] != 0 {
            next += 1
            if next > limit { return StrokePiece(canvas: rgba, width: w, height: h).map { [$0] } ?? [] }
            var minX = w, minY = h, maxX = 0, maxY = 0
            var members: [Int] = []
            var stack = [start]
            label[start] = next
            while let i = stack.popLast() {
                members.append(i)
                let px = i % w, py = i / w
                minX = min(minX, px); maxX = max(maxX, px); minY = min(minY, py); maxY = max(maxY, py)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = px + dx, ny = py + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let j = ny * w + nx
                        if label[j] == 0 && rgba[j * 4 + 3] != 0 { label[j] = next; stack.append(j) }
                    }
                }
            }
            let pw = maxX - minX + 1, ph = maxY - minY + 1
            var px = [UInt8](repeating: 0, count: pw * ph * 4)
            for i in members {
                let d = ((i / w - minY) * pw + (i % w - minX)) * 4
                for k in 0..<4 { px[d + k] = rgba[i * 4 + k] }
            }
            pieces.append(StrokePiece(x: minX, y: minY, width: pw, height: ph, pixels: px))
        }
        return pieces
    }

    /// Whether the pieces still add up to the layer's pixels. A few pixels may be off by a little
    /// (where the eraser's soft edge crossed overlapping strokes); anything more means the layer
    /// was changed some way the pieces didn't follow.
    static func match(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var off = 0
        let allowed = max(16, a.count / 4 / 200)          // 0.5 % of the pixels
        for i in stride(from: 0, to: a.count, by: 4) {
            var d = 0
            for k in 0..<4 { d = max(d, abs(Int(a[i + k]) - Int(b[i + k]))) }
            if d > 80 { return false }
            if d > 3 { off += 1; if off > allowed { return false } }
        }
        return true
    }

    // MARK: File

    /// `<layer>.strokes`: "CSTK", version 2, piece count, then each piece's x, y, width, height
    /// and its LZFSE-compressed pixels, then its recipe's byte count (0 = none) and the recipe
    /// LZFSE-compressed. All UInt32 little-endian; floats as their bits. Version 1 has no recipes.
    static func encode(_ pieces: [StrokePiece]) -> Data? {
        var data = Data("CSTK".utf8)
        func put(_ v: Int) { var u = UInt32(v).littleEndian; data.append(Data(bytes: &u, count: 4)) }
        put(2); put(pieces.count)
        for p in pieces {
            guard let packed = try? (Data(p.pixels) as NSData).compressed(using: .lzfse) as Data else { return nil }
            put(p.x); put(p.y); put(p.width); put(p.height); put(packed.count)
            data.append(packed)
            if let r = p.recipe, let packed = try? (encode(r) as NSData).compressed(using: .lzfse) as Data {
                put(packed.count)
                data.append(packed)
            } else {
                put(0)
            }
        }
        return data
    }

    /// A recipe: colour (3 floats), hardness, grain, grain scale, builds up, opacity, hard, stamp
    /// count, then each stamp's x, y, radius and alpha; then, for a filled shape or a Pen path,
    /// the number of corners of its inside (0 = none) and each one's x and y; then, for a Pen
    /// path, the byte count of its JSON and the JSON, padded to whole words.
    private static func encode(_ r: StrokeRecipe) -> Data {
        var words: [UInt32] = [r.color.x, r.color.y, r.color.z, r.tip.hardness, r.tip.grain, r.tip.grainScale].map(\.bitPattern)
        words += [r.tip.buildsUp ? 1 : 0, r.opacity.bitPattern, r.hard ? 1 : 0, UInt32(r.stamps.count)]
        for s in r.stamps { words += [s.position.x, s.position.y, s.radius, s.alpha].map(\.bitPattern) }
        if r.fill != nil || r.pen != nil {
            let fill = r.fill ?? []
            words.append(UInt32(fill.count))
            for p in fill { words += [p.x.bitPattern, p.y.bitPattern] }
        }
        var data = words.map(\.littleEndian).withUnsafeBytes { Data($0) }
        if let pen = r.pen, let json = try? JSONEncoder().encode(pen) {
            var count = UInt32(json.count).littleEndian
            data.append(Data(bytes: &count, count: 4))
            data.append(json)
            data.append(Data(count: (4 - json.count % 4) % 4))
        }
        return data
    }

    private static func decodeRecipe(_ data: Data) -> StrokeRecipe? {
        let bytes = [UInt8](data)
        guard bytes.count % 4 == 0, bytes.count >= 40 else { return nil }
        let w = stride(from: 0, to: bytes.count, by: 4).map {
            UInt32(bytes[$0]) | UInt32(bytes[$0 + 1]) << 8 | UInt32(bytes[$0 + 2]) << 16 | UInt32(bytes[$0 + 3]) << 24
        }
        let f = { (i: Int) in Float(bitPattern: w[i]) }
        let n = Int(w[9])
        guard w.count >= 10 + n * 4 else { return nil }
        var fill: [SIMD2<Float>]?
        let at = 10 + n * 4
        var pen: PenDrawing?
        if w.count > at {
            let m = Int(w[at])
            guard w.count >= at + 1 + m * 2 else { return nil }
            if m > 0 { fill = (0..<m).map { SIMD2(f(at + 1 + $0 * 2), f(at + 2 + $0 * 2)) } }
            let next = at + 1 + m * 2
            if w.count > next {
                let length = Int(w[next])
                let start = (next + 1) * 4
                guard start + length <= bytes.count,
                      let p = try? JSONDecoder().decode(PenDrawing.self, from: Data(bytes[start..<(start + length)]))
                else { return nil }
                pen = p
            }
        }
        let stamps = (0..<n).map { i in
            CanvasRenderer.Stamp(position: SIMD2(f(10 + i * 4), f(11 + i * 4)), radius: f(12 + i * 4), alpha: f(13 + i * 4))
        }
        return StrokeRecipe(stamps: stamps, color: SIMD3(f(0), f(1), f(2)),
                            tip: .init(hardness: f(3), grain: f(4), grainScale: f(5), buildsUp: w[6] != 0),
                            opacity: f(7), hard: w[8] != 0, fill: fill, pen: pen)
    }

    static func decode(_ data: Data) -> [StrokePiece]? {
        let bytes = [UInt8](data)
        var at = 0
        func get() -> Int? {
            guard at + 4 <= bytes.count else { return nil }
            let v = UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
            at += 4
            return Int(v)
        }
        guard bytes.count >= 12, String(bytes: bytes[0..<4], encoding: .utf8) == "CSTK" else { return nil }
        at = 4
        guard let version = get(), version == 1 || version == 2, let count = get(), count < 100_000 else { return nil }
        var pieces: [StrokePiece] = []
        for _ in 0..<count {
            guard let x = get(), let y = get(), let w = get(), let h = get(), let n = get(),
                  at + n <= bytes.count,
                  let raw = try? (Data(bytes[at..<(at + n)]) as NSData).decompressed(using: .lzfse) as Data,
                  raw.count == w * h * 4 else { return nil }
            at += n
            var recipe: StrokeRecipe?
            if version >= 2 {
                guard let m = get(), at + m <= bytes.count else { return nil }
                if m > 0, let packed = try? (Data(bytes[at..<(at + m)]) as NSData).decompressed(using: .lzfse) as Data {
                    recipe = decodeRecipe(packed)
                }
                at += m
            }
            pieces.append(StrokePiece(x: x, y: y, width: w, height: h, pixels: [UInt8](raw), recipe: recipe))
        }
        return pieces
    }
}
