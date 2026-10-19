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
        ("tool-rail", CGRect(x: 6, y: 262, width: 96, height: 822)),
        ("animation-rail", CGRect(x: 1856, y: 282, width: 138, height: 786)),
        ("onion-rail", CGRect(x: 1864, y: 785, width: 120, height: 140)),
        ("timeline", CGRect(x: 316, y: 960, width: 1368, height: 378)),
        ("top-bar", CGRect(x: 1790, y: 8, width: 205, height: 62)),
    ],
    "brush-library": [("brush-library", CGRect(x: 100, y: 12, width: 640, height: 935))],
    "brush-options": [("brush-options", CGRect(x: 100, y: 12, width: 640, height: 935))],
    "fill-options": [("fill-options", CGRect(x: 100, y: 196, width: 506, height: 498))],
    "lasso-selection": [("lasso-selection", CGRect(x: 575, y: 128, width: 806, height: 806))],
    "lasso-options": [("lasso-options", CGRect(x: 100, y: 388, width: 474, height: 390))],
    "layers-panel": [("layers-panel", nil)],
    "new-layer-menu": [("new-layer-menu", CGRect(x: 495, y: 600, width: 382, height: 525))],
    "more-menu": [("more-menu", CGRect(x: 1578, y: 8, width: 402, height: 828))],
    "split-menu": [("split-menu", CGRect(x: 1228, y: 8, width: 752, height: 860))],
    "repeat-popover": [("repeat-popover", CGRect(x: 1348, y: 532, width: 512, height: 380))],
    "onion-popover": [("onion-popover", nil)],
    "clip-settings": [("clip-settings", CGRect(x: 728, y: 662, width: 480, height: 420))],
    "cell-menu": [("cell-menu", CGRect(x: 742, y: 806, width: 386, height: 285))],
    "pivot": [("pivot", CGRect(x: 575, y: 128, width: 806, height: 806))],
    "clip-menu": [("clip-menu", nil)],
    "file-menu": [("file-menu", CGRect(x: 18, y: 18, width: 384, height: 600))],
    "export": [("export", CGRect(x: 520, y: 145, width: 960, height: 1092))],
    "export-checks": [("export-checks", CGRect(x: 958, y: 585, width: 500, height: 650))],
    "zen": [("zen", nil)],
    "timeline-hidden": [("timeline-hidden", nil)],
    "move-all": [("move-all", CGRect(x: 575, y: 128, width: 806, height: 806))],
    "move-stroke": [("move-stroke", CGRect(x: 575, y: 128, width: 806, height: 806))],
    "move-crossing": [("move-crossing", CGRect(x: 575, y: 28, width: 860, height: 910))],
    "preferences": [("preferences", CGRect(x: 520, y: 145, width: 960, height: 780))],
    "guide-layer": [("guide-canvas", CGRect(x: 575, y: 128, width: 806, height: 806))],
]

// Things that sit elsewhere in each language (the Spanish text is longer, or the grid was taller).
let perLanguage: [String: [String: (name: String, box: CGRect)]] = [
    "en": ["timeline-tall": ("timeline-tall", CGRect(x: 316, y: 862, width: 1368, height: 476))],
    "es": ["timeline-tall": ("timeline-tall", CGRect(x: 316, y: 810, width: 1368, height: 528))],
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
