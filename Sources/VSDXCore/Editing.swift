import CoreGraphics
import Foundation

public enum AlignKind: String, CaseIterable {
    case left, center, right, top, middle, bottom
}

public enum DistributeKind {
    case horizontal, vertical
}

public enum OrderKind {
    case front, back, forward, backward
}

public enum GridSnap {
    public static let spacing = 0.1

    public static func snap(_ value: Double) -> Double {
        (value / spacing).rounded() * spacing
    }

    public static func translation(bounds: CGRect, dx: Double, dy: Double) -> (Double, Double) {
        let movedX = Double(bounds.minX) + dx
        let movedY = Double(bounds.minY) + dy
        return (dx + snap(movedX) - movedX, dy + snap(movedY) - movedY)
    }
}

public enum ShapePorts {
    public static func standardRows() -> [GeoRow] {
        [
            row(0, 0.5, 0, 0, -1),
            row(1, 1, 0.5, 1, 0),
            row(2, 0.5, 1, 0, 1),
            row(3, 0, 0.5, -1, 0)
        ]
    }

    public static func ensure(_ shape: inout ShapeNode) {
        guard !shape.is1D, shape.connections.isEmpty else { return }
        shape.connections = standardRows()
        shape.detached = true
        shape.original = nil
    }

    public static func install(_ shape: inout ShapeNode) {
        guard !shape.is1D else { return }
        let width = Format.parseDouble(shape.cell("Width")?.value) ?? 1
        let height = Format.parseDouble(shape.cell("Height")?.value) ?? 1
        let rounding = Format.parseDouble(shape.cell("Rounding")?.value) ?? 0
        var page = DiagramPage(id: 0, name: "Ports", width: max(width, 1), height: max(height, 1))
        page.shapes = [shape]
        let scope = EvalScope(page: page, theme: ThemeColors(), colors: [:])
        var samples: [CGPoint] = []
        for section in shape.geometry where !section.noShow && !section.noLine {
            if section.rows.contains(where: { $0.type == "Ellipse" && !$0.deleted }) {
                for row in section.rows where row.type == "Ellipse" && !row.deleted {
                    samples.append(contentsOf: ellipsePoints(row, shape: shape, scope: scope))
                }
                continue
            }
            let pieces = segments(section, shape: shape, scope: scope, width: width, height: height)
            if rounding > 0.0001, let rect = axisAlignedRect(pieces) {
                samples.append(contentsOf: roundedRectPoints(rect, radius: CGFloat(rounding)))
            } else {
                for piece in pieces {
                    samples.append(piece.start)
                    samples.append(piece.mid)
                    samples.append(piece.end)
                }
            }
        }
        let unique = dedupe(samples, minimum: 0.012)
        guard !unique.isEmpty else {
            shape.connections = standardRows()
            return
        }
        let centerX = width / 2
        let centerY = height / 2
        shape.connections = unique.enumerated().map { index, point in
            let dx = Double(point.x) - centerX
            let dy = Double(point.y) - centerY
            let length = max(0.001, hypot(dx, dy))
            let fx = width == 0 ? 0 : Double(point.x) / width
            let fy = height == 0 ? 0 : Double(point.y) / height
            return row(index, fx, fy, dx / length, dy / length)
        }
        shape.detached = true
        shape.original = nil
    }

    private struct Segment {
        var start: CGPoint
        var mid: CGPoint
        var end: CGPoint
    }

    private static func segments(_ section: GeoSection, shape: ShapeNode, scope: EvalScope, width: Double, height: Double) -> [Segment] {
        var pieces: [Segment] = []
        var current: CGPoint?
        for row in section.rows where !row.deleted {
            let relative = row.type.hasPrefix("Rel")
            let end = localPoint(row, shape: shape, scope: scope, relative: relative, width: width, height: height)
            switch row.type {
            case "MoveTo", "RelMoveTo":
                current = end
            case "LineTo", "RelLineTo":
                if let start = current {
                    pieces.append(Segment(start: start, mid: mix(start, end, 0.5), end: end))
                }
                current = end
            case "RelCubBezTo", "CubBezTo":
                if let start = current {
                    let c1 = localPoint(row, shape: shape, scope: scope, relative: relative, width: width, height: height, xName: "A", yName: "B")
                    let c2 = localPoint(row, shape: shape, scope: scope, relative: relative, width: width, height: height, xName: "C", yName: "D")
                    pieces.append(Segment(start: start, mid: cubic(start, c1, c2, end, 0.5), end: end))
                }
                current = end
            case "RelQuadBezTo", "QuadBezTo":
                if let start = current {
                    let control = localPoint(row, shape: shape, scope: scope, relative: relative, width: width, height: height, xName: "A", yName: "B")
                    pieces.append(Segment(start: start, mid: quadratic(start, control, end, 0.5), end: end))
                }
                current = end
            case "ArcTo":
                if let start = current {
                    let bow = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "A"))
                    pieces.append(Segment(start: start, mid: arcMid(start, end, bow: bow), end: end))
                }
                current = end
            case "EllipticalArcTo", "RelEllipticalArcTo":
                if let start = current {
                    let through = localPoint(row, shape: shape, scope: scope, relative: relative, width: width, height: height, xName: "A", yName: "B")
                    pieces.append(Segment(start: start, mid: through, end: end))
                }
                current = end
            default:
                break
            }
        }
        return pieces
    }

    private static func localPoint(_ row: GeoRow, shape: ShapeNode, scope: EvalScope, relative: Bool, width: Double, height: Double, xName: String = "X", yName: String = "Y") -> CGPoint {
        var x = scope.evalRowNumber(shape: shape, row: row, name: xName)
        var y = scope.evalRowNumber(shape: shape, row: row, name: yName)
        if relative {
            x *= width
            y *= height
        }
        return CGPoint(x: x, y: y)
    }

    private static func ellipsePoints(_ row: GeoRow, shape: ShapeNode, scope: EvalScope) -> [CGPoint] {
        let cx = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "X"))
        let cy = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "Y"))
        let ax = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "A")) - cx
        let ay = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "B")) - cy
        let bx = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "C")) - cx
        let by = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "D")) - cy
        return (0..<8).map { step in
            let angle = CGFloat(step) / 8 * 2 * .pi
            return CGPoint(x: cx + ax * cos(angle) + bx * sin(angle), y: cy + ay * cos(angle) + by * sin(angle))
        }
    }

    private static func axisAlignedRect(_ pieces: [Segment]) -> CGRect? {
        guard pieces.count >= 4 else { return nil }
        var rect = CGRect.null
        var points: [CGPoint] = []
        for piece in pieces {
            points.append(piece.start)
            points.append(piece.end)
            rect = rect.union(CGRect(origin: piece.start, size: .zero))
            rect = rect.union(CGRect(origin: piece.end, size: .zero))
        }
        guard rect.width > 0.05, rect.height > 0.05 else { return nil }
        for point in points {
            let onX = abs(point.x - rect.minX) < 0.02 || abs(point.x - rect.maxX) < 0.02
            let onY = abs(point.y - rect.minY) < 0.02 || abs(point.y - rect.maxY) < 0.02
            if !onX || !onY { return nil }
        }
        return rect
    }

    private static func roundedRectPoints(_ rect: CGRect, radius: CGFloat) -> [CGPoint] {
        let r = min(radius, rect.width / 2, rect.height / 2)
        if r < 0.001 {
            return [
                CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)
            ]
        }
        var points: [CGPoint] = []
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX + r, y: rect.minY + r), .pi, .pi * 1.5),
            (CGPoint(x: rect.maxX - r, y: rect.minY + r), -.pi / 2, 0),
            (CGPoint(x: rect.maxX - r, y: rect.maxY - r), 0, .pi / 2),
            (CGPoint(x: rect.minX + r, y: rect.maxY - r), .pi / 2, .pi)
        ]
        for (center, start, end) in corners {
            let mid = (start + end) / 2
            for angle in [start, mid, end] {
                points.append(CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle)))
            }
        }
        if rect.width > r * 2 + 0.01 {
            points.append(CGPoint(x: rect.midX, y: rect.minY))
            points.append(CGPoint(x: rect.midX, y: rect.maxY))
        }
        if rect.height > r * 2 + 0.01 {
            points.append(CGPoint(x: rect.minX, y: rect.midY))
            points.append(CGPoint(x: rect.maxX, y: rect.midY))
        }
        return points
    }

    private static func dedupe(_ points: [CGPoint], minimum: CGFloat) -> [CGPoint] {
        var kept: [CGPoint] = []
        for point in points where !kept.contains(where: { hypot($0.x - point.x, $0.y - point.y) < minimum }) {
            kept.append(point)
        }
        return kept
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
            y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
        )
    }

    private static func quadratic(_ p0: CGPoint, _ control: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * control.x + t * t * p1.x,
            y: u * u * p0.y + 2 * u * t * control.y + t * t * p1.y
        )
    }

    private static func arcMid(_ start: CGPoint, _ end: CGPoint, bow: CGFloat) -> CGPoint {
        let mid = mix(start, end, 0.5)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let chord = hypot(dx, dy)
        if chord < 0.0001 || abs(bow) < 0.0001 { return mid }
        return CGPoint(x: mid.x + (-dy / chord) * bow, y: mid.y + (dx / chord) * bow)
    }

    private static func row(_ ix: Int, _ x: Double, _ y: Double, _ dx: Double, _ dy: Double) -> GeoRow {
        GeoRow(type: "Connection", ix: ix, cells: [
            "X": Cell(value: Format.number(x), formula: "Width*\(Format.number(x))"),
            "Y": Cell(value: Format.number(y), formula: "Height*\(Format.number(y))"),
            "DirX": Cell(value: Format.number(dx)),
            "DirY": Cell(value: Format.number(dy)),
            "Type": Cell(value: "0")
        ])
    }
}

public enum DiagramEdit {
    public static func delete(page: inout DiagramPage, ids: Set<Int>) {
        func touches(_ shape: ShapeNode) -> Bool {
            if ids.contains(shape.id) { return true }
            return shape.children.contains(where: touches)
        }
        func detach(_ shapes: inout [ShapeNode]) {
            for index in shapes.indices {
                if shapes[index].children.contains(where: touches) {
                    shapes[index].detached = true
                    shapes[index].original = nil
                }
                detach(&shapes[index].children)
            }
        }
        detach(&page.shapes)
        page.removeShapes(ids: ids)
    }

    public static func duplicate(page: inout DiagramPage, ids: [Int]) -> [Int] {
        var newIds: [Int] = []
        var next = page.nextShapeId()
        let top = page.shapes.filter { ids.contains($0.id) }
        for shape in top {
            var copy = shape
            reassign(&copy, next: &next)
            copy.original = nil
            copy.detached = true
            copy.masterId = nil
            copy.setNumber("PinX", (Format.parseDouble(copy.cell("PinX")?.value) ?? 0) + 0.25, clearFormula: true)
            copy.setNumber("PinY", (Format.parseDouble(copy.cell("PinY")?.value) ?? 0) - 0.25, clearFormula: true)
            if copy.is1D {
                copy.setNumber("BeginX", (Format.parseDouble(copy.cell("BeginX")?.value) ?? 0) + 0.25, clearFormula: true)
                copy.setNumber("BeginY", (Format.parseDouble(copy.cell("BeginY")?.value) ?? 0) - 0.25, clearFormula: true)
                copy.setNumber("EndX", (Format.parseDouble(copy.cell("EndX")?.value) ?? 0) + 0.25, clearFormula: true)
                copy.setNumber("EndY", (Format.parseDouble(copy.cell("EndY")?.value) ?? 0) - 0.25, clearFormula: true)
            }
            newIds.append(copy.id)
            page.shapes.append(copy)
        }
        return newIds
    }

    public static func nudge(page: inout DiagramPage, ids: Set<Int>, dx: Double, dy: Double, theme: ThemeColors, colors: [Int: String]) {
        translate(page: &page, ids: ids, dx: dx, dy: dy)
        reroute(page: &page, moved: ids, theme: theme, colors: colors)
    }

    public static func translate(page: inout DiagramPage, ids: Set<Int>, dx: Double, dy: Double) {
        for id in ids {
            guard var shape = page.shape(id: id) else { continue }
            let targets = Set(page.connects.filter { $0.fromId == id }.map(\.toId))
            if shape.is1D && !targets.isEmpty && !targets.isSubset(of: ids) { continue }
            let pinX = Format.parseDouble(shape.cell("PinX")?.value) ?? 0
            let pinY = Format.parseDouble(shape.cell("PinY")?.value) ?? 0
            shape.setNumber("PinX", pinX + dx, clearFormula: true)
            shape.setNumber("PinY", pinY + dy, clearFormula: true)
            if shape.is1D {
                shape.setNumber("BeginX", (Format.parseDouble(shape.cell("BeginX")?.value) ?? 0) + dx, clearFormula: true)
                shape.setNumber("BeginY", (Format.parseDouble(shape.cell("BeginY")?.value) ?? 0) + dy, clearFormula: true)
                shape.setNumber("EndX", (Format.parseDouble(shape.cell("EndX")?.value) ?? 0) + dx, clearFormula: true)
                shape.setNumber("EndY", (Format.parseDouble(shape.cell("EndY")?.value) ?? 0) + dy, clearFormula: true)
            }
            page.updateShape(id: id) { $0 = shape }
        }
    }

    public static func resize(page: inout DiagramPage, id: Int, pinX: Double, pinY: Double, width: Double, height: Double, theme: ThemeColors, colors: [Int: String]) {
        page.updateShape(id: id) { shape in
            shape.setNumber("PinX", pinX, clearFormula: true)
            shape.setNumber("PinY", pinY, clearFormula: true)
            shape.setNumber("Width", max(0.05, width), clearFormula: true)
            shape.setNumber("Height", max(0.05, height), clearFormula: true)
        }
        refreshDerived(page: &page, id: id, theme: theme, colors: colors)
        reroute(page: &page, moved: [id], theme: theme, colors: colors)
    }

    public static func refreshDerived(page: inout DiagramPage, id: Int, theme: ThemeColors, colors: [Int: String]) {
        guard var shape = page.shape(id: id) else { return }
        let scope = EvalScope(page: page, theme: theme, colors: colors)
        scope.useFormulas = true
        for name in ["LocPinX", "LocPinY"] {
            guard shape.cell(name)?.formula?.isEmpty == false else { continue }
            let value = scope.number(shape: shape, cell: name)
            if var cell = shape.cells[name] {
                cell.value = Format.number(value)
                shape.cells[name] = cell
            }
        }
        for sectionIndex in shape.geometry.indices {
            for rowIndex in shape.geometry[sectionIndex].rows.indices {
                let row = shape.geometry[sectionIndex].rows[rowIndex]
                for key in row.cells.keys {
                    guard let formula = row.formula(key), !formula.isEmpty, formula != "Inh", formula != "No Formula" else { continue }
                    let value = scope.evalRowNumber(shape: shape, row: row, name: key)
                    shape.geometry[sectionIndex].rows[rowIndex].cells[key]?.value = Format.number(value)
                }
            }
        }
        for rowIndex in shape.connections.indices {
            let row = shape.connections[rowIndex]
            for key in ["X", "Y"] {
                guard let formula = row.formula(key), !formula.isEmpty, formula != "Inh" else { continue }
                let value = scope.evalRowNumber(shape: shape, row: row, name: key)
                shape.connections[rowIndex].cells[key]?.value = Format.number(value)
            }
        }
        page.updateShape(id: id) { $0 = shape }
    }

    public static func setAngle(page: inout DiagramPage, id: Int, angle: Double) {
        page.updateShape(id: id) { shape in
            shape.setNumber("Angle", angle, clearFormula: true)
        }
    }

    public static func align(page: inout DiagramPage, ids: [Int], kind: AlignKind, theme: ThemeColors, colors: [Int: String]) {
        let items = PageLayout.items(page: page, theme: theme, colors: colors).filter { ids.contains($0.id) && $0.parentId == nil }
        guard let anchor = items.first(where: { $0.id == ids.first }) ?? items.first else { return }
        for item in items where item.id != anchor.id {
            var dx = 0.0
            var dy = 0.0
            switch kind {
            case .left: dx = Double(anchor.bounds.minX - item.bounds.minX)
            case .center: dx = Double(anchor.bounds.midX - item.bounds.midX)
            case .right: dx = Double(anchor.bounds.maxX - item.bounds.maxX)
            case .top: dy = Double(anchor.bounds.maxY - item.bounds.maxY)
            case .middle: dy = Double(anchor.bounds.midY - item.bounds.midY)
            case .bottom: dy = Double(anchor.bounds.minY - item.bounds.minY)
            }
            translate(page: &page, ids: [item.id], dx: dx, dy: dy)
        }
        reroute(page: &page, moved: Set(ids), theme: theme, colors: colors)
    }

    public static func distribute(page: inout DiagramPage, ids: [Int], kind: DistributeKind, theme: ThemeColors, colors: [Int: String]) {
        var items = PageLayout.items(page: page, theme: theme, colors: colors).filter { ids.contains($0.id) && $0.parentId == nil }
        guard items.count >= 3 else { return }
        if kind == .horizontal { items.sort { $0.bounds.minX < $1.bounds.minX } }
        else { items.sort { $0.bounds.minY < $1.bounds.minY } }
        let first = items[0]
        let last = items[items.count - 1]
        let span = kind == .horizontal ? last.bounds.maxX - first.bounds.minX : last.bounds.maxY - first.bounds.minY
        let total = items.reduce(CGFloat(0)) { $0 + (kind == .horizontal ? $1.bounds.width : $1.bounds.height) }
        let gap = (span - total) / CGFloat(items.count - 1)
        var cursor = kind == .horizontal ? first.bounds.maxX + gap : first.bounds.maxY + gap
        for item in items.dropFirst().dropLast() {
            if kind == .horizontal {
                let dx = Double(cursor - item.bounds.minX)
                translate(page: &page, ids: [item.id], dx: dx, dy: 0)
                cursor += item.bounds.width + gap
            } else {
                let dy = Double(cursor - item.bounds.minY)
                translate(page: &page, ids: [item.id], dx: 0, dy: dy)
                cursor += item.bounds.height + gap
            }
        }
        reroute(page: &page, moved: Set(ids), theme: theme, colors: colors)
    }

    public static func order(page: inout DiagramPage, ids: Set<Int>, kind: OrderKind) {
        switch kind {
        case .front:
            let moving = page.shapes.filter { ids.contains($0.id) }
            page.shapes.removeAll { ids.contains($0.id) }
            page.shapes.append(contentsOf: moving)
        case .back:
            let moving = page.shapes.filter { ids.contains($0.id) }
            page.shapes.removeAll { ids.contains($0.id) }
            page.shapes.insert(contentsOf: moving, at: 0)
        case .forward:
            for index in page.shapes.indices.reversed() where ids.contains(page.shapes[index].id) && index + 1 < page.shapes.count && !ids.contains(page.shapes[index + 1].id) {
                page.shapes.swapAt(index, index + 1)
            }
        case .backward:
            for index in page.shapes.indices where ids.contains(page.shapes[index].id) && index > 0 && !ids.contains(page.shapes[index - 1].id) {
                page.shapes.swapAt(index, index - 1)
            }
        }
    }

    public static func group(page: inout DiagramPage, ids: [Int], theme: ThemeColors, colors: [Int: String]) -> Int? {
        let items = PageLayout.items(page: page, theme: theme, colors: colors)
        let selected = page.shapes.filter { ids.contains($0.id) }
        guard selected.count >= 2 else { return nil }
        let boxes = items.filter { ids.contains($0.id) && $0.parentId == nil }
        var union = CGRect.null
        for box in boxes { union = union.union(box.bounds) }
        guard !union.isNull, union.width > 0.01, union.height > 0.01 else { return nil }
        var group = ShapeNode(id: page.nextShapeId(), kind: "Group")
        group.name = "Group"
        group.nameU = "Group"
        group.detached = true
        let width = Double(union.width)
        let height = Double(union.height)
        group.setNumber("Width", width, clearFormula: true)
        group.setNumber("Height", height, clearFormula: true)
        group.setCell("LocPinX", value: Format.number(width / 2), formula: "Width*0.5")
        group.setCell("LocPinY", value: Format.number(height / 2), formula: "Height*0.5")
        group.setNumber("PinX", Double(union.midX), clearFormula: true)
        group.setNumber("PinY", Double(union.midY), clearFormula: true)
        group.setNumber("Angle", 0, clearFormula: true)
        group.setCell("FillPattern", value: "0", clearFormula: true)
        group.setCell("LinePattern", value: "0", clearFormula: true)
        let originX = Double(union.minX)
        let originY = Double(union.minY)
        group.children = selected.map { shape in
            var child = shape
            child.parentId = group.id
            child.original = nil
            child.detached = true
            let pinX = Format.parseDouble(child.cell("PinX")?.value) ?? 0
            let pinY = Format.parseDouble(child.cell("PinY")?.value) ?? 0
            child.setNumber("PinX", pinX - originX, clearFormula: true)
            child.setNumber("PinY", pinY - originY, clearFormula: true)
            return child
        }
        page.shapes.removeAll { ids.contains($0.id) }
        page.shapes.append(group)
        return group.id
    }

    public static func ungroup(page: inout DiagramPage, ids: [Int]) -> [Int] {
        var created: [Int] = []
        for id in ids {
            guard let index = page.shapes.firstIndex(where: { $0.id == id }), !page.shapes[index].children.isEmpty else { continue }
            let group = page.shapes[index]
            let scope = EvalScope(page: page, theme: ThemeColors(), colors: [:])
            let transform = GeometryMath.localToPage(group, scope: scope)
            let angle = Format.parseDouble(group.cell("Angle")?.value) ?? 0
            var children = group.children
            for childIndex in children.indices {
                let local = CGPoint(x: Format.parseDouble(children[childIndex].cell("PinX")?.value) ?? 0, y: Format.parseDouble(children[childIndex].cell("PinY")?.value) ?? 0)
                let pagePoint = local.applying(transform)
                children[childIndex].parentId = nil
                children[childIndex].original = nil
                children[childIndex].detached = true
                children[childIndex].setNumber("PinX", Double(pagePoint.x), clearFormula: true)
                children[childIndex].setNumber("PinY", Double(pagePoint.y), clearFormula: true)
                let childAngle = Format.parseDouble(children[childIndex].cell("Angle")?.value) ?? 0
                children[childIndex].setNumber("Angle", childAngle + angle, clearFormula: true)
                created.append(children[childIndex].id)
            }
            page.shapes.remove(at: index)
            page.shapes.insert(contentsOf: children, at: index)
        }
        return created
    }

    public static func setFill(page: inout DiagramPage, ids: Set<Int>, color: String?) {
        for id in ids {
            page.updateShape(id: id) { shape in
                if let color {
                    shape.setCell("FillForegnd", value: color, clearFormula: true)
                    shape.setCell("FillPattern", value: "1", clearFormula: true)
                } else {
                    shape.setCell("FillPattern", value: "0", clearFormula: true)
                }
            }
        }
    }

    public static func setLine(page: inout DiagramPage, ids: Set<Int>, color: String? = nil, weight: Double? = nil, pattern: Int? = nil, beginArrow: Int? = nil, endArrow: Int? = nil) {
        for id in ids {
            page.updateShape(id: id) { shape in
                if let color { shape.setCell("LineColor", value: color, clearFormula: true) }
                if let weight { shape.setCell("LineWeight", value: Format.number(weight), clearFormula: true) }
                if let pattern { shape.setCell("LinePattern", value: String(pattern), clearFormula: true) }
                if let beginArrow { shape.setCell("BeginArrow", value: String(beginArrow), clearFormula: true) }
                if let endArrow { shape.setCell("EndArrow", value: String(endArrow), clearFormula: true) }
            }
        }
    }

    public static func setFont(page: inout DiagramPage, ids: Set<Int>, name: String? = nil, size: Double? = nil, color: String? = nil, bits: Int? = nil, align: Int? = nil, vertical: Int? = nil) {
        for id in ids {
            page.updateShape(id: id) { shape in
                if shape.character.isEmpty {
                    shape.character = [GeoRow(type: "", ix: 0, cells: [:])]
                }
                if let name { shape.character[0].cells["Font"] = Cell(value: name) }
                if let size { shape.character[0].cells["Size"] = Cell(value: Format.number(size)) }
                if let color { shape.character[0].cells["Color"] = Cell(value: color) }
                if let bits { shape.character[0].cells["Style"] = Cell(value: String(bits)) }
                if let align {
                    if shape.paragraph.isEmpty { shape.paragraph = [GeoRow(type: "", ix: 0)] }
                    shape.paragraph[0].cells["HorzAlign"] = Cell(value: String(align))
                }
                if let vertical { shape.setCell("VerticalAlign", value: String(vertical), clearFormula: true) }
                if shape.original != nil { shape.detached = true; shape.original = nil }
            }
        }
    }

    public static func reroute(page: inout DiagramPage, moved: Set<Int>, theme: ThemeColors, colors: [Int: String]) {
        let connectorIds = Set(page.connects.filter { moved.contains($0.toId) }.map(\.fromId))
        guard !connectorIds.isEmpty else { return }
        let scope = EvalScope(page: page, theme: theme, colors: colors)
        let layout = PageLayout.items(page: page, theme: theme, colors: colors)
        for connectorId in connectorIds {
            let links = page.connects.filter { $0.fromId == connectorId }
            guard var shape = page.shape(id: connectorId) else { continue }
            let styleValue = Int(Format.parseDouble(shape.cell("ShapeRouteStyle")?.value) ?? 1)
            let style: ConnectorStyle = styleValue == 0 ? .straight : (styleValue == 2 ? .curve : .elbow)
            let begin = endpoint(links: links, begin: true, scope: scope, layout: layout, fallback: CGPoint(x: Format.parseDouble(shape.cell("BeginX")?.value) ?? 0, y: Format.parseDouble(shape.cell("BeginY")?.value) ?? 0))
            let end = endpoint(links: links, begin: false, scope: scope, layout: layout, fallback: CGPoint(x: Format.parseDouble(shape.cell("EndX")?.value) ?? 0, y: Format.parseDouble(shape.cell("EndY")?.value) ?? 0))
            if shape.cell("UserRoute")?.value == "1", style == .elbow {
                var points = ConnectorRoute.pagePoints(shape)
                if points.count >= 2 {
                    points[0] = begin.point
                    points[points.count - 1] = end.point
                    if points.count >= 3 {
                        if abs(begin.dir.x) >= abs(begin.dir.y) { points[1].y = begin.point.y } else { points[1].x = begin.point.x }
                        let last = points.count - 1
                        if abs(end.dir.x) >= abs(end.dir.y) { points[last - 1].y = end.point.y } else { points[last - 1].x = end.point.x }
                    }
                    ConnectorRoute.apply(points: points, to: &shape)
                    shape.setCell("UserRoute", value: "1", clearFormula: true)
                }
            } else {
                let points = ConnectorRoute.route(style: style, start: begin.point, startDir: begin.dir, end: end.point, endDir: end.dir)
                ConnectorRoute.apply(points: points, to: &shape)
            }
            page.updateShape(id: connectorId) { $0 = shape }
        }
    }

    public static func addGluedConnector(page: inout DiagramPage, fromShape: Int, fromPort: Int, toShape: Int, toPort: Int, theme: ThemeColors, colors: [Int: String]) -> Int {
        page.updateShape(id: fromShape) { ShapePorts.ensure(&$0) }
        page.updateShape(id: toShape) { ShapePorts.ensure(&$0) }
        let id = page.nextShapeId()
        let shape = StencilCatalog.make(id: "connector", shapeId: id, center: CGPoint(x: 1, y: 1))
        page.shapes.append(shape)
        connect(page: &page, connectorId: id, begin: true, to: fromShape, part: 100 + fromPort, cell: "Connections.X\(fromPort + 1)")
        connect(page: &page, connectorId: id, begin: false, to: toShape, part: 100 + toPort, cell: "Connections.X\(toPort + 1)")
        reroute(page: &page, moved: [fromShape, toShape], theme: theme, colors: colors)
        return id
    }

    public static func connect(page: inout DiagramPage, connectorId: Int, begin: Bool, to shapeId: Int, part: Int, cell: String) {
        if part >= 100 {
            page.updateShape(id: shapeId) { ShapePorts.ensure(&$0) }
        }
        page.connects.removeAll { $0.fromId == connectorId && $0.isBegin == begin }
        page.connects.append(ShapeConnect(
            fromId: connectorId,
            fromCell: begin ? "BeginX" : "EndX",
            fromPart: begin ? 9 : 12,
            toId: shapeId,
            toCell: cell,
            toPart: part
        ))
    }

    private static func endpoint(links: [ShapeConnect], begin: Bool, scope: EvalScope, layout: [LayoutItem], fallback: CGPoint) -> (point: CGPoint, dir: CGPoint) {
        guard let link = links.first(where: { $0.isBegin == begin }), let item = layout.first(where: { $0.id == link.toId }), let shape = scope.shapes[link.toId] else {
            return (fallback, CGPoint(x: begin ? 1 : -1, y: 0))
        }
        if link.toPart >= 100, item.connections.indices.contains(link.toPart - 100) {
            let index = link.toPart - 100
            let row = shape.connections[safe: index]
            let angle = Format.parseDouble(shape.cell("Angle")?.value) ?? 0
            let dx = Format.parseDouble(row?.raw("DirX")) ?? 0
            let dy = Format.parseDouble(row?.raw("DirY")) ?? 0
            let dir = CGPoint(x: CGFloat(dx * cos(angle) - dy * sin(angle)), y: CGFloat(dx * sin(angle) + dy * cos(angle)))
            let length = max(0.001, hypot(dir.x, dir.y))
            return (item.connections[index], CGPoint(x: dir.x / length, y: dir.y / length))
        }
        let vector = CGPoint(x: fallback.x - item.center.x, y: fallback.y - item.center.y)
        if let nearest = item.connections.enumerated().min(by: { hypot($0.element.x - fallback.x, $0.element.y - fallback.y) < hypot($1.element.x - fallback.x, $1.element.y - fallback.y) }) {
            let out = CGPoint(x: nearest.element.x - item.center.x, y: nearest.element.y - item.center.y)
            let length = max(0.001, hypot(out.x, out.y))
            _ = vector
            return (nearest.element, CGPoint(x: out.x / length, y: out.y / length))
        }
        return (item.center, CGPoint(x: 1, y: 0))
    }

    private static func reassign(_ shape: inout ShapeNode, next: inout Int) {
        shape.id = next
        next += 1
        for index in shape.children.indices {
            shape.children[index].parentId = shape.id
            reassign(&shape.children[index], next: &next)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
