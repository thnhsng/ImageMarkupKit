import UIKit
import XCTest
@testable import ImageMarkupKit

final class NavigationTextsTests: XCTestCase {
    @MainActor
    private func makeEditor(_ configuration: MarkupEditorConfiguration = .default) -> MarkupEditorViewController {
        let source = ImageSource(assetID: "photo", pixelSize: CGSize(width: 1024, height: 768))
        let editor = MarkupEditorViewController(document: .board([source]), assets: AssetCatalog(), configuration: configuration)
        editor.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 900)
        editor.view.layoutIfNeeded()
        return editor
    }

    @MainActor
    func testDefaultTextsAreEnglish() {
        let editor = makeEditor()
        XCTAssertEqual(editor.navigationItem.leftBarButtonItem?.title, "Cancel")
        // Right items are Done, Redo, Undo.
        XCTAssertEqual(editor.navigationItem.rightBarButtonItems?.first?.title, "Done")

        let alert = editor.makeDiscardAlert()
        XCTAssertEqual(alert.title, "Discard changes?")
        XCTAssertEqual(alert.message, "Your markup will not be saved.")
        XCTAssertEqual(alert.actions.map(\.title), ["Discard", "Keep Editing"])
    }

    @MainActor
    func testCustomTextsReplaceButtonsAndDiscardAlert() {
        var texts = MarkupNavigationTexts.english
        texts.done = "保存"
        texts.cancel = "キャンセル"
        texts.discardTitle = "変更を破棄しますか？"
        texts.discardMessage = "編集内容は保存されません。"
        texts.discard = "破棄"
        texts.keepEditing = "編集を続ける"
        let editor = makeEditor(MarkupEditorConfiguration(navigationTexts: texts))

        XCTAssertEqual(editor.navigationItem.leftBarButtonItem?.title, "キャンセル")
        XCTAssertEqual(editor.navigationItem.rightBarButtonItems?.first?.title, "保存")
        XCTAssertEqual(editor.navigationItem.rightBarButtonItems?.first?.style, .done)

        let alert = editor.makeDiscardAlert()
        XCTAssertEqual(alert.title, "変更を破棄しますか？")
        XCTAssertEqual(alert.message, "編集内容は保存されません。")
        XCTAssertEqual(alert.actions.map(\.title), ["破棄", "編集を続ける"])
        XCTAssertEqual(alert.actions.map(\.style), [.destructive, .cancel])
    }

    func testEnglishMatchesBuiltInStrings() {
        let english = MarkupNavigationTexts.english
        XCTAssertEqual(english.done, Strings.done)
        XCTAssertEqual(english.cancel, Strings.cancel)
        XCTAssertEqual(MarkupEditorConfiguration().navigationTexts, english)
    }
}
