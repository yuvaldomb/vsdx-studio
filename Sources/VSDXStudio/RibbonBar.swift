import AppKit

// diagrams.net classic chrome (geEditor geClassic): menu row plus icon toolbar.
private enum DiagramBarColor {
    static let bar = color("#f1f3f4")
    static let ink = color("#3f3f3f")
    static let hover = color("#e2e2e2")
    static let orange = color("#f08705")
    static let statusText = color("#b62623")
    static let statusFill = color("#eacccc")
    static let share = color("#c2e7ff")
    static let hairline = color("#dadada")
    static let separator = color("#e5e5e5")
    static let fillSwatch = color("#dae8fc")
    static let lineSwatch = color("#6c8ebf")

    private static func color(_ hex: String) -> NSColor {
        NSColor(hex: hex) ?? .black
    }
}

final class RibbonBar: NSView {
    var onShapes: (() -> Void)?
    var onFormat: (() -> Void)?
    var onCollapse: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Untitled Diagram")
    private let statusPill = StatusPill()
    private let zoomButton = ChromeButton(kind: .zoom)
    private var actionTarget: AnyObject?
    private var didInstall = false
    private var highlightButtons: [EditorTool: ChromeButton] = [:]
    private var menus: [ObjectIdentifier: NSMenu] = [:]
    private var fillColor = DiagramBarColor.fillSwatch
    private var lineColor = DiagramBarColor.lineSwatch
    private weak var colorSender: NSButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DiagramBarColor.bar.cgColor
        titleLabel.font = NSFont.systemFont(ofSize: 18)
        titleLabel.textColor = DiagramBarColor.ink
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(rawValue: 700), for: .horizontal)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        zoomButton.setLabel("100%", size: 14, weight: .regular, monospaced: true)
        zoomButton.toolTip = "Zoom"
        zoomButton.widthAnchor.constraint(equalToConstant: 62).isActive = true
        zoomButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 102)
    }

    func install(target: AnyObject) {
        actionTarget = target
        statusPill.onClick = { [weak self] in self?.saveFromStatus() }
        guard !didInstall else { return }
        didInstall = true

        let menuRow = barRow()
        let toolRow = barRow()
        addSubview(menuRow)
        addSubview(toolRow)
        NSLayoutConstraint.activate([
            menuRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            menuRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            menuRow.topAnchor.constraint(equalTo: topAnchor),
            menuRow.heightAnchor.constraint(equalToConstant: 60),
            toolRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolRow.topAnchor.constraint(equalTo: menuRow.bottomAnchor),
            toolRow.heightAnchor.constraint(equalToConstant: 42)
        ])

        let mark = AppMark()
        let brand = horizontalStack([mark, titleLabel], spacing: 8)
        brand.setContentHuggingPriority(.required, for: .horizontal)
        let menuCluster = horizontalStack(menuButtons(), spacing: 2)
        menuCluster.setContentHuggingPriority(.required, for: .horizontal)
        menuCluster.setContentCompressionResistancePriority(.required, for: .horizontal)
        let cluster = horizontalStack([brand, menuCluster, statusPill], spacing: 12)
        cluster.setContentHuggingPriority(.required, for: .horizontal)
        cluster.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(rawValue: 750), for: .horizontal)

        let share = ChromeButton(kind: .share)
        share.setLabel("Share", size: 14, weight: .semibold)
        share.toolTip = "Share"
        share.isEnabled = false
        share.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let menuStack = horizontalStack([cluster, flexibleSpace(), share], spacing: 8)
        menuStack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 12)
        menuStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        center(menuStack, in: menuRow)

        let tools = toolItems()
        let toolStack = horizontalStack(tools, spacing: 2)
        toolStack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 8)
        toolStack.heightAnchor.constraint(equalToConstant: 28).isActive = true
        toolStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        center(toolStack, in: toolRow)
        hairline(in: toolRow, top: true)
        hairline(in: toolRow, top: false)
        update(tool: .pointer)
    }

    func update(tool: EditorTool) {
        for (item, button) in highlightButtons {
            button.isChosen = item == tool
        }
    }

    func showTab(_ index: Int) {}

    func setDocumentTitle(_ title: String) {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.stringValue = value.isEmpty ? "Untitled Diagram" : value
        titleLabel.invalidateIntrinsicContentSize()
    }

    func setStatus(_ text: String?) {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        statusPill.label.stringValue = value
        statusPill.isHidden = value.isEmpty
    }

    func setZoomPercent(_ percent: Double) {
        let value = percent.isFinite ? Int(percent.rounded()) : 100
        zoomButton.setLabel("\(value)%", size: 14, weight: .regular, monospaced: true)
    }

    func overlappingButtons() -> [String] {
        let frames = buttonFrames()
        var clashes: [String] = []
        for index in frames.indices {
            for other in (index + 1)..<frames.count where frames[index].1.intersects(frames[other].1) {
                let a = frames[index]
                let b = frames[other]
                clashes.append(String(format: "%@ (%.0f,%.0f) overlaps %@ (%.0f,%.0f)", a.0, a.1.minX, a.1.width, b.0, b.1.minX, b.1.width))
            }
        }
        return clashes
    }

    func groupDebug() -> String {
        buttonFrames()
            .sorted { lhs, rhs in
                if abs(lhs.1.minY - rhs.1.minY) > 8 { return lhs.1.minY > rhs.1.minY }
                return lhs.1.minX < rhs.1.minX
            }
            .map { String(format: "%@=%.0f", $0.0, $0.1.minX) }
            .joined(separator: " | ")
    }

    private func buttonFrames() -> [(String, NSRect)] {
        layoutSubtreeIfNeeded()
        var found: [(String, NSRect)] = []
        func walk(_ view: NSView) {
            if view.isHidden { return }
            if let button = view as? NSButton, button.bounds.width > 4, button.bounds.height > 4 {
                let frame = button.convert(button.bounds, to: self).insetBy(dx: 1, dy: 1)
                if frame.width > 1, frame.height > 1 {
                    let tip = button.toolTip ?? ""
                    let name = tip.isEmpty ? (button.title.isEmpty ? "button" : button.title) : tip
                    found.append((name, frame))
                }
            }
            for child in view.subviews { walk(child) }
        }
        walk(self)
        return found
    }

    private func barRow() -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.backgroundColor = DiagramBarColor.bar.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func center(_ stack: NSStackView, in row: NSView) {
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
    }

    private func hairline(in row: NSView, top: Bool) {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = DiagramBarColor.hairline.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(line)
        var pins = [
            line.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1)
        ]
        pins.append(top
            ? line.topAnchor.constraint(equalTo: row.topAnchor)
            : line.bottomAnchor.constraint(equalTo: row.bottomAnchor))
        NSLayoutConstraint.activate(pins)
    }

    private func horizontalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .gravityAreas
        stack.spacing = spacing
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func flexibleSpace() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        view.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        view.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return view
    }

    private func separator() -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.widthAnchor.constraint(equalToConstant: 9).isActive = true
        wrap.heightAnchor.constraint(equalToConstant: 20).isActive = true
        wrap.setContentHuggingPriority(.required, for: .horizontal)
        wrap.setContentCompressionResistancePriority(.required, for: .horizontal)
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = DiagramBarColor.separator.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 20),
            line.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: wrap.centerYAnchor)
        ])
        return wrap
    }

    private func menuButtons() -> [NSView] {
        [
            menuButton("File", fileMenu()),
            menuButton("Edit", editMenu()),
            menuButton("View", viewMenu()),
            menuButton("Arrange", arrangeMenu()),
            menuButton("Extras", extrasMenu()),
            menuButton("Help", helpMenu())
        ]
    }

    private func menuButton(_ title: String, _ menu: NSMenu) -> ChromeButton {
        let button = ChromeButton(kind: .text)
        button.setLabel(title, size: 14, weight: .regular)
        button.toolTip = title
        button.target = self
        button.action = #selector(showMenu(_:))
        menus[ObjectIdentifier(button)] = menu
        return button
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        let docs = NSDocumentController.shared
        menu.addItem(menuItem("New", #selector(NSDocumentController.newDocument(_:)), target: docs))
        menu.addItem(menuItem("Open…", #selector(NSDocumentController.openDocument(_:)), target: docs))
        menu.addItem(.separator())
        menu.addItem(menuItem("Save", #selector(NSDocument.save(_:))))
        menu.addItem(menuItem("Save As…", #selector(NSDocument.saveAs(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Export PNG…", #selector(StudioWindowController.exportPNG(_:))))
        menu.addItem(menuItem("Export PDF…", #selector(StudioWindowController.exportPDF(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Close", #selector(NSWindow.performClose(_:))))
        return menu
    }

    private func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(menuItem("Undo", Selector(("undo:"))))
        menu.addItem(menuItem("Redo", Selector(("redo:"))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Cut", #selector(StudioWindowController.cut(_:))))
        menu.addItem(menuItem("Copy", #selector(StudioWindowController.copy(_:))))
        menu.addItem(menuItem("Paste", #selector(StudioWindowController.paste(_:))))
        menu.addItem(menuItem("Delete", #selector(StudioWindowController.deleteShapes(_:))))
        menu.addItem(menuItem("Duplicate", #selector(StudioWindowController.duplicate(_:))))
        menu.addItem(menuItem("Select All", #selector(StudioWindowController.selectAll(_:))))
        return menu
    }

    private func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(menuItem("Zoom In", #selector(StudioWindowController.zoomIn(_:))))
        menu.addItem(menuItem("Zoom Out", #selector(StudioWindowController.zoomOut(_:))))
        menu.addItem(menuItem("Actual Size", #selector(StudioWindowController.zoomActual(_:))))
        menu.addItem(menuItem("Fit Page", #selector(StudioWindowController.zoomFit(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Grid", #selector(StudioWindowController.toggleGrid(_:))))
        menu.addItem(menuItem("Rulers", #selector(StudioWindowController.toggleRulers(_:))))
        menu.addItem(menuItem("Snap", #selector(StudioWindowController.toggleSnap(_:))))
        menu.addItem(menuItem("Connection Points", #selector(StudioWindowController.toggleConnections(_:))))
        return menu
    }

    private func arrangeMenu() -> NSMenu {
        let menu = NSMenu(title: "Arrange")
        menu.addItem(menuItem("To Front", resolved("orderFront:", fallback: #selector(StudioWindowController.bringToFront(_:)))))
        menu.addItem(menuItem("To Back", resolved("orderBack:", fallback: #selector(StudioWindowController.sendToBack(_:)))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Group", #selector(StudioWindowController.groupShapes(_:))))
        menu.addItem(menuItem("Ungroup", #selector(StudioWindowController.ungroupShapes(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Align Left", #selector(StudioWindowController.alignLeft(_:))))
        menu.addItem(menuItem("Align Center", #selector(StudioWindowController.alignCenter(_:))))
        menu.addItem(menuItem("Align Right", #selector(StudioWindowController.alignRight(_:))))
        menu.addItem(menuItem("Align Top", #selector(StudioWindowController.alignTop(_:))))
        menu.addItem(menuItem("Align Middle", #selector(StudioWindowController.alignMiddle(_:))))
        menu.addItem(menuItem("Align Bottom", #selector(StudioWindowController.alignBottom(_:))))
        menu.addItem(menuItem("Distribute Horizontally", #selector(StudioWindowController.distributeHorizontal(_:))))
        menu.addItem(menuItem("Distribute Vertically", #selector(StudioWindowController.distributeVertical(_:))))
        return menu
    }

    private func extrasMenu() -> NSMenu {
        let menu = NSMenu(title: "Extras")
        menu.addItem(menuItem("Add Page", #selector(StudioWindowController.addPage(_:))))
        menu.addItem(menuItem("Duplicate Page", #selector(StudioWindowController.duplicatePage(_:))))
        menu.addItem(menuItem("Rename Page", #selector(StudioWindowController.renamePage(_:))))
        menu.addItem(menuItem("Delete Page", #selector(StudioWindowController.deletePage(_:))))
        return menu
    }

    private func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(menuItem("About VSDX Studio", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp))
        return menu
    }

    private func styleItem(_ title: String, tag: Int) -> NSMenuItem {
        let item = menuItem(title, #selector(StudioWindowController.chooseConnectorStyle(_:)))
        item.tag = tag
        return item
    }

    private func menuItem(_ title: String, _ action: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if let target {
            item.target = target
        } else if let actionTarget, actionTarget.responds(to: action) {
            item.target = actionTarget
        }
        return item
    }

    private func toolItems() -> [NSView] {
        let hand = icon("Pan", ["hand.raised", "hand.raised.fill"])
        hand.identifier = NSUserInterfaceItemIdentifier("pointer")
        bind(hand, #selector(StudioWindowController.chooseTool(_:)))
        highlightButtons[.pointer] = hand

        let zoomIn = icon("Zoom In", ["plus.magnifyingglass", "plus.circle"])
        bind(zoomIn, #selector(StudioWindowController.zoomIn(_:)))
        let zoomOut = icon("Zoom Out", ["minus.magnifyingglass", "minus.circle"])
        bind(zoomOut, #selector(StudioWindowController.zoomOut(_:)))

        let undo = icon("Undo", ["arrow.uturn.backward", "arrow.counterclockwise"])
        bind(undo, resolved("undo:"))
        let redo = icon("Redo", ["arrow.uturn.forward", "arrow.clockwise"])
        bind(redo, resolved("redo:"))

        let delete = icon("Delete", ["trash", "delete.left"])
        bind(delete, #selector(StudioWindowController.deleteShapes(_:)))

        let front = icon("To Front", ["square.3.layers.3d.top.filled", "square.2.layers.3d.top.filled"])
        bind(front, resolved("orderFront:", fallback: #selector(StudioWindowController.bringToFront(_:))))
        let back = icon("To Back", ["square.3.layers.3d.bottom.filled", "square.2.layers.3d.bottom.filled"])
        bind(back, resolved("orderBack:", fallback: #selector(StudioWindowController.sendToBack(_:))))

        let fill = icon("Fill Color", ["paintbucket.fill", "paintbucket", "drop.fill"], point: 16)
        fill.tag = 1
        fill.identifier = NSUserInterfaceItemIdentifier("fill-color")
        fill.target = self
        fill.action = #selector(colorClicked(_:))
        addSwatch(to: fill, color: fillColor)
        let line = icon("Line Color", ["pencil", "pencil.tip"], point: 16)
        line.tag = 2
        line.identifier = NSUserInterfaceItemIdentifier("line-color")
        line.target = self
        line.action = #selector(colorClicked(_:))
        addSwatch(to: line, color: lineColor)
        let shadow = icon("Shadow", ["square.fill.on.square.fill", "square.on.square"])
        shadow.target = self
        shadow.action = #selector(shadowClicked(_:))

        let connector = icon("Connection", ["arrow.triangle.turn.up.right.diamond", "arrow.turn.up.right"])
        connector.identifier = NSUserInterfaceItemIdentifier("connector")
        highlightButtons[.connector] = connector
        let connectionMenu = NSMenu(title: "Connection")
        connectionMenu.addItem(styleItem("Straight", tag: 0))
        connectionMenu.addItem(styleItem("Orthogonal", tag: 1))
        connectionMenu.addItem(styleItem("Simple", tag: 3))
        connectionMenu.addItem(styleItem("Curved", tag: 2))
        menus[ObjectIdentifier(connector)] = connectionMenu
        connector.target = self
        connector.action = #selector(showMenu(_:))
        let waypoints = icon("Waypoints", ["point.3.connected.trianglepath.dotted", "point.topleft.down.to.point.bottomright.curvepath"])
        let waypointMenu = NSMenu(title: "Waypoints")
        waypointMenu.addItem(menuItem("Clear Waypoints", #selector(StudioWindowController.clearWaypoints(_:))))
        menus[ObjectIdentifier(waypoints)] = waypointMenu
        waypoints.target = self
        waypoints.action = #selector(showMenu(_:))

        let rectangle = icon("Rectangle", ["rectangle", "square"])
        rectangle.identifier = NSUserInterfaceItemIdentifier("rectangle")
        bind(rectangle, #selector(StudioWindowController.chooseTool(_:)))
        highlightButtons[.rectangle] = rectangle
        let shapes = icon("Shapes", ["diamond", "rhombus", "square.on.circle"])
        shapes.target = self
        shapes.action = #selector(shapesClicked(_:))
        let table = icon("Table", ["tablecells", "square.grid.3x2"])
        bind(table, #selector(StudioWindowController.insertTable(_:)))

        let freehand = icon("Freehand", ["scribble", "pencil.tip", "pencil.and.scribble"])
        freehand.identifier = NSUserInterfaceItemIdentifier("line")
        bind(freehand, #selector(StudioWindowController.chooseTool(_:)))
        highlightButtons[.line] = freehand
        let generate = icon("Generate", ["sparkles", "wand.and.stars"])
        generate.isEnabled = false
        let layout = icon("Layout", ["square.grid.3x3", "rectangle.3.group"])
        layout.isEnabled = false

        let fullscreen = icon("Full Screen", ["arrow.up.left.and.arrow.down.right", "arrow.up.backward.and.arrow.down.forward"])
        bind(fullscreen, #selector(NSWindow.toggleFullScreen(_:)))
        let format = icon("Format", ["sidebar.right", "sidebar.trailing", "slider.horizontal.3"])
        format.target = self
        format.action = #selector(formatClicked(_:))
        let collapse = icon("Collapse", ["chevron.up", "chevron.compact.up"])
        collapse.target = self
        collapse.action = #selector(collapseClicked(_:))

        let zoomMenu = NSMenu(title: "Zoom")
        zoomMenu.addItem(menuItem("Zoom In", #selector(StudioWindowController.zoomIn(_:))))
        zoomMenu.addItem(menuItem("Zoom Out", #selector(StudioWindowController.zoomOut(_:))))
        zoomMenu.addItem(menuItem("Actual Size", #selector(StudioWindowController.zoomActual(_:))))
        zoomMenu.addItem(menuItem("Fit Page", #selector(StudioWindowController.zoomFit(_:))))
        menus[ObjectIdentifier(zoomButton)] = zoomMenu
        zoomButton.target = self
        zoomButton.action = #selector(showMenu(_:))

        return [
            hand, separator(),
            zoomButton, separator(),
            zoomIn, zoomOut, separator(),
            undo, redo, separator(),
            delete, separator(),
            front, back, separator(),
            fill, line, shadow, separator(),
            connector, waypoints, separator(),
            rectangle, shapes, table, separator(),
            freehand, generate, layout,
            flexibleSpace(),
            fullscreen, format, collapse
        ]
    }

    private func icon(_ tip: String, _ names: [String], point: CGFloat = 18) -> ChromeButton {
        let button = ChromeButton(kind: .icon)
        button.toolTip = tip
        button.image = symbol(names, description: tip, point: point)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func addSwatch(to button: NSButton, color: NSColor) {
        let stripe = NSView()
        stripe.identifier = NSUserInterfaceItemIdentifier("swatch")
        stripe.wantsLayer = true
        stripe.layer?.backgroundColor = color.cgColor
        stripe.layer?.cornerRadius = 1
        stripe.layer?.borderWidth = 0.5
        stripe.layer?.borderColor = NSColor(white: 0, alpha: 0.28).cgColor
        stripe.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(stripe)
        NSLayoutConstraint.activate([
            stripe.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stripe.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -3),
            stripe.widthAnchor.constraint(equalToConstant: 14),
            stripe.heightAnchor.constraint(equalToConstant: 3)
        ])
    }

    private func symbol(_ names: [String], description: String, point: CGFloat) -> NSImage? {
        for name in names {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: description) else { continue }
            image.isTemplate = true
            image.size = NSSize(width: point, height: point)
            return image
        }
        return nil
    }

    private func resolved(_ name: String, fallback: Selector? = nil) -> Selector {
        let primary = NSSelectorFromString(name)
        if actionTarget?.responds(to: primary) == true { return primary }
        if let fallback, actionTarget?.responds(to: fallback) == true { return fallback }
        return primary
    }

    private func bind(_ button: NSButton, _ selector: Selector) {
        button.action = selector
        if let actionTarget, actionTarget.responds(to: selector) {
            button.target = actionTarget
        } else {
            button.target = nil
        }
    }

    @objc private func showMenu(_ sender: NSButton) {
        guard let menu = menus[ObjectIdentifier(sender)] else { return }
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: sender)
        } else {
            menu.popUp(positioning: nil, at: .zero, in: sender)
        }
    }

    private func saveFromStatus() {
        let selector = #selector(NSDocument.save(_:))
        if let controller = actionTarget as? NSWindowController, let document = controller.document {
            document.save(self)
            return
        }
        if let actionTarget, actionTarget.responds(to: selector) {
            _ = NSApp.sendAction(selector, to: actionTarget, from: self)
            return
        }
        _ = NSApp.sendAction(selector, to: nil, from: self)
    }

    @objc private func shapesClicked(_ sender: Any?) {
        onShapes?()
    }

    @objc private func formatClicked(_ sender: Any?) {
        (sender as? ChromeButton)?.isChosen.toggle()
        onFormat?()
    }

    @objc private func collapseClicked(_ sender: Any?) {
        onCollapse?()
    }

    @objc private func shadowClicked(_ sender: Any?) {
        let selector = NSSelectorFromString("toggleShadow:")
        if let actionTarget, actionTarget.responds(to: selector) {
            _ = NSApp.sendAction(selector, to: actionTarget, from: sender)
            return
        }
        (sender as? ChromeButton)?.isChosen.toggle()
    }

    @objc private func colorClicked(_ sender: NSButton) {
        let names = sender.tag == 2
            ? ["pickStroke:", "pickLine:", "setLineColor:", "lineColor:", "chooseLineColor:"]
            : ["pickFill:", "setFillColor:", "fillColor:", "chooseFillColor:"]
        if let actionTarget {
            for name in names {
                let selector = NSSelectorFromString(name)
                if actionTarget.responds(to: selector) {
                    _ = NSApp.sendAction(selector, to: actionTarget, from: sender)
                    return
                }
            }
        }
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = sender.tag == 2 ? lineColor : fillColor
        colorSender = sender
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(sender)
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        guard let button = colorSender else { return }
        if button.tag == 2 {
            lineColor = panel.color
        } else {
            fillColor = panel.color
        }
        button.subviews.first { $0.identifier?.rawValue == "swatch" }?.layer?.backgroundColor = panel.color.cgColor
    }
}

private final class AppMark: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DiagramBarColor.orange.cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 32).isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        toolTip = "VSDX Studio"
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 32, height: 36) }

    override func draw(_ dirtyRect: NSRect) {
        DiagramBarColor.orange.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        NSColor.white.setStroke()
        NSColor.white.setFill()
        let line = NSBezierPath()
        line.lineWidth = 1.5
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: 10, y: 23))
        line.line(to: NSPoint(x: 16, y: 13))
        line.move(to: NSPoint(x: 22, y: 23))
        line.line(to: NSPoint(x: 16, y: 13))
        line.stroke()
        for center in [NSPoint(x: 10, y: 23), NSPoint(x: 22, y: 23), NSPoint(x: 16, y: 13)] {
            NSBezierPath(ovalIn: NSRect(x: center.x - 2.3, y: center.y - 2.3, width: 4.6, height: 4.6)).fill()
        }
    }
}

private final class StatusPill: NSView {
    let label = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DiagramBarColor.statusFill.cgColor
        layer?.masksToBounds = true
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = DiagramBarColor.statusText
        label.isSelectable = false
        label.cell?.refusesFirstResponder = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(label)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.contains(local) else { return }
        onClick?()
    }
}

private final class ChromeButton: NSButton {
    enum Kind {
        case icon
        case text
        case zoom
        case share
    }

    let kind: Kind
    private let chromeCell = ChromeButtonCell(textCell: "")
    var isChosen = false {
        didSet { applyStyle() }
    }
    private var isHovered = false
    private var hoverArea: NSTrackingArea?

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        cell = chromeCell
        chromeCell.highlightsBy = []
        chromeCell.showsStateBy = []
        chromeCell.imageDimsWhenDisabled = false
        chromeCell.imageScaling = .scaleProportionallyDown
        chromeCell.alignment = .center
        chromeCell.isBordered = false
        chromeCell.refusesFirstResponder = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        applyStyle()
    }

    required init?(coder: NSCoder) {
        kind = .icon
        return nil
    }

    func setLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, monospaced: Bool = false) {
        let font = monospaced
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        title = text
        attributedTitle = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: DiagramBarColor.ink
        ])
        chromeCell.font = font
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        switch kind {
        case .icon:
            return NSSize(width: 28, height: 28)
        case .zoom:
            return NSSize(width: 62, height: 28)
        case .text:
            let size = attributedTitle.size()
            return NSSize(width: ceil(size.width) + 16, height: ceil(max(size.height, 14)) + 8)
        case .share:
            let size = attributedTitle.size()
            return NSSize(width: ceil(size.width) + 32, height: 32)
        }
    }

    override var acceptsFirstResponder: Bool { false }

    override var isEnabled: Bool {
        didSet { applyStyle() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        hoverArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard isEnabled else { return }
        isHovered = true
        applyStyle()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        applyStyle()
    }

    private func applyStyle() {
        let emphasized = isEnabled && (isHovered || isChosen)
        switch kind {
        case .icon:
            alphaValue = isEnabled ? 1 : 0.3
            contentTintColor = NSColor(white: 0, alpha: emphasized || !isEnabled ? 1 : 0.65)
            chromeCell.baseFill = .clear
            chromeCell.hoverFill = DiagramBarColor.hover
            chromeCell.corner = 6
            chromeCell.strokeColor = nil
            chromeCell.isHovered = emphasized
            imagePosition = .imageOnly
        case .text:
            alphaValue = 1
            contentTintColor = DiagramBarColor.ink
            chromeCell.baseFill = .clear
            chromeCell.hoverFill = DiagramBarColor.hover
            chromeCell.corner = 6
            chromeCell.strokeColor = nil
            chromeCell.isHovered = isHovered && isEnabled
            imagePosition = .noImage
        case .zoom:
            alphaValue = 1
            contentTintColor = DiagramBarColor.ink
            chromeCell.baseFill = .clear
            chromeCell.hoverFill = DiagramBarColor.hover
            chromeCell.corner = 6
            chromeCell.strokeColor = DiagramBarColor.hairline
            chromeCell.isHovered = isHovered && isEnabled
            imagePosition = .noImage
        case .share:
            alphaValue = 1
            contentTintColor = DiagramBarColor.ink
            chromeCell.baseFill = DiagramBarColor.share
            chromeCell.hoverFill = DiagramBarColor.share
            chromeCell.corner = 4
            chromeCell.strokeColor = nil
            chromeCell.isHovered = false
            imagePosition = .noImage
        }
        let fill = chromeCell.isHovered ? chromeCell.hoverFill : chromeCell.baseFill
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = chromeCell.corner
        layer?.masksToBounds = true
        needsDisplay = true
    }
}

private final class ChromeButtonCell: NSButtonCell {
    var baseFill: NSColor = .clear
    var hoverFill: NSColor = .clear
    var corner: CGFloat = 6
    var isHovered = false
    var strokeColor: NSColor?

    override init(textCell string: String) {
        super.init(textCell: string)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(withFrame frame: NSRect, in controlView: NSView) {
        let fill = isHovered ? hoverFill : baseFill
        if fill.alphaComponent > 0.001 {
            fill.setFill()
            NSBezierPath(roundedRect: frame, xRadius: corner, yRadius: corner).fill()
        }
        if let strokeColor {
            strokeColor.setStroke()
            let path = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: corner, yRadius: corner)
            path.lineWidth = 1
            path.stroke()
        }
        drawInterior(withFrame: frame, in: controlView)
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let text = attributedTitle.length > 0 ? attributedTitle : title
        let size = text.size()
        let rect = NSRect(
            x: floor(frame.midX - size.width / 2),
            y: floor(frame.midY - size.height / 2),
            width: ceil(size.width),
            height: ceil(size.height)
        )
        text.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
        return rect
    }
}
