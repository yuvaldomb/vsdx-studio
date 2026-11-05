import AppKit
import VSDXCore

private enum DrawioPane {
    static let chrome = NSColor(srgbRed: 241.0 / 255, green: 243.0 / 255, blue: 244.0 / 255, alpha: 1)
    static let line = NSColor(srgbRed: 218.0 / 255, green: 218.0 / 255, blue: 218.0 / 255, alpha: 1)
    static let more = NSColor(srgbRed: 194.0 / 255, green: 231.0 / 255, blue: 255.0 / 255, alpha: 1)
}

final class ShapesPane: NSView {
    var onPlace: ((String) -> Void)?
    private let search = NSSearchField()
    private let list = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DrawioPane.chrome.cgColor
        clipsToBounds = true

        let searchWell = NSView()
        searchWell.wantsLayer = true
        searchWell.layer?.backgroundColor = NSColor.white.cgColor
        searchWell.layer?.cornerRadius = 18
        searchWell.layer?.borderWidth = 1
        searchWell.layer?.borderColor = DrawioPane.line.cgColor
        searchWell.layer?.masksToBounds = true
        searchWell.translatesAutoresizingMaskIntoConstraints = false

        search.placeholderString = "Type / to search"
        search.font = NSFont.systemFont(ofSize: 13)
        search.isBezeled = false
        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(submitSearch)
        search.translatesAutoresizingMaskIntoConstraints = false
        searchWell.addSubview(search)
        NotificationCenter.default.addObserver(self, selector: #selector(searchEdited(_:)), name: NSControl.textDidChangeNotification, object: search)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 6
        list.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        list.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        scroll.documentView = document

        let more = FillButton()
        more.title = "+ More Shapes"
        more.fill = DrawioPane.more
        more.isBordered = false
        more.wantsLayer = true
        more.target = self
        more.action = #selector(moreShapes)
        more.toolTip = "More shapes"
        more.translatesAutoresizingMaskIntoConstraints = false

        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = DrawioPane.line.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchWell)
        addSubview(scroll)
        addSubview(more)
        addSubview(border)
        NSLayoutConstraint.activate([
            searchWell.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchWell.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            searchWell.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchWell.heightAnchor.constraint(equalToConstant: 28),
            search.leadingAnchor.constraint(equalTo: searchWell.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: searchWell.trailingAnchor, constant: -8),
            search.topAnchor.constraint(equalTo: searchWell.topAnchor, constant: 2),
            search.bottomAnchor.constraint(equalTo: searchWell.bottomAnchor, constant: -2),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: searchWell.bottomAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: more.topAnchor, constant: -6),
            more.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            more.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            more.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            more.heightAnchor.constraint(equalToConstant: 32),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        let borderWidth = border.widthAnchor.constraint(equalToConstant: 1)
        borderWidth.priority = .defaultHigh
        borderWidth.isActive = true
        let documentWidth = document.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        documentWidth.priority = .defaultHigh
        documentWidth.isActive = true
        rebuild(query: "")
    }

    required init?(coder: NSCoder) { nil }

    func focusSearch() {
        guard let window else { return }
        window.makeFirstResponder(search)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func submitSearch() { rebuild(query: search.stringValue) }
    @objc private func searchEdited(_ note: Notification) { rebuild(query: search.stringValue) }

    @objc private func moreShapes() {
        window?.makeFirstResponder(search)
    }

    private func rebuild(query: String) {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var placedSection = false
        for category in StencilCatalog.categories {
            let items = StencilCatalog.items.filter { $0.category == category && (needle.isEmpty || $0.name.lowercased().contains(needle) || $0.keywords.contains(needle)) }
            guard !items.isEmpty else { continue }
            if placedSection {
                let gap = NSView()
                gap.translatesAutoresizingMaskIntoConstraints = false
                gap.heightAnchor.constraint(equalToConstant: 8).isActive = true
                list.addArrangedSubview(gap)
            }
            placedSection = true
            let header = NSTextField(labelWithString: category)
            header.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            header.textColor = .black
            header.alignment = .left
            list.addArrangedSubview(header)
            var row: [NSView] = []
            for item in items {
                let tile = StencilTile(item: item)
                tile.onPlace = { [weak self] in self?.onPlace?(item.id) }
                tile.translatesAutoresizingMaskIntoConstraints = false
                tile.widthAnchor.constraint(equalToConstant: 38).isActive = true
                tile.heightAnchor.constraint(equalToConstant: 36).isActive = true
                row.append(tile)
                if row.count == 5 {
                    list.addArrangedSubview(tileRow(row))
                    row = []
                }
            }
            if !row.isEmpty {
                list.addArrangedSubview(tileRow(row))
            }
        }
    }

    private func tileRow(_ tiles: [NSView]) -> NSView {
        let row = NSStackView(views: tiles)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        row.distribution = .gravityAreas
        return row
    }
}

final class StencilTile: NSView, NSDraggingSource {
    var onPlace: (() -> Void)?
    private let stencilID: String

    init(item: StencilItem) {
        stencilID = item.id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        alphaValue = 0.75
        toolTip = item.name
        let icon = NSImageView()
        icon.image = StencilTile.icon(for: item.id)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            icon.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }

    required init?(coder: NSCoder) { nil }

    private var didDrag = false

    override func mouseDown(with event: NSEvent) { didDrag = false }

    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        let item = NSPasteboardItem()
        item.setString(stencilID, forType: NSPasteboard.PasteboardType("com.vsdxstudio.stencil"))
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag { onPlace?() }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    private static func icon(for id: String) -> NSImage? {
        guard let data = PageDrawing.renderIconPNG(page: StencilCatalog.previewPage(id: id), theme: ThemeColors(), colors: [:], pixels: 96) else { return nil }
        return NSImage(data: data)
    }

    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            layer?.render(in: context)
        }
        image.unlockFocus()
        return image
    }
}

final class FormatPane: NSView {
    var onChange: ((FormatChange) -> Void)?
    var onToggleGrid: ((Bool) -> Void)?
    var onToggleConnectionPoints: ((Bool) -> Void)?

    private let diagramStack = NSStackView()
    private let tabRow = NSStackView()
    private let styleStack = NSStackView()
    private let textStack = NSStackView()
    private let arrangeStack = NSStackView()
    private var tabButtons: [TextTabButton] = []
    private var formatTab = 0

    private let gridCheck: NSButton = {
        let button = NSButton(checkboxWithTitle: "Grid", target: nil, action: nil)
        button.font = NSFont.systemFont(ofSize: 12)
        button.state = .on
        return button
    }()
    private let pointsCheck: NSButton = {
        let button = NSButton(checkboxWithTitle: "Connection Points", target: nil, action: nil)
        button.font = NSFont.systemFont(ofSize: 12)
        button.state = .off
        return button
    }()

    private let xField = NSTextField()
    private let yField = NSTextField()
    private let wField = NSTextField()
    private let hField = NSTextField()
    private let angleField = NSTextField()
    private let fillWell = NSColorWell()
    private let lineWell = NSColorWell()
    private let fontWell = NSColorWell()
    private let weight = NSPopUpButton()
    private let pattern = NSPopUpButton()
    private let endArrow = NSPopUpButton()
    private let beginArrow = NSPopUpButton()
    private let opacity = NSPopUpButton()
    private let corner = NSPopUpButton()
    private let route = NSPopUpButton()
    private let shadowCheck = NSButton(checkboxWithTitle: "Shadow", target: nil, action: nil)
    private let fontName = NSPopUpButton()
    private let fontSize = NSPopUpButton()
    private let boldButton = NSButton(checkboxWithTitle: "Bold", target: nil, action: nil)
    private let italicButton = NSButton(checkboxWithTitle: "Italic", target: nil, action: nil)
    private let underlineButton = NSButton(checkboxWithTitle: "Underline", target: nil, action: nil)
    private let dataLabel = NSTextField()
    private let dataValue = NSTextField()
    private var shapeID: Int?
    private var refreshing = false

    var showsGrid = true {
        didSet { gridCheck.state = showsGrid ? .on : .off }
    }
    var showsConnectionPoints = false {
        didSet { pointsCheck.state = showsConnectionPoints ? .on : .off }
    }

    enum FormatChange {
        case position(x: Double?, y: Double?, w: Double?, h: Double?, angle: Double?)
        case fill(NSColor?)
        case line(NSColor)
        case weight(Double)
        case pattern(Int)
        case arrow(Int)
        case font(String)
        case fontSize(Double)
        case fontColor(NSColor)
        case shapeData(label: String, value: String)
        case opacity(Double)
        case shadow(Bool)
        case rounding(Double)
        case beginArrow(Int)
        case fontBit(Int)
        case textAlign(Int)
        case verticalAlign(Int)
        case route(ConnectorStyle)
        case bringFront
        case sendBack
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor

        gridCheck.target = self
        gridCheck.action = #selector(gridClicked)
        pointsCheck.target = self
        pointsCheck.action = #selector(pointsClicked)

        configure(diagramStack)
        diagramStack.addArrangedSubview(section("Diagram"))
        let gridSize = NSTextField(labelWithString: "10 pt")
        gridSize.font = NSFont.systemFont(ofSize: 12)
        gridSize.textColor = .black
        let gridRow = NSStackView(views: [gridCheck, gridSize])
        gridRow.orientation = .horizontal
        gridRow.alignment = .centerY
        gridRow.spacing = 8
        diagramStack.addArrangedSubview(gridRow)
        diagramStack.addArrangedSubview(bodyLabel("Page View"))
        diagramStack.addArrangedSubview(option("Connection Arrows", on: true))
        diagramStack.addArrangedSubview(pointsCheck)
        diagramStack.addArrangedSubview(option("Guides", on: true))

        tabRow.orientation = .horizontal
        tabRow.alignment = .centerY
        tabRow.spacing = 2
        tabRow.distribution = .gravityAreas
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        for (index, title) in ["Style", "Text", "Arrange"].enumerated() {
            let button = TextTabButton()
            button.title = title
            button.tag = index
            button.target = self
            button.action = #selector(selectFormatTab(_:))
            button.isBordered = false
            button.wantsLayer = true
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 64).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
            tabButtons.append(button)
            tabRow.addArrangedSubview(button)
        }

        configure(styleStack)
        fillWell.target = self
        fillWell.action = #selector(commitFill)
        lineWell.target = self
        lineWell.action = #selector(commitLine)
        weight.addItems(withTitles: ["0.5 pt", "0.75 pt", "1 pt", "1.5 pt", "2.25 pt", "3 pt", "6 pt"])
        weight.font = NSFont.systemFont(ofSize: 12)
        weight.target = self
        weight.action = #selector(commitWeight)
        pattern.addItems(withTitles: ["Solid", "Dashed", "Dotted", "Dash-dot", "None"])
        pattern.font = NSFont.systemFont(ofSize: 12)
        pattern.target = self
        pattern.action = #selector(commitPattern)
        endArrow.addItems(withTitles: ["No arrow", "Open arrow", "Filled arrow", "Diamond", "Circle"])
        endArrow.font = NSFont.systemFont(ofSize: 12)
        endArrow.target = self
        endArrow.action = #selector(commitArrow)
        beginArrow.addItems(withTitles: ["No arrow", "Open arrow", "Filled arrow", "Diamond", "Circle"])
        beginArrow.font = NSFont.systemFont(ofSize: 12)
        beginArrow.target = self
        beginArrow.action = #selector(commitBeginArrow)
        opacity.addItems(withTitles: ["100%", "75%", "50%", "25%", "0%"])
        opacity.font = NSFont.systemFont(ofSize: 12)
        opacity.target = self
        opacity.action = #selector(commitOpacity)
        corner.addItems(withTitles: ["Sharp", "Rounded", "Curved"])
        corner.font = NSFont.systemFont(ofSize: 12)
        corner.target = self
        corner.action = #selector(commitCorner)
        route.addItems(withTitles: ["Straight", "Orthogonal", "Simple", "Curved"])
        route.font = NSFont.systemFont(ofSize: 12)
        route.target = self
        route.action = #selector(commitRoute)
        shadowCheck.font = NSFont.systemFont(ofSize: 12)
        shadowCheck.target = self
        shadowCheck.action = #selector(commitShadow)
        styleStack.addArrangedSubview(labeled("Fill", fillWell))
        styleStack.addArrangedSubview(labeled("Line", lineWell))
        styleStack.addArrangedSubview(labeled("Weight", weight))
        styleStack.addArrangedSubview(labeled("Pattern", pattern))
        styleStack.addArrangedSubview(labeled("Route", route))
        styleStack.addArrangedSubview(labeled("Corner", corner))
        styleStack.addArrangedSubview(labeled("Start", beginArrow))
        styleStack.addArrangedSubview(labeled("Arrow", endArrow))
        styleStack.addArrangedSubview(labeled("Opacity", opacity))
        styleStack.addArrangedSubview(shadowCheck)
        styleStack.addArrangedSubview(section("Shape Data"))
        dataLabel.placeholderString = "Label"
        dataLabel.font = NSFont.systemFont(ofSize: 12)
        dataValue.placeholderString = "Value"
        dataValue.font = NSFont.systemFont(ofSize: 12)
        dataValue.target = self
        dataValue.action = #selector(commitData)
        styleStack.addArrangedSubview(labeled("Label", dataLabel))
        styleStack.addArrangedSubview(labeled("Value", dataValue))

        configure(textStack)
        fontName.addItems(withTitles: ["Calibri", "Arial", "Helvetica", "Times New Roman", "Georgia", "Courier New", "Segoe UI"])
        fontName.font = NSFont.systemFont(ofSize: 12)
        fontName.target = self
        fontName.action = #selector(commitFont)
        fontSize.addItems(withTitles: ["8", "9", "10", "11", "12", "14", "16", "18", "20", "24", "28", "36"])
        fontSize.font = NSFont.systemFont(ofSize: 12)
        fontSize.target = self
        fontSize.action = #selector(commitFontSize)
        fontWell.target = self
        fontWell.action = #selector(commitFontColor)
        for button in [boldButton, italicButton, underlineButton] {
            button.font = NSFont.systemFont(ofSize: 12)
            button.target = self
        }
        boldButton.action = #selector(commitBold)
        italicButton.action = #selector(commitItalic)
        underlineButton.action = #selector(commitUnderline)
        let styleRow = NSStackView(views: [boldButton, italicButton, underlineButton])
        styleRow.orientation = .horizontal
        styleRow.spacing = 8
        textStack.addArrangedSubview(labeled("Font", fontName))
        textStack.addArrangedSubview(labeled("Size", fontSize))
        textStack.addArrangedSubview(labeled("Color", fontWell))
        textStack.addArrangedSubview(styleRow)
        textStack.addArrangedSubview(buttonRow([
            ("Left", #selector(commitAlignLeft)),
            ("Center", #selector(commitAlignCenter)),
            ("Right", #selector(commitAlignRight))
        ]))
        textStack.addArrangedSubview(buttonRow([
            ("Top", #selector(commitAlignTop)),
            ("Middle", #selector(commitAlignMiddle)),
            ("Bottom", #selector(commitAlignBottom))
        ]))

        configure(arrangeStack)
        for field in [xField, yField, wField, hField, angleField] {
            field.target = self
            field.action = #selector(commitPosition)
            field.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }
        arrangeStack.addArrangedSubview(labeled("X", xField))
        arrangeStack.addArrangedSubview(labeled("Y", yField))
        arrangeStack.addArrangedSubview(labeled("W", wField))
        arrangeStack.addArrangedSubview(labeled("H", hField))
        arrangeStack.addArrangedSubview(labeled("Angle", angleField))
        arrangeStack.addArrangedSubview(buttonRow([
            ("To Front", #selector(commitFront)),
            ("To Back", #selector(commitBack))
        ]))

        let stack = NSStackView()
        configure(stack)
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        stack.spacing = 10
        stack.addArrangedSubview(diagramStack)
        stack.addArrangedSubview(tabRow)
        stack.addArrangedSubview(styleStack)
        stack.addArrangedSubview(textStack)
        stack.addArrangedSubview(arrangeStack)

        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document

        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = DrawioPane.line.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scroll)
        addSubview(border)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.widthAnchor.constraint(equalToConstant: 1)
        ])
        applyMode(hasShape: false)
    }

    required init?(coder: NSCoder) { nil }

    func show(shape: ShapeNode?) {
        refreshing = true
        defer { refreshing = false }
        let same = shape?.id != nil && shape?.id == shapeID
        if shape != nil && !same { formatTab = 0 }
        shapeID = shape?.id
        applyMode(hasShape: shape != nil)
        guard let shape else {
            [xField, yField, wField, hField, angleField].forEach { $0.stringValue = "" }
            return
        }
        xField.stringValue = inchesString(Format.parseDouble(shape.cell("PinX")?.value) ?? 0)
        yField.stringValue = inchesString(Format.parseDouble(shape.cell("PinY")?.value) ?? 0)
        wField.stringValue = inchesString(Format.parseDouble(shape.cell("Width")?.value) ?? 0)
        hField.stringValue = inchesString(Format.parseDouble(shape.cell("Height")?.value) ?? 0)
        let degrees = (Format.parseDouble(shape.cell("Angle")?.value) ?? 0) * 180 / .pi
        angleField.stringValue = String(format: "%.1f", degrees)
        fillWell.color = NSColor(hex: shape.cell("FillForegnd")?.value ?? "#FFFFFF") ?? .white
        lineWell.color = NSColor(hex: shape.cell("LineColor")?.value ?? "#000000") ?? .black
        let font = shape.character.first?.raw("Font") ?? "Calibri"
        if fontName.itemTitles.contains(font) { fontName.selectItem(withTitle: font) }
        let points = (Format.parseDouble(shape.character.first?.raw("Size")) ?? 12.0 / 72.0) * 72
        fontSize.selectItem(withTitle: String(Int(points.rounded())))
        fontWell.color = NSColor(hex: shape.character.first?.raw("Color") ?? "#000000") ?? .black
        if let prop = shape.properties.first {
            dataLabel.stringValue = prop.label
            dataValue.stringValue = prop.value
        } else {
            dataLabel.stringValue = ""
            dataValue.stringValue = ""
        }
        let trans = Format.parseDouble(shape.cell("FillForegndTrans")?.value) ?? 0
        let visible = Int(((1 - trans) * 100).rounded())
        let percents = [100, 75, 50, 25, 0]
        let nearest = percents.enumerated().min { abs($0.element - visible) < abs($1.element - visible) }?.offset ?? 0
        opacity.selectItem(at: nearest)
        shadowCheck.state = (Format.parseDouble(shape.cell("ShdwPattern")?.value) ?? 0) == 0 ? .off : .on
        let rounding = Format.parseDouble(shape.cell("Rounding")?.value) ?? 0
        corner.selectItem(at: rounding < 0.04 ? 0 : (rounding < 0.22 ? 1 : 2))
        switch ConnectorStyle.from(route: shape.cell("ShapeRouteStyle")?.value) {
        case .straight: route.selectItem(at: 0)
        case .elbow: route.selectItem(at: 1)
        case .simple: route.selectItem(at: 2)
        case .curve: route.selectItem(at: 3)
        }
        beginArrow.selectItem(at: arrowIndex(Int(Format.parseDouble(shape.cell("BeginArrow")?.value) ?? 0)))
        endArrow.selectItem(at: arrowIndex(Int(Format.parseDouble(shape.cell("EndArrow")?.value) ?? 0)))
        let bits = Int(shape.character.first?.raw("Style") ?? "0") ?? 0
        boldButton.state = bits & 1 == 0 ? .off : .on
        italicButton.state = bits & 2 == 0 ? .off : .on
        underlineButton.state = bits & 4 == 0 ? .off : .on
    }

    private func applyMode(hasShape: Bool) {
        diagramStack.isHidden = hasShape
        tabRow.isHidden = !hasShape
        guard hasShape else {
            styleStack.isHidden = true
            textStack.isHidden = true
            arrangeStack.isHidden = true
            return
        }
        showFormatTab(formatTab)
    }

    private func showFormatTab(_ index: Int) {
        formatTab = max(0, min(2, index))
        styleStack.isHidden = formatTab != 0
        textStack.isHidden = formatTab != 1
        arrangeStack.isHidden = formatTab != 2
        for (buttonIndex, button) in tabButtons.enumerated() {
            button.chosen = buttonIndex == formatTab
        }
    }

    @objc private func selectFormatTab(_ sender: NSButton) {
        showFormatTab(sender.tag)
    }

    @objc private func gridClicked() { onToggleGrid?(gridCheck.state == .on) }
    @objc private func pointsClicked() { onToggleConnectionPoints?(pointsCheck.state == .on) }

    @objc private func commitPosition() {
        onChange?(.position(
            x: Double(xField.stringValue),
            y: Double(yField.stringValue),
            w: Double(wField.stringValue),
            h: Double(hField.stringValue),
            angle: Double(angleField.stringValue).map { $0 * .pi / 180 }
        ))
    }

    @objc private func commitFill() { onChange?(.fill(fillWell.color)) }
    @objc private func commitLine() { onChange?(.line(lineWell.color)) }
    @objc private func commitFontColor() { onChange?(.fontColor(fontWell.color)) }
    @objc private func commitFont() { onChange?(.font(fontName.titleOfSelectedItem ?? "Calibri")) }
    @objc private func commitFontSize() {
        let points = Double(fontSize.titleOfSelectedItem ?? "12") ?? 12
        onChange?(.fontSize(points / 72))
    }
    @objc private func commitWeight() {
        let points = [0.5, 0.75, 1, 1.5, 2.25, 3, 6][max(0, weight.indexOfSelectedItem)]
        onChange?(.weight(points / 72))
    }
    @objc private func commitPattern() {
        let values = [1, 2, 3, 4, 0]
        onChange?(.pattern(values[max(0, pattern.indexOfSelectedItem)]))
    }
    @objc private func commitArrow() {
        let values = [0, 1, 13, 5, 10]
        emit(.arrow(values[max(0, endArrow.indexOfSelectedItem)]))
    }
    @objc private func commitBeginArrow() {
        let values = [0, 1, 13, 5, 10]
        emit(.beginArrow(values[max(0, beginArrow.indexOfSelectedItem)]))
    }
    @objc private func commitOpacity() {
        let values = [1.0, 0.75, 0.5, 0.25, 0.0]
        let index = max(0, min(values.count - 1, opacity.indexOfSelectedItem))
        emit(.opacity(values[index]))
    }
    @objc private func commitCorner() {
        let values = [0.0, 0.12, 0.35]
        let index = max(0, min(values.count - 1, corner.indexOfSelectedItem))
        emit(.rounding(values[index]))
    }
    @objc private func commitRoute() {
        let styles: [ConnectorStyle] = [.straight, .elbow, .simple, .curve]
        let index = max(0, min(styles.count - 1, route.indexOfSelectedItem))
        emit(.route(styles[index]))
    }
    @objc private func commitShadow() { emit(.shadow(shadowCheck.state == .on)) }
    @objc private func commitBold() { emit(.fontBit(1)) }
    @objc private func commitItalic() { emit(.fontBit(2)) }
    @objc private func commitUnderline() { emit(.fontBit(4)) }
    @objc private func commitAlignLeft() { emit(.textAlign(0)) }
    @objc private func commitAlignCenter() { emit(.textAlign(1)) }
    @objc private func commitAlignRight() { emit(.textAlign(2)) }
    @objc private func commitAlignTop() { emit(.verticalAlign(0)) }
    @objc private func commitAlignMiddle() { emit(.verticalAlign(1)) }
    @objc private func commitAlignBottom() { emit(.verticalAlign(2)) }
    @objc private func commitFront() { emit(.bringFront) }
    @objc private func commitBack() { emit(.sendBack) }
    @objc private func commitData() {
        emit(.shapeData(label: dataLabel.stringValue, value: dataValue.stringValue))
    }

    private func emit(_ change: FormatChange) {
        guard !refreshing else { return }
        onChange?(change)
    }

    private func arrowIndex(_ value: Int) -> Int {
        [0, 1, 13, 5, 10].firstIndex(of: value) ?? 0
    }

    private func buttonRow(_ items: [(String, Selector)]) -> NSView {
        let buttons = items.map { title, action -> NSButton in
            let button = NSButton(title: title, target: self, action: action)
            button.font = NSFont.systemFont(ofSize: 11)
            button.bezelStyle = .rounded
            button.controlSize = .small
            return button
        }
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 6
        return row
    }

    private func configure(_ stack: NSStackView) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
    }

    private func section(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        label.textColor = .black
        return label
    }

    private func bodyLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .black
        return label
    }

    private func option(_ title: String, on: Bool) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.font = NSFont.systemFont(ofSize: 12)
        button.state = on ? .on : .off
        return button
    }

    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 52).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false
        if control is NSTextField || control is NSPopUpButton {
            let width = control.widthAnchor.constraint(equalToConstant: 136)
            width.priority = .defaultHigh
            width.isActive = true
        }
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }
}

private final class FillButton: NSButton {
    var fill: NSColor = .clear
    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        fill.setFill()
        path.fill()
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attrs)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: origin, withAttributes: attrs)
    }
}

private final class TextTabButton: NSButton {
    var chosen = false {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.systemFont(ofSize: 12, weight: chosen ? .bold : .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: chosen ? NSColor.black : NSColor(white: 0.35, alpha: 1)
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attrs)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: origin, withAttributes: attrs)
        if chosen {
            NSColor.black.setFill()
            NSRect(x: 6, y: 1, width: max(0, bounds.width - 12), height: 2).fill()
        }
    }
}
