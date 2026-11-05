import AppKit
import VSDXCore

final class ShapesPane: NSView {
    var onPlace: ((String) -> Void)?
    private let search = NSSearchField()
    private let list = NSStackView()
    private var tiles: [(StencilItem, NSView)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = StudioChrome.pane.cgColor
        search.placeholderString = "Search shapes"
        search.target = self
        search.action = #selector(filter)
        search.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8
        list.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        list.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        scroll.documentView = document
        addSubview(search)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            search.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])
        rebuild(query: "")
    }

    required init?(coder: NSCoder) { nil }

    @objc private func filter() { rebuild(query: search.stringValue) }

    private func rebuild(query: String) {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for category in StencilCatalog.categories {
            let items = StencilCatalog.items.filter { $0.category == category && (needle.isEmpty || $0.name.lowercased().contains(needle) || $0.keywords.contains(needle)) }
            guard !items.isEmpty else { continue }
            let header = NSTextField(labelWithString: category)
            header.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            header.textColor = StudioChrome.title
            list.addArrangedSubview(header)
            let grid = NSGridView(views: [])
            grid.rowSpacing = 4
            grid.columnSpacing = 4
            var row: [NSView] = []
            for item in items {
                let tile = StencilTile(item: item)
                tile.onPlace = { [weak self] in self?.onPlace?(item.id) }
                tile.widthAnchor.constraint(equalToConstant: 92).isActive = true
                tile.heightAnchor.constraint(equalToConstant: 64).isActive = true
                row.append(tile)
                if row.count == 2 {
                    grid.addRow(with: row)
                    row = []
                }
            }
            if !row.isEmpty {
                while row.count < 2 { row.append(NSView()) }
                grid.addRow(with: row)
            }
            list.addArrangedSubview(grid)
        }
    }
}

final class StencilTile: NSView, NSDraggingSource {
    var onPlace: (() -> Void)?
    private let stencilID: String

    init(item: StencilItem) {
        stencilID = item.id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = StudioChrome.hairline.cgColor
        let icon = NSImageView()
        icon.image = StencilTile.symbol(for: item)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = StudioChrome.accent
        let label = NSTextField(labelWithString: item.name)
        label.font = NSFont.systemFont(ofSize: 9)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.heightAnchor.constraint(equalToConstant: 34)
        ])
        let stencilID = item.id
        DispatchQueue.global(qos: .utility).async {
            guard let data = PageDrawing.renderPNG(page: StencilCatalog.previewPage(id: stencilID), theme: ThemeColors(), colors: [:], pixelsPerInch: 40, margin: 2) else { return }
            DispatchQueue.main.async {
                icon.image = NSImage(data: data)
                icon.contentTintColor = nil
            }
        }
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

    private static func symbol(for item: StencilItem) -> NSImage? {
        let name: String
        switch item.category {
        case "Flowchart": name = "arrow.triangle.branch"
        case "Connectors": name = "arrow.right"
        case "Block Arrows": name = "arrow.right.square"
        case "Callouts": name = "text.bubble"
        default: name = "square.on.square"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: item.name)
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
    private let fontName = NSPopUpButton()
    private let fontSize = NSPopUpButton()
    private let dataLabel = NSTextField()
    private let dataValue = NSTextField()
    private var shapeID: Int?

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
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = StudioChrome.pane.cgColor
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(section("Size & Position"))
        stack.addArrangedSubview(grid([
            ("X", xField), ("Y", yField), ("Width", wField), ("Height", hField), ("Angle", angleField)
        ]))
        for field in [xField, yField, wField, hField, angleField] {
            field.target = self
            field.action = #selector(commitPosition)
            field.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }
        stack.addArrangedSubview(section("Fill"))
        fillWell.target = self
        fillWell.action = #selector(commitFill)
        stack.addArrangedSubview(labeled("Color", fillWell))
        stack.addArrangedSubview(section("Line"))
        lineWell.target = self
        lineWell.action = #selector(commitLine)
        weight.addItems(withTitles: ["0.5 pt", "0.75 pt", "1 pt", "1.5 pt", "2.25 pt", "3 pt", "6 pt"])
        weight.target = self
        weight.action = #selector(commitWeight)
        pattern.addItems(withTitles: ["Solid", "Dashed", "Dotted", "Dash-dot", "None"])
        pattern.target = self
        pattern.action = #selector(commitPattern)
        endArrow.addItems(withTitles: ["No arrow", "Open arrow", "Filled arrow", "Diamond", "Circle"])
        endArrow.target = self
        endArrow.action = #selector(commitArrow)
        stack.addArrangedSubview(labeled("Color", lineWell))
        stack.addArrangedSubview(labeled("Weight", weight))
        stack.addArrangedSubview(labeled("Pattern", pattern))
        stack.addArrangedSubview(labeled("End", endArrow))
        stack.addArrangedSubview(section("Text"))
        fontName.addItems(withTitles: ["Calibri", "Arial", "Helvetica", "Times New Roman", "Georgia", "Courier New", "Segoe UI"])
        fontName.target = self
        fontName.action = #selector(commitFont)
        fontSize.addItems(withTitles: ["8", "9", "10", "11", "12", "14", "16", "18", "20", "24", "28", "36"])
        fontSize.target = self
        fontSize.action = #selector(commitFontSize)
        fontWell.target = self
        fontWell.action = #selector(commitFontColor)
        stack.addArrangedSubview(labeled("Font", fontName))
        stack.addArrangedSubview(labeled("Size", fontSize))
        stack.addArrangedSubview(labeled("Color", fontWell))
        stack.addArrangedSubview(section("Shape Data"))
        dataLabel.placeholderString = "Label"
        dataValue.placeholderString = "Value"
        dataValue.target = self
        dataValue.action = #selector(commitData)
        stack.addArrangedSubview(labeled("Label", dataLabel))
        stack.addArrangedSubview(labeled("Value", dataValue))
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        addSubview(scroll)
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
            document.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func show(shape: ShapeNode?) {
        shapeID = shape?.id
        let enabled = shape != nil
        [xField, yField, wField, hField, angleField, fillWell, lineWell, fontWell, weight, pattern, endArrow, fontName, fontSize, dataLabel, dataValue].forEach { ($0 as? NSControl)?.isEnabled = enabled }
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
    }

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
        onChange?(.arrow(values[max(0, endArrow.indexOfSelectedItem)]))
    }
    @objc private func commitData() {
        onChange?(.shapeData(label: dataLabel.stringValue, value: dataValue.stringValue))
    }

    private func section(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = StudioChrome.accent
        return label
    }

    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = StudioChrome.label
        label.widthAnchor.constraint(equalToConstant: 52).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false
        if control is NSTextField || control is NSPopUpButton {
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        }
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    private func grid(_ rows: [(String, NSTextField)]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        for (title, field) in rows {
            field.placeholderString = title
            stack.addArrangedSubview(labeled(title, field))
        }
        return stack
    }
}
