import UIKit

/// Full-screen markup editor for one photo (image mode) or several photos (board mode).
/// Present it inside a `UINavigationController` (see `embeddedInNavigationController()`).
public final class MarkupEditorViewController: UIViewController {
    public weak var delegate: MarkupEditorDelegate?
    public let configuration: MarkupEditorConfiguration

    let store: EditorStore
    /// The user-facing texts of `configuration.locale`.
    var strings: Strings { store.strings }
    let canvasView = CanvasView()
    let overlayView = SelectionOverlayView()
    private(set) var interactions: InteractionController!
    private(set) var textEditing: TextEditingController!
    private(set) lazy var toolbar = MarkupToolbar(
        isBoard: store.document.isBoard,
        cameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera),
        features: features,
        strings: strings
    )
    private(set) lazy var panels = PanelPresenter(editor: self)
    private(set) lazy var imagePicking = ImagePicking(editor: self)
    private var topPlacement: [NSLayoutConstraint] = []
    private var bottomPlacement: [NSLayoutConstraint] = []
    /// Spans from the keyboard's top edge to the bottom of the screen (iOS 15 `keyboardLayoutGuide`).
    private let keyboardTracker = UIView()
    private var isExporting = false

    /// Opens an existing document. `assets` must contain every photo the document references.
    public init(document: MarkupDocument, assets: AssetCatalog, configuration: MarkupEditorConfiguration = .default) {
        self.configuration = configuration
        self.store = EditorStore(
            document: document,
            assets: AssetStore(catalog: assets),
            defaults: configuration.styleDefaults,
            strings: Strings(locale: configuration.locale)
        )
        super.init(nibName: nil, bundle: nil)
    }

    /// Annotate one photo. The file is read, never modified; it must stay available while editing.
    public convenience init(imageURL: URL, configuration: MarkupEditorConfiguration = .default) throws {
        let assets = AssetStore()
        let source = try assets.register(fileAt: imageURL)
        self.init(document: .imageDocument(source), assets: assets.catalog, configuration: configuration)
    }

    /// A board with the photos side by side, in the given order.
    public convenience init(imageURLs: [URL], configuration: MarkupEditorConfiguration = .default) throws {
        let assets = AssetStore()
        let sources = try imageURLs.map { try assets.register(fileAt: $0) }
        self.init(document: .board(sources), assets: assets.catalog, configuration: configuration)
    }

    /// Annotate an in-memory photo (e.g. from the camera). It is encoded once to a session file.
    public convenience init(image: UIImage, configuration: MarkupEditorConfiguration = .default) throws {
        let assets = AssetStore()
        let source = try assets.importImage(image)
        self.init(document: .imageDocument(source), assets: assets.catalog, configuration: configuration)
    }

    /// A board from in-memory photos.
    public convenience init(images: [UIImage], configuration: MarkupEditorConfiguration = .default) throws {
        let assets = AssetStore()
        let sources = try images.map { try assets.importImage($0) }
        self.init(document: .board(sources), assets: assets.catalog, configuration: configuration)
    }

    /// Reopens a package saved by a previous session (see `MarkupEditorConfiguration.packageDirectory`).
    /// Saving again replaces that package.
    public convenience init(packageURL: URL, configuration: MarkupEditorConfiguration = .default) throws {
        let contents = try MarkupPackage.load(from: packageURL)
        self.init(document: contents.document, assets: contents.assets, configuration: configuration)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// What the editor offers (from `configuration.features`).
    public var features: MarkupFeatures { configuration.features }

    /// The document as currently edited.
    public var document: MarkupDocument { store.document }

    /// IDs of the selected items.
    public var selectedItemIDs: [UUID] {
        get { store.selection }
        set { store.select(newValue) }
    }

    /// The active tool. Tools turned off in `configuration.features` are ignored.
    public var tool: MarkupTool {
        get { store.tool }
        set { selectTool(newValue) }
    }

    public func embeddedInNavigationController() -> UINavigationController {
        let navigation = UINavigationController(rootViewController: self)
        navigation.modalPresentationStyle = .fullScreen
        return navigation
    }

    // MARK: Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = configuration.title ?? (store.document.isBoard ? strings.titleBoard : strings.titleImage)
        isModalInPresentation = true

        setUpLayout()
        canvasView.assetURL = { [weak self] assetID in self?.store.assets.url(for: assetID) }
        canvasView.load(store.displayed)

        overlayView.frame = canvasView.overlayHost.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.overlayHost.addSubview(overlayView)
        overlayView.actionBar.strings = strings
        overlayView.actionBar.onAction = { [weak self] action in self?.perform(action) }

        let environment = InteractionEnvironment(store: store, canvas: canvasView, overlay: overlayView)
        textEditing = TextEditingController(env: environment)
        textEditing.onEditingChanged = { [weak self] editing in
            self?.refreshChrome()
            // Take keyboard shortcuts back once the text view lets go.
            if !editing { self?.becomeFirstResponder() }
        }
        environment.beginTextEditing = { [weak self] id, isNew in
            // New text is always typed in place; editing existing text can be turned off.
            guard let self, isNew || self.features.isEnabled(.editText) else { return }
            self.textEditing.begin(itemID: id, isNew: isNew)
        }
        environment.isEditingText = { [weak self] in self?.textEditing.isEditing ?? false }
        environment.endTextEditing = { [weak self] in self?.textEditing.end() }

        interactions = InteractionController(env: environment)
        interactions.excludedViews = { [weak self] in self.map { [$0.textEditing.textView] } ?? [] }
        interactions.makeToolInteraction = Self.makeInteraction(for:env:)
        interactions.onInteractionActiveChange = { [weak self] active in
            self?.overlayView.isInteracting = active
            self?.refreshOverlay()
        }
        canvasView.onViewportChange = { [weak self] in
            self?.refreshOverlay()
            self?.textEditing.layout()
        }

        toolbar.onToolSelected = { [weak self] tool in self?.selectTool(tool) }
        toolbar.onPanelRequested = { [weak self] kind, source in self?.panels.present(kind, from: source) }
        toolbar.onAddImages = { [weak self] source in self?.imagePicking.pick(from: source) }
        toolbar.onArrange = { [weak self] arrangement in
            self?.finishTextEditing()
            self?.store.arrange(arrangement)
            self?.canvasView.zoomToFit(animated: true)
        }
        toolbar.onZoomToFit = { [weak self] in self?.canvasView.zoomToFit(animated: true) }

        store.onChange = { [weak self] change in self?.storeDidChange(change) }
        configureNavigationItems()
        refreshChrome()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The keyboard layout guide moves with the keyboard, which triggers this layout pass.
        textEditing?.keyboardOverlapDidChange(canvasView.frame.maxY - keyboardTracker.frame.minY)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    // MARK: Keyboard (iPad hardware keyboard)

    // Note: `undoManager` is deliberately not overridden. UITextView registers typing undo on the responder
    // chain's manager, and the store's manager groups explicitly (groupsByEvent = false).
    public override var canBecomeFirstResponder: Bool { true }

    public override var keyCommands: [UIKeyCommand]? {
        guard textEditing?.isEditing != true else { return nil }
        var commands = [
            UIKeyCommand(title: strings.undo, action: #selector(undoTapped), input: "z", modifierFlags: .command),
            UIKeyCommand(title: strings.redo, action: #selector(redoTapped), input: "z", modifierFlags: [.command, .shift]),
            UIKeyCommand(title: strings.zoomToFit, action: #selector(zoomToFitCommand), input: "0", modifierFlags: .command),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapeCommand)),
        ]
        if features.isEnabled(.duplicate) {
            commands.append(UIKeyCommand(title: strings.duplicate, action: #selector(duplicateCommand), input: "d", modifierFlags: .command))
        }
        if features.isEnabled(.delete) {
            commands.append(UIKeyCommand(input: UIKeyCommand.inputDelete, modifierFlags: [], action: #selector(deleteCommand)))
        }
        commands += Self.toolShortcuts
            .filter { features.allows($0.value) }
            .map { input, _ in UIKeyCommand(input: input, modifierFlags: [], action: #selector(toolCommand(_:))) }
        return commands
    }

    private static let toolShortcuts: [String: MarkupTool] = [
        "v": .select, "p": .pen, "h": .highlighter, "a": .arrow, "l": .polyline, "c": .curve,
        "t": .text, "n": .note, "e": .eraser,
    ]

    @objc private func duplicateCommand() { store.duplicateSelection() }

    @objc private func zoomToFitCommand() { canvasView.zoomToFit(animated: true) }

    @objc private func deleteCommand() { store.deleteSelection() }

    @objc private func escapeCommand() {
        panels.dismiss()
        if interactions.env.polylineDraft.isActive {
            interactions.env.finishPolyline()
        } else if store.tool != .select {
            selectTool(.select)
        } else {
            store.clearSelection()
        }
    }

    @objc private func toolCommand(_ command: UIKeyCommand) {
        if let input = command.input, let tool = Self.toolShortcuts[input] { selectTool(tool) }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            applyToolbarPlacement()
        }
    }

    // MARK: Layout

    private func setUpLayout() {
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        keyboardTracker.translatesAutoresizingMaskIntoConstraints = false
        keyboardTracker.isHidden = true
        keyboardTracker.isUserInteractionEnabled = false
        view.addSubview(canvasView)
        view.addSubview(toolbar)
        view.addSubview(keyboardTracker)
        let safe = view.safeAreaLayoutGuide
        let content = toolbar.contentView

        NSLayoutConstraint.activate([
            keyboardTracker.topAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            keyboardTracker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyboardTracker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardTracker.widthAnchor.constraint(equalToConstant: 1),
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
        ])
        // Regular width: Preview-style bar under the navigation bar.
        topPlacement = [
            toolbar.topAnchor.constraint(equalTo: safe.topAnchor),
            content.topAnchor.constraint(equalTo: toolbar.topAnchor),
            content.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvasView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        // Compact width: bar at the bottom, background extending under the home indicator.
        bottomPlacement = [
            toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: toolbar.topAnchor),
            content.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            canvasView.topAnchor.constraint(equalTo: safe.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
        ]
        applyToolbarPlacement()
    }

    private func applyToolbarPlacement() {
        let compact = traitCollection.horizontalSizeClass == .compact
        NSLayoutConstraint.deactivate(compact ? topPlacement : bottomPlacement)
        NSLayoutConstraint.activate(compact ? bottomPlacement : topPlacement)
        toolbar.placement = compact ? .bottom : .top
    }

    // MARK: State changes

    private func storeDidChange(_ change: EditorChange) {
        if change.contains(.document) {
            canvasView.apply(store.displayed)
            if textEditing.isEditing { textEditing.layout() }
        }
        if change.contains(.tool) {
            interactions.updateForTool()
        }
        if change.contains(.document) {
            // Undo can remove the polyline being drawn, or points of the line whose point is marked.
            interactions.env.polylineDraft.validate(in: store.document)
        }
        if change.contains(.selection), let active = interactions.env.activeLineVertex, store.selection != [active.itemID] {
            interactions.env.activeLineVertex = nil
        }
        if change.contains(.undoState) {
            updateNavigationItems()
        }
        refreshChrome()
    }

    /// Toolbar state, selection overlay and panels.
    func refreshChrome() {
        refreshOverlay()
        toolbar.update(toolbarState())
        panels.refresh()
    }

    func refreshOverlay() {
        let item = textEditing?.isEditing == true ? nil : store.selectedItem
        overlayView.update(
            item: item, in: store.displayed, canvas: canvasView,
            actions: item.map(actions(for:)) ?? [],
            activeVertex: item.flatMap(activeVertex(of:)),
            isDrawing: item.map(isDrawingPolyline) ?? false
        )
    }

    /// The marked point of `item`, if it still exists.
    private func activeVertex(of item: MarkupItem) -> Int? {
        guard let active = interactions?.env.activeLineVertex, active.itemID == item.id,
              let count = item.lineContent?.points.count, active.index < count else { return nil }
        return active.index
    }

    /// Whether `item` is the polyline being drawn with the Polyline tool.
    private func isDrawingPolyline(_ item: MarkupItem) -> Bool {
        store.tool == .polyline && interactions?.env.polylineDraft.itemID == item.id
    }

    private func toolbarState() -> MarkupToolbar.State {
        let style = textEditing?.editingStyle ?? store.currentStyle
        let item = store.selectedItem
        let fillEnabled: Bool
        let textEnabled: Bool
        if let item {
            switch item.content {
            case .shape, .text: fillEnabled = true
            // A polyline being drawn can get its fill before it is closed.
            case .line(let line): fillEnabled = line.isClosed || isDrawingPolyline(item)
            default: fillEnabled = false
            }
            textEnabled = item.isText
        } else {
            switch store.tool {
            case .pen, .highlighter, .arrow, .curve, .eraser: fillEnabled = false
            default: fillEnabled = true
            }
            textEnabled = store.tool == .text || store.tool == .note || store.tool == .select
        }
        return MarkupToolbar.State(
            tool: store.tool,
            strokeColor: style.strokeColor,
            fillColor: style.fillColor,
            strokeEnabled: store.tool != .eraser,
            fillEnabled: fillEnabled,
            textEnabled: textEnabled || (textEditing?.isEditing ?? false)
        )
    }

    // MARK: Tools

    func selectTool(_ tool: MarkupTool) {
        guard features.allows(tool) else { return }
        finishTextEditing()
        panels.dismiss()
        // Picking any tool (even Polyline again) ends the polyline being drawn.
        interactions?.env.polylineDraft.reset()
        if tool != .select { store.clearSelection() }
        store.tool = tool
    }

    static func makeInteraction(for tool: MarkupTool, env: InteractionEnvironment) -> CanvasInteraction? {
        switch tool {
        case .select: return nil
        case .pen: return PenInteraction(env: env, isHighlighter: false)
        case .highlighter: return PenInteraction(env: env, isHighlighter: true)
        case .shape(let kind, let lockAspect): return ShapeCreateInteraction(env: env, kind: kind, lockAspect: lockAspect)
        case .arrow: return ArrowCreateInteraction(env: env)
        case .polyline: return PolylineCreateInteraction(env: env)
        case .curve: return ArrowCreateInteraction(env: env, kind: .curve)
        case .text: return TextCreateInteraction(env: env, isNote: false)
        case .note: return TextCreateInteraction(env: env, isNote: true)
        case .eraser: return EraserInteraction(env: env)
        }
    }

    func finishTextEditing() {
        if textEditing?.isEditing == true { textEditing.end() }
    }

    // MARK: Selection actions

    /// Actions for the selected item, minus those turned off in `configuration.features`
    /// (Unlock always stays, so a locked item never gets stuck).
    private func actions(for item: MarkupItem) -> [SelectionActionBar.Action] {
        if item.isLocked { return [.unlock] }
        var actions: [SelectionActionBar.Action] = []
        if let line = item.lineContent, line.hasEditablePoints {
            let canClose = line.points.count >= 3
            if isDrawingPolyline(item) {
                return canClose ? [.finishPath, .closePath] : [.finishPath]
            }
            if activeVertex(of: item) != nil && line.points.count > 2 { actions.append(.deletePoint) }
            if line.isClosed {
                actions.append(.openPath)
            } else if canClose {
                actions.append(.closePath)
            }
        }
        if item.isText { actions.append(.editText) }
        actions += [.duplicate, .bringToFront, .sendToBack, .lock, .delete]
        return actions.filter { action in
            switch action {
            case .editText: return features.isEnabled(.editText)
            case .duplicate: return features.isEnabled(.duplicate)
            case .bringToFront: return features.isEnabled(.bringToFront)
            case .sendToBack: return features.isEnabled(.sendToBack)
            case .lock: return features.isEnabled(.lock)
            case .delete: return features.isEnabled(.delete)
            case .unlock, .finishPath, .closePath, .openPath, .deletePoint: return true
            }
        }
    }

    private func perform(_ action: SelectionActionBar.Action) {
        switch action {
        case .editText:
            if let item = store.selectedItem { textEditing.begin(itemID: item.id, isNew: false) }
        case .duplicate: store.duplicateSelection()
        case .bringToFront: store.moveSelection(.front)
        case .sendToBack: store.moveSelection(.back)
        case .lock, .unlock: store.toggleLockOnSelection()
        case .delete: store.deleteSelection()
        case .finishPath: interactions.env.finishPolyline()
        case .closePath, .openPath:
            guard let item = store.selectedItem else { return }
            if isDrawingPolyline(item) {
                interactions.env.finishPolyline(close: action == .closePath)
            } else {
                store.setLineClosed(action == .closePath, for: item.id)
            }
        case .deletePoint:
            guard let item = store.selectedItem, let index = activeVertex(of: item) else { return }
            interactions.env.activeLineVertex = nil
            store.removeLinePoint(index, of: item.id)
        }
    }

    // MARK: Navigation bar

    private lazy var undoItem = UIBarButtonItem(image: SymbolCatalog.sf("arrow.uturn.backward"), style: .plain, target: self, action: #selector(undoTapped))
    private lazy var redoItem = UIBarButtonItem(image: SymbolCatalog.sf("arrow.uturn.forward"), style: .plain, target: self, action: #selector(redoTapped))
    private lazy var doneItem = UIBarButtonItem(
        title: configuration.navigationTexts.done, style: .done, target: self, action: #selector(doneTapped)
    )

    private func configureNavigationItems() {
        undoItem.accessibilityLabel = strings.undo
        redoItem.accessibilityLabel = strings.redo
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: configuration.navigationTexts.cancel, style: .plain, target: self, action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItems = [doneItem, redoItem, undoItem]
        updateNavigationItems()
    }

    private lazy var progressItem: UIBarButtonItem = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.accessibilityLabel = strings.exporting
        return UIBarButtonItem(customView: spinner)
    }()

    private func updateNavigationItems() {
        undoItem.isEnabled = store.undoManager.canUndo && !isExporting
        redoItem.isEnabled = store.undoManager.canRedo && !isExporting
        navigationItem.rightBarButtonItems = [isExporting ? progressItem : doneItem, redoItem, undoItem]
    }

    @objc func undoTapped() {
        finishTextEditing()
        store.undo()
    }

    @objc func redoTapped() {
        finishTextEditing()
        store.redo()
    }

    @objc private func cancelTapped() {
        finishTextEditing()
        panels.dismiss()
        interactions.env.polylineDraft.reset()
        guard store.hasChanges else {
            finishCancelling()
            return
        }
        present(makeDiscardAlert(), animated: true)
    }

    /// The confirmation Cancel shows when there are unsaved changes.
    func makeDiscardAlert() -> UIAlertController {
        let texts = configuration.navigationTexts
        let alert = UIAlertController(title: texts.discardTitle, message: texts.discardMessage, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: texts.discard, style: .destructive) { [weak self] _ in self?.finishCancelling() })
        alert.addAction(UIAlertAction(title: texts.keepEditing, style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        return alert
    }

    private func finishCancelling() {
        delegate?.markupEditorDidCancel(self)
    }

    /// Flattens the document, saves the editable package (when configured) and reports the result.
    @objc func doneTapped() {
        guard !isExporting else { return }
        finishTextEditing()
        panels.dismiss()
        interactions.env.polylineDraft.reset()
        store.clearSelection()
        isExporting = true
        view.isUserInteractionEnabled = false
        updateNavigationItems()
        let document = store.document
        let catalog = store.assets.catalog
        let options = configuration.exportOptions
        let packageDirectory = configuration.packageDirectory
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> (MarkupRendering, Result<URL?, Error>) in
                let rendering = MarkupRenderer.renderSynchronously(document, assets: catalog, options: options)
                guard let packageDirectory else { return (rendering, .success(nil)) }
                do {
                    return (rendering, .success(try MarkupPackage.save(document, assets: catalog, export: rendering, in: packageDirectory)))
                } catch {
                    return (rendering, .failure(error))
                }
            }.value
            guard let self else { return }
            self.isExporting = false
            self.view.isUserInteractionEnabled = true
            self.updateNavigationItems()
            let (rendering, saved) = outcome
            switch saved {
            case .success(let packageURL):
                let result = MarkupResult(image: rendering.image, imageData: rendering.data, document: document, assets: catalog, packageURL: packageURL)
                self.delegate?.markupEditor(self, didFinishWith: result)
            case .failure(let error):
                self.delegate?.markupEditor(self, didFailWith: error)
            }
        }
    }
}
