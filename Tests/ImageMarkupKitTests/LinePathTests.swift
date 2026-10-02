import UIKit
import XCTest
@testable import ImageMarkupKit

/// Polylines and curves: geometry, hit testing, persistence, editing and the drawing gestures.
final class LinePathTests: XCTestCase {
    private func document(with items: [MarkupItem]) -> MarkupDocument {
        MarkupDocument(kind: .board, items: items)
    }

    private func line(_ item: MarkupItem?) throws -> LineContent {
        try XCTUnwrap(item?.lineContent)
    }

    // MARK: Geometry

    func testCurvePassesThroughEveryPoint() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 80), CGPoint(x: 200, y: 0), CGPoint(x: 300, y: 60)]
        let samples = LinePath.flattened(points, kind: .curve, closed: false)
        XCTAssertGreaterThan(samples.count, 30, "curves are sampled densely")
        for point in points {
            XCTAssertTrue(samples.contains(point), "\(point) is on the curve")
        }
        let closed = LinePath.flattened(points, kind: .curve, closed: true)
        XCTAssertEqual(closed.first, closed.last, "closed curves return to the start")
    }

    func testPolylineSamplesAreItsPoints() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]
        XCTAssertEqual(LinePath.flattened(points, kind: .polyline, closed: false), points)
        XCTAssertEqual(LinePath.flattened(points, kind: .polyline, closed: true), points + [points[0]])
        XCTAssertEqual(LinePath.insertionPoints(points, kind: .polyline, closed: false), [CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 50)])
    }

    func testCurveBoundsCoverTheSamples() {
        let curve = MarkupItem.curve(through: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 100), CGPoint(x: 60, y: 100), CGPoint(x: 100, y: 0)],
                                     style: ItemStyle(lineWidth: 2))
        let doc = document(with: [curve])
        let bounds = ItemGeometry.visualBounds(of: curve, in: doc)
        for sample in LinePath.samples(of: try! line(curve), in: doc) {
            XCTAssertTrue(bounds.contains(sample), "\(sample) inside \(bounds)")
        }
    }

    func testStraightLineGeometryIsUnchanged() {
        let geometry = PathFactory.lineGeometry(start: .zero, end: CGPoint(x: 100, y: 0), lineWidth: 6, startHead: .none, endHead: .arrow)
        // Head length max(6 × 3.2, 14) = 19.2; the shaft stops 0.7 × 19.2 inside it.
        let shaft = geometry.shaft.boundingBoxOfPath
        XCTAssertEqual(shaft.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(shaft.maxX, 100 - 19.2 * 0.7, accuracy: 1e-9)
        let heads = try! XCTUnwrap(geometry.heads).boundingBoxOfPath
        XCTAssertEqual(heads.maxX, 100, accuracy: 1e-9)
        XCTAssertEqual(heads.minX, 100 - 19.2, accuracy: 1e-9)
    }

    func testArrowheadFollowsTheLastSegment() {
        let polyline = MarkupItem.polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)],
                                           endHead: .arrow, style: ItemStyle(lineWidth: 6))
        let geometry = PathFactory.lineGeometry(try! line(polyline), in: document(with: [polyline]), lineWidth: 6)
        let heads = try! XCTUnwrap(geometry.heads).boundingBoxOfPath
        XCTAssertEqual(heads.midX, 100, accuracy: 1e-6, "points down the last segment")
        XCTAssertEqual(heads.maxY, 100, accuracy: 1e-6)
        XCTAssertEqual(heads.minY, 100 - 19.2, accuracy: 1e-6)
    }

    func testClosedLinesHaveNoArrowheads() {
        let polygon = MarkupItem.polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 50, y: 80)],
                                          closed: true, endHead: .arrow, style: ItemStyle())
        XCTAssertNil(PathFactory.lineGeometry(try! line(polygon), in: document(with: [polygon]), lineWidth: 6).heads)
    }

    // MARK: Hit testing and erasing

    func testPolylineHitFollowsEverySegment() {
        let polyline = MarkupItem.polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)], style: ItemStyle(lineWidth: 2))
        let doc = document(with: [polyline])
        XCTAssertNotNil(HitTesting.item(at: CGPoint(x: 102, y: 60), in: doc, tolerance: 3), "second segment")
        XCTAssertNil(HitTesting.item(at: CGPoint(x: 50, y: 50), in: doc, tolerance: 3), "an open polyline has no inside")
    }

    func testCurveHitFollowsTheCurveNotTheChord() {
        let curve = MarkupItem.curve(through: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 0)], style: ItemStyle(lineWidth: 2))
        let doc = document(with: [curve])
        XCTAssertNotNil(HitTesting.item(at: CGPoint(x: 100, y: 97), in: doc, tolerance: 3))
        XCTAssertNil(HitTesting.item(at: CGPoint(x: 100, y: 0), in: doc, tolerance: 3))
    }

    func testClosedPolygonInside() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 200), CGPoint(x: 0, y: 200)]
        let filled = MarkupItem.polyline(points: points, closed: true, style: ItemStyle(fillColor: .yellow))
        XCTAssertNotNil(HitTesting.item(at: CGPoint(x: 100, y: 100), in: document(with: [filled]), tolerance: 2))

        let outline = MarkupItem.polyline(points: points, closed: true, style: ItemStyle())
        let dot = MarkupItem.shape(.ellipse, frame: CGRect(x: 90, y: 90, width: 20, height: 20), style: ItemStyle(strokeColor: nil, fillColor: .blue, lineWidth: 0))
        let doc = document(with: [dot, outline])
        XCTAssertEqual(HitTesting.item(at: CGPoint(x: 100, y: 100), in: doc, tolerance: 2)?.id, dot.id, "drawn pixels win")
        XCTAssertEqual(HitTesting.item(at: CGPoint(x: 40, y: 150), in: doc, tolerance: 2)?.id, outline.id, "empty inside is grabbable")
    }

    func testEraserHitsLaterSegments() {
        let polyline = MarkupItem.polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)], style: ItemStyle(lineWidth: 2))
        let doc = document(with: [polyline])
        XCTAssertEqual(HitTesting.erasableItems(alongSegment: CGPoint(x: 80, y: 60), CGPoint(x: 120, y: 60), radius: 3, in: doc), [polyline.id])
        XCTAssertEqual(HitTesting.erasableItems(alongSegment: CGPoint(x: 20, y: 60), CGPoint(x: 60, y: 60), radius: 3, in: doc), [])
    }

    // MARK: Export

    func testExportDrawsCurvesAndFilledPolygons() {
        var board = MarkupDocument(kind: .board, backgroundColor: .white)
        board.items.append(.polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 200), CGPoint(x: 0, y: 200)],
                                     closed: true, style: ItemStyle(strokeColor: .red, fillColor: .blue, lineWidth: 4)))
        board.items.append(.curve(through: [CGPoint(x: 300, y: 0), CGPoint(x: 400, y: 200), CGPoint(x: 500, y: 0)],
                                  style: ItemStyle(strokeColor: .red, lineWidth: 10)))
        let options = MarkupExportOptions(format: .png)
        let plan = ExportPlanner.plan(for: board, options: options)
        let rendering = MarkupRenderer.renderSynchronously(board, assets: AssetCatalog(), options: options)
        func pixel(atCanvas p: CGPoint) -> TestSupport.RGBA {
            TestSupport.pixel(rendering.image, x: Int((p.x - plan.rect.minX) * plan.scaleX), y: Int((p.y - plan.rect.minY) * plan.scaleY))
        }
        let red = TestSupport.RGBA(r: 255, g: 59, b: 48, a: 255)
        let white = TestSupport.RGBA(r: 255, g: 255, b: 255, a: 255)
        XCTAssertTrue(pixel(atCanvas: CGPoint(x: 100, y: 100)).isClose(to: .init(r: 0, g: 122, b: 255, a: 255)), "polygon fill")
        XCTAssertTrue(pixel(atCanvas: CGPoint(x: 200, y: 100)).isClose(to: red), "polygon border")
        XCTAssertTrue(pixel(atCanvas: CGPoint(x: 400, y: 199)).isClose(to: red), "the curve reaches its middle point")
        XCTAssertTrue(pixel(atCanvas: CGPoint(x: 400, y: 20)).isClose(to: white), "not the chord")
    }

    // MARK: Persistence

    func testStraightLinesEncodeAsBefore() throws {
        let arrow = MarkupItem.line(from: .zero, to: CGPoint(x: 10, y: 10), style: ItemStyle())
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(arrow), encoding: .utf8))
        for key in ["kind", "waypoints", "isClosed"] {
            XCTAssertFalse(json.contains(key), "\(key) is not written for straight lines")
        }
    }

    func testPolylineAndCurveRoundTrip() throws {
        var doc = MarkupDocument.imageDocument(ImageSource(assetID: "a", pixelSize: CGSize(width: 1000, height: 800)))
        doc.items += [
            MarkupItem.polyline(points: [CGPoint(x: 1, y: 2), CGPoint(x: 30, y: 40), CGPoint(x: 50, y: 6)], endHead: .arrow, style: ItemStyle()),
            MarkupItem.polyline(points: [CGPoint(x: 1, y: 2), CGPoint(x: 30, y: 40), CGPoint(x: 50, y: 6)], closed: true, style: ItemStyle(fillColor: .yellow)),
            MarkupItem.curve(through: [CGPoint(x: 5, y: 5), CGPoint(x: 60, y: 90), CGPoint(x: 120, y: 5), CGPoint(x: 150, y: 40)], style: ItemStyle()),
        ]
        let decoded = try MarkupDocument.decode(from: doc.jsonData())
        XCTAssertEqual(decoded, doc)
        XCTAssertEqual(decoded.items.compactMap(\.lineContent).map(\.kind), [.polyline, .polyline, .curve])
    }

    func testLegacyLinesDecodeAsStraight() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "document_v1", withExtension: "json", subdirectory: "Fixtures"))
        let document = try MarkupDocument.decode(from: Data(contentsOf: url))
        let lines = document.items.compactMap(\.lineContent)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.allSatisfy { $0.kind == .straight && $0.waypoints.isEmpty && !$0.isClosed })
    }

    // MARK: Moving and editing

    func testMovingAndDuplicatingCarryWaypoints() throws {
        let polyline = MarkupItem.polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)], style: ItemStyle())
        let doc = document(with: [polyline])
        let moved = TransformMath.translated(polyline, by: CGPoint(x: 10, y: 20), in: doc)
        XCTAssertEqual(try line(moved).waypoints, [CGPoint(x: 60, y: 70)])
    }

    @MainActor
    func testDuplicateOffsetsWaypoints() throws {
        let polyline = MarkupItem.polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)], style: ItemStyle())
        let store = EditorStore(document: document(with: [polyline]), assets: AssetStore())
        store.select([polyline.id])
        store.duplicateSelection()
        XCTAssertEqual(try line(store.selectedItem).waypoints, [CGPoint(x: 74, y: 74)])
    }

    func testPhotoCarriesAttachedWaypoints() throws {
        var board = MarkupDocument.board([ImageSource(assetID: "a", pixelSize: CGSize(width: 400, height: 300))])
        let photo = board.items[0]
        let center = try XCTUnwrap(photo.box?.center)
        var polyline = MarkupItem.polyline(points: [center, center + CGPoint(x: 20, y: 10), center + CGPoint(x: 40, y: 0)], style: ItemStyle())
        polyline.parentID = photo.id
        board.items.append(polyline)
        var moved = photo
        moved.box = photo.box?.offsetBy(CGPoint(x: 300, y: 0))
        var result = board
        result.update(photo.id) { $0 = moved }
        Attachments.carryChildren(of: photo, to: moved, from: board, into: &result)
        XCTAssertEqual(try line(result.item(polyline.id)).waypoints, [center + CGPoint(x: 320, y: 10)])
    }

    @MainActor
    func testRemovingPointsAndClosing() throws {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]
        let polyline = MarkupItem.polyline(points: points, style: ItemStyle())
        let store = EditorStore(document: document(with: [polyline]), assets: AssetStore())

        store.setLineClosed(true, for: polyline.id)
        XCTAssertTrue(try line(store.document.item(polyline.id)).isClosed)

        store.removeLinePoint(0, of: polyline.id)
        var content = try line(store.document.item(polyline.id))
        XCTAssertEqual(content.points, Array(points.dropFirst()), "the next point becomes the start")
        XCTAssertTrue(content.isClosed)

        store.removeLinePoint(1, of: polyline.id)
        content = try line(store.document.item(polyline.id))
        XCTAssertEqual(content.points, [points[1], points[3]])
        XCTAssertFalse(content.isClosed, "two points cannot stay closed")

        store.removeLinePoint(0, of: polyline.id)
        XCTAssertEqual(try line(store.document.item(polyline.id)).points.count, 2, "a line keeps two points")
    }

    @MainActor
    func testClosingDropsEndpointBindings() throws {
        var board = MarkupDocument.board([ImageSource(assetID: "a", pixelSize: CGSize(width: 400, height: 300))])
        var polyline = MarkupItem.polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)], style: ItemStyle())
        guard case .line(var content) = polyline.content else { return XCTFail() }
        content.start.binding = ConnectorBinding(itemID: board.items[0].id, anchor: CGPoint(x: 0.5, y: 0.5))
        polyline.content = .line(content)
        board.items.append(polyline)
        let store = EditorStore(document: board, assets: AssetStore())
        store.setLineClosed(true, for: polyline.id)
        XCTAssertNil(try line(store.document.item(polyline.id)).start.binding)
    }

    // MARK: Gestures

    @MainActor
    private func makeEditor() -> MarkupEditorViewController {
        let document = MarkupDocument.imageDocument(ImageSource(assetID: "photo", pixelSize: CGSize(width: 1024, height: 768)))
        let editor = MarkupEditorViewController(document: document, assets: AssetCatalog())
        editor.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 900)
        editor.view.layoutIfNeeded()
        return editor
    }

    @MainActor
    func testPolylineTapsAddOneUndoStepPerPoint() throws {
        let editor = makeEditor()
        let points = [CGPoint(x: 100, y: 100), CGPoint(x: 500, y: 150), CGPoint(x: 800, y: 600), CGPoint(x: 300, y: 650)]
        // The last tap lands on the last point again: that finishes the polyline.
        editor.debugPerform(.taps(.polyline, points: points + [points[3]]))

        let item = try XCTUnwrap(editor.document.items.last)
        let content = try line(item)
        XCTAssertEqual(content.kind, .polyline)
        XCTAssertEqual(content.points, points)
        XCTAssertFalse(content.isClosed)
        XCTAssertEqual(content.endHead, .none, "polylines have no arrowheads by default")
        XCTAssertEqual(editor.tool, .select)
        XCTAssertEqual(editor.selectedItemIDs, [item.id])

        editor.undoTapped()
        XCTAssertEqual(try line(editor.document.item(item.id)).points, Array(points.prefix(3)), "Undo removes the last point")
        editor.undoTapped()
        editor.undoTapped()
        XCTAssertNil(editor.document.item(item.id))
    }

    @MainActor
    func testTappingTheFirstPointClosesThePolyline() throws {
        let editor = makeEditor()
        let points = [CGPoint(x: 100, y: 100), CGPoint(x: 500, y: 150), CGPoint(x: 800, y: 600)]
        editor.debugPerform(.taps(.polyline, points: points + [points[0]]))
        let content = try line(editor.document.items.last)
        XCTAssertEqual(content.points, points)
        XCTAssertTrue(content.isClosed)
        XCTAssertEqual(editor.tool, .select)
    }

    @MainActor
    func testUndoPastCreationEndsTheDraft() throws {
        let editor = makeEditor()
        editor.debugPerform(.taps(.polyline, points: [CGPoint(x: 100, y: 100), CGPoint(x: 500, y: 150)]))
        XCTAssertTrue(editor.interactions.env.polylineDraft.isActive)
        editor.undoTapped()
        XCTAssertFalse(editor.interactions.env.polylineDraft.isActive)
        // The next tap starts a new polyline instead of extending the removed one.
        editor.debugPerform(.taps(.polyline, points: [CGPoint(x: 300, y: 300), CGPoint(x: 600, y: 300)]))
        XCTAssertEqual(try line(editor.document.items.last).points, [CGPoint(x: 300, y: 300), CGPoint(x: 600, y: 300)])
    }

    @MainActor
    func testOverlayOffersPointAndInsertHandles() throws {
        let editor = makeEditor()
        let points = [CGPoint(x: 100, y: 300), CGPoint(x: 500, y: 300), CGPoint(x: 900, y: 300)]
        let polyline = MarkupItem.polyline(points: points, style: ItemStyle())
        editor.store.perform("Add", select: [polyline.id]) { $0.items.append(polyline) }
        editor.refreshOverlay()
        let overlay = editor.overlayView
        func screen(_ p: CGPoint) -> CGPoint { editor.canvasView.point(fromCanvas: p, to: overlay) }

        XCTAssertEqual(overlay.handle(at: screen(points[1])), .lineVertex(1))
        XCTAssertEqual(overlay.handle(at: screen(CGPoint(x: 300, y: 300))), .lineInsert(0))
        // "+" handles grab less than point handles, so the line around them can still be dragged.
        let beside = screen(CGPoint(x: 300, y: 300)) + CGPoint(x: SelectionOverlayView.insertTouchRadius + 2, y: 0)
        XCTAssertNil(overlay.handle(at: beside))

        // Straight arrows keep just their two end handles.
        let arrow = MarkupItem.line(from: CGPoint(x: 100, y: 600), to: CGPoint(x: 900, y: 600), style: ItemStyle())
        editor.store.perform("Add", select: [arrow.id]) { $0.items.append(arrow) }
        editor.refreshOverlay()
        XCTAssertEqual(overlay.handles.map(\.kind), [.lineVertex(0), .lineVertex(1)])
    }

    @MainActor
    func testCurveIsDrawnStraightThenBent() throws {
        let editor = makeEditor()
        editor.debugPerform(.draw(.curve, points: [CGPoint(x: 100, y: 400), CGPoint(x: 500, y: 400), CGPoint(x: 900, y: 400)]))
        let index = editor.document.items.count - 1
        var content = try line(editor.document.items.last)
        XCTAssertEqual(content.kind, .curve)
        XCTAssertEqual(content.waypoints, [CGPoint(x: 500, y: 400)], "one bend point in the middle")
        XCTAssertEqual(editor.tool, .select)

        editor.debugPerform(.dragLineVertex(itemIndex: index, vertex: 1, by: CGPoint(x: 0, y: -200)))
        content = try line(editor.document.items.last)
        XCTAssertEqual(content.waypoints, [CGPoint(x: 500, y: 200)])

        editor.debugPerform(.insertLineVertex(itemIndex: index, segment: 1, by: CGPoint(x: 0, y: 250)))
        content = try line(editor.document.items.last)
        XCTAssertEqual(content.waypoints.count, 2, "a second bend point for an S-curve")
        XCTAssertEqual(content.waypoints[0], CGPoint(x: 500, y: 200))
        XCTAssertGreaterThan(content.waypoints[1].y, 400)
    }
}
