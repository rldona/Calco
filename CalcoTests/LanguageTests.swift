import XCTest
@testable import Calco

/// English by default whatever the iPad's language; Spanish from Preferences, at once.
final class LanguageTests: XCTestCase {

    override func tearDown() {
        AppLanguage.apply(.english, save: false)
        super.tearDown()
    }

    func testSpanishAppliesAtOnceAndEnglishIsTheKeys() {
        AppLanguage.apply(.spanish, save: false)
        XCTAssertEqual(String(localized: "Delete drawing", bundle: AppLanguage.bundle), "Eliminar dibujo")
        let n = 3
        XCTAssertEqual(String(localized: "Lasts \(n) frames", bundle: AppLanguage.bundle), "Dura 3 fotogramas", "formats keep their numbers")

        AppLanguage.apply(.english, save: false)
        XCTAssertEqual(String(localized: "Delete drawing", bundle: AppLanguage.bundle), "Delete drawing")
    }

    func testEveryLanguageNamesItself() {
        XCTAssertEqual(AppLanguage.allCases.map(\.name), ["English", "Español"])
    }
}
