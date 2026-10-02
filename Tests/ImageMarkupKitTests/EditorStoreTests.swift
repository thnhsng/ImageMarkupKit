import UIKit
import XCTest
@testable import ImageMarkupKit

final class EditorStoreTests: XCTestCase {
    @MainActor
    private func makeStore(_ document: MarkupDocument? = nil) -> EditorStore {
        let doc = document ?? MarkupDocument.board([ImageSource(assetID: "a", pixelSize: CGSize(width: 400, height: 300))])
        return EditorStore(document: doc, assets: AssetStore())
    }

    @MainActor
    func testCommitUndoRedo() {
        let store = makeStore()
        let original = store.document
        let rect = MarkupItem.shape(.rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10), style: ItemStyle())
        store.perform("Add") { $0.items.append(rect) }
        XCTAssertTrue(store.document.contains(rect.id))
        XCTAssertTrue(store.undoManager.canUndo)

        store.perform("Move") { $0.update(rect.id) { $0.box = $0.box?.offsetBy(CGPoint(x: 5, y: 0)) } }
        store.undo()
        XCTAssertEqual(store.document.item(rect.id)?.box?.frame.minX, 0)
        store.undo()
        XCTAssertEqual(store.document, original)
        XCTAssertFalse(store.undoManager.canUndo)
        store.redo()
        store.redo()
        XCTAssertEqual(store.document.item(rect.id)?.box?.frame.minX, 5)
    }

    @MainActor
    func testCoalescedCommitsAreOneUndoStep() {
        let store = makeStore()
        let rect = MarkupItem.shape(.rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10), style: ItemStyle(lineWidth: 2))
        store.perform("Add", select: [rect.id]) { $0.items.append(rect) }
        for width in stride(from: 3.0, through: 20.0, by: 1.0) {
            store.updateStyle(coalescingKey: "lineWidth") { $0.lineWidth = CGFloat(width) }
        }
        XCTAssertEqual(store.document.item(rect.id)?.style.lineWidth, 20)
        store.undo()
        XCTAssertEqual(store.document.item(rect.id)?.style.lineWidth, 2, "a whole slider drag undoes in one step")
    }

    @MainActor
    func testStyleChangeBecomesTheDefault() {
        let store = makeStore()
        let rect = MarkupItem.shape(.rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10), style: ItemStyle())
        store.perform("Add", select: [rect.id]) { $0.items.append(rect) }
        store.updateStyle { $0.strokeColor = .blue }
        XCTAssertEqual(store.defaults.shape.strokeColor, .blue)

        store.clearSelection()
        store.tool = .pen
        store.updateStyle { $0.lineWidth = 12 }
        XCTAssertEqual(store.defaults.pen.lineWidth, 12, "without a selection only the tool default changes")
        XCTAssertFalse(store.undoManager.canRedo)
    }

    @MainActor
    func testDeleteFreezesConnectorsAndDetachesChildren() {
        var board = MarkupDocument.board([
            ImageSource(assetID: "a", pixelSize: CGSize(width: 400, height: 300)),
            ImageSource(assetID: "b", pixelSize: CGSize(width: 400, height: 300)),
        ])
        let a = board.items[0], b = board.items[1]
        let connector = MarkupItem.connector(from: ConnectorBinding(itemID: a.id, anchor: CGPoint(x: 0.5, y: 0.5)),
                                             to: ConnectorBinding(itemID: b.id, anchor: CGPoint(x: 0.5, y: 0.5)),
                                             in: board, style: ItemStyle())
        var note = MarkupItem.text("x", at: CGPoint(x: 900, y: 100), font: FontSpec(), color: .red)
        note.parentID = b.id
        board.items += [connector, note]
        let store = makeStore(board)
        let endBefore = Bindings.resolve(try! XCTUnwrap(connector.lineContent).end, in: store.document)

        store.select([b.id])
        store.deleteSelection()

        let line = try! XCTUnwrap(store.document.item(connector.id)?.lineContent)
        XCTAssertNil(line.end.binding)
        XCTAssertNotNil(line.start.binding)
        XCTAssertEqual(line.end.point, endBefore, "the freed end stays where it was")
        XCTAssertNil(store.document.item(note.id)?.parentID)
    }

    @MainActor
    func testDuplicateDropsBindings() {
        var board = MarkupDocument.board([ImageSource(assetID: "a", pixelSize: CGSize(width: 400, height: 300))])
        let connector = MarkupItem.connector(from: ConnectorBinding(itemID: board.items[0].id, anchor: .zero),
                                             to: ConnectorBinding(itemID: board.items[0].id, anchor: CGPoint(x: 1, y: 1)),
                                             in: board, style: ItemStyle())
        board.items.append(connector)
        let store = makeStore(board)
        store.select([connector.id])
        store.duplicateSelection()
        let copy = try! XCTUnwrap(store.selectedItem?.lineContent)
        XCTAssertNil(copy.start.binding)
        XCTAssertNil(copy.end.binding)
        XCTAssertNotEqual(store.selection, [connector.id])
    }

    @MainActor
    func testZOrderStaysWithinBands() {
        var board = MarkupDocument.board([
            ImageSource(assetID: "a", pixelSize: CGSize(width: 400, height: 300)),
            ImageSource(assetID: "b", pixelSize: CGSize(width: 400, height: 300)),
        ])
        let rect = MarkupItem.shape(.rectangle, frame: .init(x: 0, y: 0, width: 5, height: 5), style: ItemStyle())
        board.items.append(rect)
        let store = makeStore(board)
        store.select([rect.id])
        store.moveSelection(.back)
        XCTAssertEqual(store.document.items.map(\.isImage), [true, true, false], "annotations never go below photos")
        let firstImage = store.document.items[0].id
        store.select([firstImage])
        store.moveSelection(.front)
        XCTAssertEqual(store.document.items[1].id, firstImage, "a photo moves to the top of the photo band")
        XCTAssertFalse(store.document.items[2].isImage)
    }

    @MainActor
    func testLockedItemsAreNotDeleted() {
        let store = makeStore()
        var rect = MarkupItem.shape(.rectangle, frame: .init(x: 0, y: 0, width: 5, height: 5), style: ItemStyle())
        rect.isLocked = true
        store.perform("Add", select: [rect.id]) { $0.items.append(rect) }
        store.deleteSelection()
        XCTAssertTrue(store.document.contains(rect.id))
    }
}
