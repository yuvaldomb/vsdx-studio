import AppKit
import VSDXCore

private enum DrawioChrome {
    static let background = NSColor(srgbRed: 241.0 / 255, green: 243.0 / 255, blue: 244.0 / 255, alpha: 1)
    static let line = NSColor(srgbRed: 218.0 / 255, green: 218.0 / 255, blue: 218.0 / 255, alpha: 1)
    static let pageFill = NSColor(srgbRed: 225.0 / 255, green: 233.0 / 255, blue: 247.0 / 255, alpha: 1)
    static let pageText = NSColor(srgbRed: 11.0 / 255, green: 87.0 / 255, blue: 208.0 / 255, alpha: 1)
}

final class StudioWindowController: NSWindowController, CanvasHost, NSWindowDelegate, NSTextFieldDelegate {
    private let studioDocument: StudioDocument
    private let ribbon = RibbonBar()
    private let shapesPane = ShapesPane()
    private let formatPane = FormatPane()
    private let formatClip = NSView()
    private let canvas = CanvasView()
    private let scroll = NSScrollView()
    private let split = NSSplitView()
    private let hRuler = RulerView(horizontal: true)
    private let vRuler = RulerView(horizontal: false)
    private let rulerCorner = NSView()
    private let pageBar = NSStackView()
    private static var nextCascade = NSPoint.zero
    private var snapshot: Diagram?
    private var showRulers = false
    private var hRulerHeight: NSLayoutConstraint!
    private var vRulerWidth: NSLayoutConstraint!
    private var formatClipWidth: NSLayoutConstraint!
    private var shapesWidth: NSLayoutConstraint!
    private var shapesCollapsed = false
    private(set) var formatVisible = true
    var connectorStyle: ConnectorStyle = .elbow
    private var pickingFill = true
    private weak var colorButton: NSButton?

    var pageIndex = 0
    var selection: [Int] = [] {
        didSet {
            canvas.selection = selection
            canvas.needsDisplay = true
            showFormat()
        }
    }
    var tool: EditorTool = .pointer {
        didSet {
            canvas.tool = tool
            ribbon.update(tool: tool)
            canvas.needsDisplay = true
        }
    }
    var zoom: CGFloat = 1 {
        didSet {
            canvas.zoom = zoom
            canvas.updateFrame()
            syncRulers()
            ribbon.setZoomPercent(Double(zoom * 100))
        }
    }
    var snapEnabled = true
    var showGrid = true {
        didSet {
            canvas.showGrid = showGrid
            canvas.needsDisplay = true
            formatPane.showsGrid = showGrid
        }
    }
    var showConnections = false {
        didSet {
            canvas.showConnections = showConnections
            canvas.needsDisplay = true
            formatPane.showsConnectionPoints = showConnections
        }
    }
    var diagram: Diagram { studioDocument.diagram }

    init(document: StudioDocument) {
        studioDocument = document
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 980, height: 640)
        window.title = "Drawing.vsdx"
        window.titleVisibility = .visible
        window.backgroundColor = DrawioChrome.background
        window.appearance = NSAppearance(named: .aqua)
        super.init(window: window)
        window.delegate = self
        build()
        canvas.host = self
        ribbon.install(target: self)
        ribbon.onShapes = { [weak self] in self?.showShapesLibrary() }
        ribbon.onFormat = { [weak self] in self?.toggleFormat() }
        ribbon.onCollapse = { [weak self] in self?.toggleShapesPane() }
        ribbon.update(tool: .pointer)
        ribbon.setZoomPercent(Double(zoom * 100))
        shapesPane.onPlace = { [weak self] id in self?.placeShapeForTest(id) }
        formatPane.onChange = { [weak self] change in self?.apply(change) }
        formatPane.onToggleGrid = { [weak self] on in
            guard let self, self.showGrid != on else { return }
            self.toggleGrid(nil)
        }
        formatPane.onToggleConnectionPoints = { [weak self] on in
            guard let self, self.showConnections != on else { return }
            self.toggleConnections(nil)
        }
        syncFromDocument(rebuildPanels: true)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            if StudioWindowController.nextCascade == .zero {
                StudioWindowController.nextCascade = NSPoint(x: screen.visibleFrame.minX, y: screen.visibleFrame.maxY)
            }
            StudioWindowController.nextCascade = window.cascadeTopLeft(from: StudioWindowController.nextCascade)
        }
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        layoutSplit()
        NSColorPanel.shared.orderOut(nil)
    }

    required init?(coder: NSCoder) { nil }

    private func build() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = DrawioChrome.background.cgColor
        ribbon.translatesAutoresizingMaskIntoConstraints = false
        shapesPane.translatesAutoresizingMaskIntoConstraints = false
        formatPane.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = StudioChrome.pasteboard
        scroll.documentView = canvas
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrollChanged), name: NSView.boundsDidChangeNotification, object: scroll.contentView)

        hRuler.translatesAutoresizingMaskIntoConstraints = false
        vRuler.translatesAutoresizingMaskIntoConstraints = false
        rulerCorner.wantsLayer = true
        rulerCorner.layer?.backgroundColor = NSColor.white.cgColor
        rulerCorner.translatesAutoresizingMaskIntoConstraints = false
        hRuler.isHidden = true
        vRuler.isHidden = true
        rulerCorner.isHidden = true

        let canvasColumn = NSView()
        canvasColumn.translatesAutoresizingMaskIntoConstraints = false
        canvasColumn.addSubview(scroll)
        canvasColumn.addSubview(hRuler)
        canvasColumn.addSubview(vRuler)
        canvasColumn.addSubview(rulerCorner)
        hRulerHeight = hRuler.heightAnchor.constraint(equalToConstant: 0)
        vRulerWidth = vRuler.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            rulerCorner.leadingAnchor.constraint(equalTo: canvasColumn.leadingAnchor),
            rulerCorner.topAnchor.constraint(equalTo: canvasColumn.topAnchor),
            rulerCorner.widthAnchor.constraint(equalTo: vRuler.widthAnchor),
            rulerCorner.heightAnchor.constraint(equalTo: hRuler.heightAnchor),
            hRuler.leadingAnchor.constraint(equalTo: rulerCorner.trailingAnchor),
            hRuler.trailingAnchor.constraint(equalTo: canvasColumn.trailingAnchor),
            hRuler.topAnchor.constraint(equalTo: canvasColumn.topAnchor),
            hRulerHeight,
            vRuler.leadingAnchor.constraint(equalTo: canvasColumn.leadingAnchor),
            vRuler.topAnchor.constraint(equalTo: rulerCorner.bottomAnchor),
            vRuler.bottomAnchor.constraint(equalTo: canvasColumn.bottomAnchor),
            vRulerWidth,
            scroll.leadingAnchor.constraint(equalTo: vRuler.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: canvasColumn.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: hRuler.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: canvasColumn.bottomAnchor)
        ])

        pageBar.orientation = .horizontal
        pageBar.alignment = .centerY
        pageBar.spacing = 2
        pageBar.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        pageBar.translatesAutoresizingMaskIntoConstraints = false
        let pageWrap = NSView()
        pageWrap.identifier = NSUserInterfaceItemIdentifier("pageBar")
        pageWrap.wantsLayer = true
        pageWrap.layer?.backgroundColor = DrawioChrome.background.cgColor
        pageWrap.translatesAutoresizingMaskIntoConstraints = false
        let pageLine = NSView()
        pageLine.wantsLayer = true
        pageLine.layer?.backgroundColor = DrawioChrome.line.cgColor
        pageLine.translatesAutoresizingMaskIntoConstraints = false
        pageWrap.addSubview(pageLine)
        pageWrap.addSubview(pageBar)
        NSLayoutConstraint.activate([
            pageLine.leadingAnchor.constraint(equalTo: pageWrap.leadingAnchor),
            pageLine.trailingAnchor.constraint(equalTo: pageWrap.trailingAnchor),
            pageLine.topAnchor.constraint(equalTo: pageWrap.topAnchor),
            pageLine.heightAnchor.constraint(equalToConstant: 1),
            pageBar.leadingAnchor.constraint(equalTo: pageWrap.leadingAnchor),
            pageBar.trailingAnchor.constraint(lessThanOrEqualTo: pageWrap.trailingAnchor),
            pageBar.topAnchor.constraint(equalTo: pageLine.bottomAnchor),
            pageBar.bottomAnchor.constraint(equalTo: pageWrap.bottomAnchor),
            pageWrap.heightAnchor.constraint(equalToConstant: 32)
        ])

        formatClip.identifier = NSUserInterfaceItemIdentifier("formatClip")
        formatClip.wantsLayer = true
        formatClip.layer?.backgroundColor = NSColor.white.cgColor
        formatClip.layer?.masksToBounds = true
        formatClip.clipsToBounds = true
        formatClip.translatesAutoresizingMaskIntoConstraints = false
        formatClip.addSubview(formatPane)
        formatClipWidth = formatClip.widthAnchor.constraint(equalToConstant: 240)
        NSLayoutConstraint.activate([
            formatClipWidth,
            formatPane.leadingAnchor.constraint(equalTo: formatClip.leadingAnchor),
            formatPane.topAnchor.constraint(equalTo: formatClip.topAnchor),
            formatPane.bottomAnchor.constraint(equalTo: formatClip.bottomAnchor),
            formatPane.widthAnchor.constraint(equalToConstant: 240)
        ])

        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(shapesPane)
        split.addArrangedSubview(canvasColumn)
        split.addArrangedSubview(formatClip)
        shapesWidth = shapesPane.widthAnchor.constraint(equalToConstant: 232)
        shapesWidth.isActive = true
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        canvasColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
        canvasColumn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        split.setHoldingPriority(NSLayoutConstraint.Priority(rawValue: 260), forSubviewAt: 0)
        split.setHoldingPriority(NSLayoutConstraint.Priority(rawValue: 50), forSubviewAt: 1)
        split.setHoldingPriority(NSLayoutConstraint.Priority(rawValue: 260), forSubviewAt: 2)

        content.addSubview(ribbon)
        content.addSubview(split)
        content.addSubview(pageWrap)
        NSLayoutConstraint.activate([
            ribbon.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            ribbon.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            ribbon.topAnchor.constraint(equalTo: content.topAnchor),
            ribbon.heightAnchor.constraint(equalToConstant: 102),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.topAnchor.constraint(equalTo: ribbon.bottomAnchor),
            split.bottomAnchor.constraint(equalTo: pageWrap.topAnchor),
            pageWrap.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pageWrap.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pageWrap.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        applyRulers()
        layoutSplit()
    }

    private func layoutSplit() {
        let shapes: CGFloat = shapesCollapsed ? 0 : 232
        shapesWidth?.constant = shapes
        let width = split.bounds.width
        guard width > 700 else { return }
        let format: CGFloat = formatVisible ? 240 : 0
        split.setPosition(shapes, ofDividerAt: 0)
        split.setPosition(width - format, ofDividerAt: 1)
    }

    private func showShapesLibrary() {
        if shapesCollapsed {
            setShapesCollapsed(false)
        } else {
            shapesPane.focusSearch()
        }
    }

    private func toggleShapesPane() {
        setShapesCollapsed(!shapesCollapsed)
    }

    private func setShapesCollapsed(_ collapsed: Bool) {
        shapesCollapsed = collapsed
        shapesWidth.constant = collapsed ? 0 : 232
        shapesPane.isHidden = collapsed
        split.layoutSubtreeIfNeeded()
        layoutSplit()
    }

    private func applyFormatVisibility() {
        formatClipWidth.constant = formatVisible ? 240 : 0
        formatClip.isHidden = !formatVisible
        split.layoutSubtreeIfNeeded()
        layoutSplit()
    }

    private func applyRulers() {
        hRuler.isHidden = !showRulers
        vRuler.isHidden = !showRulers
        rulerCorner.isHidden = !showRulers
        hRulerHeight.constant = showRulers ? 24 : 0
        vRulerWidth.constant = showRulers ? 24 : 0
        if showRulers { syncRulers() }
    }

    func windowDidResize(_ notification: Notification) {
        layoutSplit()
        syncRulers()
    }

    func syncFromDocument(rebuildPanels: Bool) {
        if !diagram.pages.indices.contains(pageIndex) { pageIndex = 0 }
        let page = diagram.pages[pageIndex]
        canvas.reload(page: page, theme: diagram.theme, colors: diagram.colors)
        canvas.selection = selection.filter { page.shape(id: $0) != nil }
        selection = canvas.selection
        canvas.showGrid = showGrid
        canvas.snapEnabled = snapEnabled
        canvas.showConnections = showConnections
        window?.title = (studioDocument.displayName as String?) ?? page.name
        ribbon.setDocumentTitle(window?.title ?? page.name)
        if studioDocument.isDocumentEdited {
            ribbon.setStatus("Unsaved changes. Click here to save.")
        } else {
            ribbon.setStatus(nil)
        }
        rebuildPageBar()
        if rebuildPanels { showFormat() }
        syncRulers()
    }

    private func showFormat() {
        let shape = selection.last.flatMap { diagram.pages[pageIndex].shape(id: $0) }
        formatPane.showsGrid = showGrid
        formatPane.showsConnectionPoints = showConnections
        formatPane.show(shape: shape)
    }

    private func rebuildPageBar() {
        pageBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, page) in diagram.pages.enumerated() {
            pageBar.addArrangedSubview(pageTab(title: page.name, tag: index, selected: index == pageIndex, action: #selector(selectPage(_:))))
        }
        pageBar.addArrangedSubview(pageTab(title: "+", tag: 0, selected: false, action: #selector(addPage(_:))))
    }

    private func pageTab(title: String, tag: Int, selected: Bool, action: Selector) -> NSButton {
        let button = PageTabButton()
        button.target = self
        button.action = action
        button.tag = tag
        button.title = title
        button.isBordered = false
        button.wantsLayer = true
        button.focusRingType = .none
        button.filled = selected
        button.fillColor = DrawioChrome.pageFill
        button.titleColor = selected ? DrawioChrome.pageText : NSColor.black
        let font = NSFont.systemFont(ofSize: 13, weight: selected ? .medium : .regular)
        button.font = font
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: max(28, ceil(textWidth) + 16)).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    @objc private func scrollChanged() { syncRulers() }

    private func syncRulers() {
        let origin = scroll.contentView.bounds.origin
        hRuler.pixelsPerInch = canvas.pixelsPerInch
        vRuler.pixelsPerInch = canvas.pixelsPerInch
        hRuler.zeroOffset = 48 - origin.x
        let pageBottom = 48 + CGFloat(diagram.pages[pageIndex].height) * canvas.pixelsPerInch
        vRuler.zeroOffset = pageBottom - origin.y
        vRuler.scaleDirection = -1
        hRuler.needsDisplay = true
        vRuler.needsDisplay = true
    }

    func beginPreview() { snapshot = diagram }
    func preview(_ body: (inout Diagram) -> Void) {
        guard var copy = snapshot else { return }
        body(&copy)
        studioDocument.replaceWithoutUndo(copy)
    }
    func commitPreview(_ name: String) {
        guard let before = snapshot else { return }
        let after = studioDocument.diagram
        snapshot = nil
        studioDocument.diagram = before
        studioDocument.mutate(name) { $0 = after }
    }
    func cancelPreview() {
        if let snapshot { studioDocument.replaceWithoutUndo(snapshot) }
        self.snapshot = nil
    }
    func statusPoint(_ point: CGPoint?) {
        guard let point, showRulers else { return }
        let page = diagram.pages[pageIndex]
        hRuler.marker = 48 - scroll.contentView.bounds.origin.x + point.x * canvas.pixelsPerInch
        let pageBottom = 48 + CGFloat(page.height) * canvas.pixelsPerInch
        vRuler.marker = pageBottom - scroll.contentView.bounds.origin.y - point.y * canvas.pixelsPerInch
        hRuler.needsDisplay = true
        vRuler.needsDisplay = true
    }

    func showRibbonTabForTest(_ index: Int) {
        ribbon.showTab(index)
        window?.layoutIfNeeded()
    }

    func writeGUISnapshot(to url: URL) {
        guard let view = window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * 2),
                pixelsHigh: Int(bounds.height * 2),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else { return }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    func placeShapeForTest(_ id: String) {
        let visible = scroll.contentView.bounds
        canvas.placeStencil(id, at: CGPoint(x: visible.midX, y: visible.midY))
    }

    private func apply(_ change: FormatPane.FormatChange) {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        studioDocument.mutate("Format") { diagram in
            let index = self.pageIndex
            switch change {
            case .position(let x, let y, let w, let h, let angle):
                for id in ids {
                    diagram.pages[index].updateShape(id: id) { shape in
                        if let x { shape.setNumber("PinX", x, clearFormula: true) }
                        if let y { shape.setNumber("PinY", y, clearFormula: true) }
                        if let w { shape.setNumber("Width", max(0.1, w), clearFormula: true) }
                        if let h { shape.setNumber("Height", max(0.1, h), clearFormula: true) }
                        if let angle { shape.setNumber("Angle", angle, clearFormula: true) }
                    }
                    if w != nil || h != nil {
                        DiagramEdit.refreshDerived(page: &diagram.pages[index], id: id, theme: diagram.theme, colors: diagram.colors)
                    }
                }
            case .fill(let color):
                DiagramEdit.setFill(page: &diagram.pages[index], ids: ids, color: color?.hexString)
            case .line(let color):
                DiagramEdit.setLine(page: &diagram.pages[index], ids: ids, color: color.hexString)
            case .weight(let width):
                DiagramEdit.setLine(page: &diagram.pages[index], ids: ids, weight: width)
            case .pattern(let value):
                DiagramEdit.setLine(page: &diagram.pages[index], ids: ids, pattern: value)
            case .arrow(let value):
                DiagramEdit.setLine(page: &diagram.pages[index], ids: ids, endArrow: value)
            case .font(let name):
                DiagramEdit.setFont(page: &diagram.pages[index], ids: ids, name: name)
            case .fontSize(let size):
                DiagramEdit.setFont(page: &diagram.pages[index], ids: ids, size: size)
            case .fontColor(let color):
                DiagramEdit.setFont(page: &diagram.pages[index], ids: ids, color: color.hexString)
            case .shapeData(let label, let value):
                for id in ids {
                    diagram.pages[index].updateShape(id: id) { shape in
                        let name = label.isEmpty ? "Property" : label
                        if let index = shape.properties.firstIndex(where: { $0.label == name || $0.name == name }) {
                            shape.properties[index].label = name
                            shape.properties[index].value = value
                        } else {
                            shape.properties.append(PropRow(name: name, label: name, value: value))
                        }
                        shape.detached = true
                        shape.original = nil
                    }
                }
            case .opacity(let fraction):
                DiagramEdit.setOpacity(page: &diagram.pages[index], ids: ids, fraction: fraction)
            case .shadow(let enabled):
                DiagramEdit.setShadow(page: &diagram.pages[index], ids: ids, enabled: enabled)
            case .rounding(let inches):
                DiagramEdit.setRounding(page: &diagram.pages[index], ids: ids, inches: inches)
            case .beginArrow(let value):
                DiagramEdit.setLine(page: &diagram.pages[index], ids: ids, beginArrow: value)
            case .fontBit(let bit):
                DiagramEdit.toggleFontBit(page: &diagram.pages[index], ids: ids, bit: bit)
            case .textAlign(let align):
                DiagramEdit.setFont(page: &diagram.pages[index], ids: ids, align: align)
            case .verticalAlign(let align):
                DiagramEdit.setFont(page: &diagram.pages[index], ids: ids, vertical: align)
            case .route(let style):
                self.connectorStyle = style
                for id in ids {
                    guard var shape = diagram.pages[index].shape(id: id), shape.is1D else { continue }
                    shape.setCell("UserRoute", value: "0", clearFormula: true)
                    shape.setCell("ShapeRouteStyle", value: style.routeValue, clearFormula: true)
                    diagram.pages[index].updateShape(id: id) { $0 = shape }
                }
                DiagramEdit.resetRoutes(page: &diagram.pages[index], ids: ids, theme: diagram.theme, colors: diagram.colors)
            case .bringFront:
                DiagramEdit.order(page: &diagram.pages[index], ids: ids, kind: .front)
            case .sendBack:
                DiagramEdit.order(page: &diagram.pages[index], ids: ids, kind: .back)
            }
        }
    }

    private func currentPage() -> DiagramPage { diagram.pages[pageIndex] }

    @objc func undo(_ sender: Any?) {
        studioDocument.undoManager?.undo()
    }

    @objc func redo(_ sender: Any?) {
        studioDocument.undoManager?.redo()
    }

    @objc func toggleFullScreen(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }

    @objc func toggleShadow(_ sender: Any?) {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        let enable = ids.contains { id in
            let pattern = Format.parseDouble(currentPage().shape(id: id)?.cell("ShdwPattern")?.value) ?? 0
            return pattern == 0
        }
        studioDocument.mutate("Shadow") { diagram in
            DiagramEdit.setShadow(page: &diagram.pages[self.pageIndex], ids: ids, enabled: enable)
        }
    }

    @objc func pickFill(_ sender: Any?) { beginColorPick(fill: true, sender: sender) }
    @objc func pickStroke(_ sender: Any?) { beginColorPick(fill: false, sender: sender) }

    @objc func chooseConnectorStyle(_ sender: NSMenuItem) {
        switch sender.tag {
        case 0: connectorStyle = .straight
        case 2: connectorStyle = .curve
        case 3: connectorStyle = .simple
        default: connectorStyle = .elbow
        }
        tool = .connector
    }

    @objc func clearWaypoints(_ sender: Any?) {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        studioDocument.mutate("Clear Waypoints") { diagram in
            DiagramEdit.resetRoutes(page: &diagram.pages[self.pageIndex], ids: ids, theme: diagram.theme, colors: diagram.colors)
        }
    }

    @objc func insertTable(_ sender: Any?) {
        studioDocument.mutate("Insert Table") { diagram in
            let index = self.pageIndex
            let page = diagram.pages[index]
            let originX = page.width / 2 - 1.8
            let originY = page.height / 2 - 0.9
            var ids: [Int] = []
            for row in 0..<3 {
                for column in 0..<3 {
                    let id = diagram.pages[index].nextShapeId()
                    let center = CGPoint(
                        x: originX + Double(column) * 1.2 + 0.6,
                        y: originY + Double(row) * 0.6 + 0.3
                    )
                    var shape = StencilCatalog.make(id: "rectangle", shapeId: id, center: center)
                    shape.setNumber("Width", 1.2, clearFormula: true)
                    shape.setNumber("Height", 0.6, clearFormula: true)
                    shape.setTextContent("")
                    diagram.pages[index].shapes.append(shape)
                    ids.append(id)
                }
            }
            if let group = DiagramEdit.group(page: &diagram.pages[index], ids: ids, theme: diagram.theme, colors: diagram.colors) {
                self.selection = [group]
            } else {
                self.selection = ids
            }
        }
    }

    private func beginColorPick(fill: Bool, sender: Any?) {
        pickingFill = fill
        colorButton = sender as? NSButton
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = false
        let shape = selection.last.flatMap { currentPage().shape(id: $0) }
        let hex = fill ? (shape?.cell("FillForegnd")?.value ?? "#FFFFFF") : (shape?.cell("LineColor")?.value ?? "#000000")
        panel.color = NSColor(hex: hex) ?? (fill ? .white : .black)
        window?.makeFirstResponder(nil)
        panel.orderFront(sender)
    }

    @objc func changeColor(_ sender: NSColorPanel?) {
        guard let sender else { return }
        colorPicked(sender)
    }

    @objc private func colorPicked(_ panel: NSColorPanel) {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        colorButton?.subviews.first { $0.identifier?.rawValue == "swatch" }?.layer?.backgroundColor = panel.color.cgColor
        studioDocument.mutate(pickingFill ? "Fill Color" : "Line Color") { diagram in
            if self.pickingFill {
                DiagramEdit.setFill(page: &diagram.pages[self.pageIndex], ids: ids, color: panel.color.hexString)
            } else {
                DiagramEdit.setLine(page: &diagram.pages[self.pageIndex], ids: ids, color: panel.color.hexString)
            }
        }
    }

    @objc func chooseTool(_ sender: Any?) {
        let control = sender as? NSControl
        if let raw = control?.identifier?.rawValue, let tool = EditorTool(rawValue: raw) {
            self.tool = tool
        }
    }

    @objc func copy(_ sender: Any?) { copyShapes(sender) }
    @objc func paste(_ sender: Any?) { pasteShapes(sender) }
    @objc func cut(_ sender: Any?) {
        copyShapes(sender)
        deleteShapes(sender)
    }
    @objc override func selectAll(_ sender: Any?) {
        selection = currentPage().shapes.map(\.id)
    }

    @objc func copyShapes(_ sender: Any?) {
        ShapeClipboard.shapes = selection.compactMap { id in
            var shape = currentPage().shape(id: id)
            shape?.original = nil
            shape?.detached = true
            return shape
        }
    }

    @objc func pasteShapes(_ sender: Any?) {
        guard !ShapeClipboard.shapes.isEmpty else { return }
        studioDocument.mutate("Paste") { diagram in
            var next = diagram.pages[self.pageIndex].nextShapeId()
            var ids: [Int] = []
            for var shape in ShapeClipboard.shapes {
                self.reassign(&shape, next: &next)
                let pinX = (Format.parseDouble(shape.cell("PinX")?.value) ?? 0) + 0.25
                let pinY = (Format.parseDouble(shape.cell("PinY")?.value) ?? 0) - 0.25
                shape.setNumber("PinX", pinX, clearFormula: true)
                shape.setNumber("PinY", pinY, clearFormula: true)
                ids.append(shape.id)
                diagram.pages[self.pageIndex].shapes.append(shape)
            }
            self.selection = ids
        }
    }

    @objc func duplicate(_ sender: Any?) {
        let ids = selection
        guard !ids.isEmpty else { return }
        studioDocument.mutate("Duplicate") { diagram in
            let newIDs = DiagramEdit.duplicate(page: &diagram.pages[self.pageIndex], ids: ids)
            self.selection = newIDs
        }
    }

    @objc func deleteShapes(_ sender: Any?) {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        studioDocument.mutate("Delete") { diagram in
            DiagramEdit.delete(page: &diagram.pages[self.pageIndex], ids: ids)
        }
        selection = []
    }

    @objc func groupShapes(_ sender: Any?) {
        let ids = selection
        studioDocument.mutate("Group") { diagram in
            if let id = DiagramEdit.group(page: &diagram.pages[self.pageIndex], ids: ids, theme: diagram.theme, colors: diagram.colors) {
                self.selection = [id]
            }
        }
    }

    @objc func ungroupShapes(_ sender: Any?) {
        let ids = selection
        studioDocument.mutate("Ungroup") { diagram in
            self.selection = DiagramEdit.ungroup(page: &diagram.pages[self.pageIndex], ids: ids)
        }
    }

    @objc func bringToFront(_ sender: Any?) { order(.front) }
    @objc func sendToBack(_ sender: Any?) { order(.back) }
    @objc func alignLeft(_ sender: Any?) { align(.left) }
    @objc func alignCenter(_ sender: Any?) { align(.center) }
    @objc func alignRight(_ sender: Any?) { align(.right) }
    @objc func alignTop(_ sender: Any?) { align(.top) }
    @objc func alignMiddle(_ sender: Any?) { align(.middle) }
    @objc func alignBottom(_ sender: Any?) { align(.bottom) }
    @objc func distributeHorizontal(_ sender: Any?) { distribute(.horizontal) }
    @objc func distributeVertical(_ sender: Any?) { distribute(.vertical) }

    @objc func toggleBold(_ sender: Any?) { toggleStyle(bit: 1) }
    @objc func toggleItalic(_ sender: Any?) { toggleStyle(bit: 2) }
    @objc func toggleUnderline(_ sender: Any?) { toggleStyle(bit: 4) }
    @objc func alignTextLeft(_ sender: Any?) { setTextAlign(0) }
    @objc func alignTextCenter(_ sender: Any?) { setTextAlign(1) }
    @objc func alignTextRight(_ sender: Any?) { setTextAlign(2) }

    @objc func applyQuickStyle(_ sender: NSButton) {
        let index = max(0, min(quickStyles.count - 1, sender.tag))
        let style = quickStyles[index]
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        studioDocument.mutate("Shape Style") { diagram in
            DiagramEdit.setFill(page: &diagram.pages[self.pageIndex], ids: ids, color: style.fill)
            DiagramEdit.setLine(page: &diagram.pages[self.pageIndex], ids: ids, color: style.line)
            DiagramEdit.setFont(page: &diagram.pages[self.pageIndex], ids: ids, color: style.text)
        }
    }

    @objc func applyPageSize(_ sender: Any?) {
        let sizes: [(Double, Double)] = [(11, 8.5), (8.5, 11), (17, 11), (8.27, 11.69), (11.69, 8.27), (16.54, 11.69)]
        let index: Int
        if let popup = sender as? NSPopUpButton {
            index = popup.indexOfSelectedItem
        } else if let button = sender as? NSButton {
            index = button.tag
        } else {
            return
        }
        let size = sizes[max(0, min(sizes.count - 1, index))]
        studioDocument.mutate("Page Size") { diagram in
            diagram.pages[self.pageIndex].width = size.0
            diagram.pages[self.pageIndex].height = size.1
        }
    }

    @objc func addPage(_ sender: Any?) {
        studioDocument.mutate("Insert Page") { diagram in
            let id = (diagram.pages.map(\.id).max() ?? 0) + 1
            var page = DiagramPage(id: id, name: "Page-\(diagram.pages.count + 1)")
            page.partName = "visio/pages/page\(diagram.pages.count + 1).xml"
            diagram.pages.append(page)
            self.pageIndex = diagram.pages.count - 1
        }
    }

    @objc func duplicatePage(_ sender: Any?) {
        studioDocument.mutate("Duplicate Page") { diagram in
            var page = diagram.pages[self.pageIndex]
            page.id = (diagram.pages.map(\.id).max() ?? 0) + 1
            page.name = page.name + " copy"
            page.nameU = page.name
            page.partName = "visio/pages/page\(diagram.pages.count + 1).xml"
            page.pageSheet = nil
            diagram.pages.append(page)
            self.pageIndex = diagram.pages.count - 1
        }
    }

    @objc func renamePage(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Rename page"
        alert.informativeText = "Type the new page name."
        let field = NSTextField(string: currentPage().name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        studioDocument.mutate("Rename Page") { diagram in
            diagram.pages[self.pageIndex].name = name
            diagram.pages[self.pageIndex].nameU = name
        }
    }

    @objc func deletePage(_ sender: Any?) {
        guard diagram.pages.count > 1 else { return }
        studioDocument.mutate("Delete Page") { diagram in
            diagram.pages.remove(at: self.pageIndex)
            self.pageIndex = min(self.pageIndex, diagram.pages.count - 1)
        }
        selection = []
    }

    @objc func selectPage(_ sender: NSButton) {
        pageIndex = sender.tag
        selection = []
        syncFromDocument(rebuildPanels: true)
        studioDocument.diagram.activePageIndex = pageIndex
    }

    @objc func zoomIn(_ sender: Any?) { zoom = min(4, zoom * 1.2) }
    @objc func zoomOut(_ sender: Any?) { zoom = max(0.15, zoom / 1.2) }
    @objc func zoomActual(_ sender: Any?) { zoom = 1 }
    @objc func zoomFit(_ sender: Any?) {
        let visible = scroll.contentView.bounds.size
        let page = currentPage()
        let pixelsPerInch = canvas.pixelsPerInch / max(canvas.zoom, 0.001)
        guard page.width > 0, page.height > 0, pixelsPerInch > 0 else { return }
        let fit = min(
            (visible.width - 80) / (CGFloat(page.width) * pixelsPerInch),
            (visible.height - 80) / (CGFloat(page.height) * pixelsPerInch)
        )
        zoom = min(4, max(0.15, fit))
    }
    @objc func toggleGrid(_ sender: Any?) { showGrid.toggle() }
    @objc func toggleRulers(_ sender: Any?) {
        showRulers.toggle()
        applyRulers()
    }
    func toggleFormat() {
        formatVisible.toggle()
        applyFormatVisibility()
    }

    @objc func toggleFormat(_ sender: Any?) {
        toggleFormat()
    }
    @objc func toggleSnap(_ sender: Any?) {
        snapEnabled.toggle()
        canvas.snapEnabled = snapEnabled
    }
    @objc func toggleConnections(_ sender: Any?) { showConnections.toggle() }

    @objc func exportPNG(_ sender: Any?) { export(png: true) }
    @objc func exportPDF(_ sender: Any?) { export(png: false) }

    private func order(_ kind: OrderKind) {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        studioDocument.mutate("Reorder") { diagram in
            DiagramEdit.order(page: &diagram.pages[self.pageIndex], ids: ids, kind: kind)
        }
    }

    private func align(_ kind: AlignKind) {
        let ids = selection
        guard ids.count > 1 else { return }
        studioDocument.mutate("Align") { diagram in
            DiagramEdit.align(page: &diagram.pages[self.pageIndex], ids: ids, kind: kind, theme: diagram.theme, colors: diagram.colors)
        }
    }

    private func distribute(_ kind: DistributeKind) {
        let ids = selection
        studioDocument.mutate("Distribute") { diagram in
            DiagramEdit.distribute(page: &diagram.pages[self.pageIndex], ids: ids, kind: kind, theme: diagram.theme, colors: diagram.colors)
        }
    }

    private func toggleStyle(bit: Int) {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        studioDocument.mutate("Font Style") { diagram in
            DiagramEdit.toggleFontBit(page: &diagram.pages[self.pageIndex], ids: ids, bit: bit)
        }
    }

    private func setTextAlign(_ align: Int) {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        studioDocument.mutate("Align Text") { diagram in
            DiagramEdit.setFont(page: &diagram.pages[self.pageIndex], ids: ids, align: align)
        }
    }

    private func export(png: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [png ? .png : .pdf]
        panel.nameFieldStringValue = (currentPage().name) + (png ? ".png" : ".pdf")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let page = currentPage()
        if png {
            if let data = PageDrawing.renderPNG(page: page, theme: diagram.theme, colors: diagram.colors, pixelsPerInch: 144, margin: 0) {
                try? data.write(to: url)
            }
        } else {
            var media = CGRect(x: 0, y: 0, width: page.width * 72, height: page.height * 72)
            guard let consumer = CGDataConsumer(url: url as CFURL), let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return }
            context.beginPDFPage(nil)
            context.scaleBy(x: 72, y: 72)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: page.width, height: page.height))
            PageDrawing.draw(page: page, theme: diagram.theme, colors: diagram.colors, in: context, pixelsPerInch: 72)
            context.endPDFPage()
            context.closePDF()
        }
    }

    private func reassign(_ shape: inout ShapeNode, next: inout Int) {
        shape.id = next
        shape.original = nil
        shape.detached = true
        next += 1
        for index in shape.children.indices {
            shape.children[index].parentId = shape.id
            reassign(&shape.children[index], next: &next)
        }
    }

}

private final class PageTabButton: NSButton {
    var filled = false
    var fillColor: NSColor = .clear
    var titleColor: NSColor = .black

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if filled {
            fillColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let font = self.font ?? NSFont.systemFont(ofSize: 13)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: titleColor
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: origin, withAttributes: attributes)
    }
}

final class RulerView: NSView {
    var horizontal: Bool
    var pixelsPerInch: CGFloat = 100
    var zeroOffset: CGFloat = 48
    var scaleDirection: CGFloat = 1
    var marker: CGFloat?

    init(horizontal: Bool) {
        self.horizontal = horizontal
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
        StudioChrome.hairline.setStroke()
        let border = NSBezierPath()
        if horizontal {
            border.move(to: NSPoint(x: 0, y: bounds.maxY))
            border.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        } else {
            border.move(to: NSPoint(x: bounds.maxX, y: 0))
            border.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        }
        border.stroke()
        let length: CGFloat = horizontal ? bounds.width : bounds.height
        let step = pixelsPerInch / 4
        guard step > 3 else { return }
        var position = zeroOffset.truncatingRemainder(dividingBy: step)
        if position < 0 { position += step }
        let path = NSBezierPath()
        NSColor.darkGray.setStroke()
        NSColor.darkGray.setFill()
        while position < length {
            let inches = (position - zeroOffset) / pixelsPerInch * scaleDirection
            let major = abs(inches.truncatingRemainder(dividingBy: 1)) < 0.02 || abs(abs(inches.truncatingRemainder(dividingBy: 1)) - 1) < 0.02
            let tick: CGFloat = major ? 12 : 6
            if horizontal {
                path.move(to: NSPoint(x: position, y: bounds.maxY))
                path.line(to: NSPoint(x: position, y: bounds.maxY - tick))
                if major {
                    let text = String(format: "%.0f", inches.rounded()) as NSString
                    text.draw(at: NSPoint(x: position + 2, y: 1), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray])
                }
            } else {
                path.move(to: NSPoint(x: bounds.maxX, y: position))
                path.line(to: NSPoint(x: bounds.maxX - tick, y: position))
                if major {
                    let text = String(format: "%.0f", inches.rounded()) as NSString
                    text.draw(at: NSPoint(x: 1, y: position + 2), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray])
                }
            }
            position += step
        }
        path.stroke()
        if let marker {
            NSColor.systemRed.setStroke()
            let mark = NSBezierPath()
            if horizontal {
                mark.move(to: NSPoint(x: marker, y: 0))
                mark.line(to: NSPoint(x: marker, y: bounds.maxY))
            } else {
                mark.move(to: NSPoint(x: 0, y: marker))
                mark.line(to: NSPoint(x: bounds.maxX, y: marker))
            }
            mark.stroke()
        }
    }
}
