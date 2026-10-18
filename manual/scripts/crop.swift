// Turns raw simulator screenshots (manual/raw/<lang>/*.png, 2420x1668) into the manual's images:
// full screens without the status bar, and crops of single features, as JPEG.
// Run from manual/: swift scripts/crop.swift
//
// Boxes are (x, y, width, height) measured on a 2000-pixel-wide view of the screenshot;
// they're scaled to the real 2420 pixels here.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let scale = 2420.0 / 2000.0
let statusBar = 50.0          // in the 2000-wide space: the clock row, cut from full screens

let crops: [String: [(name: String, box: CGRect?)]] = [
    "gallery": [("gallery", nil)],
    "new-project": [("new-project", CGRect(x: 520, y: 145, width: 960, height: 1090))],
    "editor": [
        ("editor", nil),
        ("tool-rail", CGRect(x: 8, y: 128, width: 96, height: 905)),
        ("timeline", CGRect(x: 10, y: 1045, width: 1980, height: 290)),
        ("bottom-bar", CGRect(x: 20, y: 1256, width: 1970, height: 68)),
        ("onion-controls", CGRect(x: 1260, y: 1060, width: 725, height: 60)),
        ("top-bar", CGRect(x: 1630, y: 58, width: 370, height: 66)),
    ],
    "brush-options": [("brush-options", CGRect(x: 105, y: 52, width: 500, height: 920))],
    "fill-options": [("fill-options", CGRect(x: 105, y: 58, width: 500, height: 498))],
    "lasso-selection": [("lasso-selection", CGRect(x: 640, y: 172, width: 815, height: 815))],
    "lasso-options": [("lasso-options", CGRect(x: 105, y: 252, width: 468, height: 385))],
    "layers-panel": [("layers-panel", CGRect(x: 55, y: 658, width: 352, height: 605))],
    "new-layer-menu": [("new-layer-menu", CGRect(x: 28, y: 1052, width: 375, height: 255))],
    "frame-menu": [("frame-menu", CGRect(x: 1583, y: 778, width: 405, height: 470))],
    "cell-menu": [("cell-menu", CGRect(x: 503, y: 850, width: 378, height: 280))],
    "pivot": [("pivot", CGRect(x: 620, y: 170, width: 860, height: 860))],
    "onion-popover": [("onion-popover", CGRect(x: 1476, y: 126, width: 502, height: 402))],
    "clip-menu": [("clip-menu", CGRect(x: 403, y: 888, width: 378, height: 222))],
    "file-menu": [("file-menu", CGRect(x: 20, y: 73, width: 376, height: 622))],
    "export": [("export", CGRect(x: 520, y: 145, width: 960, height: 1092))],
    "export-checks": [("export-checks", CGRect(x: 958, y: 585, width: 500, height: 650))],
    "zen": [("zen", nil)],
    "sync-layers": [("sync-layers-bar", CGRect(x: 930, y: 1256, width: 1060, height: 68))],
    "preferences": [("preferences", CGRect(x: 520, y: 145, width: 960, height: 422))],
]

// Popovers that sit elsewhere in each language, because the bar is wider in Spanish.
let perLanguage: [String: [String: (name: String, box: CGRect)]] = [
    "en": ["repeat-popover": ("repeat-popover", CGRect(x: 1190, y: 912, width: 502, height: 345)),
           "split-menu": ("split-menu", CGRect(x: 1030, y: 1090, width: 377, height: 218))],
    "es": ["repeat-popover": ("repeat-popover", CGRect(x: 1090, y: 888, width: 502, height: 368)),
           "split-menu": ("split-menu", CGRect(x: 930, y: 1090, width: 377, height: 218))],
]

func load(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func saveJPEG(_ image: CGImage, maxWidth: Int, to path: String) {
    let w = min(maxWidth, image.width)
    let h = Int((Double(image.height) * Double(w) / Double(image.width)).rounded())
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

for lang in ["en", "es"] {
    var all = crops
    for (raw, out) in perLanguage[lang] ?? [:] { all[raw] = [(out.name, out.box)] }
    for (raw, outs) in all {
        guard let image = load("raw/\(lang)/\(raw).png") else { print("missing", lang, raw); continue }
        for (name, box) in outs {
            let kind = box == nil ? "screens" : "crops"
            let dir = "public/\(kind)/\(lang)"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let b = box ?? CGRect(x: 0, y: statusBar, width: 2000, height: 1379 - statusBar)
            let px = CGRect(x: b.minX * scale, y: b.minY * scale, width: b.width * scale, height: b.height * scale)
                .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let cut = image.cropping(to: px) else { print("bad box", raw, name); continue }
            saveJPEG(cut, maxWidth: kind == "screens" ? 1600 : 1000, to: "\(dir)/\(name).jpg")
        }
    }
}
print("done")
