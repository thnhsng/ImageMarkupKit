import UIKit

/// Presents style panels as popovers anchored to their toolbar button. In compact width UIKit adapts the popover
/// to a sheet, configured here (iOS 15: medium/large detents, canvas left interactive at medium).
@MainActor
final class PanelPresenter: NSObject, UIPopoverPresentationControllerDelegate {
    private unowned let editor: MarkupEditorViewController
    private weak var current: PanelViewController?

    init(editor: MarkupEditorViewController) {
        self.editor = editor
    }

    func present(_ kind: PanelKind, from source: UIView) {
        if let current, current.kind == kind {
            current.dismiss(animated: true)
            return
        }
        dismiss()
        editor.finishTextEditing()
        let panel: PanelViewController
        switch kind {
        case .shapeStyle: panel = ShapeStylePanel(editor: editor, kind: kind)
        case .borderColor: panel = ColorPanel(editor: editor, kind: kind)
        case .fillColor: panel = ColorPanel(editor: editor, kind: kind)
        case .textStyle: panel = TextStylePanel(editor: editor, kind: kind)
        }
        panel.modalPresentationStyle = .popover
        if let popover = panel.popoverPresentationController {
            // `sourceItem` is iOS 16+; a view and rect work on iOS 15.
            popover.sourceView = source
            popover.sourceRect = source.bounds
            popover.permittedArrowDirections = [.up, .down]
            popover.delegate = self
            let sheet = popover.adaptiveSheetPresentationController
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.largestUndimmedDetentIdentifier = .medium
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        current = panel
        editor.present(panel, animated: true)
    }

    func refresh() {
        current?.reload()
    }

    func dismiss() {
        guard let current, current.presentingViewController != nil else { return }
        current.dismiss(animated: true)
    }

    var presentedPanel: PanelViewController? { current }
}

/// Base class for style panels: a scrolling vertical stack of labelled rows.
class PanelViewController: UIViewController {
    unowned let editor: MarkupEditorViewController
    let kind: PanelKind
    let stack = UIStackView()
    private let scrollView = UIScrollView()

    var store: EditorStore { editor.store }

    init(editor: MarkupEditorViewController, kind: PanelKind) {
        self.editor = editor
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -18),
        ])
        buildContent()
        reload()
    }

    /// Adds the panel's controls to `stack`.
    func buildContent() {}

    /// Refreshes controls from the current selection / tool defaults, then resizes the popover.
    func reload() {
        guard isViewLoaded else { return }
        reloadContent()
        updatePreferredContentSize()
    }

    /// Subclasses update their controls here.
    func reloadContent() {}

    /// Sized from the content, outside any layout pass: changing `preferredContentSize` while UIKit lays out the
    /// popover rebuilds its background views mid-traversal ("view.superview is nil during traversal").
    private func updatePreferredContentSize() {
        let width: CGFloat = 320
        let fitting = stack.systemLayoutSizeFitting(
            CGSize(width: width - 36, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let size = CGSize(width: width, height: min(ceil(fitting.height) + 36, 560))
        if abs(preferredContentSize.height - size.height) > 0.5 || preferredContentSize.width != size.width {
            preferredContentSize = size
        }
    }

    func addTitle(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        stack.addArrangedSubview(label)
    }

    func addRow(_ title: String, _ control: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .vertical
        row.spacing = 6
        stack.addArrangedSubview(row)
        return row
    }
}
