import CoreGraphics
import Foundation

public struct StencilItem: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var category: String
    public var keywords: String

    public init(id: String, name: String, category: String, keywords: String) {
        self.id = id
        self.name = name
        self.category = category
        self.keywords = keywords
    }
}

public enum StencilCatalog {
    public static let categories = ["Basic Shapes", "Flowchart", "Connectors", "Block Arrows", "Callouts"]

    public static let items: [StencilItem] = basic + flowchart + connectors + arrows + callouts

    public static func make(id: String, shapeId: Int, center: CGPoint) -> ShapeNode {
        var shape = factory(id)(shapeId)
        shape.setNumber("PinX", Double(center.x), clearFormula: true)
        shape.setNumber("PinY", Double(center.y), clearFormula: true)
        if !shape.is1D { ShapePorts.install(&shape) }
        shape.name = items.first { $0.id == id }?.name ?? "Shape"
        shape.nameU = shape.name
        shape.detached = true
        shape.original = nil
        return shape
    }

    public static func previewPage(id: String) -> DiagramPage {
        var page = DiagramPage(id: 0, name: "Preview", width: 2.2, height: 1.5)
        var shape = make(id: id, shapeId: 1, center: CGPoint(x: 1.1, y: 0.75))
        if let style = previewStyle(id) {
            let start = CGPoint(x: 0.28, y: 0.42)
            let end = CGPoint(x: 1.92, y: 1.08)
            let points = ConnectorRoute.route(
                style: style,
                start: start,
                startDir: CGPoint(x: 1, y: 0),
                end: end,
                endDir: CGPoint(x: -1, y: 0)
            )
            ConnectorRoute.apply(points: points, to: &shape, style: style)
        }
        page.shapes = [shape]
        return page
    }

    private static func previewStyle(_ id: String) -> ConnectorStyle? {
        switch id {
        case "line", "straight-arrow": return .straight
        case "elbow": return .simple
        case "curve": return .curve
        case "connector": return .elbow
        default: return nil
        }
    }

    private static func factory(_ id: String) -> (Int) -> ShapeNode {
        switch id {
        case "square": return { box($0, 1, 1, polygon: nil) }
        case "ellipse": return { ellipse($0, 1.5, 1) }
        case "circle": return { ellipse($0, 1, 1) }
        case "diamond": return { poly($0, 1.5, 1, [(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)]) }
        case "triangle": return { poly($0, 1.4, 1.2, [(0.5, 1), (1, 0), (0, 0)]) }
        case "right-triangle": return { poly($0, 1.3, 1.1, [(0, 0), (1, 0), (0, 1)]) }
        case "pentagon": return { regular($0, 1.2, 1.2, sides: 5, star: false) }
        case "hexagon": return { regular($0, 1.4, 1.2, sides: 6, star: false) }
        case "heptagon": return { regular($0, 1.2, 1.2, sides: 7, star: false) }
        case "octagon": return { regular($0, 1.2, 1.2, sides: 8, star: false) }
        case "star5": return { regular($0, 1.3, 1.3, sides: 5, star: true) }
        case "star6": return { regular($0, 1.3, 1.3, sides: 6, star: true) }
        case "cross": return { poly($0, 1.2, 1.2, crossPoints) }
        case "parallelogram": return { poly($0, 1.6, 1, [(0.2, 0), (1, 0), (0.8, 1), (0, 1)]) }
        case "trapezoid": return { poly($0, 1.6, 1, [(0.15, 0), (0.85, 0), (1, 1), (0, 1)]) }
        case "plus": return { poly($0, 1.2, 1.2, plusPoints) }
        case "frame": return { frame($0) }
        case "can": return { can($0) }
        case "rounded": return { rounded($0, 1.6, 1, radius: 0.15) }
        case "text": return { textBox($0) }
        case "process": return { box($0, 1.5, 1, polygon: nil, text: "Process") }
        case "decision": return { poly($0, 1.5, 1.2, [(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)], text: "Decision") }
        case "terminator": return { rounded($0, 1.6, 0.8, radius: 0.4, text: "Start") }
        case "data": return { poly($0, 1.5, 1, [(0.18, 0), (1, 0), (0.82, 1), (0, 1)], text: "Data") }
        case "document": return { document($0) }
        case "predefined": return { predefined($0) }
        case "stored": return { stored($0) }
        case "database": return { database($0) }
        case "manual-input": return { poly($0, 1.5, 1, [(0, 0.15), (1, 0), (1, 1), (0, 1)], text: "Input") }
        case "preparation": return { poly($0, 1.6, 1, [(0.18, 0), (0.82, 0), (1, 0.5), (0.82, 1), (0.18, 1), (0, 0.5)], text: "Prep") }
        case "display": return { display($0) }
        case "delay": return { delay($0) }
        case "flow-connector": return { ellipse($0, 0.55, 0.55, text: "") }
        case "off-page": return { poly($0, 1.4, 0.9, [(0, 0), (0.75, 0), (1, 0.5), (0.75, 1), (0, 1)], text: "Page") }
        case "internal": return { internalStorage($0) }
        case "or": return { orJunction($0) }
        case "note": return { note($0) }
        case "line": return { connector($0, style: .straight, arrow: 0) }
        case "connector": return { connector($0, style: .elbow, arrow: 13) }
        case "straight-arrow": return { connector($0, style: .straight, arrow: 13) }
        case "elbow": return { connector($0, style: .elbow, arrow: 13) }
        case "curve": return { connector($0, style: .curve, arrow: 13) }
        case "arrow-right": return { poly($0, 1.6, 0.8, rightArrow) }
        case "arrow-left": return { poly($0, 1.6, 0.8, rightArrow.map { (1 - $0.0, $0.1) }) }
        case "arrow-up": return { poly($0, 0.9, 1.4, upArrow) }
        case "arrow-down": return { poly($0, 0.9, 1.4, upArrow.map { ($0.0, 1 - $0.1) }) }
        case "chevron": return { poly($0, 1.2, 1, [(0, 0), (0.7, 0), (1, 0.5), (0.7, 1), (0, 1), (0.3, 0.5)]) }
        case "notched": return { poly($0, 1.6, 0.8, [(0.2, 0), (0.7, 0), (1, 0.5), (0.7, 1), (0.2, 1), (0, 0.5)]) }
        case "callout": return { callout($0) }
        case "speech": return { speech($0) }
        default: return { box($0, 1.5, 1, polygon: nil) }
        }
    }

    private static let basic: [StencilItem] = [
        item("rectangle", "Rectangle", "Basic Shapes", "rect box"),
        item("rounded", "Rounded Rectangle", "Basic Shapes", "round rect"),
        item("square", "Square", "Basic Shapes", "square"),
        item("ellipse", "Ellipse", "Basic Shapes", "oval"),
        item("circle", "Circle", "Basic Shapes", "circle"),
        item("diamond", "Diamond", "Basic Shapes", "diamond"),
        item("triangle", "Triangle", "Basic Shapes", "triangle"),
        item("right-triangle", "Right Triangle", "Basic Shapes", "triangle"),
        item("pentagon", "Pentagon", "Basic Shapes", "polygon"),
        item("hexagon", "Hexagon", "Basic Shapes", "polygon"),
        item("heptagon", "Heptagon", "Basic Shapes", "polygon"),
        item("octagon", "Octagon", "Basic Shapes", "polygon"),
        item("star5", "5-Point Star", "Basic Shapes", "star"),
        item("star6", "6-Point Star", "Basic Shapes", "star"),
        item("cross", "Cross", "Basic Shapes", "cross"),
        item("plus", "Plus", "Basic Shapes", "plus"),
        item("parallelogram", "Parallelogram", "Basic Shapes", "slant"),
        item("trapezoid", "Trapezoid", "Basic Shapes", "trap"),
        item("frame", "Frame", "Basic Shapes", "frame hole"),
        item("can", "Can", "Basic Shapes", "cylinder"),
        item("text", "Text Box", "Basic Shapes", "text label")
    ]

    private static let flowchart: [StencilItem] = [
        item("process", "Process", "Flowchart", "process rectangle"),
        item("decision", "Decision", "Flowchart", "decision diamond"),
        item("terminator", "Start/End", "Flowchart", "terminator"),
        item("data", "Data", "Flowchart", "data io"),
        item("document", "Document", "Flowchart", "document"),
        item("predefined", "Predefined Process", "Flowchart", "sub process"),
        item("stored", "Stored Data", "Flowchart", "stored"),
        item("database", "Database", "Flowchart", "database cylinder"),
        item("manual-input", "Manual Input", "Flowchart", "input"),
        item("preparation", "Preparation", "Flowchart", "hexagon"),
        item("display", "Display", "Flowchart", "display"),
        item("delay", "Delay", "Flowchart", "delay"),
        item("internal", "Internal Storage", "Flowchart", "storage"),
        item("flow-connector", "Connector", "Flowchart", "junction circle"),
        item("off-page", "Off-page Reference", "Flowchart", "off page"),
        item("or", "Or", "Flowchart", "or junction"),
        item("note", "Note", "Flowchart", "annotation")
    ]

    private static let connectors: [StencilItem] = [
        item("connector", "Dynamic Connector", "Connectors", "connector elbow"),
        item("elbow", "Right-Angle Connector", "Connectors", "elbow"),
        item("line", "Line", "Connectors", "line"),
        item("straight-arrow", "Line Arrow", "Connectors", "arrow line"),
        item("curve", "Curved Connector", "Connectors", "curve")
    ]

    private static let arrows: [StencilItem] = [
        item("arrow-right", "Right Arrow", "Block Arrows", "arrow"),
        item("arrow-left", "Left Arrow", "Block Arrows", "arrow"),
        item("arrow-up", "Up Arrow", "Block Arrows", "arrow"),
        item("arrow-down", "Down Arrow", "Block Arrows", "arrow"),
        item("chevron", "Chevron", "Block Arrows", "chevron"),
        item("notched", "Notched Arrow", "Block Arrows", "arrow")
    ]

    private static let callouts: [StencilItem] = [
        item("callout", "Box Callout", "Callouts", "callout"),
        item("speech", "Speech Bubble", "Callouts", "speech")
    ]

    private static func item(_ id: String, _ name: String, _ category: String, _ keywords: String) -> StencilItem {
        StencilItem(id: id, name: name, category: category, keywords: keywords + " " + name.lowercased())
    }
}

public enum ConnectorStyle: Equatable {
    case straight, simple, elbow, curve

    public var routeValue: String {
        switch self {
        case .straight: return "0"
        case .simple: return "3"
        case .curve: return "2"
        case .elbow: return "1"
        }
    }

    public static func from(route value: String?) -> ConnectorStyle {
        switch Int(Format.parseDouble(value) ?? 1) {
        case 0: return .straight
        case 2: return .curve
        case 3: return .simple
        default: return .elbow
        }
    }
}

public enum ConnectorRoute {
    public static func apply(points: [CGPoint], to shape: inout ShapeNode, style: ConnectorStyle = .elbow) {
        guard points.count >= 2 else { return }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = Double(xs.min() ?? 0)
        let maxX = Double(xs.max() ?? 0)
        let minY = Double(ys.min() ?? 0)
        let maxY = Double(ys.max() ?? 0)
        let width = max(0.01, maxX - minX)
        let height = max(0, maxY - minY)
        shape.setNumber("Width", width, clearFormula: true)
        shape.setNumber("Height", height, clearFormula: true)
        shape.setNumber("LocPinX", width / 2, clearFormula: true)
        shape.setNumber("LocPinY", height / 2, clearFormula: true)
        shape.setNumber("PinX", minX + width / 2, clearFormula: true)
        shape.setNumber("PinY", minY + height / 2, clearFormula: true)
        shape.setNumber("Angle", 0, clearFormula: true)
        shape.setNumber("BeginX", Double(points[0].x), clearFormula: true)
        shape.setNumber("BeginY", Double(points[0].y), clearFormula: true)
        shape.setNumber("EndX", Double(points[points.count - 1].x), clearFormula: true)
        shape.setNumber("EndY", Double(points[points.count - 1].y), clearFormula: true)
        shape.setCell("ShapeRouteStyle", value: style.routeValue, clearFormula: true)
        shape.setCell("FillPattern", value: "0", clearFormula: true)
        var section = GeoSection()
        section.noFill = true
        if style == .curve, points.count >= 3 {
            let start = local(points[0], minX: minX, minY: minY)
            let control = local(points[1], minX: minX, minY: minY)
            let end = local(points[points.count - 1], minX: minX, minY: minY)
            section.rows = [
                GeoRow(type: "MoveTo", ix: 1, cells: [
                    "X": Cell(value: Format.number(start.0)),
                    "Y": Cell(value: Format.number(start.1))
                ]),
                GeoRow(type: "QuadBezTo", ix: 2, cells: [
                    "X": Cell(value: Format.number(end.0)),
                    "Y": Cell(value: Format.number(end.1)),
                    "A": Cell(value: Format.number(control.0)),
                    "B": Cell(value: Format.number(control.1))
                ])
            ]
        } else {
            for (index, point) in points.enumerated() {
                let pair = local(point, minX: minX, minY: minY)
                section.rows.append(GeoRow(type: index == 0 ? "MoveTo" : "LineTo", ix: index + 1, cells: [
                    "X": Cell(value: Format.number(pair.0)),
                    "Y": Cell(value: Format.number(pair.1))
                ]))
            }
        }
        shape.geometry = [section]
        shape.detached = true
        shape.original = nil
    }

    private static func local(_ point: CGPoint, minX: Double, minY: Double) -> (Double, Double) {
        (Double(point.x) - minX, Double(point.y) - minY)
    }

    public static func route(style: ConnectorStyle, start: CGPoint, startDir: CGPoint, end: CGPoint, endDir: CGPoint) -> [CGPoint] {
        switch style {
        case .straight:
            return [start, end]
        case .curve:
            return curve(start, end)
        case .simple:
            return simple(start, end)
        case .elbow:
            return elbow(start, startDir, end, endDir)
        }
    }

    private static func simple(_ start: CGPoint, _ end: CGPoint) -> [CGPoint] {
        if abs(end.x - start.x) < 0.02 || abs(end.y - start.y) < 0.02 {
            return [start, end]
        }
        if abs(end.x - start.x) >= abs(end.y - start.y) {
            return [start, CGPoint(x: end.x, y: start.y), end]
        }
        return [start, CGPoint(x: start.x, y: end.y), end]
    }

    private static func curve(_ start: CGPoint, _ end: CGPoint) -> [CGPoint] {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(0.2, hypot(dx, dy))
        let bend = CGPoint(x: mid.x - dy / length * 0.35, y: mid.y + dx / length * 0.35)
        return [start, bend, end]
    }

    public static func pagePoints(_ shape: ShapeNode) -> [CGPoint] {
        let pinX = Format.parseDouble(shape.cell("PinX")?.value) ?? 0
        let pinY = Format.parseDouble(shape.cell("PinY")?.value) ?? 0
        let locX = Format.parseDouble(shape.cell("LocPinX")?.value) ?? 0
        let locY = Format.parseDouble(shape.cell("LocPinY")?.value) ?? 0
        let angle = Format.parseDouble(shape.cell("Angle")?.value) ?? 0
        let width = Format.parseDouble(shape.cell("Width")?.value) ?? 0
        let height = Format.parseDouble(shape.cell("Height")?.value) ?? 0
        guard let section = shape.geometry.first else { return [] }
        func map(_ x: Double, _ y: Double, relative: Bool) -> CGPoint {
            var px = x
            var py = y
            if relative {
                px *= width
                py *= height
            }
            let localX = px - locX
            let localY = py - locY
            return CGPoint(
                x: pinX + localX * cos(angle) - localY * sin(angle),
                y: pinY + localX * sin(angle) + localY * cos(angle)
            )
        }
        var result: [CGPoint] = []
        for row in section.rows where !row.deleted {
            let relative = row.type.hasPrefix("Rel")
            if row.type == "QuadBezTo" || row.type == "RelQuadBezTo" {
                let ax = Format.parseDouble(row.raw("A")) ?? 0
                let ay = Format.parseDouble(row.raw("B")) ?? 0
                result.append(map(ax, ay, relative))
            }
            let x = Format.parseDouble(row.raw("X")) ?? 0
            let y = Format.parseDouble(row.raw("Y")) ?? 0
            result.append(map(x, y, relative))
        }
        return result
    }

    public static func axisDirection(from: CGPoint, to: CGPoint) -> CGPoint {
        if abs(to.x - from.x) >= abs(to.y - from.y) {
            return CGPoint(x: to.x >= from.x ? 1 : -1, y: 0)
        }
        return CGPoint(x: 0, y: to.y >= from.y ? 1 : -1)
    }

    private static func elbow(_ start: CGPoint, _ startDir: CGPoint, _ end: CGPoint, _ endDir: CGPoint) -> [CGPoint] {
        let leave = axis(startDir, fallback: axisDirection(from: start, to: end))
        let arrive = axis(endDir, fallback: axisDirection(from: end, to: start))
        if abs(start.y - end.y) < 0.02, leave.y == 0, arrive.y == 0, leave.x * (end.x - start.x) > 0, arrive.x * (start.x - end.x) > 0 {
            return [start, end]
        }
        if abs(start.x - end.x) < 0.02, leave.x == 0, arrive.x == 0, leave.y * (end.y - start.y) > 0, arrive.y * (start.y - end.y) > 0 {
            return [start, end]
        }
        let jetty = CGFloat(0.2)
        let out = CGPoint(x: start.x + leave.x * jetty, y: start.y + leave.y * jetty)
        let inn = CGPoint(x: end.x + arrive.x * jetty, y: end.y + arrive.y * jetty)
        var points = [start, out]
        let leaveHorizontal = leave.y == 0
        let arriveHorizontal = arrive.y == 0
        if leaveHorizontal == arriveHorizontal {
            let forward = leaveHorizontal
                ? leave.x * (inn.x - out.x) > 0 && arrive.x * (out.x - inn.x) > 0
                : leave.y * (inn.y - out.y) > 0 && arrive.y * (out.y - inn.y) > 0
            if forward && leaveHorizontal {
                let midX = (out.x + inn.x) / 2
                points.append(CGPoint(x: midX, y: out.y))
                points.append(CGPoint(x: midX, y: inn.y))
            } else if forward {
                let midY = (out.y + inn.y) / 2
                points.append(CGPoint(x: out.x, y: midY))
                points.append(CGPoint(x: inn.x, y: midY))
            } else if leaveHorizontal {
                let midY = (out.y + inn.y) / 2
                points.append(CGPoint(x: out.x, y: midY))
                points.append(CGPoint(x: inn.x, y: midY))
            } else {
                let midX = (out.x + inn.x) / 2
                points.append(CGPoint(x: midX, y: out.y))
                points.append(CGPoint(x: midX, y: inn.y))
            }
        } else if leaveHorizontal {
            points.append(CGPoint(x: inn.x, y: out.y))
        } else {
            points.append(CGPoint(x: out.x, y: inn.y))
        }
        points.append(inn)
        points.append(end)
        return simplify(points)
    }

    private static func axis(_ dir: CGPoint, fallback: CGPoint) -> CGPoint {
        if abs(dir.x) < 0.01 && abs(dir.y) < 0.01 { return fallback }
        if abs(dir.x) >= abs(dir.y) { return CGPoint(x: dir.x >= 0 ? 1 : -1, y: 0) }
        return CGPoint(x: 0, y: dir.y >= 0 ? 1 : -1)
    }

    private static func simplify(_ points: [CGPoint]) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var result = [last]
        for point in points.dropFirst() {
            if hypot(point.x - last.x, point.y - last.y) < 0.01 { continue }
            if result.count >= 2 {
                let prev = result[result.count - 2]
                let collinear = abs((last.x - prev.x) * (point.y - last.y) - (last.y - prev.y) * (point.x - last.x)) < 0.0001
                if collinear {
                    let dot = (last.x - prev.x) * (point.x - last.x) + (last.y - prev.y) * (point.y - last.y)
                    if dot < 0 { result.removeLast() }
                    else { result[result.count - 1] = point }
                    last = result[result.count - 1]
                    if dot < 0 {
                        result.append(point)
                        last = point
                    }
                    continue
                }
            }
            result.append(point)
            last = point
        }
        return result
    }
}

private let crossPoints: [(Double, Double)] = [(0.35, 0), (0.65, 0), (0.65, 0.35), (1, 0.35), (1, 0.65), (0.65, 0.65), (0.65, 1), (0.35, 1), (0.35, 0.65), (0, 0.65), (0, 0.35), (0.35, 0.35)]
private let plusPoints: [(Double, Double)] = [(0.35, 0), (0.65, 0), (0.65, 0.35), (1, 0.35), (1, 0.65), (0.65, 0.65), (0.65, 1), (0.35, 1), (0.35, 0.65), (0, 0.65), (0, 0.35), (0.35, 0.35)]
private let rightArrow: [(Double, Double)] = [(0, 0.2), (0.62, 0.2), (0.62, 0), (1, 0.5), (0.62, 1), (0.62, 0.8), (0, 0.8)]
private let upArrow: [(Double, Double)] = [(0.2, 0), (0.8, 0), (0.8, 0.62), (1, 0.62), (0.5, 1), (0, 0.62), (0.2, 0.62)]

private func box(_ id: Int, _ width: Double, _ height: Double, polygon: [(Double, Double)]?, text: String = "") -> ShapeNode {
    if let polygon { return poly(id, width, height, polygon, text: text) }
    return poly(id, width, height, [(0, 0), (1, 0), (1, 1), (0, 1)], text: text)
}

private func poly(_ id: Int, _ width: Double, _ height: Double, _ points: [(Double, Double)], text: String = "") -> ShapeNode {
    var shape = base(id, width, height, text: text)
    shape.geometry = [polygonSection(points)]
    shape.connections = sideConnections()
    return shape
}

private func rounded(_ id: Int, _ width: Double, _ height: Double, radius: Double, text: String = "") -> ShapeNode {
    var shape = poly(id, width, height, [(0, 0), (1, 0), (1, 1), (0, 1)], text: text)
    shape.setNumber("Rounding", radius)
    return shape
}

private func ellipse(_ id: Int, _ width: Double, _ height: Double, text: String = "") -> ShapeNode {
    var shape = base(id, width, height, text: text)
    var section = GeoSection()
    section.rows = [GeoRow(type: "Ellipse", ix: 1, cells: [
        "X": Cell(value: Format.number(width / 2), formula: "Width*0.5"),
        "Y": Cell(value: Format.number(height / 2), formula: "Height*0.5"),
        "A": Cell(value: Format.number(width), formula: "Width*1"),
        "B": Cell(value: Format.number(height / 2), formula: "Height*0.5"),
        "C": Cell(value: Format.number(width / 2), formula: "Width*0.5"),
        "D": Cell(value: Format.number(height), formula: "Height*1")
    ])]
    shape.geometry = [section]
    shape.connections = sideConnections()
    return shape
}

private func regular(_ id: Int, _ width: Double, _ height: Double, sides: Int, star: Bool) -> ShapeNode {
    var points: [(Double, Double)] = []
    let count = star ? sides * 2 : sides
    for index in 0..<count {
        let radius = star && index % 2 == 1 ? 0.38 : 0.5
        let angle = (Double(index) / Double(count)) * 2 * Double.pi - Double.pi / 2
        points.append((0.5 + cos(angle) * radius, 0.5 + sin(angle) * radius))
    }
    return poly(id, width, height, points)
}

private func frame(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.6, 1.1, text: "")
    var outer = polygonSection([(0, 0), (1, 0), (1, 1), (0, 1)])
    var inner = polygonSection([(0.12, 0.16), (0.88, 0.16), (0.88, 0.84), (0.12, 0.84)])
    inner.noFill = false
    shape.geometry = [outer, inner]
    shape.connections = sideConnections()
    return shape
}

private func can(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.1, 1.4, text: "")
    shape.geometry = [cylinderSection(top: 0.82)]
    shape.connections = sideConnections()
    return shape
}

private func database(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.2, 1.4, text: "Data")
    shape.geometry = [cylinderSection(top: 0.78)]
    shape.connections = sideConnections()
    return shape
}

private func stored(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.5, 1, text: "Stored")
    var section = GeoSection()
    section.rows = [
        rel("RelMoveTo", 1, 0.12, 0),
        rel("RelCubBezTo", 2, 0, 0.5, 0.12, 0.15, 0.12, 0.85),
        rel("RelLineTo", 3, 0, 1),
        rel("RelLineTo", 4, 1, 1),
        rel("RelLineTo", 5, 1, 0),
        rel("RelLineTo", 6, 0.12, 0)
    ]
    shape.geometry = [section]
    shape.connections = sideConnections()
    return shape
}

private func document(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.4, 1.1, text: "Document")
    var section = GeoSection()
    section.rows = [
        rel("RelMoveTo", 1, 0, 0.22),
        rel("RelLineTo", 2, 0, 1),
        rel("RelLineTo", 3, 1, 1),
        rel("RelLineTo", 4, 1, 0.22),
        rel("RelCubBezTo", 5, 0.5, 0.02, 0.85, 0.22, 0.7, 0.02),
        rel("RelCubBezTo", 6, 0, 0.22, 0.3, 0.02, 0.15, 0.22)
    ]
    shape.geometry = [section]
    shape.connections = sideConnections()
    return shape
}

private func predefined(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.6, 1, text: "Process")
    var main = polygonSection([(0, 0), (1, 0), (1, 1), (0, 1)])
    var bars = GeoSection()
    bars.noFill = true
    bars.rows = [
        rel("RelMoveTo", 1, 0.12, 0),
        rel("RelLineTo", 2, 0.12, 1),
        rel("RelMoveTo", 3, 0.88, 0),
        rel("RelLineTo", 4, 0.88, 1)
    ]
    shape.geometry = [main, bars]
    shape.connections = sideConnections()
    return shape
}

private func display(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.5, 1, text: "Display")
    var section = GeoSection()
    section.rows = [
        rel("RelMoveTo", 1, 0.15, 0),
        rel("RelLineTo", 2, 0.85, 0),
        rel("RelCubBezTo", 3, 1, 0.5, 0.85, 0, 1, 0.2),
        rel("RelCubBezTo", 4, 0.85, 1, 1, 0.8, 0.85, 1),
        rel("RelLineTo", 5, 0, 1),
        rel("RelLineTo", 6, 0.15, 0)
    ]
    shape.geometry = [section]
    shape.connections = sideConnections()
    return shape
}

private func delay(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.4, 1, text: "Delay")
    var section = GeoSection()
    section.rows = [
        rel("RelMoveTo", 1, 0, 0),
        rel("RelLineTo", 2, 0.65, 0),
        rel("RelCubBezTo", 3, 0.65, 1, 1, 0, 1.05, 0.5),
        rel("RelCubBezTo", 4, 0.65, 1, 1.05, 0.5, 1, 1),
        rel("RelLineTo", 5, 0, 1),
        rel("RelLineTo", 6, 0, 0)
    ]
    shape.geometry = [section]
    shape.connections = sideConnections()
    return shape
}

private func internalStorage(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.3, 1.1, text: "Storage")
    var main = polygonSection([(0, 0), (1, 0), (1, 1), (0, 1)])
    var bars = GeoSection()
    bars.noFill = true
    bars.rows = [
        rel("RelMoveTo", 1, 0, 0.78),
        rel("RelLineTo", 2, 1, 0.78),
        rel("RelMoveTo", 3, 0.18, 0),
        rel("RelLineTo", 4, 0.18, 1)
    ]
    shape.geometry = [main, bars]
    shape.connections = sideConnections()
    return shape
}

private func orJunction(_ id: Int) -> ShapeNode {
    var shape = ellipse(id, 0.7, 0.7, text: "")
    var lines = GeoSection()
    lines.noFill = true
    lines.rows = [
        rel("RelMoveTo", 1, 0.5, 0.12),
        rel("RelLineTo", 2, 0.5, 0.88),
        rel("RelMoveTo", 3, 0.12, 0.5),
        rel("RelLineTo", 4, 0.88, 0.5)
    ]
    shape.geometry.append(lines)
    return shape
}

private func note(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.5, 1, text: "Note")
    shape.geometry = [polygonSection([(0, 0), (1, 0), (1, 0.75), (0.75, 1), (0, 1)])]
    shape.connections = sideConnections()
    shape.setCell("FillForegnd", value: "#FFF2CC", clearFormula: true)
    return shape
}

private func callout(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.8, 1.1, text: "Callout")
    shape.geometry = [polygonSection([(0, 0.25), (0.2, 0.25), (0.08, 0), (0.45, 0.25), (1, 0.25), (1, 1), (0, 1)])]
    shape.connections = sideConnections()
    return shape
}

private func speech(_ id: Int) -> ShapeNode {
    var shape = rounded(id, 1.7, 1.15, radius: 0.18, text: "Comment")
    return shape
}

private func textBox(_ id: Int) -> ShapeNode {
    var shape = base(id, 1.8, 0.6, text: "Text")
    shape.geometry = [polygonSection([(0, 0), (1, 0), (1, 1), (0, 1)])]
    shape.setCell("FillPattern", value: "0", clearFormula: true)
    shape.setCell("LinePattern", value: "0", clearFormula: true)
    shape.paragraph = [GeoRow(type: "", ix: 0, cells: ["HorzAlign": Cell(value: "0")])]
    shape.setCell("VerticalAlign", value: "1", clearFormula: true)
    return shape
}

private func connector(_ id: Int, style: ConnectorStyle, arrow: Int) -> ShapeNode {
    var shape = base(id, 1.5, 0, text: "")
    shape.setCell("LinePattern", value: "1", clearFormula: true)
    shape.setCell("FillPattern", value: "0", clearFormula: true)
    shape.setCell("EndArrow", value: String(arrow), clearFormula: true)
    shape.setCell("EndArrowSize", value: "2", clearFormula: true)
    shape.setCell("BeginArrow", value: "0", clearFormula: true)
    let points: [CGPoint]
    switch style {
    case .straight:
        points = [CGPoint(x: 0, y: 0), CGPoint(x: 1.5, y: 0)]
    case .simple:
        points = [CGPoint(x: 0, y: 0), CGPoint(x: 0.9, y: 0), CGPoint(x: 0.9, y: 0.55)]
    case .curve:
        points = ConnectorRoute.route(
            style: .curve,
            start: CGPoint(x: 0, y: 0.1),
            startDir: CGPoint(x: 1, y: 0),
            end: CGPoint(x: 1.5, y: 0.7),
            endDir: CGPoint(x: 1, y: 0)
        )
    case .elbow:
        points = [CGPoint(x: 0, y: 0), CGPoint(x: 0.75, y: 0), CGPoint(x: 0.75, y: 0.5), CGPoint(x: 1.5, y: 0.5)]
    }
    ConnectorRoute.apply(points: points, to: &shape, style: style)
    shape.setCell("ObjType", value: "2", clearFormula: true)
    return shape
}

private func base(_ id: Int, _ width: Double, _ height: Double, text: String) -> ShapeNode {
    var shape = ShapeNode(id: id)
    shape.setCell("Width", value: Format.number(width))
    shape.setCell("Height", value: Format.number(height))
    shape.setCell("LocPinX", value: Format.number(width / 2), formula: "Width*0.5")
    shape.setCell("LocPinY", value: Format.number(height / 2), formula: "Height*0.5")
    shape.setCell("Angle", value: "0")
    shape.setCell("FillForegnd", value: "#FFFFFF")
    shape.setCell("FillPattern", value: "1")
    shape.setCell("LineColor", value: "#000000")
    shape.setCell("LineWeight", value: "0.0104166667")
    shape.setCell("LinePattern", value: "1")
    shape.setCell("VerticalAlign", value: "1")
    shape.character = [GeoRow(type: "", ix: 0, cells: [
        "Font": Cell(value: "Calibri"),
        "Size": Cell(value: "0.1666667"),
        "Color": Cell(value: "#000000"),
        "Style": Cell(value: "0")
    ])]
    shape.paragraph = [GeoRow(type: "", ix: 0, cells: ["HorzAlign": Cell(value: "1")])]
    shape.text = text
    shape.hasText = !text.isEmpty
    shape.detached = true
    return shape
}

private func polygonSection(_ points: [(Double, Double)]) -> GeoSection {
    var section = GeoSection()
    let closed = points + [points[0]]
    for (index, point) in closed.enumerated() {
        section.rows.append(rel(index == 0 ? "RelMoveTo" : "RelLineTo", index + 1, point.0, point.1))
    }
    return section
}

private func cylinderSection(top: Double) -> GeoSection {
    var section = GeoSection()
    let bottom = 1 - top
    section.rows = [
        rel("RelMoveTo", 1, 0, bottom),
        rel("RelLineTo", 2, 0, top),
        rel("RelCubBezTo", 3, 1, top, 0, top + 0.16, 0.5, top + 0.16),
        rel("RelCubBezTo", 4, 1, top, 0.5, top + 0.16, 1, top + 0.16),
        rel("RelLineTo", 5, 1, bottom),
        rel("RelCubBezTo", 6, 0, bottom, 1, bottom - 0.12, 0.5, bottom - 0.12),
        rel("RelCubBezTo", 7, 0, bottom, 0.5, bottom - 0.12, 0, bottom - 0.12)
    ]
    return section
}

private func rel(_ type: String, _ ix: Int, _ x: Double, _ y: Double, _ a: Double? = nil, _ b: Double? = nil, _ c: Double? = nil, _ d: Double? = nil) -> GeoRow {
    var cells: [String: Cell] = [
        "X": Cell(value: Format.number(x)),
        "Y": Cell(value: Format.number(y))
    ]
    if let a, let b {
        cells["A"] = Cell(value: Format.number(a))
        cells["B"] = Cell(value: Format.number(b))
    }
    if let c, let d {
        cells["C"] = Cell(value: Format.number(c))
        cells["D"] = Cell(value: Format.number(d))
    }
    return GeoRow(type: type, ix: ix, cells: cells)
}

private func sideConnections() -> [GeoRow] {
    [
        connection(0, 0.5, 0, 0, -1),
        connection(1, 1, 0.5, 1, 0),
        connection(2, 0.5, 1, 0, 1),
        connection(3, 0, 0.5, -1, 0)
    ]
}

private func connection(_ ix: Int, _ x: Double, _ y: Double, _ dx: Double, _ dy: Double) -> GeoRow {
    GeoRow(type: "Connection", ix: ix, cells: [
        "X": Cell(value: Format.number(x), formula: "Width*\(Format.number(x))"),
        "Y": Cell(value: Format.number(y), formula: "Height*\(Format.number(y))"),
        "DirX": Cell(value: Format.number(dx)),
        "DirY": Cell(value: Format.number(dy)),
        "Type": Cell(value: "0")
    ])
}
