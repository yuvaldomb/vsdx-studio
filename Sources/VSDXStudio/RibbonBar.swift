import AppKit

final class RibbonBar: NSView {
    private let tabRow = NSStackView()
    private let contentHost = NSView()
    private var tabButtons: [NSButton] = []
    private var pages: [NSView] = []
    private var toolButtons: [EditorTool: CommandButton] = [:]
    private var selectedTab = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor

        tabRow.orientation = .horizontal
        tabRow.alignment = .centerY
        tabRow.spacing = 2
        tabRow.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        tabRow.setContentHuggingPriority(.required, for: .horizontal)

        let tabSpacer = NSView()
        tabSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tabRow)
        addSubview(line)
        addSubview(contentHost)
        NSLayoutConstraint.activate([
            tabRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabRow.topAnchor.constraint(equalTo: topAnchor),
            tabRow.heightAnchor.constraint(equalToConstant: 34),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: tabRow.bottomAnchor),
            contentHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: line.bottomAnchor),
            contentHost.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        _ = tabSpacer
    }

    required init?(coder: NSCoder) { nil }

    func install(target: AnyObject) {
        let titles = ["Home", "Insert", "Design", "View"]
        let built = [home(target), insert(target), design(target), viewTab(target)]
        for (index, title) in titles.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(selectTab(_:)))
            button.tag = index
            button.bezelStyle = .recessed
            button.setButtonType(.momentaryChange)
            button.isBordered = false
            button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            tabButtons.append(button)
            tabRow.addArrangedSubview(button)
            pages.append(scrollable(built[index]))
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabRow.addArrangedSubview(spacer)
        showTab(0)
    }

    override func layout() {
        super.layout()
        if let scroll = contentHost.subviews.first as? NSScrollView {
            scroll.frame = contentHost.bounds
        }
        positionGroups()
    }

    private func positionGroups() {
        guard let scroll = contentHost.subviews.first as? NSScrollView,
              let document = scroll.documentView else { return }
        let height = max(scroll.bounds.height, contentHost.bounds.height, 80)
        var x: CGFloat = 8
        for group in document.subviews {
            let width = (group as? RibbonGroup)?.preferredWidth ?? 44
            group.frame = NSRect(x: x, y: 4, width: width, height: max(72, height - 8))
            x += width
        }
        document.frame = NSRect(x: 0, y: 0, width: max(x + 8, scroll.bounds.width), height: height)
    }

    func update(tool: EditorTool) {
        for (item, button) in toolButtons {
            button.isChosen = item == tool
        }
    }

    func showTab(_ index: Int) {
        selectedTab = index
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        guard pages.indices.contains(index) else { return }
        let page = pages[index]
        page.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            page.topAnchor.constraint(equalTo: contentHost.topAnchor),
            page.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor)
        ])
        for (buttonIndex, button) in tabButtons.enumerated() {
            let selected = buttonIndex == index
            button.font = NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
            button.contentTintColor = selected ? StudioChrome.accent : StudioChrome.title
        }
        layoutSubtreeIfNeeded()
        positionGroups()
    }

    func overlappingButtons() -> [String] {
        layoutSubtreeIfNeeded()
        var found: [(String, NSRect)] = []
        func walk(_ view: NSView) {
            if view.isHidden { return }
            if let button = view as? NSButton, button.frame.width > 4, button.frame.height > 4, button.superview is NSStackView || button.superview === tabRow {
                let frame = button.convert(button.bounds, to: self).insetBy(dx: 1, dy: 1)
                found.append((button.title.isEmpty ? "swatch" : button.title, frame))
            }
            if let button = view as? CommandButton, button.frame.width > 4 {
                let frame = button.convert(button.bounds, to: self).insetBy(dx: 1, dy: 1)
                found.append((button.toolTip ?? "command", frame))
            }
            for child in view.subviews { walk(child) }
        }
        walk(self)
        var clashes: [String] = []
        for index in found.indices {
            for other in (index + 1)..<found.count where found[index].1.intersects(found[other].1) {
                let a = found[index].1
                let b = found[other].1
                clashes.append(String(format: "%@ (%.0f,%.0f) overlaps %@ (%.0f,%.0f)", found[index].0, a.minX, a.width, found[other].0, b.minX, b.width))
            }
        }
        return clashes
    }

    func groupDebug() -> String {
        guard let scroll = contentHost.subviews.first as? NSScrollView, let document = scroll.documentView else { return "no-scroll" }
        return document.subviews.map { view in
            let preferred = (view as? RibbonGroup)?.preferredWidth ?? -1
            return String(format: "x=%.0f w=%.0f pref=%.0f subs=%d", view.frame.minX, view.frame.width, preferred, view.subviews.count)
        }.joined(separator: " | ")
    }

    @objc private func selectTab(_ sender: NSButton) {
        showTab(sender.tag)
    }

    private func scrollable(_ row: NSView) -> NSView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = false
        let document = NSView()
        for group in Array(row.subviews) {
            group.removeFromSuperview()
            document.addSubview(group)
        }
        scroll.documentView = document
        return scroll
    }

    private func home(_ target: AnyObject) -> NSView {
        row([
            group("Clipboard", [
                command("Paste", "doc.on.clipboard", #selector(StudioWindowController.pasteShapes(_:)), target, width: 64),
                command("Copy", "doc.on.doc", #selector(NSText.copy(_:)), target, width: 64),
                command("Cut", "scissors", #selector(NSText.cut(_:)), target, width: 64)
            ]),
            group("Tools", [
                tool(.pointer, "Select", "cursorarrow", target),
                tool(.rectangle, "Rectangle", "rectangle", target),
                tool(.ellipse, "Ellipse", "oval", target),
                tool(.line, "Line", "line.diagonal", target),
                tool(.connector, "Connector", "arrow.triangle.turn.up.right.diamond", target),
                tool(.text, "Text", "character.textbox", target)
            ]),
            group("Arrange", [
                command("Front", "square.3.layers.3d.top.filled", #selector(StudioWindowController.bringToFront(_:)), target, width: 62),
                command("Back", "square.3.layers.3d.bottom.filled", #selector(StudioWindowController.sendToBack(_:)), target, width: 62),
                command("Group", "rectangle.3.group", #selector(StudioWindowController.groupShapes(_:)), target, width: 62),
                command("Ungroup", "rectangle.3.group.dashed", #selector(StudioWindowController.ungroupShapes(_:)), target, width: 70)
            ]),
            group("Font", [
                icon("Bold", "bold", #selector(StudioWindowController.toggleBold(_:)), target),
                icon("Italic", "italic", #selector(StudioWindowController.toggleItalic(_:)), target),
                icon("Underline", "underline", #selector(StudioWindowController.toggleUnderline(_:)), target),
                icon("Align Left", "text.alignleft", #selector(StudioWindowController.alignTextLeft(_:)), target),
                icon("Center", "text.aligncenter", #selector(StudioWindowController.alignTextCenter(_:)), target),
                icon("Align Right", "text.alignright", #selector(StudioWindowController.alignTextRight(_:)), target)
            ]),
            styleGroup(target)
        ])
    }

    private func insert(_ target: AnyObject) -> NSView {
        row([
            group("Pages", [
                command("Blank Page", "doc.badge.plus", #selector(StudioWindowController.addPage(_:)), target, width: 92),
                command("Duplicate", "doc.on.doc", #selector(StudioWindowController.duplicatePage(_:)), target, width: 84),
                command("Rename", "pencil", #selector(StudioWindowController.renamePage(_:)), target, width: 76),
                command("Delete", "trash", #selector(StudioWindowController.deletePage(_:)), target, width: 72)
            ]),
            group("Shapes", [
                tool(.text, "Text Box", "character.textbox", target),
                tool(.rectangle, "Rectangle", "rectangle", target),
                tool(.ellipse, "Ellipse", "oval", target),
                tool(.connector, "Connector", "arrow.triangle.turn.up.right.diamond", target)
            ])
        ])
    }

    private func design(_ target: AnyObject) -> NSView {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: ["Letter Landscape", "Letter Portrait", "Tabloid", "A4 Portrait", "A4 Landscape", "A3 Landscape"])
        popup.target = target
        popup.action = #selector(StudioWindowController.applyPageSize(_:))
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 180).isActive = true
        popup.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row([
            group("Page Size", [popup]),
            styleGroup(target, title: "Theme")
        ])
    }

    private func viewTab(_ target: AnyObject) -> NSView {
        row([
            group("Zoom", [
                command("Zoom In", "plus.magnifyingglass", #selector(StudioWindowController.zoomIn(_:)), target, width: 76),
                command("Zoom Out", "minus.magnifyingglass", #selector(StudioWindowController.zoomOut(_:)), target, width: 80),
                command("100%", "1.magnifyingglass", #selector(StudioWindowController.zoomActual(_:)), target, width: 68),
                command("Fit Page", "arrow.up.left.and.arrow.down.right", #selector(StudioWindowController.zoomFit(_:)), target, width: 76)
            ]),
            group("Show", [
                command("Grid", "grid", #selector(StudioWindowController.toggleGrid(_:)), target, width: 64),
                command("Rulers", "ruler", #selector(StudioWindowController.toggleRulers(_:)), target, width: 68),
                command("Snap", "scope", #selector(StudioWindowController.toggleSnap(_:)), target, width: 64),
                command("Connect", "smallcircle.filled.circle", #selector(StudioWindowController.toggleConnections(_:)), target, width: 76)
            ])
        ])
    }

    private func row(_ groups: [NSView]) -> NSView {
        let stack = NSStackView(views: groups)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.setContentHuggingPriority(.required, for: .horizontal)
        return stack
    }

    private func group(_ title: String, _ controls: [NSView]) -> NSView {
        let buttons = NSStackView(views: controls)
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 4
        buttons.edgeInsets = NSEdgeInsets(top: 2, left: 10, bottom: 0, right: 10)
        buttons.setContentCompressionResistancePriority(.required, for: .horizontal)

        let caption = NSTextField(labelWithString: title)
        caption.font = NSFont.systemFont(ofSize: 10)
        caption.textColor = StudioChrome.label
        caption.alignment = .center
        caption.setContentCompressionResistancePriority(.required, for: .horizontal)

        let column = NSStackView(views: [buttons, caption])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false

        let wrap = RibbonGroup()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(column)
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(separator)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            column.topAnchor.constraint(equalTo: wrap.topAnchor),
            column.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: column.trailingAnchor),
            separator.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 6),
            separator.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -6)
        ])
        wrap.setContentCompressionResistancePriority(.required, for: .horizontal)
        wrap.setContentHuggingPriority(.required, for: .horizontal)
        wrap.preferredWidth = max(measuredWidth(column) + 1, 44)
        return wrap
    }

    private func measuredWidth(_ view: NSView) -> CGFloat {
        if let stack = view as? NSStackView {
            if stack.orientation == .horizontal {
                var width = stack.edgeInsets.left + stack.edgeInsets.right
                for (index, item) in stack.arrangedSubviews.enumerated() {
                    if index > 0 { width += stack.spacing }
                    width += measuredWidth(item)
                }
                return width
            }
            return stack.arrangedSubviews.map(measuredWidth).max() ?? 0
        }
        let fixed = view.constraints.first {
            $0.firstAttribute == .width && $0.relation == .equal && $0.secondItem == nil
        }?.constant
        return fixed ?? 0
    }

    private func styleGroup(_ target: AnyObject, title: String = "Shape Styles") -> NSView {
        var swatches: [NSView] = []
        for (index, style) in quickStyles.enumerated() {
            let button = NSButton(title: "", target: target, action: #selector(StudioWindowController.applyQuickStyle(_:)))
            button.tag = index
            button.bezelStyle = .shadowlessSquare
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor(hex: style.fill)?.cgColor
            button.layer?.borderColor = NSColor(hex: style.line)?.cgColor
            button.layer?.borderWidth = 2
            button.layer?.cornerRadius = 3
            button.toolTip = "Apply this color"
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 18).isActive = true
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            swatches.append(button)
        }
        let top = NSStackView(views: Array(swatches.prefix(6)))
        let bottom = NSStackView(views: Array(swatches.dropFirst(6)))
        top.orientation = .horizontal
        bottom.orientation = .horizontal
        top.spacing = 4
        bottom.spacing = 4
        let grid = NSStackView(views: [top, bottom])
        grid.orientation = .vertical
        grid.spacing = 4
        grid.alignment = .leading
        return group(title, [grid])
    }

    private func command(_ title: String, _ symbol: String, _ action: Selector, _ target: AnyObject, width: CGFloat) -> CommandButton {
        CommandButton(title: title, symbol: symbolImage(symbol, title), target: target, action: action, width: width)
    }

    private func icon(_ title: String, _ symbol: String, _ action: Selector, _ target: AnyObject) -> NSButton {
        let button = NSButton(title: "", target: target, action: action)
        button.image = symbolImage(symbol, title)
        button.imagePosition = .imageOnly
        button.bezelStyle = .recessed
        button.toolTip = title
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    private func tool(_ tool: EditorTool, _ title: String, _ symbol: String, _ target: AnyObject) -> CommandButton {
        let button = command(title, symbol, #selector(StudioWindowController.chooseTool(_:)), target, width: 70)
        button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
        toolButtons[tool] = button
        return button
    }

    private func symbolImage(_ name: String, _ title: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: title)
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        return image
    }
}

private final class RibbonGroup: NSView {
    var preferredWidth: CGFloat = 44
}

final class CommandButton: NSControl {
    var isChosen = false {
        didSet { layer?.backgroundColor = (isChosen ? StudioChrome.accentSoft : NSColor.clear).cgColor }
    }

    init(title: String, symbol: NSImage?, target: AnyObject?, action: Selector, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 54))
        self.target = target
        self.action = action
        toolTip = title
        wantsLayer = true
        layer?.cornerRadius = 6
        let icon = NSImageView()
        icon.image = symbol
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.textColor = StudioChrome.title
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(label)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 54),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseUp(with event: NSEvent) {
        if let action, bounds.contains(convert(event.locationInWindow, from: nil)) {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
}
