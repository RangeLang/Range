import XCTest
import SwiftTreeSitter
import TreeSitterNeat

final class TreeSitterNeatTests: XCTestCase {
    func testCanLoadGrammar() throws {
        let parser = Parser()
        let language = Language(language: tree_sitter_neat())
        XCTAssertNoThrow(try parser.setLanguage(language),
                         "Error loading Neat grammar")
    }
}
