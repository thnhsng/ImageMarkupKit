import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Imports photos from the picker. Public so host apps can reuse it before opening the editor.
public enum MarkupImageImport {
    /// Picker configuration for boards: any number of photos, in the order they were picked, originals kept
    /// (HEIC stays HEIC). PHPicker needs no photo-library permission.
    public static func pickerConfiguration(selectionLimit: Int = 0) -> PHPickerConfiguration {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        return configuration
    }

    /// Copies the picked photos into `directory`, preserving pick order; at most three imports run at once.
    /// Unreadable items are skipped.
    public static func copyPickerResults(_ results: [PHPickerResult], to directory: URL) async -> [URL] {
        await importResults(results, into: directory).map(\.url)
    }

    static func importResults(_ results: [PHPickerResult], into directory: URL) async -> [ImportedAsset] {
        let providers = results.map(\.itemProvider)
        var imported = [ImportedAsset?](repeating: nil, count: providers.count)
        await withTaskGroup(of: (Int, ImportedAsset?).self) { group in
            var next = 0
            func startNext() {
                guard next < providers.count else { return }
                let index = next
                let provider = providers[index]
                next += 1
                group.addTask { (index, await importOne(provider, into: directory)) }
            }
            for _ in 0..<min(3, providers.count) { startNext() }
            while let (index, asset) = await group.next() {
                imported[index] = asset
                startNext()
            }
        }
        return imported.compactMap { $0 }
    }

    private static func importOne(_ provider: NSItemProvider, into directory: URL) async -> ImportedAsset? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                // The file is deleted when this closure returns: copy it now, on this background queue.
                let asset = url.flatMap { try? AssetStore.copyIntoSession($0, directory: directory) }
                continuation.resume(returning: asset)
            }
        }
    }
}

/// Adds photos to an open board from the photo library or the camera.
@MainActor
final class ImagePicking: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private unowned let editor: MarkupEditorViewController

    init(editor: MarkupEditorViewController) {
        self.editor = editor
    }

    func pick(from source: AddImageSource) {
        editor.finishTextEditing()
        editor.panels.dismiss()
        switch source {
        case .photoLibrary:
            let picker = PHPickerViewController(configuration: MarkupImageImport.pickerConfiguration())
            picker.delegate = self
            editor.present(picker, animated: true)
        case .camera:
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = self
            editor.present(picker, animated: true)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        let directory = editor.store.assets.sessionDirectory
        Task { [weak self] in
            let imported = await MarkupImageImport.importResults(results, into: directory)
            self?.add(imported)
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage, let source = try? editor.store.assets.importImage(image) else { return }
        editor.store.addImages([source])
        editor.canvasView.zoomToFit(animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func add(_ imported: [ImportedAsset]) {
        guard !imported.isEmpty else { return }
        let sources = imported.map { editor.store.assets.add($0) }
        editor.store.addImages(sources)
        editor.canvasView.zoomToFit(animated: true)
    }
}
