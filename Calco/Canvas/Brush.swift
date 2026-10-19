import Foundation
import simd

/// How a brush lays paint: its tip, how the Pencil changes it, and how a stroke builds up.
/// Presets only for now; each remembers its own size and opacity (EditorState).
struct Brush: Identifiable, Equatable {
    enum Section: CaseIterable { case line, sketch, color }

    let id: String
    let icon: String           // SF Symbol for the rail
    let section: Section

    /// Radius in canvas pixels at full pressure, until you change it.
    var defaultSize: Float
    var defaultOpacity: Float = 1
    /// How much of the size the pressure takes away when light (0 = constant size).
    var sizePressure: Float = 0.85
    /// How much of the opacity the pressure takes away when light (0 = constant).
    var opacityPressure: Float = 0
    /// 1 = crisp edge (one antialiased pixel), 0 = fully soft falloff.
    var hardness: Float = 1
    /// Paper grain, 0–1, fixed to the canvas so going over it shows the paper's tooth.
    var grain: Float = 0
    /// Size of the grain in canvas pixels.
    var grainScale: Float = 2
    /// Paint per stamp, 0–1. Below 1 with `buildsUp`, the stroke darkens as you go over it.
    var flow: Float = 1
    /// Stamps add up within a stroke (airbrush, pencil). Otherwise the stroke is even, like a
    /// marker: crossing itself doesn't darken it.
    var buildsUp = false
    /// Distance between stamps as a fraction of the radius.
    var spacing: Float = 0.2
    /// Starts thin and grows over the first stretch of the stroke.
    var taper = false
    /// Tilting the Pencil widens it and makes it lighter (shading with the side of the lead).
    var tilt = false
    /// Always this colour (straight RGB), whatever colour is chosen: the blue sketch pencil.
    var fixedColor: SIMD3<Float>?

    static let inker = Brush(id: "inker", icon: "pencil.tip", section: .line, defaultSize: 6, sizePressure: 0.85)
    static let ballpoint = Brush(id: "ballpoint", icon: "pencil.line", section: .line, defaultSize: 2, sizePressure: 0.25)
    static let marker = Brush(id: "marker", icon: "highlighter", section: .line, defaultSize: 10, defaultOpacity: 0.7,
                              sizePressure: 0)
    static let pencil = Brush(id: "pencil", icon: "pencil", section: .sketch, defaultSize: 3, sizePressure: 0.3,
                              opacityPressure: 0.75, hardness: 0.7, grain: 0.7, grainScale: 1.6,
                              flow: 0.55, buildsUp: true, spacing: 0.15, tilt: true)
    static let bluePencil = Brush(id: "bluePencil", icon: "pencil.and.scribble", section: .sketch, defaultSize: 3,
                                  sizePressure: 0.3, opacityPressure: 0.75, hardness: 0.7, grain: 0.7,
                                  grainScale: 1.6, flow: 0.55, buildsUp: true, spacing: 0.15, tilt: true,
                                  fixedColor: SIMD3(0.31, 0.53, 0.85))
    static let charcoal = Brush(id: "charcoal", icon: "scribble", section: .sketch, defaultSize: 9, sizePressure: 0.5,
                                opacityPressure: 0.6, hardness: 0.5, grain: 0.9, grainScale: 3,
                                flow: 0.7, buildsUp: true, spacing: 0.12, tilt: true)
    static let paintbrush = Brush(id: "paintbrush", icon: "paintbrush.pointed", section: .color, defaultSize: 10,
                                  sizePressure: 0.9, hardness: 0.55, taper: true)
    static let airbrush = Brush(id: "airbrush", icon: "aqi.medium", section: .color, defaultSize: 24, sizePressure: 0,
                                opacityPressure: 0.8, hardness: 0, flow: 0.08, buildsUp: true, spacing: 0.1)
    static let flat = Brush(id: "flat", icon: "paintbrush", section: .color, defaultSize: 12, sizePressure: 0)

    static let all: [Brush] = [.inker, .ballpoint, .marker, .pencil, .bluePencil, .charcoal,
                               .paintbrush, .airbrush, .flat]

    static func named(_ id: String) -> Brush { all.first { $0.id == id } ?? .inker }

    var name: String {
        switch id {
        case "ballpoint": String(localized: "Ballpoint", bundle: AppLanguage.bundle)
        case "marker": String(localized: "Marker", bundle: AppLanguage.bundle)
        case "pencil": String(localized: "Pencil", bundle: AppLanguage.bundle)
        case "bluePencil": String(localized: "Blue pencil", bundle: AppLanguage.bundle)
        case "charcoal": String(localized: "Charcoal", bundle: AppLanguage.bundle)
        case "paintbrush": String(localized: "Paintbrush", bundle: AppLanguage.bundle)
        case "airbrush": String(localized: "Airbrush", bundle: AppLanguage.bundle)
        case "flat": String(localized: "Flat", bundle: AppLanguage.bundle)
        default: String(localized: "Inker", bundle: AppLanguage.bundle)
        }
    }

    var detail: String {
        switch id {
        case "ballpoint": String(localized: "Fine and steady", bundle: AppLanguage.bundle)
        case "marker": String(localized: "Bold, even within a stroke", bundle: AppLanguage.bundle)
        case "pencil": String(localized: "Paper grain; tilt it to shade", bundle: AppLanguage.bundle)
        case "bluePencil": String(localized: "For roughing out the motion", bundle: AppLanguage.bundle)
        case "charcoal": String(localized: "Rough, for quick masses", bundle: AppLanguage.bundle)
        case "paintbrush": String(localized: "Soft edge, tapering tip", bundle: AppLanguage.bundle)
        case "airbrush": String(localized: "Very soft; builds up as you go over", bundle: AppLanguage.bundle)
        case "flat": String(localized: "Hard fill, no pressure", bundle: AppLanguage.bundle)
        default: String(localized: "Clean line that thins with pressure", bundle: AppLanguage.bundle)
        }
    }

    var sectionTitle: String {
        switch section {
        case .line: String(localized: "Line", bundle: AppLanguage.bundle)
        case .sketch: String(localized: "Sketch", bundle: AppLanguage.bundle)
        case .color: String(localized: "Colour", bundle: AppLanguage.bundle)
        }
    }

    /// Radius for a pressure (0–1), before tilt and taper.
    func radius(size: Float, force: Float) -> Float {
        let f = min(max(force, 0), 1)
        return size * (1 - sizePressure * (1 - f))
    }

    /// Stamp alpha for a pressure (0–1), before tilt and taper.
    func alpha(force: Float) -> Float {
        let f = min(max(force, 0), 1)
        return flow * (1 - opacityPressure * (1 - f))
    }
}
