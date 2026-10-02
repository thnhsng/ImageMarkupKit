import PhotosUI
import UIKit
import ImageMarkupKit

/// Presents the markup editor for the demo's flows and shows the exported result.
final class DemoFlows: NSObject, MarkupEditorDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    static let shared = DemoFlows()

    private weak var navigation: UINavigationController?
    private var pickingBoard = false
    var onEditorShown: ((MarkupEditorViewController) -> Void)?
    var onResultShown: ((ResultViewController) -> Void)?

    /// Where editable packages are saved (Application Support/Markups).
    static var packageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Markups", isDirectory: true)
    }

    static var lastPackageURL: URL? {
        MarkupPackage.packages(in: packageDirectory).first
    }

    private var configuration: MarkupEditorConfiguration {
        MarkupEditorConfiguration(packageDirectory: Self.packageDirectory, features: Self.features)
    }

    /// Tools to offer, from `MarkupFeatures.json` in the app bundle (debug builds: `-demoFeatures <file>` picks
    /// another JSON resource, e.g. `MarkupFeatures-inspection`).
    static var features: MarkupFeatures {
        var resource = "MarkupFeatures"
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "demoFeatures") { resource = override }
        #endif
        do {
            return try MarkupFeatures.fromBundle(resource: resource)
        } catch {
            // A typo in the file: fail loudly while developing, fall back to every tool in release builds.
            assertionFailure("\(resource).json: \(error)")
            return .all
        }
    }

    // MARK: Opening the editor

    func presentEditor(document: MarkupDocument, assets: AssetCatalog, from navigation: UINavigationController, animated: Bool = true) {
        present(MarkupEditorViewController(document: document, assets: assets, configuration: configuration), from: navigation, animated: animated)
    }

    func present(_ editor: MarkupEditorViewController, from navigation: UINavigationController, animated: Bool = true) {
        self.navigation = navigation
        editor.delegate = self
        navigation.present(editor.embeddedInNavigationController(), animated: animated) { [weak self] in
            self?.onEditorShown?(editor)
        }
    }

    /// Photo library: one photo to annotate, or several for a board (in pick order).
    func pickPhotos(forBoard board: Bool, from navigation: UINavigationController) {
        self.navigation = navigation
        pickingBoard = board
        let picker = PHPickerViewController(configuration: MarkupImageImport.pickerConfiguration(selectionLimit: board ? 0 : 1))
        picker.delegate = self
        navigation.present(picker, animated: true)
    }

    func takePhoto(from navigation: UINavigationController) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        self.navigation = navigation
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        navigation.present(picker, animated: true)
    }

    func reopen(_ packageURL: URL, from navigation: UINavigationController, animated: Bool = true) {
        do {
            present(try MarkupEditorViewController(packageURL: packageURL, configuration: configuration), from: navigation, animated: animated)
        } catch {
            showError(error, on: navigation)
        }
    }

    // MARK: PHPickerViewControllerDelegate

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty, let navigation else { return }
        // Picker files are temporary: copy them before opening the editor (which only reads them).
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Picked/\(UUID().uuidString)", isDirectory: true)
        let board = pickingBoard
        Task {
            let urls = await MarkupImageImport.copyPickerResults(results, to: directory)
            guard !urls.isEmpty else { return }
            do {
                let editor = board
                    ? try MarkupEditorViewController(imageURLs: urls, configuration: configuration)
                    : try MarkupEditorViewController(imageURL: urls[0], configuration: configuration)
                present(editor, from: navigation)
            } catch {
                showError(error, on: navigation)
            }
        }
    }

    // MARK: UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage, let navigation else { return }
        do {
            present(try MarkupEditorViewController(image: image, configuration: configuration), from: navigation)
        } catch {
            showError(error, on: navigation)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    // MARK: MarkupEditorDelegate

    func markupEditor(_ editor: MarkupEditorViewController, didFinishWith result: MarkupResult) {
        editor.dismiss(animated: true)
        let resultController = ResultViewController(data: result.imageData, packageURL: result.packageURL)
        navigation?.pushViewController(resultController, animated: true)
        onResultShown?(resultController)
    }

    func markupEditorDidCancel(_ editor: MarkupEditorViewController) {
        editor.dismiss(animated: true)
    }

    func markupEditor(_ editor: MarkupEditorViewController, didFailWith error: Error) {
        showError(error, on: editor)
    }

    private func showError(_ error: Error, on presenter: UIViewController) {
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }
}
