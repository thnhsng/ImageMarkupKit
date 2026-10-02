//
//  ViewController.swift
//  demo_images
//
//  Created by thnhsng on 25/9/26.
//

import UIKit
import ImageMarkupKit

/// Demo launcher. The class name must stay `ViewController`: Main.storyboard binds to it.
class ViewController: UIViewController {

    private let stack = UIStackView()
    private let versionLabel = UILabel()
    private weak var reopenButton: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Markup Demo"
        view.backgroundColor = .systemGroupedBackground

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        // Full margin width on iPhone, capped at 480 pt and centered on iPad.
        let preferredWidth = stack.widthAnchor.constraint(equalTo: view.layoutMarginsGuide.widthAnchor)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.layoutMarginsGuide.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            preferredWidth,
        ])

        addSection("Photos")
        addButton("Annotate a photo…", symbol: "pencil.tip.crop.circle") { [weak self] in self?.pickPhotos(board: false) }
        addButton("New board from photos…", symbol: "rectangle.3.offgrid") { [weak self] in self?.pickPhotos(board: true) }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            addButton("Take a photo", symbol: "camera") { [weak self] in self?.takePhoto() }
        }

        addSection("Saved")
        reopenButton = addButton("Reopen last saved", symbol: "clock.arrow.circlepath") { [weak self] in self?.reopenLast() }

        addSection("Samples")
        addButton("Sample: annotated photo", symbol: "photo") { [weak self] in self?.openSamplePhoto() }
        addButton("Sample: board with 3 photos", symbol: "square.grid.2x2") { [weak self] in self?.openSampleBoard() }

        versionLabel.text = "ImageMarkupKit \(ImageMarkupKit.version) linked"
        versionLabel.font = .preferredFont(forTextStyle: .footnote)
        versionLabel.textColor = .secondaryLabel
        versionLabel.textAlignment = .center
        stack.setCustomSpacing(24, after: stack.arrangedSubviews.last ?? versionLabel)
        stack.addArrangedSubview(versionLabel)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reopenButton?.isEnabled = DemoFlows.lastPackageURL != nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        DemoScenarios.runIfRequested(from: self)
        #endif
    }

    // MARK: Flows

    private func pickPhotos(board: Bool) {
        guard let navigationController else { return }
        DemoFlows.shared.pickPhotos(forBoard: board, from: navigationController)
    }

    private func takePhoto() {
        guard let navigationController else { return }
        DemoFlows.shared.takePhoto(from: navigationController)
    }

    private func reopenLast() {
        guard let navigationController, let url = DemoFlows.lastPackageURL else { return }
        DemoFlows.shared.reopen(url, from: navigationController)
    }

    private func openSamplePhoto() {
        guard let navigationController else { return }
        let (document, assets) = DemoContent.annotatedPhoto()
        DemoFlows.shared.presentEditor(document: document, assets: assets, from: navigationController)
    }

    private func openSampleBoard() {
        guard let navigationController else { return }
        let (document, assets) = DemoContent.annotatedBoard()
        DemoFlows.shared.presentEditor(document: document, assets: assets, from: navigationController)
    }

    // MARK: Layout helpers

    private func addSection(_ title: String) {
        let label = UILabel()
        label.text = title.uppercased()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        if !stack.arrangedSubviews.isEmpty, let last = stack.arrangedSubviews.last {
            stack.setCustomSpacing(24, after: last)
        }
        stack.addArrangedSubview(label)
    }

    @discardableResult
    private func addButton(_ title: String, symbol: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 10
        configuration.cornerStyle = .large
        configuration.buttonSize = .large
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.contentHorizontalAlignment = .leading
        stack.addArrangedSubview(button)
        return button
    }
}
