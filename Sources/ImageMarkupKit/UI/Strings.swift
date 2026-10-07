import Foundation

/// All user-facing strings, in English and Japanese: the same texts as the web package (`image-markup-kit`).
/// The editor holds one table (`EditorStore.strings`), picked by `MarkupEditorConfiguration.locale`.
struct Strings: Sendable {
    let locale: MarkupLocale

    init(locale: MarkupLocale) {
        self.locale = locale
    }

    static let english = Strings(locale: .english)
    static let japanese = Strings(locale: .japanese)

    private func text(_ english: String, _ japanese: String) -> String {
        switch locale {
        case .english: return english
        case .japanese: return japanese
        }
    }

    // Navigation
    var cancel: String { text("Cancel", "キャンセル") }
    var done: String { text("Done", "完了") }
    var undo: String { text("Undo", "取り消す") }
    var redo: String { text("Redo", "やり直す") }
    var titleImage: String { text("Markup", "マークアップ") }
    var titleBoard: String { text("Board", "ボード") }
    var discardTitle: String { text("Discard changes?", "変更を破棄しますか？") }
    var discardMessage: String { text("Your markup will not be saved.", "マークアップは保存されません。") }
    var discard: String { text("Discard", "破棄") }
    var keepEditing: String { text("Keep Editing", "編集を続ける") }
    var exporting: String { text("Exporting…", "書き出し中…") }
    var exportFailed: String { text("Could not save the image.", "画像を保存できませんでした。") }

    // Undo action names
    var actionDelete: String { text("Delete", "削除") }
    var actionDuplicate: String { text("Duplicate", "複製") }
    var actionBringToFront: String { text("Bring to Front", "最前面へ移動") }
    var actionSendToBack: String { text("Send to Back", "最背面へ移動") }
    var actionLock: String { text("Lock", "ロック") }
    var actionUnlock: String { text("Unlock", "ロック解除") }
    var actionStyle: String { text("Change Style", "スタイルの変更") }
    var actionMove: String { text("Move", "移動") }
    var actionResize: String { text("Resize", "サイズ変更") }
    var actionRotate: String { text("Rotate", "回転") }
    var actionDraw: String { text("Draw", "描画") }
    var actionHighlight: String { text("Highlight", "ハイライト") }
    var actionAddShape: String { text("Add Shape", "図形の追加") }
    var actionAddArrow: String { text("Add Arrow", "矢印の追加") }
    var actionMoveEndpoint: String { text("Move Endpoint", "端点の移動") }
    var actionAddPolyline: String { text("Add Polyline", "折れ線の追加") }
    var actionAddCurve: String { text("Add Curve", "曲線の追加") }
    var actionAddPoint: String { text("Add Point", "点の追加") }
    var actionMovePoint: String { text("Move Point", "点の移動") }
    var actionDeletePoint: String { text("Delete Point", "点の削除") }
    var actionCloseShape: String { text("Close Shape", "図形を閉じる") }
    var actionOpenShape: String { text("Open Shape", "図形を開く") }
    var actionAddText: String { text("Add Text", "テキストの追加") }
    var actionEditText: String { text("Edit Text", "テキストの編集") }
    var actionErase: String { text("Erase", "消去") }
    var actionArrange: String { text("Arrange", "整列") }
    var actionAddImages: String { text("Add Images", "画像の追加") }

    // Tools
    var toolSelect: String { text("Select", "選択") }
    var toolSketch: String { text("Sketch", "スケッチ") }
    var toolHighlight: String { text("Highlight", "ハイライト") }
    var toolShapes: String { text("Shapes", "図形") }
    var toolArrow: String { text("Arrow / Line", "矢印 / 線") }
    var toolPolyline: String { text("Polyline", "折れ線") }
    var toolCurve: String { text("Curve", "曲線") }
    var toolLines: String { text("Lines", "線") }
    var toolText: String { text("Text", "テキスト") }
    var toolNote: String { text("Note", "メモ") }
    var toolEraser: String { text("Eraser", "消しゴム") }
    var shapeStyle: String { text("Shape Style", "図形のスタイル") }
    var borderColor: String { text("Border Color", "枠線の色") }
    var fillColor: String { text("Fill Color", "塗りつぶしの色") }
    var textStyle: String { text("Text Style", "テキストのスタイル") }
    var addImages: String { text("Add Images", "画像を追加") }
    var photoLibrary: String { text("Photo Library", "写真を選択") }
    var camera: String { text("Camera", "カメラ") }
    var arrange: String { text("Arrange", "整列") }
    var arrangeRow: String { text("Row", "横に並べる") }
    var arrangeColumn: String { text("Column", "縦に並べる") }
    var arrangeGrid: String { text("Grid", "グリッド") }
    var arrangeTidy: String { text("Tidy Up", "整頓") }
    var zoomToFit: String { text("Zoom to Fit", "全体を表示") }

    // Shapes
    func shapeName(_ kind: ShapeKind, lockAspect: Bool) -> String {
        switch (kind, lockAspect) {
        case (.rectangle, true): return text("Square", "正方形")
        case (.rectangle, false): return text("Rectangle", "長方形")
        case (.roundedRectangle, _): return text("Rounded Rectangle", "角丸長方形")
        case (.ellipse, true): return text("Circle", "円")
        case (.ellipse, false): return text("Oval", "楕円")
        case (.triangle, _): return text("Triangle", "三角形")
        case (.diamond, _): return text("Diamond", "ひし形")
        case (.star, _): return text("Star", "星")
        case (.pentagon, _): return text("Pentagon", "五角形")
        case (.speechBubble, _): return text("Speech Bubble", "吹き出し")
        case (.highlightBox, _): return text("Highlight Box", "ハイライトボックス")
        }
    }

    // Selection action bar
    var editText: String { text("Edit Text", "テキストを編集") }
    var duplicate: String { text("Duplicate", "複製") }
    var bringToFront: String { text("Bring to Front", "最前面へ") }
    var sendToBack: String { text("Send to Back", "最背面へ") }
    var lock: String { text("Lock", "ロック") }
    var unlock: String { text("Unlock", "ロック解除") }
    var delete: String { text("Delete", "削除") }
    var finishPath: String { text("Finish", "完了") }
    var closeShape: String { text("Close Shape", "図形を閉じる") }
    var openShape: String { text("Open Shape", "図形を開く") }
    var deletePoint: String { text("Delete Point", "点を削除") }

    // Panels
    var lineWidth: String { text("Line Width", "線の太さ") }
    var lineStyle: String { text("Line Style", "線の種類") }
    var solid: String { text("Solid", "実線") }
    var dashed: String { text("Dashed", "破線") }
    var dotted: String { text("Dotted", "点線") }
    var arrowheads: String { text("Arrowheads", "矢印") }
    var opacity: String { text("Opacity", "不透明度") }
    var cornerRadius: String { text("Corners", "角の丸み") }
    var shadow: String { text("Shadow", "影") }
    var noColor: String { text("None", "なし") }
    var customColor: String { text("Custom…", "カスタム…") }
    var font: String { text("Font", "フォント") }
    var fontSize: String { text("Size", "サイズ") }
    var smaller: String { text("Smaller", "小さく") }
    var larger: String { text("Larger", "大きく") }
    var bold: String { text("Bold", "太字") }
    var italic: String { text("Italic", "斜体") }
    var alignment: String { text("Alignment", "配置") }
    var textColor: String { text("Text Color", "文字の色") }

    func fontFamilyName(_ family: FontFamily) -> String {
        switch family {
        case .system: return text("System", "システム")
        case .rounded: return text("Rounded", "ラウンド")
        case .serif: return text("Serif", "セリフ")
        case .monospaced: return text("Mono", "等幅")
        case .hiraginoSans: return text("Hiragino Sans", "ゴシック")
        case .hiraginoMincho: return text("Hiragino Mincho", "明朝")
        }
    }
}
