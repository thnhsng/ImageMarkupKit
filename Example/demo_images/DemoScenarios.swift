#if DEBUG
import UIKit
import ImageMarkupKit

/// Launch-argument driven states for screenshots, e.g. `-demoScenario render`.
/// Each scenario writes `DEMO_READY <name>` to stderr once it has settled (stdout is block-buffered).
enum DemoScenarios {
    private static var hasRun = false

    static var requested: String? { UserDefaults.standard.string(forKey: "demoScenario") }

    static func runIfRequested(from launcher: UIViewController) {
        guard !hasRun, let name = requested, let navigation = launcher.navigationController else { return }
        hasRun = true
        switch name {
        case "render":
            let (document, catalog) = DemoContent.annotatedPhoto()
            showRendering(of: document, catalog: catalog, scenario: name, in: navigation)
        case "renderBoard":
            let (document, catalog) = DemoContent.annotatedBoard()
            showRendering(of: document, catalog: catalog, scenario: name, in: navigation)
        case "annotate":
            let (document, catalog) = DemoContent.annotatedPhoto()
            openEditor(document: document, catalog: catalog, scenario: name, in: navigation)
        case "board":
            let (document, catalog) = DemoContent.annotatedBoard()
            openEditor(document: document, catalog: catalog, scenario: name, in: navigation)
        case "importBoard":
            // The host-app path for picked files: URLs in, default side-by-side layout.
            DemoFlows.shared.onEditorShown = { _ in
                DemoFlows.shared.onEditorShown = nil
                settle(name, delay: 1.5)
            }
            do {
                let editor = try MarkupEditorViewController(imageURLs: SampleImages.urls(), configuration: MarkupEditorConfiguration(packageDirectory: DemoFlows.packageDirectory, features: DemoFlows.features))
                DemoFlows.shared.present(editor, from: navigation, animated: false)
            } catch {
                log("DEMO_ERROR \(error)")
            }
        case "export":
            // Opens the annotated board and taps Done: export + editable package, then the result screen.
            let (document, catalog) = DemoContent.annotatedBoard()
            DemoFlows.shared.onResultShown = { _ in
                DemoFlows.shared.onResultShown = nil
                if let url = DemoFlows.lastPackageURL {
                    log("DEMO_INFO package=\(url.path)")
                }
                settle(name, delay: 1.5)
            }
            DemoFlows.shared.onEditorShown = { editor in
                DemoFlows.shared.onEditorShown = nil
                applyEditorArguments(to: editor)
                editor.debugDone()
            }
            DemoFlows.shared.presentEditor(document: document, assets: catalog, from: navigation, animated: false)
        case "stress":
            // Ten 12 MP photos on one board: display decode caps + export pixel budget.
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Stress", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = SampleImages.urls()[0]
            let urls = (0..<10).map { index -> URL in
                let url = directory.appendingPathComponent("photo-\(index).jpg")
                if !FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.copyItem(at: source, to: url) }
                return url
            }
            log("DEMO_INFO memory launch=\(memoryReport())")
            DemoFlows.shared.onEditorShown = { editor in
                DemoFlows.shared.onEditorShown = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    log("DEMO_INFO memory editor=\(memoryReport())")
                    DemoFlows.shared.onResultShown = { _ in
                        DemoFlows.shared.onResultShown = nil
                        // Measure once the export task has finished and released the full-size image.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            log("DEMO_INFO memory afterExport=\(memoryReport())")
                            settle(name, delay: 0.5)
                        }
                    }
                    editor.debugDone()
                }
            }
            do {
                let editor = try MarkupEditorViewController(imageURLs: urls, configuration: MarkupEditorConfiguration(packageDirectory: DemoFlows.packageDirectory, features: DemoFlows.features))
                DemoFlows.shared.present(editor, from: navigation, animated: false)
            } catch {
                log("DEMO_ERROR \(error)")
            }
        case "roundtrip":
            guard let url = DemoFlows.lastPackageURL else {
                log("DEMO_ERROR no saved package")
                return
            }
            DemoFlows.shared.onEditorShown = { _ in
                DemoFlows.shared.onEditorShown = nil
                settle(name, delay: 1.5)
            }
            DemoFlows.shared.reopen(url, from: navigation, animated: false)
        default:
            log("DEMO_ERROR unknown scenario \(name)")
        }
    }

    private static func showRendering(of document: MarkupDocument, catalog: AssetCatalog, scenario: String, in navigation: UINavigationController) {
        Task {
            let rendering = await MarkupRenderer.render(document, assets: catalog)
            navigation.pushViewController(ResultViewController(data: rendering.data), animated: false)
            log("DEMO_INFO \(scenario) pixelSize=\(Int(rendering.pixelSize.width))x\(Int(rendering.pixelSize.height)) bytes=\(rendering.data.count)")
            settle(scenario)
        }
    }

    private static func openEditor(document: MarkupDocument, catalog: AssetCatalog, scenario: String, in navigation: UINavigationController) {
        DemoFlows.shared.onEditorShown = { editor in
            DemoFlows.shared.onEditorShown = nil
            applyEditorArguments(to: editor)
            settle(scenario, delay: 1.2)
        }
        DemoFlows.shared.presentEditor(document: document, assets: catalog, from: navigation, animated: false)
    }

    /// Applies `-demoSelect <index>`, `-demoMutate <name>`, `-demoTool <name>`, `-demoEditText <index>`
    /// and `-demoPanel <name>` to a freshly opened editor.
    private static func applyEditorArguments(to editor: MarkupEditorViewController) {
        let arguments = UserDefaults.standard
        if let mutation = arguments.string(forKey: "demoMutate") {
            mutate(editor, mutation)
        }
        if let tool = arguments.string(forKey: "demoTool") {
            demonstrate(tool, in: editor)
        }
        if arguments.object(forKey: "demoSelect") != nil {
            let index = arguments.integer(forKey: "demoSelect")
            if editor.document.items.indices.contains(index) {
                editor.selectedItemIDs = [editor.document.items[index].id]
            }
        }
        if arguments.object(forKey: "demoEditText") != nil {
            editor.debugBeginEditingText(itemIndex: arguments.integer(forKey: "demoEditText"))
        }
        if let panel = arguments.string(forKey: "demoPanel") {
            editor.debugPresentPanel(panel)
        }
    }

    /// Board scenarios: items 0, 1, 2 are photos A, B, C.
    private static func mutate(_ editor: MarkupEditorViewController, _ mutation: String) {
        switch mutation {
        case "move": editor.debugPerform(.drag(itemIndex: 1, by: CGPoint(x: 150, y: 520)))
        case "rotate": editor.debugPerform(.rotate(itemIndex: 0, degrees: 20))
        case "resize": editor.debugPerform(.resize(itemIndex: 2, u: 1, v: 1, by: CGPoint(x: -700, y: -260)))
        case "arrange": editor.debugArrange(.column)
        default:
            log("DEMO_ERROR unknown mutation \(mutation)")
            return
        }
        editor.selectedItemIDs = []
        editor.debugZoomToFit()
        log("DEMO_INFO mutate \(mutation) items=\(editor.document.items.count)")
    }

    /// Uses one tool on the annotated photo (canvas 1024 × 768).
    private static func demonstrate(_ tool: String, in editor: MarkupEditorViewController) {
        switch tool {
        case "pen":
            let loop = (0...40).map { i -> CGPoint in
                let t = CGFloat(i) / 40 * 2 * .pi
                return CGPoint(x: 820 + cos(t) * 90, y: 600 + sin(t) * 60)
            }
            editor.debugPerform(.draw(.pen, points: loop))
        case "highlighter":
            editor.debugPerform(.draw(.highlighter, points: [CGPoint(x: 420, y: 430), CGPoint(x: 700, y: 440)]))
        case "shape":
            editor.debugPerform(.draw(.shape(.star, lockAspect: false), points: [CGPoint(x: 560, y: 470), CGPoint(x: 700, y: 610)]))
        case "arrow":
            // Ends on the red rectangle, so the arrow attaches to it.
            editor.debugPerform(.draw(.arrow, points: [CGPoint(x: 80, y: 720), CGPoint(x: 150, y: 400), CGPoint(x: 260, y: 170)]))
        case "boardArrow":
            // From photo A to photo C.
            editor.debugPerform(.draw(.arrow, points: [CGPoint(x: 600, y: 480), CGPoint(x: 1400, y: 520), CGPoint(x: 2300, y: 500)]))
        case "polyline":
            // Four points, then a tap on the last one finishes.
            let points = [CGPoint(x: 380, y: 640), CGPoint(x: 520, y: 470), CGPoint(x: 680, y: 610), CGPoint(x: 900, y: 420)]
            editor.debugPerform(.taps(.polyline, points: points + [points[3]]))
        case "polylineDrawing":
            // Still drawing: the action bar offers Finish and Close Shape, and there are no "+" handles yet.
            editor.debugPerform(.taps(.polyline, points: [CGPoint(x: 380, y: 640), CGPoint(x: 520, y: 470), CGPoint(x: 680, y: 610)]))
        case "polygon":
            // A tap on the first point closes the shape; then give it a translucent fill.
            let points = [CGPoint(x: 560, y: 420), CGPoint(x: 820, y: 460), CGPoint(x: 860, y: 660), CGPoint(x: 600, y: 700)]
            editor.debugPerform(.taps(.polyline, points: points + [points[0]]))
            editor.debugSetFill(RGBAColor.yellow.withAlpha(0.35))
        case "curve":
            // Drawn straight, bent at its middle point, then a second bend point makes an S.
            editor.debugPerform(.draw(.curve, points: [CGPoint(x: 380, y: 560), CGPoint(x: 640, y: 560), CGPoint(x: 900, y: 560)]))
            let index = editor.document.items.count - 1
            editor.debugPerform(.dragLineVertex(itemIndex: index, vertex: 1, by: CGPoint(x: -60, y: -150)))
            editor.debugPerform(.insertLineVertex(itemIndex: index, segment: 1, by: CGPoint(x: 0, y: 140)))
        case "text":
            editor.debugPerform(.draw(.text, points: [CGPoint(x: 520, y: 260)]))
            editor.debugTypeText("Bolt loose / ボルト緩み")
        case "eraser":
            editor.debugPerform(.draw(.eraser, points: [CGPoint(x: 150, y: 470), CGPoint(x: 150, y: 570)]))
        default:
            log("DEMO_ERROR unknown tool \(tool)")
        }
    }

    /// Reports readiness after the next layout pass has had time to reach the screen.
    static func settle(_ scenario: String, delay: TimeInterval = 0.8) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            log("DEMO_READY \(scenario)")
        }
    }

    /// Current and peak physical footprint (what jetsam counts), in MB.
    static func memoryReport() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "n/a" }
        let current = Double(info.phys_footprint) / 1_048_576
        let peak = Double(info.ledger_phys_footprint_peak) / 1_048_576
        return String(format: "%.0fMB(peak %.0fMB)", current, peak)
    }

    /// Unbuffered stderr write. `FileHandle.write(_:)` raises an Objective-C exception (and crashes) when the write
    /// fails, e.g. on a full disk; `fputs` just returns an error.
    static func log(_ message: String) {
        fputs(message + "\n", stderr)
    }
}
#endif
