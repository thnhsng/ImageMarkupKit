import UIKit

enum PanelKind {
    case shapeStyle, borderColor, fillColor, textStyle
}

enum AddImageSource {
    case photoLibrary, camera
}

/// The markup toolbar, modelled on macOS Preview: tools, board actions, then style controls.
/// - Top placement (regular width, iPad): one row under the navigation bar, style controls on the right.
/// - Bottom placement (compact width, iPhone): two rows so every control is visible — tools, then styles and
///   board actions. Either layout scrolls horizontally if the screen is too narrow.
final class MarkupToolbar: UIView {
    enum Placement { case top, bottom }

    static let rowHeight: CGFloat = 50

    var onToolSelected: ((MarkupTool) -> Void)?
    var onPanelRequested: ((PanelKind, UIView) -> Void)?
    var onAddImages: ((AddImageSource) -> Void)?
    var onArrange: ((BoardLayout.Arrangement) -> Void)?
    var onZoomToFit: (() -> Void)?

    var placement: Placement = .top {
        didSet { if placement != oldValue { applyLayout() } }
    }

    /// Holds the buttons; the editor pins it inside the safe area.
    let contentView = UIView()
    private let scrollView = UIScrollView()
    private let mainStack = UIStackView()
    private let separator = UIView()
    private var separatorTop: NSLayoutConstraint!
    private var separatorBottom: NSLayoutConstraint!
    private var separatorHeight: NSLayoutConstraint!
    private var contentHeight: NSLayoutConstraint!
    private var buttons: [ToolbarCatalog.Item: UIButton] = [:]
    private var toolViews: [UIView] = []
    private var boardViews: [UIView] = []
    private var styleViews: [UIView] = []
    private let spacer = UIView()
    private let isBoard: Bool
    private let cameraAvailable: Bool
    private let features: MarkupFeatures
    private let strings: Strings
    /// Entries of the Shapes and Arrow menus that the configuration allows.
    private let shapeEntries: [(kind: ShapeKind, lockAspect: Bool)]
    private let lineTools: [MarkupTool]
    private var currentTool: MarkupTool = .select
    private var lastShape: (kind: ShapeKind, lockAspect: Bool)
    private var lastLineTool: MarkupTool

    init(isBoard: Bool, cameraAvailable: Bool, features: MarkupFeatures = .all, strings: Strings = .english) {
        self.isBoard = isBoard
        self.cameraAvailable = cameraAvailable
        self.features = features
        self.strings = strings
        shapeEntries = ToolbarCatalog.shapes.filter { features.isEnabled(MarkupFeature(shape: $0.kind, lockAspect: $0.lockAspect)) }
        lineTools = ToolbarCatalog.lineTools.filter(features.allows)
        lastShape = shapeEntries.first ?? (.rectangle, false)
        lastLineTool = lineTools.first ?? .arrow
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        accessibilityIdentifier = "markup.toolbar"

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        mainStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(mainStack)

        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 12).isActive = true

        separatorTop = separator.topAnchor.constraint(equalTo: topAnchor)
        separatorBottom = separator.bottomAnchor.constraint(equalTo: bottomAnchor)
        contentHeight = contentView.heightAnchor.constraint(equalToConstant: Self.rowHeight)
        separatorHeight = separator.heightAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([
            contentHeight,
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            mainStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            mainStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            // Fill the width when everything fits (style group on the right, or rows centered).
            mainStack.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor, constant: -16),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorHeight,
        ])
        buildItems()
        applyLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // One physical pixel on the screen this toolbar is on.
        separatorHeight.constant = 1 / max(traitCollection.displayScale, 1)
    }

    // MARK: Layout

    private func applyLayout() {
        // The hairline sits on the edge facing the canvas. Deactivate before activating: having both pinned for a
        // moment conflicts with the 1-pixel height.
        let (active, inactive) = placement == .bottom ? (separatorTop, separatorBottom) : (separatorBottom, separatorTop)
        inactive?.isActive = false
        active?.isActive = true
        mainStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch placement {
        case .top:
            contentHeight.constant = Self.rowHeight
            mainStack.axis = .horizontal
            mainStack.alignment = .center
            mainStack.distribution = .fill
            mainStack.spacing = 2
            var views = toolViews
            if !boardViews.isEmpty { views += [makeDivider()] + boardViews }
            views += [spacer] + styleViews
            views.forEach { mainStack.addArrangedSubview($0) }
        case .bottom:
            var second = styleViews
            if !boardViews.isEmpty { second += (second.isEmpty ? [] : [makeDivider()]) + boardViews }
            // One row when the configuration leaves no style buttons or board actions.
            contentHeight.constant = Self.rowHeight * (second.isEmpty ? 1 : 2)
            mainStack.axis = .vertical
            mainStack.alignment = .center
            mainStack.spacing = 0
            mainStack.distribution = .fillEqually
            mainStack.addArrangedSubview(makeRow(toolViews))
            if !second.isEmpty { mainStack.addArrangedSubview(makeRow(second)) }
        }
    }

    private func makeRow(_ views: [UIView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 2
        return row
    }

    // MARK: Items

    /// Only what `features` allows. A menu left with a single entry becomes a plain button for it.
    private func buildItems() {
        toolViews.append(makeToolButton(.select, tool: .select))
        if features.isEnabled(.pen) { toolViews.append(makeToolButton(.sketch, tool: .pen)) }
        if features.isEnabled(.highlighter) { toolViews.append(makeToolButton(.highlight, tool: .highlighter)) }
        if let only = shapeEntries.first, shapeEntries.count == 1 {
            toolViews.append(makeToolButton(.shapes, tool: .shape(only.kind, lockAspect: only.lockAspect)))
        } else if !shapeEntries.isEmpty {
            let shapes = makeButton(.shapes)
            shapes.showsMenuAsPrimaryAction = true
            shapes.menu = shapesMenu()
            toolViews.append(shapes)
        }
        if let only = lineTools.first, lineTools.count == 1 {
            toolViews.append(makeToolButton(.arrow, tool: only))
        } else if !lineTools.isEmpty {
            let lines = makeButton(.arrow)
            lines.showsMenuAsPrimaryAction = true
            lines.menu = linesMenu()
            toolViews.append(lines)
        }
        if features.isEnabled(.text) { toolViews.append(makeToolButton(.text, tool: .text)) }
        if features.isEnabled(.note) { toolViews.append(makeToolButton(.note, tool: .note)) }
        if features.isEnabled(.eraser) { toolViews.append(makeToolButton(.eraser, tool: .eraser)) }

        if isBoard {
            var sources: [AddImageSource] = []
            if features.isEnabled(.photoLibrary) { sources.append(.photoLibrary) }
            if features.isEnabled(.camera) && cameraAvailable { sources.append(.camera) }
            if let only = sources.first, sources.count == 1 {
                let add = makeButton(.addImages)
                add.addAction(UIAction { [weak self] _ in self?.onAddImages?(only) }, for: .primaryActionTriggered)
                boardViews.append(add)
            } else if !sources.isEmpty {
                let add = makeButton(.addImages)
                add.showsMenuAsPrimaryAction = true
                add.menu = addImagesMenu(sources)
                boardViews.append(add)
            }
            if features.isEnabled(.arrange) {
                let arrange = makeButton(.arrange)
                arrange.showsMenuAsPrimaryAction = true
                arrange.menu = arrangeMenu()
                boardViews.append(arrange)
            }
        }

        let styleButtons: [(ToolbarCatalog.Item, PanelKind, MarkupFeature)] = [
            (.shapeStyle, .shapeStyle, .shapeStyle), (.borderColor, .borderColor, .borderColor),
            (.fillColor, .fillColor, .fillColor), (.textStyle, .textStyle, .textStyle),
        ]
        for (item, panel, feature) in styleButtons where features.isEnabled(feature) {
            let button = makeButton(item)
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button else { return }
                self.onPanelRequested?(panel, button)
            }, for: .primaryActionTriggered)
            styleViews.append(button)
        }
    }

    private func makeToolButton(_ item: ToolbarCatalog.Item, tool: MarkupTool) -> UIButton {
        let button = makeButton(item)
        button.addAction(UIAction { [weak self] _ in self?.onToolSelected?(tool) }, for: .primaryActionTriggered)
        return button
    }

    private func makeButton(_ item: ToolbarCatalog.Item) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = ToolbarCatalog.image(for: item)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseForegroundColor = .label
        let button = UIButton(configuration: configuration)
        button.configurationUpdateHandler = { button in
            guard var configuration = button.configuration else { return }
            configuration.background.backgroundColor = button.isSelected ? UIColor.tintColor.withAlphaComponent(0.18) : .clear
            configuration.background.cornerRadius = 8
            configuration.baseForegroundColor = button.isSelected ? .tintColor : (button.isEnabled ? .label : .tertiaryLabel)
            button.configuration = configuration
        }
        button.accessibilityLabel = ToolbarCatalog.title(for: item, strings: strings)
        button.accessibilityIdentifier = "toolbar.\(item)"
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
        buttons[item] = button
        return button
    }

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 24),
        ])
        return divider
    }

    private func shapesMenu() -> UIMenu {
        let actions = shapeEntries.map { entry -> UIAction in
            let isCurrent: Bool
            if case .shape(let kind, let lock) = currentTool { isCurrent = kind == entry.kind && lock == entry.lockAspect } else { isCurrent = false }
            return UIAction(
                title: strings.shapeName(entry.kind, lockAspect: entry.lockAspect),
                image: ToolbarCatalog.shapeImage(entry.kind, lockAspect: entry.lockAspect),
                state: isCurrent ? .on : .off
            ) { [weak self] _ in
                self?.lastShape = entry
                self?.onToolSelected?(.shape(entry.kind, lockAspect: entry.lockAspect))
            }
        }
        return UIMenu(title: strings.toolShapes, options: .singleSelection, children: actions)
    }

    /// Arrow / line, polyline and curve share one button, like the shapes.
    private func linesMenu() -> UIMenu {
        let actions = lineTools.map { tool in
            UIAction(
                title: ToolbarCatalog.lineToolTitle(tool, strings: strings),
                image: ToolbarCatalog.lineToolImage(tool),
                state: currentTool == tool ? .on : .off
            ) { [weak self] _ in
                self?.lastLineTool = tool
                self?.onToolSelected?(tool)
            }
        }
        return UIMenu(title: strings.toolLines, options: .singleSelection, children: actions)
    }

    private func addImagesMenu(_ sources: [AddImageSource]) -> UIMenu {
        let actions = sources.map { source in
            switch source {
            case .photoLibrary:
                return UIAction(title: strings.photoLibrary, image: SymbolCatalog.sf("photo.on.rectangle.angled", "photo")) { [weak self] _ in
                    self?.onAddImages?(.photoLibrary)
                }
            case .camera:
                return UIAction(title: strings.camera, image: SymbolCatalog.sf("camera")) { [weak self] _ in
                    self?.onAddImages?(.camera)
                }
            }
        }
        return UIMenu(title: strings.addImages, children: actions)
    }

    private func arrangeMenu() -> UIMenu {
        let arrangements = BoardLayout.Arrangement.allCases.map { arrangement in
            UIAction(title: ToolbarCatalog.arrangementTitle(arrangement, strings: strings), image: ToolbarCatalog.arrangementImage(arrangement)) { [weak self] _ in
                self?.onArrange?(arrangement)
            }
        }
        let zoom = UIAction(title: strings.zoomToFit, image: SymbolCatalog.sf("arrow.up.left.and.arrow.down.right")) { [weak self] _ in
            self?.onZoomToFit?()
        }
        return UIMenu(title: strings.arrange, children: [UIMenu(options: .displayInline, children: arrangements), zoom])
    }

    // MARK: State

    struct State: Equatable {
        var tool: MarkupTool
        var strokeColor: RGBAColor?
        var fillColor: RGBAColor?
        var strokeEnabled: Bool
        var fillEnabled: Bool
        var textEnabled: Bool
    }

    func update(_ state: State) {
        currentTool = state.tool
        let selectedItem: ToolbarCatalog.Item
        switch state.tool {
        case .select: selectedItem = .select
        case .pen: selectedItem = .sketch
        case .highlighter: selectedItem = .highlight
        case .shape(let kind, let lock):
            selectedItem = .shapes
            lastShape = (kind, lock)
        case .arrow, .polyline, .curve:
            selectedItem = .arrow
            lastLineTool = state.tool
        case .text: selectedItem = .text
        case .note: selectedItem = .note
        case .eraser: selectedItem = .eraser
        }
        for item in [ToolbarCatalog.Item.select, .sketch, .highlight, .shapes, .arrow, .text, .note, .eraser] {
            buttons[item]?.isSelected = item == selectedItem
        }
        if let shapes = buttons[.shapes] {
            shapes.configuration?.image = ToolbarCatalog.shapeImage(lastShape.kind, lockAspect: lastShape.lockAspect)
            if shapeEntries.count > 1 { shapes.menu = shapesMenu() }
        }
        if let lines = buttons[.arrow] {
            lines.configuration?.image = ToolbarCatalog.lineToolImage(lastLineTool)
            lines.accessibilityLabel = ToolbarCatalog.lineToolTitle(lastLineTool, strings: strings)
            if lineTools.count > 1 { lines.menu = linesMenu() }
        }
        buttons[.borderColor]?.configuration?.image = ToolbarCatalog.swatch(state.strokeColor, filled: false)
        buttons[.fillColor]?.configuration?.image = ToolbarCatalog.swatch(state.fillColor, filled: true)
        buttons[.borderColor]?.isEnabled = state.strokeEnabled
        buttons[.fillColor]?.isEnabled = state.fillEnabled
        buttons[.textStyle]?.isEnabled = state.textEnabled
    }

    func button(for item: ToolbarCatalog.Item) -> UIButton? { buttons[item] }
}
