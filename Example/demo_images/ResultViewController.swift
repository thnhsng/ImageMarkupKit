import ImageIO
import Photos
import UIKit
import ImageMarkupKit

/// Shows an exported image with its pixel size and byte count; saves, shares, or reopens it for editing.
/// In a host app this is where the JPEG (and optionally the package) would be attached to a record.
///
/// Only a 2048 px preview is decoded for display; saving and sharing use the JPEG bytes as they are.
final class ResultViewController: UIViewController, UIScrollViewDelegate {
    private let data: Data
    private let packageURL: URL?
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let infoLabel = UILabel()

    init(data: Data, packageURL: URL? = nil) {
        self.data = data
        self.packageURL = packageURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Exported image"
        view.backgroundColor = .systemGroupedBackground

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 8
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let source = CGImageSourceCreateWithData(data as CFData, nil)
        if let source {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
            ]
            imageView.image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        }
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        // A large image's intrinsic size must not squeeze the info label out.
        imageView.setContentCompressionResistancePriority(.defaultLow - 1, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        scrollView.addSubview(imageView)

        var pixels = ""
        if let source, let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
            pixels = "\(width)×\(height) px · "
        }
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        var info = "\(pixels)JPEG \(bytes)"
        if let packageURL { info += "\nEditable package: \(packageURL.lastPathComponent)" }
        infoLabel.text = info
        infoLabel.numberOfLines = 0
        infoLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        infoLabel.textAlignment = .center
        infoLabel.accessibilityIdentifier = "result.info"
        infoLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let buttons = UIStackView(arrangedSubviews: [
            makeButton("Save to Photos", symbol: "square.and.arrow.down") { [weak self] _ in self?.saveToPhotos() },
            makeButton("Share", symbol: "square.and.arrow.up") { [weak self] button in self?.share(from: button) },
        ])
        if packageURL != nil {
            buttons.addArrangedSubview(makeButton("Edit again", symbol: "pencil.tip.crop.circle") { [weak self] _ in self?.editAgain() })
        }
        buttons.axis = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 8

        let footer = UIStackView(arrangedSubviews: [infoLabel, buttons])
        footer.axis = .vertical
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),

            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            footer.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    // MARK: Actions

    private func makeButton(_ title: String, symbol: String, action: @escaping (UIButton) -> Void) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePlacement = .top
        configuration.imagePadding = 4
        configuration.buttonSize = .small
        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { [weak button] _ in if let button { action(button) } }, for: .primaryActionTriggered)
        return button
    }

    /// Adds the JPEG bytes as they are (no re-encode); asks for add-only access the first time.
    private func saveToPhotos() {
        let data = data
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.showAlert("Could not save", "Photo library access was denied.") }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }) { success, error in
                DispatchQueue.main.async {
                    self.showAlert(success ? "Saved to Photos" : "Could not save", error?.localizedDescription)
                }
            }
        }
    }

    private func showAlert(_ title: String, _ message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func share(from button: UIButton) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("markup-\(Int(Date().timeIntervalSince1970)).jpg")
        try? data.write(to: url)
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad presents the share sheet as a popover, which needs an anchor.
        activity.popoverPresentationController?.sourceView = button
        activity.popoverPresentationController?.sourceRect = button.bounds
        present(activity, animated: true)
    }

    private func editAgain() {
        guard let packageURL, let navigation = navigationController else { return }
        navigation.popViewController(animated: false)
        DemoFlows.shared.reopen(packageURL, from: navigation)
    }
}
