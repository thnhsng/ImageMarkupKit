import UIKit

// MARK: - Shape Style

/// Line width, line style, arrowheads, opacity, corner radius and shadow (Preview's "Shape Style").
final class ShapeStylePanel: PanelViewController {
    private let widthSlider = UISlider()
    private let widthLabel = UILabel()
    private lazy var dashControl = UISegmentedControl(items: [editor.strings.solid, editor.strings.dashed, editor.strings.dotted])
    private let headsControl = UISegmentedControl(items: [
        SymbolCatalog.sf("line.diagonal", "minus") as Any,
        SymbolCatalog.sf("arrow.right") as Any,
        SymbolCatalog.sf("arrow.left") as Any,
        SymbolCatalog.sf("arrow.left.and.right") as Any,
    ])
    private let opacitySlider = UISlider()
    private let cornerSlider = UISlider()
    private let shadowSwitch = UISwitch()
    private var headsRow: UIView?
    private var cornerRow: UIView?

    override func buildContent() {
        addTitle(editor.strings.shapeStyle)

        widthSlider.minimumValue = 1
        widthSlider.maximumValue = 40
        widthSlider.addTarget(self, action: #selector(widthChanged), for: .valueChanged)
        widthSlider.addTarget(self, action: #selector(endCoalescing), for: [.touchUpInside, .touchUpOutside])
        widthSlider.accessibilityIdentifier = "panel.lineWidth"
        widthLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        widthLabel.setContentHuggingPriority(.required, for: .horizontal)
        let widthRow = UIStackView(arrangedSubviews: [widthSlider, widthLabel])
        widthRow.spacing = 12
        _ = addRow(editor.strings.lineWidth, widthRow)

        dashControl.addTarget(self, action: #selector(dashChanged), for: .valueChanged)
        _ = addRow(editor.strings.lineStyle, dashControl)

        headsControl.addTarget(self, action: #selector(headsChanged), for: .valueChanged)
        headsRow = addRow(editor.strings.arrowheads, headsControl)

        opacitySlider.minimumValue = 0.1
        opacitySlider.maximumValue = 1
        opacitySlider.minimumValueImage = SymbolCatalog.sf("circle.lefthalf.filled", "circle")
        opacitySlider.addTarget(self, action: #selector(opacityChanged), for: .valueChanged)
        opacitySlider.addTarget(self, action: #selector(endCoalescing), for: [.touchUpInside, .touchUpOutside])
        _ = addRow(editor.strings.opacity, opacitySlider)

        cornerSlider.minimumValue = 0
        cornerSlider.maximumValue = 60
        cornerSlider.addTarget(self, action: #selector(cornerChanged), for: .valueChanged)
        cornerSlider.addTarget(self, action: #selector(endCoalescing), for: [.touchUpInside, .touchUpOutside])
        cornerRow = addRow(editor.strings.cornerRadius, cornerSlider)

        let shadowRow = UIStackView(arrangedSubviews: [UILabel.panelLabel(editor.strings.shadow), shadowSwitch])
        shadowSwitch.addTarget(self, action: #selector(shadowChanged), for: .valueChanged)
        stack.addArrangedSubview(shadowRow)
    }

    override func reloadContent() {
        let style = store.currentStyle
        widthSlider.value = Float(style.lineWidth)
        widthLabel.text = "\(Int(style.lineWidth.rounded())) pt"
        dashControl.selectedSegmentIndex = DashStyle.allCases.firstIndex(of: style.dash) ?? 0
        opacitySlider.value = Float(style.opacity)
        cornerSlider.value = Float(style.cornerRadius)
        shadowSwitch.isOn = style.shadow

        let item = store.selectedItem
        // Closed polylines and curves have no ends, so no arrowheads.
        let isLineContext = item.map { $0.lineContent.map { !$0.isClosed } ?? false }
            ?? [MarkupTool.arrow, .polyline, .curve].contains(store.tool)
        headsRow?.isHidden = !isLineContext
        let heads = store.currentArrowHeads
        switch (heads.start, heads.end) {
        case (.none, .none): headsControl.selectedSegmentIndex = 0
        case (.none, .arrow): headsControl.selectedSegmentIndex = 1
        case (.arrow, .none): headsControl.selectedSegmentIndex = 2
        case (.arrow, .arrow): headsControl.selectedSegmentIndex = 3
        }
        var showsCorners = false
        if let item {
            if let shape = item.shapeContent { showsCorners = [.rectangle, .roundedRectangle, .highlightBox, .speechBubble].contains(shape.kind) }
            showsCorners = showsCorners || item.isText
        } else if case .shape(let kind, _) = store.tool {
            showsCorners = [.rectangle, .roundedRectangle, .highlightBox, .speechBubble].contains(kind)
        } else {
            showsCorners = store.tool == .note
        }
        cornerRow?.isHidden = !showsCorners
    }

    @objc private func widthChanged() {
        let value = CGFloat(widthSlider.value.rounded())
        widthLabel.text = "\(Int(value)) pt"
        store.updateStyle(coalescingKey: "lineWidth") { $0.lineWidth = value }
    }

    @objc private func dashChanged() {
        let dash = DashStyle.allCases[dashControl.selectedSegmentIndex]
        store.updateStyle { $0.dash = dash }
    }

    @objc private func headsChanged() {
        let pairs: [(ArrowHead, ArrowHead)] = [(.none, .none), (.none, .arrow), (.arrow, .none), (.arrow, .arrow)]
        let (start, end) = pairs[headsControl.selectedSegmentIndex]
        store.updateArrowHeads(start: start, end: end)
    }

    @objc private func opacityChanged() {
        let value = CGFloat(opacitySlider.value)
        store.updateStyle(coalescingKey: "opacity") { $0.opacity = value }
    }

    @objc private func cornerChanged() {
        let value = CGFloat(cornerSlider.value.rounded())
        store.updateStyle(coalescingKey: "cornerRadius") { $0.cornerRadius = value }
    }

    @objc private func shadowChanged() {
        let on = shadowSwitch.isOn
        store.updateStyle { $0.shadow = on }
    }

    @objc private func endCoalescing() {
        store.endCoalescing()
    }
}

// MARK: - Colors

/// Border or fill color: a palette like Preview's, "None", and the system color picker for anything else.
final class ColorPanel: PanelViewController, UIColorPickerViewControllerDelegate {
    private var swatchButtons: [(RGBAColor?, UIButton)] = []
    private var isFill: Bool { kind == .fillColor }

    override func buildContent() {
        addTitle(isFill ? editor.strings.fillColor : editor.strings.borderColor)
        let columns = 4
        var colors: [RGBAColor?] = RGBAColor.palette.map { $0 }
        colors.insert(nil, at: 0)
        var row: UIStackView?
        for (index, color) in colors.enumerated() {
            if index % columns == 0 {
                row = UIStackView()
                row?.distribution = .fillEqually
                row?.spacing = 10
                stack.addArrangedSubview(row!)
            }
            let button = UIButton(type: .custom)
            button.setImage(ToolbarCatalog.swatch(color, filled: true, size: 40), for: .normal)
            button.accessibilityLabel = color?.hexString ?? editor.strings.noColor
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            button.layer.cornerRadius = 8
            button.addAction(UIAction { [weak self] _ in self?.choose(color) }, for: .primaryActionTriggered)
            row?.addArrangedSubview(button)
            swatchButtons.append((color, button))
        }
        // Pad the last row so swatches keep their size.
        if let row, row.arrangedSubviews.count < columns {
            for _ in row.arrangedSubviews.count..<columns { row.addArrangedSubview(UIView()) }
        }

        var configuration = UIButton.Configuration.gray()
        configuration.title = editor.strings.customColor
        configuration.image = SymbolCatalog.sf("paintpalette", "eyedropper")
        configuration.imagePadding = 8
        let custom = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.showPicker() })
        stack.addArrangedSubview(custom)
    }

    private var currentColor: RGBAColor? {
        let style = store.currentStyle
        return isFill ? style.fillColor : style.strokeColor
    }

    /// Lines, strokes and plain text need their color; "None" is only offered where it makes sense.
    private var allowsNone: Bool {
        if isFill { return true }
        if let item = store.selectedItem {
            switch item.content {
            case .shape, .image: return true
            case .text: return true
            default: return false
            }
        }
        switch store.tool {
        case .shape, .text, .note, .select: return true
        default: return false
        }
    }

    override func reloadContent() {
        let current = currentColor
        for (color, button) in swatchButtons {
            let selected = color == current
            button.layer.borderWidth = selected ? 3 : 0
            button.layer.borderColor = UIColor.tintColor.cgColor
            if color == nil { button.isEnabled = allowsNone }
        }
    }

    private func choose(_ color: RGBAColor?) {
        apply(color, coalescingKey: nil)
    }

    private func apply(_ color: RGBAColor?, coalescingKey: String?) {
        if isFill {
            store.updateStyle(coalescingKey: coalescingKey) { $0.fillColor = color }
        } else {
            store.updateStyle(coalescingKey: coalescingKey) { style in
                style.strokeColor = color
                if color != nil && style.lineWidth <= 0 { style.lineWidth = 4 }
            }
        }
    }

    private func showPicker() {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = true
        picker.selectedColor = currentColor?.uiColor ?? .red
        picker.delegate = self
        present(picker, animated: true)
    }

    // iOS 15: `continuously` lets a whole drag in the picker be one undo step.
    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        apply(RGBAColor(color), coalescingKey: "colorPicker")
        if !continuously { store.endCoalescing() }
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        store.endCoalescing()
    }
}

// MARK: - Text Style

/// Font family, size, bold/italic, alignment and text color (Preview's "Text Style").
final class TextStylePanel: PanelViewController {
    private let familyButton = UIButton(configuration: .gray())
    private let sizeSlider = UISlider()
    private let sizeStepper = UIStepper()
    private let sizeLabel = UILabel()
    private let boldButton = UIButton(configuration: .gray())
    private let italicButton = UIButton(configuration: .gray())
    private let alignmentControl = UISegmentedControl(items: [
        SymbolCatalog.sf("text.alignleft") as Any,
        SymbolCatalog.sf("text.aligncenter") as Any,
        SymbolCatalog.sf("text.alignright") as Any,
    ])
    private var colorButtons: [(RGBAColor, UIButton)] = []

    override func buildContent() {
        addTitle(editor.strings.textStyle)

        familyButton.showsMenuAsPrimaryAction = true
        familyButton.changesSelectionAsPrimaryAction = true
        familyButton.contentHorizontalAlignment = .leading
        _ = addRow(editor.strings.font, familyButton)

        sizeSlider.minimumValue = 8
        sizeSlider.maximumValue = 200
        sizeSlider.addTarget(self, action: #selector(sizeSliderChanged), for: .valueChanged)
        sizeSlider.addTarget(self, action: #selector(endCoalescing), for: [.touchUpInside, .touchUpOutside])
        sizeSlider.accessibilityIdentifier = "panel.fontSize"
        sizeStepper.minimumValue = 8
        sizeStepper.maximumValue = 400
        sizeStepper.stepValue = 2
        sizeStepper.addTarget(self, action: #selector(stepperChanged), for: .valueChanged)
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        sizeLabel.setContentHuggingPriority(.required, for: .horizontal)
        let sizeRow = UIStackView(arrangedSubviews: [sizeSlider, sizeLabel, sizeStepper])
        sizeRow.spacing = 10
        sizeRow.alignment = .center
        _ = addRow(editor.strings.fontSize, sizeRow)

        boldButton.configuration?.image = SymbolCatalog.sf("bold")
        boldButton.accessibilityLabel = editor.strings.bold
        boldButton.addAction(UIAction { [weak self] _ in
            self?.store.updateText { $0.font.bold.toggle() }
        }, for: .primaryActionTriggered)
        italicButton.configuration?.image = SymbolCatalog.sf("italic")
        italicButton.accessibilityLabel = editor.strings.italic
        italicButton.addAction(UIAction { [weak self] _ in
            self?.store.updateText { $0.font.italic.toggle() }
        }, for: .primaryActionTriggered)
        alignmentControl.addTarget(self, action: #selector(alignmentChanged), for: .valueChanged)
        let styleRow = UIStackView(arrangedSubviews: [boldButton, italicButton, alignmentControl])
        styleRow.spacing = 10
        styleRow.distribution = .fill
        _ = addRow(editor.strings.alignment, styleRow)

        let colorRow = UIStackView()
        colorRow.distribution = .fillEqually
        colorRow.spacing = 8
        for color in [RGBAColor.black, .white, .red, .orange, .yellow, .green, .blue, .purple] {
            let button = UIButton(type: .custom)
            button.setImage(ToolbarCatalog.swatch(color, filled: true, size: 32), for: .normal)
            button.accessibilityLabel = color.hexString
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            button.layer.cornerRadius = 6
            button.addAction(UIAction { [weak self] _ in self?.store.updateText { $0.color = color } }, for: .primaryActionTriggered)
            colorRow.addArrangedSubview(button)
            colorButtons.append((color, button))
        }
        _ = addRow(editor.strings.textColor, colorRow)
    }

    override func reloadContent() {
        let content = store.currentTextContent
        familyButton.menu = UIMenu(options: .singleSelection, children: FontFamily.allCases.map { family in
            UIAction(title: editor.strings.fontFamilyName(family), state: family == content.font.family ? .on : .off) { [weak self] _ in
                self?.store.updateText { $0.font.family = family }
            }
        })
        familyButton.configuration?.title = editor.strings.fontFamilyName(content.font.family)
        sizeSlider.value = Float(content.font.size)
        sizeStepper.value = Double(content.font.size)
        sizeLabel.text = "\(Int(content.font.size.rounded()))"
        setToggle(boldButton, on: content.font.bold)
        setToggle(italicButton, on: content.font.italic)
        alignmentControl.selectedSegmentIndex = TextAlignmentOption.allCases.firstIndex(of: content.alignment) ?? 0
        for (color, button) in colorButtons {
            button.layer.borderWidth = color == content.color ? 3 : 0
            button.layer.borderColor = UIColor.tintColor.cgColor
        }
    }

    private func setToggle(_ button: UIButton, on: Bool) {
        button.configuration?.baseBackgroundColor = on ? .tintColor : .systemGray5
        button.configuration?.baseForegroundColor = on ? .white : .label
    }

    @objc private func sizeSliderChanged() {
        let size = CGFloat(sizeSlider.value.rounded())
        sizeLabel.text = "\(Int(size))"
        store.updateText(coalescingKey: "fontSize") { $0.font.size = size }
    }

    @objc private func stepperChanged() {
        let size = CGFloat(sizeStepper.value)
        store.updateText(coalescingKey: "fontSize") { $0.font.size = size }
    }

    @objc private func alignmentChanged() {
        let alignment = TextAlignmentOption.allCases[alignmentControl.selectedSegmentIndex]
        store.updateText { $0.alignment = alignment }
    }

    @objc private func endCoalescing() {
        store.endCoalescing()
    }
}

extension UILabel {
    static func panelLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        return label
    }
}
