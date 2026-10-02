import Foundation

/// All user-facing strings. English for the PoC; this is the single place to localize (JA / VI).
enum Strings {
    // Navigation
    static let cancel = "Cancel"
    static let done = "Done"
    static let undo = "Undo"
    static let redo = "Redo"
    static let titleImage = "Markup"
    static let titleBoard = "Board"
    static let discardTitle = "Discard changes?"
    static let discardMessage = "Your markup will not be saved."
    static let discard = "Discard"
    static let keepEditing = "Keep Editing"
    static let exporting = "Exporting…"
    static let exportFailed = "Could not save the image."

    // Undo action names
    static let actionDelete = "Delete"
    static let actionDuplicate = "Duplicate"
    static let actionBringToFront = "Bring to Front"
    static let actionSendToBack = "Send to Back"
    static let actionLock = "Lock"
    static let actionUnlock = "Unlock"
    static let actionStyle = "Change Style"
    static let actionMove = "Move"
    static let actionResize = "Resize"
    static let actionRotate = "Rotate"
    static let actionDraw = "Draw"
    static let actionHighlight = "Highlight"
    static let actionAddShape = "Add Shape"
    static let actionAddArrow = "Add Arrow"
    static let actionMoveEndpoint = "Move Endpoint"
    static let actionAddPolyline = "Add Polyline"
    static let actionAddCurve = "Add Curve"
    static let actionAddPoint = "Add Point"
    static let actionMovePoint = "Move Point"
    static let actionDeletePoint = "Delete Point"
    static let actionCloseShape = "Close Shape"
    static let actionOpenShape = "Open Shape"
    static let actionAddText = "Add Text"
    static let actionEditText = "Edit Text"
    static let actionErase = "Erase"
    static let actionArrange = "Arrange"
    static let actionAddImages = "Add Images"

    // Tools
    static let toolSelect = "Select"
    static let toolSketch = "Sketch"
    static let toolHighlight = "Highlight"
    static let toolShapes = "Shapes"
    static let toolArrow = "Arrow / Line"
    static let toolPolyline = "Polyline"
    static let toolCurve = "Curve"
    static let toolLines = "Lines"
    static let toolText = "Text"
    static let toolNote = "Note"
    static let toolEraser = "Eraser"
    static let shapeStyle = "Shape Style"
    static let borderColor = "Border Color"
    static let fillColor = "Fill Color"
    static let textStyle = "Text Style"
    static let addImages = "Add Images"
    static let photoLibrary = "Photo Library"
    static let camera = "Camera"
    static let arrange = "Arrange"
    static let arrangeRow = "Row"
    static let arrangeColumn = "Column"
    static let arrangeGrid = "Grid"
    static let arrangeTidy = "Tidy Up"
    static let zoomToFit = "Zoom to Fit"

    // Shapes
    static func shapeName(_ kind: ShapeKind, lockAspect: Bool) -> String {
        switch (kind, lockAspect) {
        case (.rectangle, true): return "Square"
        case (.rectangle, false): return "Rectangle"
        case (.roundedRectangle, _): return "Rounded Rectangle"
        case (.ellipse, true): return "Circle"
        case (.ellipse, false): return "Oval"
        case (.triangle, _): return "Triangle"
        case (.diamond, _): return "Diamond"
        case (.star, _): return "Star"
        case (.pentagon, _): return "Pentagon"
        case (.speechBubble, _): return "Speech Bubble"
        case (.highlightBox, _): return "Highlight Box"
        }
    }

    // Selection action bar
    static let editText = "Edit Text"
    static let duplicate = "Duplicate"
    static let bringToFront = "Bring to Front"
    static let sendToBack = "Send to Back"
    static let lock = "Lock"
    static let unlock = "Unlock"
    static let delete = "Delete"
    static let finishPath = "Finish"
    static let closeShape = "Close Shape"
    static let openShape = "Open Shape"
    static let deletePoint = "Delete Point"

    // Panels
    static let lineWidth = "Line Width"
    static let lineStyle = "Line Style"
    static let solid = "Solid"
    static let dashed = "Dashed"
    static let dotted = "Dotted"
    static let arrowheads = "Arrowheads"
    static let opacity = "Opacity"
    static let cornerRadius = "Corners"
    static let shadow = "Shadow"
    static let noColor = "None"
    static let customColor = "Custom…"
    static let font = "Font"
    static let fontSize = "Size"
    static let bold = "Bold"
    static let italic = "Italic"
    static let alignment = "Alignment"
    static let textColor = "Text Color"
    static let fontFamilyNames: [FontFamily: String] = [
        .system: "System",
        .rounded: "Rounded",
        .serif: "Serif",
        .monospaced: "Mono",
        .hiraginoSans: "Hiragino Sans",
        .hiraginoMincho: "Hiragino Mincho",
    ]

    // Defaults for new text
    static let newNoteText = ""
}
