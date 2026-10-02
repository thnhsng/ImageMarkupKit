import UIKit
import XCTest
@testable import ImageMarkupKit

final class BoardLayoutTests: XCTestCase {
    private func sources(_ count: Int) -> [ImageSource] {
        (0..<count).map { ImageSource(assetID: "\($0)", pixelSize: $0 % 2 == 0 ? CGSize(width: 400, height: 300) : CGSize(width: 300, height: 400)) }
    }

    func testDefaultBoardIsSideBySideThreePerRow() {
        let board = MarkupDocument.board(sources(4))
        let frames = board.imageItems.compactMap { $0.box?.frame }
        XCTAssertEqual(frames.map(\.height), [600, 600, 600, 600])
        XCTAssertEqual(frames[1].minX, frames[0].maxX + BoardLayout.gap, accuracy: 1e-9)
        XCTAssertEqual(frames[2].minY, frames[0].minY)
        XCTAssertEqual(frames[3].minY, frames[0].maxY + BoardLayout.gap, accuracy: 1e-9)
    }

    func testAppendingContinuesTheReadingOrder() {
        var board = MarkupDocument.board(sources(2))
        let before = board.imageItems.compactMap { $0.box?.frame }
        board.appendImages(sources(2))
        let frames = board.imageItems.compactMap { $0.box?.frame }
        XCTAssertEqual(Array(frames.prefix(2)), before, "existing photos stay put")
        XCTAssertEqual(frames[2].minY, frames[0].minY, "third photo joins the first row")
        XCTAssertGreaterThan(frames[3].minY, frames[0].maxY, "fourth wraps")
    }

    func testAppendingAfterManualMovesAvoidsOverlap() {
        var board = MarkupDocument.board(sources(2))
        // Move the second photo where the third would go.
        let third = BoardLayout.flowFrames(for: sources(3).map(\.pixelSize))[2]
        board.update(board.items[1].id) { $0.box = Box(frame: third) }
        board.appendImages(sources(1))
        let frames = board.imageItems.compactMap { $0.box?.frame }
        XCTAssertFalse(frames[2].intersects(frames[1]))
        XCTAssertFalse(frames[2].intersects(frames[0]))
    }

    @MainActor
    func testArrangeColumnAndGrid() {
        let store = EditorStore(document: .board(sources(4)), assets: AssetStore())
        store.arrange(.column)
        let column = store.document.imageItems.compactMap { $0.box?.frame }
        XCTAssertTrue(column.allSatisfy { abs($0.width - 800) < 1e-9 })
        for i in 1..<column.count { XCTAssertGreaterThan(column[i].minY, column[i - 1].maxY) }

        store.arrange(.grid)
        let grid = store.document.imageItems.compactMap { $0.box?.frame }
        XCTAssertEqual(grid[0].minY, grid[1].minY)
        XCTAssertGreaterThan(grid[2].minY, grid[0].maxY, "2 per row for 4 photos")
        store.undo()
        XCTAssertEqual(store.document.imageItems.compactMap { $0.box?.frame }, column, "arrange is one undo step")
    }

    func testChildrenFollowTheirPhoto() throws {
        var board = MarkupDocument.board(sources(1))
        let photo = board.items[0]
        let photoBox = try XCTUnwrap(photo.box)
        let circle = MarkupItem.shape(.ellipse, frame: CGRect(x: 100, y: 100, width: 80, height: 80), style: ItemStyle())
        let label = MarkupItem.text("Crack", at: CGPoint(x: 300, y: 200), font: FontSpec(size: 30), color: .red)
        board.items += [circle, label]
        board.attachAnnotationsToPhotos()
        XCTAssertEqual(board.item(circle.id)?.parentID, photo.id)
        XCTAssertEqual(board.item(label.id)?.parentID, photo.id)

        // Move, scale ×2 about the photo's center, and rotate 90°.
        var moved = photo
        let newFrame = CGRect(center: photoBox.center + CGPoint(x: 1000, y: 0), size: CGSize(width: photoBox.frame.width * 2, height: photoBox.frame.height * 2))
        moved.box = Box(frame: newFrame, rotation: .pi / 2)
        var result = board
        result.update(photo.id) { $0 = moved }
        Attachments.carryChildren(of: photo, to: moved, from: board, into: &result)

        let circleBox = try XCTUnwrap(result.item(circle.id)?.box)
        XCTAssertEqual(circleBox.frame.width, 160, accuracy: 1e-9, "shapes scale with the photo")
        XCTAssertEqual(circleBox.rotation, .pi / 2, accuracy: 1e-9, "and rotate with it")
        // The circle keeps its relative position: same normalized point of the photo.
        let before = photoBox.normalizedPoint(world: try XCTUnwrap(circle.box).center)
        let after = try XCTUnwrap(moved.box).normalizedPoint(world: circleBox.center)
        XCTAssertEqual(before.x, after.x, accuracy: 1e-9)
        XCTAssertEqual(before.y, after.y, accuracy: 1e-9)

        let labelBox = try XCTUnwrap(result.item(label.id)?.box)
        XCTAssertEqual(labelBox.frame.size, try XCTUnwrap(label.box).frame.size, "text keeps its size")
        XCTAssertEqual(labelBox.rotation, 0, "and its orientation")
    }

    func testParentIsTopmostPhotoUnderTheCenter() {
        var board = MarkupDocument.board(sources(2))
        let second = board.imageItems[1]
        let center = second.box!.center
        let mark = MarkupItem.shape(.rectangle, frame: CGRect(center: center, size: CGSize(width: 20, height: 20)), style: ItemStyle())
        let outside = MarkupItem.shape(.rectangle, frame: CGRect(x: -500, y: -500, width: 20, height: 20), style: ItemStyle())
        board.items += [mark, outside]
        board.attachAnnotationsToPhotos()
        XCTAssertEqual(board.item(mark.id)?.parentID, second.id)
        XCTAssertNil(board.item(outside.id)?.parentID)
    }
}
