import AppKit
import VSDXCore

protocol CanvasHost: AnyObject {
    var diagram: Diagram { get }
    var pageIndex: Int { get }
    var selection: [Int] { get set }
    var tool: EditorTool { get set }
    var zoom: CGFloat { get set }
    var snapEnabled: Bool { get }
    var showGrid: Bool { get }
    var showConnections: Bool { get }
    func beginPreview()
    func preview(_ body: (inout Diagram) -> Void)
    func commitPreview(_ name: String)
    func cancelPreview()
    func statusPoint(_ point: CGPoint?)
}

final class CanvasView: NSView {
    weak var host: CanvasHost?
    var page = DiagramPage(id: 0, name: "Page-1")
    var theme = ThemeColors()
    var colors: [Int: String] = [:]
    var selection: [Int] = []
    var tool: EditorTool = .pointer
    var showGrid = true
    var showConnections = true
    var snapEnabled = true
    var zoom: CGFloat = 1
    var guides: [GuideLine] = []

    private var dragMode: DragMode = .none
    private var marquee = CGRect.null
    private var hoverID: Int?
    private var wireEnd: CGPoint?
    private var wireTarget: PortHit?
    private var snapOff = false
    private let textEditor = NSTextView()
    private var editingID: Int?
    private let margin: CGFloat = 48

    private enum DragMode {
        case none
        case marquee(CGPoint)
        case move(CGPoint, Set<Int>, CGRect)
        case resize(Handle, Int)
        case rotate(Int)
        case create(CGPoint)
        case endpoint(Int, Bool, CGPoint)
        case wire(Int, Int, CGPoint)
        case bend(Int, Int)
        case segment(Int, Int)
        case pan(CGPoint)
    }

    private struct PortHit {
        var shape: Int
        var index: Int
        var anchor: CGPoint
        var knob: CGPoint
        var dir: CGPoint
    }

    private enum Handle {
        case n, s, e, w, ne, nw, se, sw
        case beginPoint, endPoint
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var pixelsPerInch: CGFloat { 72 * zoom }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        textEditor.isRichText = false
        textEditor.drawsBackground = true
        textEditor.backgroundColor = NSColor.white.withAlphaComponent(0.92)
        textEditor.isHidden = true
        textEditor.delegate = self
        textEditor.textContainerInset = NSSize(width: 2, height: 2)
        addSubview(textEditor)
        registerForDraggedTypes([NSPasteboard.PasteboardType("com.vsdxstudio.stencil")])
    }

    required init?(coder: NSCoder) { nil }

    func reload(page: DiagramPage, theme: ThemeColors, colors: [Int: String]) {
        let editing = editingID
        self.page = page
        self.theme = theme
        self.colors = colors
        self.guides = page.guides
        updateFrame()
        if let editing, page.shape(id: editing) == nil { endTextEditing(commit: false) }
        needsDisplay = true
    }

    func updateFrame() {
        let size = NSSize(width: margin * 2 + CGFloat(page.width) * pixelsPerInch, height: margin * 2 + CGFloat(page.height) * pixelsPerInch)
        if frame.size != size { setFrameSize(size) }
    }

    func zoomBy(_ factor: CGFloat, anchorInView: CGPoint?) {
        guard let host else { return }
        let next = min(4, max(0.15, zoom * factor))
        guard abs(next - zoom) > 0.001 else { return }
        let anchor = anchorInView ?? bounds.center
        let pageAnchor = viewToPage(anchor)
        host.zoom = next
        zoom = next
        updateFrame()
        if let scroll = enclosingScrollView {
            let viewAnchor = pageToView(pageAnchor)
            var origin = scroll.contentView.bounds.origin
            origin.x += viewAnchor.x - anchor.x
            origin.y += viewAnchor.y - anchor.y
            scroll.contentView.setBoundsOrigin(origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        StudioChrome.pasteboard.setFill()
        dirtyRect.fill()
        let pageRect = pageViewRect()
        NSColor.black.withAlphaComponent(0.18).setFill()
        pageRect.offsetBy(dx: 4, dy: 4).fill()
        NSColor.white.setFill()
        pageRect.fill()
        NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
        NSBezierPath(rect: pageRect).stroke()
        if showGrid { drawGrid(in: pageRect) }
        drawGuides(in: pageRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: margin, y: margin)
        context.scaleBy(x: pixelsPerInch, y: pixelsPerInch)
        context.translateBy(x: 0, y: CGFloat(page.height))
        context.scaleBy(x: 1, y: -1)
        PageDrawing.draw(page: page, theme: theme, colors: colors, in: context, pixelsPerInch: pixelsPerInch)
        context.restoreGState()
        drawSelection()
        drawConnections()
        drawHoverArrows()
        drawWire()
        if !marquee.isNull { drawMarquee() }
    }

    private func drawGrid(in pageRect: NSRect) {
        let minor = pixelsPerInch * 0.1
        guard minor > 3 else { return }
        strokeGrid(in: pageRect, step: minor, color: NSColor(srgbRed: 230 / 255, green: 230 / 255, blue: 230 / 255, alpha: 0.2))
        strokeGrid(in: pageRect, step: minor * 4, color: NSColor(srgbRed: 230 / 255, green: 230 / 255, blue: 230 / 255, alpha: 1))
    }

    private func strokeGrid(in pageRect: NSRect, step: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        var x = pageRect.minX
        while x <= pageRect.maxX + 0.5 {
            path.move(to: NSPoint(x: x, y: pageRect.minY))
            path.line(to: NSPoint(x: x, y: pageRect.maxY))
            x += step
        }
        var y = pageRect.minY
        while y <= pageRect.maxY + 0.5 {
            path.move(to: NSPoint(x: pageRect.minX, y: y))
            path.line(to: NSPoint(x: pageRect.maxX, y: y))
            y += step
        }
        color.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawGuides(in pageRect: NSRect) {
        NSColor.systemBlue.withAlphaComponent(0.7).setStroke()
        for guide in guides {
            let path = NSBezierPath()
            if guide.horizontal {
                let y = pageToView(CGPoint(x: 0, y: guide.position)).y
                path.move(to: NSPoint(x: pageRect.minX, y: y))
                path.line(to: NSPoint(x: pageRect.maxX, y: y))
            } else {
                let x = pageToView(CGPoint(x: guide.position, y: 0)).x
                path.move(to: NSPoint(x: x, y: pageRect.minY))
                path.line(to: NSPoint(x: x, y: pageRect.maxY))
            }
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawConnections() {
        let items = layoutItems()
        let wiring = isWiring || tool == .connector || tool == .line
        for item in items where !item.is1D {
            let show = showConnections || wiring || (item.id == hoverID && !selection.contains(item.id))
            guard show else { continue }
            for port in ports(of: item) {
                let highlighted = wireTarget?.shape == item.id && wireTarget?.index == port.index
                let view = pageToView(port.anchor)
                let arm: CGFloat = highlighted ? 5 : 3.5
                let mark = NSBezierPath()
                mark.move(to: NSPoint(x: view.x - arm, y: view.y - arm))
                mark.line(to: NSPoint(x: view.x + arm, y: view.y + arm))
                mark.move(to: NSPoint(x: view.x - arm, y: view.y + arm))
                mark.line(to: NSPoint(x: view.x + arm, y: view.y - arm))
                (highlighted ? NSColor.systemGreen : NSColor.systemBlue).setStroke()
                mark.lineWidth = highlighted ? 2 : 1.4
                mark.lineCapStyle = .round
                mark.stroke()
            }
        }
    }

    private func drawWire() {
        guard case .wire(let shape, let index, let anchor) = dragMode, let end = wireEnd else { return }
        let target = wireTarget?.anchor ?? end
        let startDir = layoutItems().first { $0.id == shape }?.connectionDirs[safe: index] ?? CGPoint(x: 1, y: 0)
        let dir = wireTarget?.dir ?? CGPoint(x: -startDir.x, y: -startDir.y)
        let points = ConnectorRoute.route(style: .elbow, start: anchor, startDir: startDir, end: target, endDir: dir)
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let view = pageToView(point)
            if index == 0 { path.move(to: view) } else { path.line(to: view) }
        }
        NSColor.systemBlue.setStroke()
        path.lineWidth = 1.6
        path.stroke()
        if points.count >= 2 {
            let tip = pageToView(points[points.count - 1])
            let from = pageToView(points[points.count - 2])
            drawArrowHead(tip: tip, from: from)
        }
    }

    private func drawArrowHead(tip: NSPoint, from: NSPoint) {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let length: CGFloat = 11
        let width: CGFloat = 7
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: NSPoint(x: tip.x - length * cos(angle) + width * sin(angle), y: tip.y - length * sin(angle) - width * cos(angle)))
        path.line(to: NSPoint(x: tip.x - length * 0.72 * cos(angle), y: tip.y - length * 0.72 * sin(angle)))
        path.line(to: NSPoint(x: tip.x - length * cos(angle) - width * sin(angle), y: tip.y - length * sin(angle) + width * cos(angle)))
        path.close()
        NSColor.systemBlue.setFill()
        path.fill()
    }

    private func drawHoverArrows() {
        guard tool == .pointer, !isWiring, let id = hoverID, let item = layoutItems().first(where: { $0.id == id && !$0.is1D }) else { return }
        let sides: [(CGPoint, CGPoint)] = [
            (CGPoint(x: item.bounds.midX, y: item.bounds.minY), CGPoint(x: 0, y: -1)),
            (CGPoint(x: item.bounds.maxX, y: item.bounds.midY), CGPoint(x: 1, y: 0)),
            (CGPoint(x: item.bounds.midX, y: item.bounds.maxY), CGPoint(x: 0, y: 1)),
            (CGPoint(x: item.bounds.minX, y: item.bounds.midY), CGPoint(x: -1, y: 0))
        ]
        for (mid, dir) in sides {
            let tip = pageToView(CGPoint(x: mid.x + dir.x * 0.22, y: mid.y + dir.y * 0.22))
            let tail = pageToView(CGPoint(x: mid.x + dir.x * 0.05, y: mid.y + dir.y * 0.05))
            drawArrowHead(tip: tip, from: tail)
        }
    }

    private func drawSelection() {
        for id in selection {
            guard let shape = page.shape(id: id) else { continue }
            let handles = handleMap(shape)
            if !shape.is1D {
                let corners: [Handle] = [.nw, .ne, .se, .sw]
                let outline = NSBezierPath()
                for (index, handle) in corners.enumerated() {
                    guard let point = handles[handle] else { continue }
                    let view = pageToView(point)
                    if index == 0 { outline.move(to: view) } else { outline.line(to: view) }
                }
                outline.close()
                NSColor.systemBlue.setStroke()
                outline.lineWidth = 1.25
                let dash: [CGFloat] = [5, 4]
                outline.setLineDash(dash, count: 2, phase: 0)
                outline.stroke()
            }
            NSColor.systemBlue.setFill()
            if shape.is1D {
                for point in ConnectorRoute.pagePoints(shape) {
                    let view = pageToView(point)
                    NSBezierPath(ovalIn: NSRect(x: view.x - 4.5, y: view.y - 4.5, width: 9, height: 9)).fill()
                }
            } else {
                for (_, point) in handles {
                    let view = pageToView(point)
                    NSBezierPath(ovalIn: NSRect(x: view.x - 4.5, y: view.y - 4.5, width: 9, height: 9)).fill()
                }
            }
            if !shape.is1D, let corner = handles[.ne] {
                drawRotateIcon(at: rotateKnob(for: corner))
            }
        }
    }

    private func rotateKnob(for corner: CGPoint) -> NSPoint {
        let view = pageToView(corner)
        return NSPoint(x: view.x + 16, y: view.y - 16)
    }

    private func drawRotateIcon(at center: NSPoint) {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: 6, startAngle: 50, endAngle: 310, clockwise: false)
        NSColor.systemBlue.setStroke()
        arc.lineWidth = 1.5
        arc.stroke()
        let angle = 310 * CGFloat.pi / 180
        let tip = NSPoint(x: center.x + 6 * cos(angle), y: center.y + 6 * sin(angle))
        let head = NSBezierPath()
        head.move(to: tip)
        head.line(to: NSPoint(x: tip.x - 5, y: tip.y + 1))
        head.move(to: tip)
        head.line(to: NSPoint(x: tip.x + 1, y: tip.y + 5))
        head.lineWidth = 1.5
        head.stroke()
    }

    private func drawMarquee() {
        let rect = NSRect(
            x: pageToView(CGPoint(x: marquee.minX, y: marquee.maxY)).x,
            y: pageToView(CGPoint(x: marquee.minX, y: marquee.maxY)).y,
            width: marquee.width * pixelsPerInch,
            height: marquee.height * pixelsPerInch
        )
        StudioChrome.accent.withAlphaComponent(0.12).setFill()
        StudioChrome.accent.setStroke()
        let path = NSBezierPath(rect: rect)
        path.fill()
        path.lineWidth = 1
        let pattern: [CGFloat] = [4, 3]
        path.setLineDash(pattern, count: 2, phase: 0)
        path.stroke()
    }

    func pageToView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: margin + point.x * pixelsPerInch, y: margin + (CGFloat(page.height) - point.y) * pixelsPerInch)
    }

    func viewToPage(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - margin) / pixelsPerInch,
            y: CGFloat(page.height) - (point.y - margin) / pixelsPerInch
        )
    }

    private func pageViewRect() -> NSRect {
        NSRect(x: margin, y: margin, width: CGFloat(page.width) * pixelsPerInch, height: CGFloat(page.height) * pixelsPerInch)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        endTextEditing(commit: true)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let pagePoint = viewToPage(viewPoint)
        host?.statusPoint(pagePoint)
        let shift = event.modifierFlags.contains(.shift)
        snapOff = event.modifierFlags.contains(.option)
        if tool == .connector || tool == .line, let port = hitPort(at: pagePoint) {
            dragMode = .wire(port.shape, port.index, port.anchor)
            wireEnd = pagePoint
            wireTarget = nil
            needsDisplay = true
            return
        }
        if tool == .pointer, let connector = connectorUnder(pagePoint) {
            host?.beginPreview()
            selection = [connector.id]
            host?.selection = selection
            if let shape = page.shape(id: connector.id), let bend = hitBend(on: connector.id, at: pagePoint) {
                let count = ConnectorRoute.pagePoints(shape).count
                if bend == 0 || bend == count - 1 {
                    dragMode = .endpoint(connector.id, bend == 0, pagePoint)
                } else {
                    dragMode = .bend(connector.id, bend)
                }
            } else {
                dragMode = .segment(connector.id, connector.index)
            }
            needsDisplay = true
            return
        }
        if tool == .pointer, let arrow = hitArrow(at: pagePoint) {
            dragMode = .wire(arrow.shape, arrow.index, arrow.anchor)
            wireEnd = pagePoint
            wireTarget = nil
            needsDisplay = true
            return
        }
        if tool == .pointer, let handle = hitHandle(at: viewPoint) {
            host?.beginPreview()
            if handle.1 == .beginPoint || handle.1 == .endPoint {
                dragMode = .endpoint(handle.0, handle.1 == .beginPoint, pagePoint)
            } else {
                dragMode = .resize(handle.1, handle.0)
            }
            return
        }
        if tool == .pointer, let port = hitPort(at: pagePoint) {
            dragMode = .wire(port.shape, port.index, port.anchor)
            wireEnd = pagePoint
            wireTarget = nil
            needsDisplay = true
            return
        }
        if tool == .pointer, hitRotate(at: viewPoint) != nil, let id = selection.last {
            host?.beginPreview()
            dragMode = .rotate(id)
            return
        }
        switch tool {
        case .pointer:
            if let hit = PageLayout.hitTest(page: page, point: pagePoint, theme: theme, colors: colors, slop: 8 / pixelsPerInch) {
                let id = selectionTarget(hit)
                if shift {
                    if selection.contains(id) { selection.removeAll { $0 == id } } else { selection.append(id) }
                } else if !selection.contains(id) {
                    selection = [id]
                }
                host?.selection = selection
                host?.beginPreview()
                dragMode = .move(pagePoint, Set(selection), selectionBounds(Set(selection)))
            } else {
                if !shift { selection = []; host?.selection = [] }
                dragMode = .marquee(pagePoint)
                marquee = CGRect(origin: pagePoint, size: .zero)
            }
        case .text:
            if let hit = PageLayout.hitTest(page: page, point: pagePoint, theme: theme, colors: colors, slop: 6 / pixelsPerInch) {
                selection = [selectionTarget(hit)]
                host?.selection = selection
                beginTextEditing(id: selection[0])
            } else {
                host?.beginPreview()
                dragMode = .create(pagePoint)
            }
        case .rectangle, .ellipse, .line, .connector:
            host?.beginPreview()
            dragMode = .create(pagePoint)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let pagePoint = viewToPage(convert(event.locationInWindow, from: nil))
        host?.statusPoint(pagePoint)
        let shift = event.modifierFlags.contains(.shift)
        snapOff = event.modifierFlags.contains(.option)
        switch dragMode {
        case .marquee(let start):
            marquee = CGRect(x: min(start.x, pagePoint.x), y: min(start.y, pagePoint.y), width: abs(pagePoint.x - start.x), height: abs(pagePoint.y - start.y))
            let items = PageLayout.items(page: page, theme: theme, colors: colors)
            selection = items.filter { $0.parentId == nil && $0.bounds.intersects(marquee) }.map(\.id)
            host?.selection = selection
            needsDisplay = true
        case .move(let start, let ids, let bounds):
            var dx = Double(pagePoint.x - start.x)
            var dy = Double(pagePoint.y - start.y)
            if snapEnabled && !snapOff, !bounds.isNull {
                let snapped = GridSnap.translation(bounds: bounds, dx: dx, dy: dy)
                dx = snapped.0
                dy = snapped.1
            }
            host?.preview { diagram in
                guard diagram.pages.indices.contains(host?.pageIndex ?? 0) else { return }
                let index = host?.pageIndex ?? 0
                DiagramEdit.translate(page: &diagram.pages[index], ids: ids, dx: dx, dy: dy)
                DiagramEdit.reroute(page: &diagram.pages[index], moved: ids, theme: diagram.theme, colors: diagram.colors)
            }
        case .resize(let handle, let id):
            host?.preview { diagram in
                let index = host?.pageIndex ?? 0
                guard let original = self.dragOriginal(in: diagram, id: id) else { return }
                let box = self.resized(original: original, handle: handle, mouse: pagePoint, constrain: shift)
                DiagramEdit.resize(page: &diagram.pages[index], id: id, pinX: box.pinX, pinY: box.pinY, width: box.width, height: box.height, theme: diagram.theme, colors: diagram.colors)
            }
        case .rotate(let id):
            host?.preview { diagram in
                let index = host?.pageIndex ?? 0
                guard let shape = diagram.pages[index].shape(id: id) else { return }
                let pinX = Format.parseDouble(shape.cell("PinX")?.value) ?? 0
                let pinY = Format.parseDouble(shape.cell("PinY")?.value) ?? 0
                var angle = atan2(Double(pagePoint.y) - pinY, Double(pagePoint.x) - pinX) - .pi / 2
                if shift {
                    let step = 15.0 * .pi / 180
                    angle = (angle / step).rounded() * step
                }
                DiagramEdit.setAngle(page: &diagram.pages[index], id: id, angle: angle)
            }
        case .create(let start):
            if tool == .line || tool == .connector {
                let begin = lineAnchor(start)
                let end = lineAnchor(pagePoint)
                wireTarget = end.port
                host?.preview { diagram in
                    self.previewCreate(in: &diagram, start: begin.point, current: end.point, constrain: shift && end.port == nil, snapPoints: false)
                }
            } else {
                host?.preview { diagram in
                    self.previewCreate(in: &diagram, start: start, current: pagePoint, constrain: shift, snapPoints: true)
                }
            }
        case .endpoint(let id, let begin, _):
            let snapped = nearestPort(to: pagePoint, ignoring: id, limit: portSnapLimit)?.anchor ?? pagePoint
            host?.preview { diagram in
                self.previewEndpoint(in: &diagram, id: id, begin: begin, point: snapped)
            }
        case .wire(_, _, _):
            wireEnd = pagePoint
            if case .wire(let shape, _, _) = dragMode {
                wireTarget = nearestPort(to: pagePoint, ignoring: shape, limit: portSnapLimit)
            }
            needsDisplay = true
        case .bend(let id, let index):
            let point = snappedPagePoint(pagePoint)
            host?.preview { diagram in
                self.moveConnectorPoint(in: &diagram, id: id, index: index, to: point, bend: true)
            }
        case .segment(let id, let index):
            let point = snappedPagePoint(pagePoint)
            host?.preview { diagram in
                self.moveConnectorPoint(in: &diagram, id: id, index: index, to: point, bend: false)
            }
        case .pan, .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let pagePoint = viewToPage(convert(event.locationInWindow, from: nil))
        switch dragMode {
        case .marquee:
            marquee = .null
            host?.selection = selection
            needsDisplay = true
        case .move, .resize, .rotate, .create, .endpoint, .wire, .bend, .segment:
            if case .create(let start) = dragMode {
                if tool == .line || tool == .connector {
                    let begin = lineAnchor(start)
                    var end = lineAnchor(pagePoint)
                    if hypot(end.point.x - begin.point.x, end.point.y - begin.point.y) < 0.05 {
                        end = (point: CGPoint(x: begin.point.x + 1.5, y: begin.point.y), port: nil)
                    }
                    host?.preview { diagram in
                        self.previewCreate(in: &diagram, start: begin.point, current: end.point, constrain: false, snapPoints: false)
                        self.attachNewConnector(in: &diagram, begin: begin.port, end: end.port)
                    }
                } else if hypot(pagePoint.x - start.x, pagePoint.y - start.y) < 0.05 {
                    host?.preview { diagram in
                        self.previewCreate(in: &diagram, start: start, current: CGPoint(x: start.x + 1.5, y: start.y - 1), constrain: false, snapPoints: true)
                    }
                }
            }
            if case .endpoint(let id, let begin, _) = dragMode {
                glueEndpoint(id: id, begin: begin, point: pagePoint)
            }
            if case .wire(let shape, let index, let anchor) = dragMode {
                finishWire(fromShape: shape, fromPort: index, anchor: anchor, end: pagePoint)
            }
            host?.commitPreview(dragName())
            marquee = .null
        case .pan, .none:
            break
        }
        dragMode = .none
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let pagePoint = viewToPage(convert(event.locationInWindow, from: nil))
        if let hit = PageLayout.hitTest(page: page, point: pagePoint, theme: theme, colors: colors, slop: 8 / pixelsPerInch) {
            let id = selectionTarget(hit)
            if !selection.contains(id) {
                selection = [id]
                host?.selection = selection
            }
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Duplicate", action: #selector(StudioWindowController.duplicate(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Delete", action: #selector(StudioWindowController.deleteShapes(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Group", action: #selector(StudioWindowController.groupShapes(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Ungroup", action: #selector(StudioWindowController.ungroupShapes(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Bring to Front", action: #selector(StudioWindowController.bringToFront(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Send to Back", action: #selector(StudioWindowController.sendToBack(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Edit Text", action: #selector(editTextFromMenu(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func editTextFromMenu(_ sender: Any?) {
        if let id = selection.last { beginTextEditing(id: id) }
    }

    override func mouseMoved(with event: NSEvent) {
        let pagePoint = viewToPage(convert(event.locationInWindow, from: nil))
        host?.statusPoint(pagePoint)
        let hit = PageLayout.hitTest(page: page, point: pagePoint, theme: theme, colors: colors, slop: 4 / pixelsPerInch)
        if hit != hoverID {
            hoverID = hit
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 53:
            host?.cancelPreview()
            dragMode = .none
            wireEnd = nil
            wireTarget = nil
            host?.tool = .pointer
            tool = .pointer
            needsDisplay = true
        case 51, 117:
            NSApp.sendAction(#selector(StudioWindowController.deleteShapes(_:)), to: nil, from: self)
        case 123: nudge(dx: event.modifierFlags.contains(.shift) ? -0.4 : -0.1, dy: 0)
        case 124: nudge(dx: event.modifierFlags.contains(.shift) ? 0.4 : 0.1, dy: 0)
        case 125: nudge(dx: 0, dy: event.modifierFlags.contains(.shift) ? -0.4 : -0.1)
        case 126: nudge(dx: 0, dy: event.modifierFlags.contains(.shift) ? 0.4 : 0.1)
        default:
            switch chars {
            case "v": host?.tool = .pointer
            case "t": host?.tool = .text
            case "r": host?.tool = .rectangle
            case "o": host?.tool = .ellipse
            case "l": host?.tool = .line
            case "c": host?.tool = .connector
            case "\r", "\u{3}":
                if let id = selection.last { beginTextEditing(id: id) }
            default:
                super.keyDown(with: event)
            }
        }
    }

    override func magnify(with event: NSEvent) {
        zoomBy(1 + event.magnification, anchorInView: convert(event.locationInWindow, from: nil))
    }

    func nudge(dx: Double, dy: Double) {
        guard let host, !selection.isEmpty else { return }
        let ids = Set(selection)
        host.commitDirect("Nudge") { diagram in
            let index = host.pageIndex
            DiagramEdit.nudge(page: &diagram.pages[index], ids: ids, dx: dx, dy: dy, theme: diagram.theme, colors: diagram.colors)
        }
    }

    private func dragName() -> String {
        switch tool {
        case .rectangle, .ellipse, .line, .connector, .text: return "Insert Shape"
        case .pointer:
            if case .resize = dragMode { return "Resize" }
            if case .rotate = dragMode { return "Rotate" }
            if case .wire = dragMode { return "Connect" }
            return "Move"
        }
    }

    private var isWiring: Bool {
        if case .wire = dragMode { return true }
        if case .endpoint = dragMode { return true }
        if case .create = dragMode, tool == .line || tool == .connector { return true }
        return false
    }

    private func selectionTarget(_ id: Int) -> Int {
        var current = id
        var top = id
        while let parent = page.shape(id: current)?.parentId {
            top = parent
            current = parent
        }
        if selection.contains(top), id != top { return id }
        return top
    }

    private func snappedPagePoint(_ point: CGPoint) -> CGPoint {
        guard snapEnabled && !snapOff else { return point }
        return CGPoint(x: GridSnap.snap(Double(point.x)), y: GridSnap.snap(Double(point.y)))
    }

    private func connectorUnder(_ point: CGPoint) -> (id: Int, index: Int)? {
        if let shapeHit = PageLayout.hitTest(page: page, point: point, theme: theme, colors: colors, slop: 0), page.shape(id: shapeHit)?.is1D == false {
            return nil
        }
        var best: (Int, Int, CGFloat)?
        for item in layoutItems() where item.is1D {
            guard let shape = page.shape(id: item.id) else { continue }
            let points = ConnectorRoute.pagePoints(shape)
            guard points.count >= 2 else { continue }
            for index in 0..<points.count - 1 {
                let distance = distanceToSegment(point, points[index], points[index + 1])
                if distance < 0.08, best == nil || distance < best!.2 {
                    best = (item.id, index, distance)
                }
            }
        }
        if let best { return (best.0, best.1) }
        return nil
    }

    private func hitBend(on id: Int, at point: CGPoint) -> Int? {
        guard let shape = page.shape(id: id) else { return nil }
        let points = ConnectorRoute.pagePoints(shape)
        return points.enumerated().min {
            hypot($0.element.x - point.x, $0.element.y - point.y) < hypot($1.element.x - point.x, $1.element.y - point.y)
        }.flatMap { hypot($0.element.x - point.x, $0.element.y - point.y) <= 0.12 ? $0.offset : nil }
    }

    private func hitArrow(at point: CGPoint) -> PortHit? {
        guard let id = hoverID, let item = layoutItems().first(where: { $0.id == id && !$0.is1D }) else { return nil }
        let sides: [(CGPoint, CGPoint)] = [
            (CGPoint(x: item.bounds.midX, y: item.bounds.minY), CGPoint(x: 0, y: -1)),
            (CGPoint(x: item.bounds.maxX, y: item.bounds.midY), CGPoint(x: 1, y: 0)),
            (CGPoint(x: item.bounds.midX, y: item.bounds.maxY), CGPoint(x: 0, y: 1)),
            (CGPoint(x: item.bounds.minX, y: item.bounds.midY), CGPoint(x: -1, y: 0))
        ]
        for (mid, dir) in sides {
            let tip = CGPoint(x: mid.x + dir.x * 0.22, y: mid.y + dir.y * 0.22)
            guard hypot(tip.x - point.x, tip.y - point.y) <= 0.16 else { continue }
            let ports = ports(of: item)
            guard let port = ports.min(by: { hypot($0.anchor.x - mid.x, $0.anchor.y - mid.y) < hypot($1.anchor.x - mid.x, $1.anchor.y - mid.y) }) else { continue }
            return PortHit(shape: item.id, index: port.index, anchor: port.anchor, knob: tip, dir: dir)
        }
        return nil
    }

    private func distanceToSegment(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = dx * dx + dy * dy
        if length < 0.000001 { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    private func moveConnectorPoint(in diagram: inout Diagram, id: Int, index: Int, to point: CGPoint, bend: Bool) {
        let pageIndex = host?.pageIndex ?? 0
        guard var shape = diagram.pages[pageIndex].shape(id: id) else { return }
        var points = ConnectorRoute.pagePoints(shape)
        guard points.indices.contains(index) else { return }
        if bend {
            let old = points[index]
            let previous = index > 0 ? points[index - 1] : old
            let next = index + 1 < points.count ? points[index + 1] : old
            points[index] = point
            if index > 0 {
                if abs(previous.y - old.y) <= abs(previous.x - old.x) { points[index - 1].y = point.y }
                else { points[index - 1].x = point.x }
            }
            if index + 1 < points.count {
                if abs(next.y - old.y) <= abs(next.x - old.x) { points[index + 1].y = point.y }
                else { points[index + 1].x = point.x }
            }
        } else if index + 1 < points.count {
            let horizontal = abs(points[index].y - points[index + 1].y) <= abs(points[index].x - points[index + 1].x)
            if horizontal {
                points[index].y = point.y
                points[index + 1].y = point.y
            } else {
                points[index].x = point.x
                points[index + 1].x = point.x
            }
        }
        ConnectorRoute.apply(points: points, to: &shape)
        shape.id = id
        shape.setCell("UserRoute", value: "1", clearFormula: true)
        diagram.pages[pageIndex].updateShape(id: id) { $0 = shape }
    }

    private func hitHandle(at viewPoint: CGPoint) -> (Int, Handle)? {
        for id in selection.reversed() {
            guard let shape = page.shape(id: id) else { continue }
            for (handle, point) in handleMap(shape) {
                let view = pageToView(point)
                if hypot(view.x - viewPoint.x, view.y - viewPoint.y) <= 7 { return (id, handle) }
            }
        }
        return nil
    }

    private func hitRotate(at viewPoint: CGPoint) -> Int? {
        for id in selection.reversed() {
            guard let shape = page.shape(id: id), !shape.is1D, let corner = handleMap(shape)[.ne] else { continue }
            let knob = rotateKnob(for: corner)
            if hypot(knob.x - viewPoint.x, knob.y - viewPoint.y) <= 9 { return id }
        }
        return nil
    }

    private func handleMap(_ shape: ShapeNode) -> [Handle: CGPoint] {
        let scope = EvalScope(page: page, theme: theme, colors: colors)
        let transform = GeometryMath.localToPage(shape, scope: scope)
        if shape.is1D {
            let begin = CGPoint(x: scope.number(shape: shape, cell: "BeginX"), y: scope.number(shape: shape, cell: "BeginY"))
            let end = CGPoint(x: scope.number(shape: shape, cell: "EndX"), y: scope.number(shape: shape, cell: "EndY"))
            return [.beginPoint: begin, .endPoint: end]
        }
        let width = scope.number(shape: shape, cell: "Width")
        let height = scope.number(shape: shape, cell: "Height")
        let locals: [Handle: CGPoint] = [
            .nw: CGPoint(x: 0, y: height), .n: CGPoint(x: width / 2, y: height), .ne: CGPoint(x: width, y: height),
            .e: CGPoint(x: width, y: height / 2), .se: CGPoint(x: width, y: 0), .s: CGPoint(x: width / 2, y: 0),
            .sw: CGPoint(x: 0, y: 0), .w: CGPoint(x: 0, y: height / 2)
        ]
        return locals.mapValues { $0.applying(transform) }
    }

    private func dragOriginal(in diagram: Diagram, id: Int) -> ShapeNode? {
        diagram.pages[safe: host?.pageIndex ?? 0]?.shape(id: id)
    }

    private func resized(original: ShapeNode, handle: Handle, mouse: CGPoint, constrain: Bool) -> (pinX: Double, pinY: Double, width: Double, height: Double) {
        let angle = Format.parseDouble(original.cell("Angle")?.value) ?? 0
        let width = Format.parseDouble(original.cell("Width")?.value) ?? 1
        let height = Format.parseDouble(original.cell("Height")?.value) ?? 1
        let pinX = Format.parseDouble(original.cell("PinX")?.value) ?? 0
        let pinY = Format.parseDouble(original.cell("PinY")?.value) ?? 0
        let dx = Double(mouse.x) - pinX
        let dy = Double(mouse.y) - pinY
        let lx = dx * cos(-angle) - dy * sin(-angle)
        let ly = dx * sin(-angle) + dy * cos(-angle)
        var left = -width / 2
        var right = width / 2
        var bottom = -height / 2
        var top = height / 2
        switch handle {
        case .e, .ne, .se: right = max(left + 0.1, lx)
        case .w, .nw, .sw: left = min(right - 0.1, lx)
        default: break
        }
        switch handle {
        case .n, .ne, .nw: top = max(bottom + 0.1, ly)
        case .s, .se, .sw: bottom = min(top - 0.1, ly)
        default: break
        }
        var newWidth = right - left
        var newHeight = top - bottom
        if constrain, width > 0, height > 0, [.ne, .nw, .se, .sw].contains(handle) {
            let scale = max(newWidth / width, newHeight / height)
            newWidth = width * scale
            newHeight = height * scale
            if handle == .e || handle == .ne || handle == .se { right = left + newWidth } else { left = right - newWidth }
            if handle == .n || handle == .ne || handle == .nw { top = bottom + newHeight } else { bottom = top - newHeight }
        }
        let centerX = (left + right) / 2
        let centerY = (bottom + top) / 2
        let pageX = pinX + centerX * cos(angle) - centerY * sin(angle)
        let pageY = pinY + centerX * sin(angle) + centerY * cos(angle)
        return (pageX, pageY, max(0.1, newWidth), max(0.1, newHeight))
    }

    private func selectionBounds(_ ids: Set<Int>) -> CGRect {
        let items = layoutItems().filter { ids.contains($0.id) && $0.parentId == nil && !$0.is1D }
        guard let first = items.first else { return .null }
        return items.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
    }

    private func previewCreate(in diagram: inout Diagram, start: CGPoint, current: CGPoint, constrain: Bool, snapPoints: Bool) {
        let index = host?.pageIndex ?? 0
        guard diagram.pages.indices.contains(index) else { return }
        var end = current
        var origin = start
        if snapPoints && snapEnabled && !snapOff {
            origin = CGPoint(x: GridSnap.snap(Double(origin.x)), y: GridSnap.snap(Double(origin.y)))
            end = CGPoint(x: GridSnap.snap(Double(end.x)), y: GridSnap.snap(Double(end.y)))
        }
        if constrain {
            let side = max(abs(end.x - origin.x), abs(end.y - origin.y))
            end.x = origin.x + (end.x >= origin.x ? side : -side)
            end.y = origin.y + (end.y >= origin.y ? side : -side)
        }
        let id = diagram.pages[index].nextShapeId()
        var shape: ShapeNode
        switch tool {
        case .ellipse:
            shape = StencilCatalog.make(id: "ellipse", shapeId: id, center: CGPoint(x: (origin.x + end.x) / 2, y: (origin.y + end.y) / 2))
            shape.setNumber("Width", max(0.1, abs(Double(end.x - origin.x))), clearFormula: true)
            shape.setNumber("Height", max(0.1, abs(Double(end.y - origin.y))), clearFormula: true)
        case .line:
            shape = StencilCatalog.make(id: "line", shapeId: id, center: origin)
            ConnectorRoute.apply(points: [origin, end], to: &shape)
        case .connector:
            shape = StencilCatalog.make(id: "connector", shapeId: id, center: origin)
            let leave = ConnectorRoute.axisDirection(from: origin, to: end)
            let arrive = ConnectorRoute.axisDirection(from: end, to: origin)
            let points = ConnectorRoute.route(style: .elbow, start: origin, startDir: leave, end: end, endDir: arrive)
            ConnectorRoute.apply(points: points, to: &shape)
        case .text:
            shape = StencilCatalog.make(id: "text", shapeId: id, center: CGPoint(x: (origin.x + end.x) / 2, y: (origin.y + end.y) / 2))
            shape.setNumber("Width", max(0.4, abs(Double(end.x - start.x))), clearFormula: true)
            shape.setNumber("Height", max(0.3, abs(Double(end.y - origin.y))), clearFormula: true)
            shape.setTextContent("Text")
        default:
            shape = StencilCatalog.make(id: "rectangle", shapeId: id, center: CGPoint(x: (origin.x + end.x) / 2, y: (origin.y + end.y) / 2))
            shape.setNumber("Width", max(0.1, abs(Double(end.x - origin.x))), clearFormula: true)
            shape.setNumber("Height", max(0.1, abs(Double(end.y - origin.y))), clearFormula: true)
        }
        shape.id = id
        diagram.pages[index].shapes.append(shape)
        DiagramEdit.refreshDerived(page: &diagram.pages[index], id: id, theme: diagram.theme, colors: diagram.colors)
        selection = [id]
        host?.selection = [id]
    }

    private func previewEndpoint(in diagram: inout Diagram, id: Int, begin: Bool, point: CGPoint) {
        let index = host?.pageIndex ?? 0
        guard var shape = diagram.pages[index].shape(id: id) else { return }
        let other = CGPoint(
            x: Format.parseDouble(shape.cell(begin ? "EndX" : "BeginX")?.value) ?? 0,
            y: Format.parseDouble(shape.cell(begin ? "EndY" : "BeginY")?.value) ?? 0
        )
        let start = begin ? point : other
        let end = begin ? other : point
        let styleValue = Int(Format.parseDouble(shape.cell("ShapeRouteStyle")?.value) ?? 1)
        let style: ConnectorStyle = styleValue == 0 ? .straight : .elbow
        let points = ConnectorRoute.route(style: style, start: start, startDir: ConnectorRoute.axisDirection(from: start, to: end), end: end, endDir: ConnectorRoute.axisDirection(from: end, to: start))
        ConnectorRoute.apply(points: points, to: &shape)
        shape.id = id
        diagram.pages[index].updateShape(id: id) { $0 = shape }
    }

    private var portSnapLimit: CGFloat { 16 / pixelsPerInch }

    private func lineAnchor(_ point: CGPoint) -> (point: CGPoint, port: PortHit?) {
        if let port = nearestPort(to: point, ignoring: -1, limit: portSnapLimit) {
            return (port.anchor, port)
        }
        if snapEnabled && !snapOff {
            return (CGPoint(x: GridSnap.snap(Double(point.x)), y: GridSnap.snap(Double(point.y))), nil)
        }
        return (point, nil)
    }

    private func attachNewConnector(in diagram: inout Diagram, begin: PortHit?, end: PortHit?) {
        let index = host?.pageIndex ?? 0
        guard diagram.pages.indices.contains(index), let id = diagram.pages[index].shapes.last?.id else { return }
        if let begin {
            DiagramEdit.connect(page: &diagram.pages[index], connectorId: id, begin: true, to: begin.shape, part: 100 + begin.index, cell: "Connections.X\(begin.index + 1)")
        }
        if let end {
            DiagramEdit.connect(page: &diagram.pages[index], connectorId: id, begin: false, to: end.shape, part: 100 + end.index, cell: "Connections.X\(end.index + 1)")
        }
        let moved = Set([begin?.shape, end?.shape].compactMap { $0 })
        if !moved.isEmpty {
            DiagramEdit.reroute(page: &diagram.pages[index], moved: moved, theme: diagram.theme, colors: diagram.colors)
        }
    }

    private func glueEndpoint(id: Int, begin: Bool, point: CGPoint) {
        guard let target = nearestPort(to: point, ignoring: id, limit: portSnapLimit) else { return }
        host?.preview { diagram in
            let index = self.host?.pageIndex ?? 0
            self.previewEndpoint(in: &diagram, id: id, begin: begin, point: target.anchor)
            DiagramEdit.connect(page: &diagram.pages[index], connectorId: id, begin: begin, to: target.shape, part: 100 + target.index, cell: "Connections.X\(target.index + 1)")
            DiagramEdit.reroute(page: &diagram.pages[index], moved: [target.shape], theme: diagram.theme, colors: diagram.colors)
        }
    }

    private func finishWire(fromShape: Int, fromPort: Int, anchor: CGPoint, end: CGPoint) {
        wireEnd = nil
        let target = wireTarget ?? nearestPort(to: end, ignoring: fromShape, limit: portSnapLimit)
        wireTarget = nil
        guard let target, target.shape != fromShape else { return }
        guard hypot(end.x - anchor.x, end.y - anchor.y) > 0.15 else { return }
        host?.commitDirect("Connect") { diagram in
            let index = self.host?.pageIndex ?? 0
            let id = DiagramEdit.addGluedConnector(
                page: &diagram.pages[index],
                fromShape: fromShape,
                fromPort: fromPort,
                toShape: target.shape,
                toPort: target.index,
                theme: diagram.theme,
                colors: diagram.colors
            )
            self.selection = [id]
            self.host?.selection = [id]
        }
    }

    private func layoutItems() -> [LayoutItem] {
        PageLayout.items(page: page, theme: theme, colors: colors)
    }

    private func ports(of item: LayoutItem) -> [PortHit] {
        item.connections.enumerated().map { index, anchor in
            let dir = item.connectionDirs.indices.contains(index) ? item.connectionDirs[index] : CGPoint(x: 0, y: 1)
            return PortHit(shape: item.id, index: index, anchor: anchor, knob: anchor, dir: dir)
        }
    }

    private func visiblePorts() -> [PortHit] {
        let wiring = isWiring || tool == .connector || tool == .line
        return layoutItems().filter { item in
            !item.is1D && (showConnections || wiring || item.id == hoverID || selection.contains(item.id))
        }.flatMap(ports(of:))
    }

    private func hitPort(at point: CGPoint) -> PortHit? {
        nearestPort(to: point, ignoring: -1, limit: portSnapLimit, visibleOnly: true)
    }

    private func nearestPort(to point: CGPoint, ignoring: Int, limit: CGFloat, visibleOnly: Bool = false) -> PortHit? {
        let source = visibleOnly ? visiblePorts() : layoutItems().filter { $0.id != ignoring && !$0.is1D }.flatMap(ports(of:))
        let ports = visibleOnly ? source.filter { $0.shape != ignoring } : source
        return ports.min { hypot($0.anchor.x - point.x, $0.anchor.y - point.y) < hypot($1.anchor.x - point.x, $1.anchor.y - point.y) }
            .flatMap { hypot($0.anchor.x - point.x, $0.anchor.y - point.y) <= limit ? $0 : nil }
    }

    func placeStencil(_ id: String, at viewPoint: CGPoint) {
        var pagePoint = viewToPage(viewPoint)
        host?.commitDirect("Insert Shape") { diagram in
            let index = self.host?.pageIndex ?? 0
            let shapeID = diagram.pages[index].nextShapeId()
            var shape = StencilCatalog.make(id: id, shapeId: shapeID, center: pagePoint)
            if self.snapEnabled {
                let width = Format.parseDouble(shape.cell("Width")?.value) ?? 1
                let height = Format.parseDouble(shape.cell("Height")?.value) ?? 1
                let bounds = CGRect(x: pagePoint.x - width / 2, y: pagePoint.y - height / 2, width: width, height: height)
                let delta = GridSnap.translation(bounds: bounds, dx: 0, dy: 0)
                pagePoint.x += delta.0
                pagePoint.y += delta.1
                shape.setNumber("PinX", Double(pagePoint.x), clearFormula: true)
                shape.setNumber("PinY", Double(pagePoint.y), clearFormula: true)
            }
            diagram.pages[index].shapes.append(shape)
            DiagramEdit.refreshDerived(page: &diagram.pages[index], id: shapeID, theme: diagram.theme, colors: diagram.colors)
        }
        if let newID = host?.diagram.pages[host?.pageIndex ?? 0].shapes.last?.id {
            selection = [newID]
            host?.selection = selection
        }
    }

    func beginTextEditing(id: Int) {
        guard let shape = page.shape(id: id) else { return }
        let scope = EvalScope(page: page, theme: theme, colors: colors)
        let transform = GeometryMath.localToPage(shape, scope: scope)
        let width = scope.number(shape: shape, cell: "Width")
        let height = scope.number(shape: shape, cell: "Height")
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0), CGPoint(x: width, y: height), CGPoint(x: 0, y: height)].map { pageToView($0.applying(transform)) }
        let minX = corners.map(\.x).min() ?? 0
        let minY = corners.map(\.y).min() ?? 0
        let maxX = corners.map(\.x).max() ?? 40
        let maxY = corners.map(\.y).max() ?? 20
        textEditor.string = shape.text
        textEditor.font = NSFont(name: "Calibri", size: 12 * zoom) ?? NSFont.systemFont(ofSize: 12 * zoom)
        textEditor.alignment = .center
        textEditor.frame = NSRect(x: minX, y: minY, width: max(40, maxX - minX), height: max(24, maxY - minY))
        textEditor.isHidden = false
        editingID = id
        window?.makeFirstResponder(textEditor)
    }

    func endTextEditing(commit: Bool) {
        guard let id = editingID else { return }
        let text = textEditor.string
        editingID = nil
        textEditor.isHidden = true
        window?.makeFirstResponder(self)
        guard commit else { return }
        host?.commitDirect("Edit Text") { diagram in
            let index = self.host?.pageIndex ?? 0
            diagram.pages[index].updateShape(id: id) { $0.setTextContent(text) }
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard let id = pasteboard.string(forType: NSPasteboard.PasteboardType("com.vsdxstudio.stencil")) else { return false }
        placeStencil(id, at: convert(sender.draggingLocation, from: nil))
        return true
    }
}

extension CanvasView: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        endTextEditing(commit: true)
    }
}

extension CanvasHost {
    func commitDirect(_ name: String, _ body: (inout Diagram) -> Void) {
        beginPreview()
        preview(body)
        commitPreview(name)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension NSRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
