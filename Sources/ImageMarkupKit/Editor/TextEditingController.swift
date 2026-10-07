import UIKit

/// Edits a text item in place with a screen-space `UITextView` laid over it (font and insets scaled by zoom).
/// Rotated text is edited unrotated. One undo step is recorded when editing ends; an emptied box is removed,
/// and a brand-new box left empty leaves no trace.
@MainActor
final class TextEditingController: NSObject, UITextViewDelegate {
    private let env: InteractionEnvironment
    let textView = UITextView()
    private(set) var itemID: UUID?
    private var isNew = false
    /// The document the edit applies to (the committed document, or the preview holding a new box).
    private var baseDocument = MarkupDocument(kind: .board)
    private var originalContent: TextContent?
    var onEditingChanged: ((Bool) -> Void)?

    init(env: InteractionEnvironment) {
        self.env = env
        super.init()
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityIdentifier = "markup.textEditor"
        textView.inputAccessoryView = makeAccessoryBar()
    }

    var isEditing: Bool { itemID != nil }

    // MARK: Begin / end

    func begin(itemID: UUID, isNew: Bool) {
        if isEditing { end() }
        guard let item = env.store.displayed.item(itemID), let content = item.textContent, !item.isLocked else { return }
        self.itemID = itemID
        self.isNew = isNew
        baseDocument = env.store.displayed
        originalContent = content
        env.store.select([itemID])
        env.canvas.hiddenItemIDs.insert(itemID)
        textView.text = content.text
        env.canvas.overlayHost.addSubview(textView)
        env.canvas.scrollView.pinchGestureRecognizer?.isEnabled = false
        layout()
        textView.becomeFirstResponder()
        onEditingChanged?(true)
    }

    /// Commits the edit (or discards an empty new box).
    func end() {
        guard let id = itemID else { return }
        itemID = nil
        let text = textView.text ?? ""
        if textView.isFirstResponder { textView.resignFirstResponder() }
        textView.removeFromSuperview()
        env.canvas.hiddenItemIDs.remove(id)
        env.canvas.scrollView.pinchGestureRecognizer?.isEnabled = true
        env.canvas.keyboardInset = 0

        var document = documentWithText(text, for: id)
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isNew {
            if isEmpty {
                env.store.setPreview(nil)
                env.store.clearSelection()
            } else {
                document = Attachments.reassigningParents(of: [id], in: document)
                env.store.commit(document, actionName: env.store.strings.actionAddText, select: [id])
                env.finishCreating(id, keepTool: false)
            }
        } else if isEmpty {
            document.items.removeAll { $0.id == id }
            env.store.commit(document, actionName: env.store.strings.actionDelete, select: [])
        } else if document.item(id)?.textContent != originalContent {
            env.store.commit(document, actionName: env.store.strings.actionEditText, select: [id])
        } else {
            env.store.setPreview(nil)
        }
        onEditingChanged?(false)
    }

    /// Applies a text-attribute change (font size, color…) to the box being edited.
    func applyTextChange(_ change: (inout TextContent) -> Void) {
        guard let id = itemID else { return }
        baseDocument.update(id) { item in
            guard case .text(var content) = item.content else { return }
            change(&content)
            item.content = .text(content)
        }
        textViewDidChange(textView)
    }

    /// Applies a style change (fill, border…) to the box being edited.
    func applyStyleChange(_ change: (inout ItemStyle) -> Void) {
        guard let id = itemID else { return }
        baseDocument.update(id) { change(&$0.style) }
        textViewDidChange(textView)
    }

    var editingContent: TextContent? {
        guard let id = itemID else { return nil }
        return env.store.displayed.item(id)?.textContent
    }

    var editingStyle: ItemStyle? {
        guard let id = itemID else { return nil }
        return env.store.displayed.item(id)?.style
    }

    private func documentWithText(_ text: String, for id: UUID) -> MarkupDocument {
        var document = baseDocument
        document.update(id) { item in
            guard case .text(var content) = item.content else { return }
            content.text = text
            item.content = .text(TextLayout.fitted(content))
        }
        return document
    }

    // MARK: Layout

    /// Positions and styles the text view over the item for the current zoom and scroll position.
    func layout() {
        guard let id = itemID, let item = env.store.displayed.item(id), let content = item.textContent else { return }
        let zoom = env.zoom
        let center = env.canvas.point(fromCanvas: content.box.center, to: env.canvas.overlayHost)
        let size = CGSize(width: content.box.frame.width * zoom, height: content.box.frame.height * zoom)
        textView.transform = .identity
        textView.frame = CGRect(center: center, size: size)

        var font = content.font
        font.size *= zoom
        textView.font = TextLayout.font(for: font)
        textView.textColor = content.color.uiColor
        switch content.alignment {
        case .left: textView.textAlignment = .left
        case .center: textView.textAlignment = .center
        case .right: textView.textAlignment = .right
        }
        let inset = content.padding * zoom
        textView.textContainerInset = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        if content.fixedWidth == nil {
            // Auto width: never wrap while typing; the box grows instead.
            textView.textContainer.widthTracksTextView = false
            textView.textContainer.size = CGSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
        } else {
            textView.textContainer.widthTracksTextView = true
        }
        let style = item.style
        textView.backgroundColor = style.fillColor?.uiColor ?? UIColor.systemBackground.withAlphaComponent(0.35)
        textView.layer.cornerRadius = min(style.cornerRadius * zoom, size.height / 2)
        if let stroke = style.strokeColor, style.lineWidth > 0 {
            textView.layer.borderColor = stroke.cgColor
            textView.layer.borderWidth = style.lineWidth * zoom
        } else {
            textView.layer.borderColor = UIColor.systemBlue.cgColor
            textView.layer.borderWidth = 1
        }
        textView.alpha = max(style.opacity, 0.3)
    }

    // MARK: UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        guard let id = itemID else { return }
        env.store.setPreview(documentWithText(textView.text ?? "", for: id))
        layout()
        scrollToVisible()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        end()
    }

    // MARK: Keyboard

    /// Called by the editor with how much of the canvas the keyboard covers (from `keyboardLayoutGuide`, which
    /// avoids converting the keyboard's screen frame — that conversion fails with several UIScreen objects).
    func keyboardOverlapDidChange(_ overlap: CGFloat) {
        guard isEditing else { return }
        let inset = max(0, overlap)
        guard abs(env.canvas.keyboardInset - inset) > 0.5 else { return }
        env.canvas.keyboardInset = inset
        scrollToVisible()
    }

    /// Keeps the text view above the keyboard.
    private func scrollToVisible() {
        guard let id = itemID, let box = env.store.displayed.item(id)?.box else { return }
        let visibleHeight = env.canvas.bounds.height - env.canvas.keyboardInset
        let frame = textView.frame
        if frame.maxY > visibleHeight - 12 || frame.minY < 12 {
            env.canvas.center(onCanvasPoint: box.center)
            layout()
        }
    }

    // MARK: Accessory bar

    private func makeAccessoryBar() -> UIToolbar {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let smaller = UIBarButtonItem(image: SymbolCatalog.sf("textformat.size.smaller", "minus"), style: .plain, target: self, action: #selector(decreaseFont))
        smaller.accessibilityLabel = env.store.strings.smaller
        let larger = UIBarButtonItem(image: SymbolCatalog.sf("textformat.size.larger", "plus"), style: .plain, target: self, action: #selector(increaseFont))
        larger.accessibilityLabel = env.store.strings.larger
        let bold = UIBarButtonItem(image: SymbolCatalog.sf("bold"), style: .plain, target: self, action: #selector(toggleBold))
        bold.accessibilityLabel = env.store.strings.bold
        let done = UIBarButtonItem(title: env.store.strings.done, style: .done, target: self, action: #selector(doneTapped))
        toolbar.items = [smaller, larger, bold, UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), done]
        toolbar.sizeToFit()
        return toolbar
    }

    @objc private func decreaseFont() {
        applyTextChange { $0.font.size = max(8, ($0.font.size / 1.15).rounded()) }
    }

    @objc private func increaseFont() {
        applyTextChange { $0.font.size = min(400, ($0.font.size * 1.15).rounded()) }
    }

    @objc private func toggleBold() {
        applyTextChange { $0.font.bold.toggle() }
    }

    @objc private func doneTapped() {
        end()
    }
}
