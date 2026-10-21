import XCTest
import Metal
@testable import Calco

/// The Shapes tool: its geometry, how it clicks into place, and the strokes it lays.
final class ShapeGeometryTests: XCTestCase {

    private func options(_ kind: ShapeOptions.Kind, _ outline: ShapeOptions.Outline = .solid) -> ShapeOptions {
        var o = ShapeOptions()
        o.kind = kind
        o.outline = outline
        return o
    }

    func testNearlyEvenClicksIntoASquareAndLinesEvery45Degrees() {
        let even = ShapeGeometry.snapped(.rectangle, from: .zero, to: CGPoint(x: 100, y: 97))
        XCTAssertEqual(even.snap, .even)
        XCTAssertEqual(even.end, CGPoint(x: 100, y: 100))
        XCTAssertEqual(ShapeGeometry.snapped(.ellipse, from: .zero, to: CGPoint(x: 100, y: 60)).snap, .none)

        let line = ShapeGeometry.snapped(.line, from: .zero, to: CGPoint(x: 100, y: 4))
        XCTAssertEqual(line.snap, .angle(0))
        XCTAssertEqual(line.end.y, 0, accuracy: 0.001)
        XCTAssertEqual(ShapeGeometry.snapped(.arrow, from: .zero, to: CGPoint(x: 70, y: 72)).snap, .angle(45))
        XCTAssertEqual(ShapeGeometry.snapped(.line, from: .zero, to: CGPoint(x: 100, y: 30)).snap, .none)
    }

    func testShapesFitTheDraggedBox() {
        let a = CGPoint(x: 10, y: 20), b = CGPoint(x: 110, y: 80)
        for kind in ShapeOptions.Kind.allCases where kind != .line && kind != .arrow {
            let pts = ShapeGeometry.paths(options(kind), from: a, to: b).flatMap(\.points)
            XCTAssertGreaterThanOrEqual(pts.map(\.x).min()!, 9.99, "\(kind)")
            XCTAssertLessThanOrEqual(pts.map(\.x).max()!, 110.01, "\(kind)")
            XCTAssertGreaterThanOrEqual(pts.map(\.y).min()!, 19.99, "\(kind)")
            XCTAssertLessThanOrEqual(pts.map(\.y).max()!, 80.01, "\(kind)")
        }
        var star = options(.star); star.points = 7
        XCTAssertEqual(ShapeGeometry.paths(star, from: a, to: b)[0].points.count, 14)
        var polygon = options(.polygon); polygon.sides = 5
        XCTAssertEqual(ShapeGeometry.paths(polygon, from: a, to: b)[0].points.count, 5)
        XCTAssertEqual(ShapeGeometry.paths(options(.arrow), from: a, to: b).count, 2, "the line and its head")
        XCTAssertNil(ShapeGeometry.fillPolygon(options(.line), from: a, to: b), "a line has no inside")
    }

    func testDashesAndDotsLeaveGaps() {
        let path = [(points: [CGPoint(x: 0, y: 0), CGPoint(x: 280, y: 0)], closed: false)]
        let solid = ShapeGeometry.stamps(along: path, radius: 2, spacing: 0.2, outline: .solid)
        let dashed = ShapeGeometry.stamps(along: path, radius: 2, spacing: 0.2, outline: .dashed)
        let dotted = ShapeGeometry.stamps(along: path, radius: 2, spacing: 0.2, outline: .dotted)
        XCTAssertEqual(solid.count, 701, accuracy: 2)
        XCTAssertEqual(Double(dashed.count) / Double(solid.count), 4.0 / 7, accuracy: 0.03, "4 parts in 7 painted")
        XCTAssertEqual(dotted.count, 48, accuracy: 2, "a dot every 3 radii")
        // Dashes: somewhere along it there's a gap wider than a stamp.
        let xs = dashed.map(\.position.x).sorted()
        XCTAssertGreaterThan(zip(xs, xs.dropFirst()).map { $1 - $0 }.max()!, 8)
    }
}

@MainActor
final class ShapeToolTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func alpha(_ state: EditorState, x: Int, y: Int) -> UInt8 {
        guard let l = state.currentLayer,
              let t = state.store.existingTexture(clip: state.clip.id, frame: state.currentFrame!.id, layer: l.id),
              let px = state.renderer.readbackBytes(t) else { return 0 }
        return px[(y * state.renderer.canvasSize.x + x) * 4 + 3]
    }

    func testAFilledShapeIsOnePieceAndOneUndoStep() throws {
        let state = try makeState()
        state.tool = .shape
        state.shapeOptions.kind = .rectangle
        state.shapeOptions.fill = .filled
        state.drawShape(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 160))
        XCTAssertGreaterThan(alpha(state, x: 150, y: 130), 250, "filled inside")
        XCTAssertEqual(alpha(state, x: 250, y: 130), 0)
        let key = try XCTUnwrap(state.currentDrawingKey)
        let pieces = try XCTUnwrap(state.strokes[key])
        XCTAssertEqual(pieces.count, 1)
        XCTAssertNotNil(pieces[0].recipe?.fill, "it keeps its inside, to paint again sharp")
        state.undo()
        XCTAssertEqual(alpha(state, x: 150, y: 130), 0)
    }

    func testAnOutlineLeavesTheInsideClearAndATapDrawsNothing() throws {
        let state = try makeState()
        state.tool = .shape
        state.shapeOptions.kind = .ellipse
        state.shapeOptions.fill = .none
        state.shapeOptions.size = 3
        state.drawShape(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200))
        XCTAssertEqual(alpha(state, x: 150, y: 150), 0)
        XCTAssertGreaterThan(alpha(state, x: 100, y: 150), 200, "the outline at the left edge")
        XCTAssertFalse(state.canRedo)
        let before = state.canUndo
        state.drawShape(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 300.5, y: 300))
        XCTAssertEqual(state.canUndo, before)
        XCTAssertEqual(alpha(state, x: 300, y: 300), 0)
    }
}

/// The inside can have its own colour, kept with the shape.
@MainActor
final class ShapeFillColourTests: XCTestCase {

    func testTheInsideHasItsOwnColourAndKeepsIt() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else { throw XCTSkip("Metal unavailable") }
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let l = state.currentLayer!
            let t = state.store.existingTexture(clip: state.clip.id, frame: state.currentFrame!.id, layer: l.id)!
            let px = state.renderer.readbackBytes(t)!
            let i = (y * state.renderer.canvasSize.x + x) * 4
            return Array(px[i..<(i + 4)])
        }
        state.tool = .shape
        state.setColor(SIMD4(1, 0, 0, 1))
        state.shapeOptions.kind = .rectangle
        state.shapeOptions.fill = .filled
        state.shapeOptions.outline = .solid
        state.shapeOptions.size = 3
        state.shapeOptions.fillColor = SIMD3(0, 0, 1)
        state.drawShape(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 160))
        XCTAssertEqual(pixel(150, 130), [0, 0, 255, 255], "blue inside")
        XCTAssertEqual(pixel(150, 100), [255, 0, 0, 255], "red line")

        // Opened again with the Node tool, it brings its fill colour along.
        state.shapeOptions.fillColor = nil
        state.tool = .node
        _ = state.nodeTouchDown(at: CGPoint(x: 150, y: 100), tolerance: 6, time: 0)
        XCTAssertEqual(state.shapeOptions.fillColor, SIMD3(0, 0, 1))
        state.shapeOptions.fillColor = SIMD3(0, 1, 0)
        state.finishPen()
        XCTAssertEqual(pixel(150, 130), [0, 255, 0, 255], "only the inside changed")
        XCTAssertEqual(pixel(150, 100), [255, 0, 0, 255])
    }
}
