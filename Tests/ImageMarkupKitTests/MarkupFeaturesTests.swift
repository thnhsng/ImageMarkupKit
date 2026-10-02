import UIKit
import XCTest
@testable import ImageMarkupKit

final class MarkupFeaturesTests: XCTestCase {
    private func features(_ json: String) throws -> MarkupFeatures {
        try MarkupFeatures(jsonData: Data(json.utf8))
    }

    // MARK: Configuration file

    func testGroupsAndItemsTurnOff() throws {
        let config = try features("""
        {
          "_comment": "ignored",
          "shapes": { "enabled": false, "items": { "star": true } },
          "draw": { "items": { "highlighter": false } },
          "lines": { "enabled": true }
        }
        """)
        XCTAssertFalse(config.isEnabled(.star), "a disabled group hides its items, even those set to true")
        XCTAssertFalse(config.isEnabled(group: .shapes))
        XCTAssertFalse(config.isEnabled(.highlighter))
        XCTAssertTrue(config.isEnabled(.pen), "missing items are on")
        XCTAssertTrue(config.isEnabled(.curve))
        XCTAssertTrue(config.isEnabled(.delete), "missing groups are on")
        XCTAssertTrue(config.isEnabled(group: .draw))
    }

    func testGroupWithEveryItemOffIsOff() throws {
        let config = try features(#"{ "text": { "items": { "text": false, "note": false } } }"#)
        XCTAssertFalse(config.isEnabled(group: .text))
    }

    func testUnknownNamesAreErrors() {
        XCTAssertThrowsError(try features(#"{ "shape": { "enabled": false } }"#)) {
            XCTAssertEqual($0 as? MarkupFeaturesError, .unknownKey("shape"))
        }
        XCTAssertThrowsError(try features(#"{ "draw": { "items": { "hightlighter": false } } }"#)) {
            XCTAssertEqual($0 as? MarkupFeaturesError, .unknownKey("draw.items.hightlighter"))
        }
        XCTAssertThrowsError(try features(#"{ "draw": { "items": { "star": false } } }"#), "items belong to their own group") {
            XCTAssertEqual($0 as? MarkupFeaturesError, .unknownKey("draw.items.star"))
        }
        XCTAssertThrowsError(try features(#"{ "draw": { "tools": { "pen": false } } }"#)) {
            XCTAssertEqual($0 as? MarkupFeaturesError, .unknownKey("draw.tools"))
        }
        XCTAssertThrowsError(try features(#"{ "draw": { "enabled": "no" } }"#)) {
            XCTAssertEqual($0 as? MarkupFeaturesError, .invalidValue("draw.enabled"))
        }
        XCTAssertThrowsError(try features(#"{ "shapes": false }"#)) {
            XCTAssertEqual($0 as? MarkupFeaturesError, .invalidValue("shapes"))
            XCTAssertEqual("\($0)", "\"shapes\" in the markup features configuration must be an object.")
        }
        XCTAssertThrowsError(try features(#"{ "lines": { "items": { "curve": 0 } } }"#)) {
            XCTAssertEqual($0 as? MarkupFeaturesError, .invalidValue("lines.items.curve"))
        }
    }

    func testTemplateListsEverythingAndRoundTrips() throws {
        var config = MarkupFeatures.all
        config.setEnabled(false, group: .board)
        config.setEnabled(false, .curve)
        let json = try XCTUnwrap(String(data: config.jsonData(), encoding: .utf8))
        for feature in MarkupFeature.allCases {
            XCTAssertTrue(json.contains("\"\(feature.rawValue)\""), "\(feature) is listed")
        }
        XCTAssertEqual(try MarkupFeatures(jsonData: config.jsonData()), config)
    }

    func testMissingBundleFileMeansEverything() throws {
        XCTAssertEqual(try MarkupFeatures.fromBundle(Bundle(for: Self.self), resource: "NoSuchFile"), .all)
    }

    func testToolsMapToTheirFeature() {
        var config = MarkupFeatures.all
        config.setEnabled(false, .circle)
        XCTAssertFalse(config.allows(.shape(.ellipse, lockAspect: true)))
        XCTAssertTrue(config.allows(.shape(.ellipse, lockAspect: false)), "oval is separate from circle")
        config.setEnabled(false, group: .draw)
        XCTAssertFalse(config.allows(.pen))
        XCTAssertTrue(config.allows(.select), "Select is always available")
    }

    // MARK: Editor

    @MainActor
    private func makeEditor(_ features: MarkupFeatures, board: Bool = false) -> MarkupEditorViewController {
        let source = ImageSource(assetID: "photo", pixelSize: CGSize(width: 1024, height: 768))
        let document = board ? MarkupDocument.board([source]) : MarkupDocument.imageDocument(source)
        let editor = MarkupEditorViewController(document: document, assets: AssetCatalog(), configuration: MarkupEditorConfiguration(features: features))
        editor.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 900)
        editor.view.layoutIfNeeded()
        return editor
    }

    @MainActor
    func testToolbarShowsOnlyEnabledItems() throws {
        var config = MarkupFeatures.all
        config.setEnabled(false, group: .shapes)
        config.setEnabled(false, .highlighter)
        config.setEnabled(false, .polyline)
        config.setEnabled(false, .curve)
        config.setEnabled(false, .fillColor)
        config.setEnabled(false, .arrange)
        let editor = makeEditor(config, board: true)
        let toolbar = editor.toolbar

        XCTAssertNil(toolbar.button(for: .shapes))
        XCTAssertNil(toolbar.button(for: .highlight))
        XCTAssertNil(toolbar.button(for: .fillColor))
        XCTAssertNil(toolbar.button(for: .arrange))
        XCTAssertNotNil(toolbar.button(for: .sketch))
        XCTAssertNotNil(toolbar.button(for: .borderColor))
        let arrow = try XCTUnwrap(toolbar.button(for: .arrow))
        XCTAssertFalse(arrow.showsMenuAsPrimaryAction, "one line tool left: a plain button, no menu")
    }

    @MainActor
    func testDisabledToolsCannotBeSelected() {
        var config = MarkupFeatures.all
        config.setEnabled(false, .highlighter)
        let editor = makeEditor(config)
        editor.tool = .highlighter
        XCTAssertEqual(editor.tool, .select)
        editor.tool = .pen
        XCTAssertEqual(editor.tool, .pen)
        let inputs = editor.keyCommands?.compactMap(\.input) ?? []
        XCTAssertFalse(inputs.contains("h"), "no shortcut for a disabled tool")
        XCTAssertTrue(inputs.contains("p"))
    }

    @MainActor
    func testActionBarAndTextEditingFollowFeatures() {
        var config = MarkupFeatures.all
        config.setEnabled(false, .lock)
        config.setEnabled(false, .editText)
        let editor = makeEditor(config)
        let text = MarkupItem.text("Hello", at: CGPoint(x: 100, y: 100), font: FontSpec(), color: .red)
        editor.store.perform("Add", select: [text.id]) { $0.items.append(text) }
        editor.refreshOverlay()
        let actions = editor.overlayView.actionBar.actions
        XCTAssertFalse(actions.contains(.lock))
        XCTAssertFalse(actions.contains(.editText))
        XCTAssertTrue(actions.contains(.delete))

        editor.interactions.env.beginTextEditing?(text.id, false)
        XCTAssertFalse(editor.textEditing.isEditing, "existing text cannot be edited")
    }
}
