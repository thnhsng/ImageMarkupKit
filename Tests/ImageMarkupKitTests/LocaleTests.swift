import UIKit
import XCTest
@testable import ImageMarkupKit

final class LocaleTests: XCTestCase {
    @MainActor
    private func makeEditor(_ configuration: MarkupEditorConfiguration) -> MarkupEditorViewController {
        let sources = [
            ImageSource(assetID: "a", pixelSize: CGSize(width: 1024, height: 768)),
            ImageSource(assetID: "b", pixelSize: CGSize(width: 768, height: 1024)),
        ]
        let editor = MarkupEditorViewController(document: .board(sources), assets: AssetCatalog(), configuration: configuration)
        editor.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 900)
        editor.view.layoutIfNeeded()
        return editor
    }

    private func accessibilityLabels(in view: UIView) -> Set<String> {
        var labels = Set<String>()
        if let label = view.accessibilityLabel { labels.insert(label) }
        for subview in view.subviews { labels.formUnion(accessibilityLabels(in: subview)) }
        return labels
    }

    func testLocalesUseTheWebPackageCodes() {
        XCTAssertEqual(MarkupLocale(rawValue: "en"), .english)
        XCTAssertEqual(MarkupLocale(rawValue: "ja"), .japanese)
        XCTAssertEqual(MarkupEditorConfiguration().locale, .english)
    }

    @MainActor
    func testJapaneseEditor() {
        let editor = makeEditor(MarkupEditorConfiguration(locale: .japanese))

        XCTAssertEqual(editor.title, "ボード")
        XCTAssertEqual(editor.navigationItem.leftBarButtonItem?.title, "キャンセル")
        XCTAssertEqual(editor.navigationItem.rightBarButtonItems?.first?.title, "完了")
        let alert = editor.makeDiscardAlert()
        XCTAssertEqual(alert.title, "変更を破棄しますか？")
        XCTAssertEqual(alert.message, "マークアップは保存されません。")
        XCTAssertEqual(alert.actions.map(\.title), ["破棄", "編集を続ける"])

        let toolbar = accessibilityLabels(in: editor.toolbar)
        for label in ["選択", "スケッチ", "ハイライト", "図形", "矢印 / 線", "テキスト", "メモ", "消しゴム", "画像を追加", "整列", "図形のスタイル"] {
            XCTAssertTrue(toolbar.contains(label), "toolbar has no \(label): \(toolbar.sorted())")
        }
        XCTAssertEqual(editor.overlayView.actionBar.strings.locale, .japanese)
    }

    @MainActor
    func testEnglishStaysTheDefault() {
        let editor = makeEditor(.default)
        XCTAssertEqual(editor.title, "Board")
        XCTAssertTrue(accessibilityLabels(in: editor.toolbar).isSuperset(of: ["Select", "Sketch", "Add Images", "Arrange"]))
    }

    @MainActor
    func testUndoActionNamesFollowTheLocale() {
        let store = EditorStore(
            document: .board([ImageSource(assetID: "a", pixelSize: CGSize(width: 400, height: 300))]),
            assets: AssetStore(),
            strings: .japanese
        )
        store.addImages([ImageSource(assetID: "b", pixelSize: CGSize(width: 300, height: 400))])
        XCTAssertEqual(store.undoManager.undoActionName, "画像の追加")
        store.arrange(.column)
        XCTAssertEqual(store.undoManager.undoActionName, "整列")
        store.select([store.document.items[0].id])
        store.deleteSelection()
        XCTAssertEqual(store.undoManager.undoActionName, "削除")
    }

    func testNavigationTextsFollowTheLocaleUntilSet() {
        var configuration = MarkupEditorConfiguration(locale: .japanese)
        XCTAssertEqual(configuration.navigationTexts, .japanese)
        XCTAssertEqual(configuration.navigationTexts, MarkupNavigationTexts(locale: .japanese))

        // Changing one text keeps the locale's others.
        configuration.navigationTexts.done = "保存"
        XCTAssertEqual(configuration.navigationTexts.done, "保存")
        XCTAssertEqual(configuration.navigationTexts.cancel, "キャンセル")

        // Texts that were set do not follow a later locale change; texts that were not set do.
        configuration.locale = .english
        XCTAssertEqual(configuration.navigationTexts.done, "保存")
        var english = MarkupEditorConfiguration()
        english.locale = .japanese
        XCTAssertEqual(english.navigationTexts.done, "完了")

        XCTAssertEqual(MarkupEditorConfiguration(locale: .japanese, navigationTexts: .english).navigationTexts, .english)
    }

    func testEveryJapaneseTextIsTranslated() {
        let texts: [KeyPath<Strings, String>] = [
            \.cancel, \.done, \.undo, \.redo, \.titleImage, \.titleBoard, \.discardTitle, \.discardMessage, \.discard,
            \.keepEditing, \.exporting, \.exportFailed,
            \.actionDelete, \.actionDuplicate, \.actionBringToFront, \.actionSendToBack, \.actionLock, \.actionUnlock,
            \.actionStyle, \.actionMove, \.actionResize, \.actionRotate, \.actionDraw, \.actionHighlight,
            \.actionAddShape, \.actionAddArrow, \.actionMoveEndpoint, \.actionAddPolyline, \.actionAddCurve,
            \.actionAddPoint, \.actionMovePoint, \.actionDeletePoint, \.actionCloseShape, \.actionOpenShape,
            \.actionAddText, \.actionEditText, \.actionErase, \.actionArrange, \.actionAddImages,
            \.toolSelect, \.toolSketch, \.toolHighlight, \.toolShapes, \.toolArrow, \.toolPolyline, \.toolCurve,
            \.toolLines, \.toolText, \.toolNote, \.toolEraser, \.shapeStyle, \.borderColor, \.fillColor, \.textStyle,
            \.addImages, \.photoLibrary, \.camera, \.arrange, \.arrangeRow, \.arrangeColumn, \.arrangeGrid,
            \.arrangeTidy, \.zoomToFit,
            \.editText, \.duplicate, \.bringToFront, \.sendToBack, \.lock, \.unlock, \.delete, \.finishPath,
            \.closeShape, \.openShape, \.deletePoint,
            \.lineWidth, \.lineStyle, \.solid, \.dashed, \.dotted, \.arrowheads, \.opacity, \.cornerRadius, \.shadow,
            \.noColor, \.customColor, \.font, \.fontSize, \.smaller, \.larger, \.bold, \.italic, \.alignment,
            \.textColor,
        ]
        for text in texts {
            let english = Strings.english[keyPath: text]
            let japanese = Strings.japanese[keyPath: text]
            XCTAssertFalse(japanese.isEmpty, "\(text) is empty")
            XCTAssertNotEqual(japanese, english, "\(text) is not translated")
        }
        for kind in ShapeKind.allCases {
            for lockAspect in [false, true] {
                XCTAssertNotEqual(
                    Strings.japanese.shapeName(kind, lockAspect: lockAspect),
                    Strings.english.shapeName(kind, lockAspect: lockAspect)
                )
            }
        }
        for family in FontFamily.allCases {
            XCTAssertNotEqual(Strings.japanese.fontFamilyName(family), Strings.english.fontFamilyName(family))
        }
        XCTAssertEqual(SelectionActionBar.Action.delete.title(.japanese), "削除")
        XCTAssertEqual(SelectionActionBar.Action.allCases.map { $0.title(.english) }.count, SelectionActionBar.Action.allCases.count)
    }
}
