import UIKit

/// Floating capsule of actions for the selected item (custom view: `UIEditMenuInteraction` is iOS 16+).
final class SelectionActionBar: UIView {
    enum Action: CaseIterable {
        case editText, duplicate, bringToFront, sendToBack, lock, unlock, delete
        /// Polylines and curves: finish drawing, join / separate the ends, remove the tapped point.
        case finishPath, closePath, openPath, deletePoint

        var symbol: UIImage? {
            switch self {
            case .finishPath: return SymbolCatalog.sf("checkmark")
            case .closePath: return ToolbarCatalog.pathIcon(closed: true)
            case .openPath: return ToolbarCatalog.pathIcon(closed: false)
            case .deletePoint: return SymbolCatalog.sf("minus.circle")
            case .editText: return SymbolCatalog.sf("character.cursor.ibeam", "textbox")
            case .duplicate: return SymbolCatalog.sf("plus.square.on.square")
            case .bringToFront: return SymbolCatalog.sf("square.2.stack.3d.top.fill")
            case .sendToBack: return SymbolCatalog.sf("square.2.stack.3d.bottom.fill")
            case .lock: return SymbolCatalog.sf("lock")
            case .unlock: return SymbolCatalog.sf("lock.open")
            case .delete: return SymbolCatalog.sf("trash")
            }
        }

        var title: String {
            switch self {
            case .editText: return Strings.editText
            case .duplicate: return Strings.duplicate
            case .bringToFront: return Strings.bringToFront
            case .sendToBack: return Strings.sendToBack
            case .lock: return Strings.lock
            case .unlock: return Strings.unlock
            case .delete: return Strings.delete
            case .finishPath: return Strings.finishPath
            case .closePath: return Strings.closeShape
            case .openPath: return Strings.openShape
            case .deletePoint: return Strings.deletePoint
            }
        }
    }

    var onAction: ((Action) -> Void)?
    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let stack = UIStackView()
    private(set) var actions: [Action] = []
    private static let buttonSize: CGFloat = 40

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)

        background.clipsToBounds = true
        background.frame = bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(background)

        stack.axis = .horizontal
        stack.spacing = 2
        stack.frame = bounds
        stack.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        background.contentView.addSubview(stack)
        accessibilityIdentifier = "markup.actionBar"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(actions: [Action]) {
        guard actions != self.actions else { return }
        self.actions = actions
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Size the bar (and its stack) for the new buttons first, so the stack never holds more fixed-width
        // buttons than its current width fits (that logs "Unable to simultaneously satisfy constraints").
        let size = sizeThatFits(.zero)
        bounds = CGRect(origin: .zero, size: size)
        layer.cornerRadius = size.height / 2
        background.layer.cornerRadius = size.height / 2
        stack.frame = bounds.insetBy(dx: 6, dy: 2)
        for action in actions {
            let button = UIButton(type: .system)
            button.setImage(action.symbol, for: .normal)
            button.tintColor = action == .delete ? .systemRed : (action == .finishPath ? .tintColor : .label)
            button.accessibilityLabel = action.title
            button.addAction(UIAction { [weak self] _ in self?.onAction?(action) }, for: .primaryActionTriggered)
            let width = button.widthAnchor.constraint(equalToConstant: Self.buttonSize)
            width.priority = .required - 1
            width.isActive = true
            stack.addArrangedSubview(button)
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let count = CGFloat(actions.count)
        return CGSize(width: count * Self.buttonSize + max(count - 1, 0) * stack.spacing + 12, height: Self.buttonSize + 4)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stack.frame = bounds.insetBy(dx: 6, dy: 2)
    }
}
