import XCTest
@testable import Calco

final class ProjectDocumentTests: XCTestCase {
    func testRoundTrip() throws {
        let project = Project(
            name: "Hero",
            canvas: CanvasSize(width: 512, height: 512),
            clips: [
                Clip(id: "idle", name: "Idle",
                     layers: [Layer(id: "line", name: "Line"), Layer(id: "color", name: "Color")],
                     frames: [Frame(id: "000", hold: 2), Frame(id: "001", hold: 2)])
            ]
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Hero.calco")
        try ProjectDocument.save(project, to: url)
        let loaded = try ProjectDocument.load(from: url)
        XCTAssertEqual(project, loaded)
    }
}
