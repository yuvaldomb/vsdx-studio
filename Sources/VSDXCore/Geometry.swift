import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum GeometryMath {
    public static func localToParent(_ shape: ShapeNode, scope: EvalScope) -> CGAffineTransform {
        let pinX = scope.number(shape: shape, cell: "PinX")
        let pinY = scope.number(shape: shape, cell: "PinY")
        let angle = scope.number(shape: shape, cell: "Angle")
        let locX = scope.number(shape: shape, cell: "LocPinX")
        let locY = scope.number(shape: shape, cell: "LocPinY")
        let flipX: CGFloat = scope.number(shape: shape, cell: "FlipX") == 0 ? 1 : -1
        let flipY: CGFloat = scope.number(shape: shape, cell: "FlipY") == 0 ? 1 : -1
        let c = CGFloat(cos(angle))
        let s = CGFloat(sin(angle))
        let fx = flipX
        let fy = flipY
        let locXF = CGFloat(locX)
        let locYF = CGFloat(locY)
        return CGAffineTransform(
            a: c * fx,
            b: s * fx,
            c: -s * fy,
            d: c * fy,
            tx: CGFloat(pinX) - c * fx * locXF + s * fy * locYF,
            ty: CGFloat(pinY) - s * fx * locXF - c * fy * locYF
        )
    }

    public static func localToPage(_ shape: ShapeNode, scope: EvalScope) -> CGAffineTransform {
        var transform = localToParent(shape, scope: scope)
        var parent = shape.parentId
        var hops = 0
        while let parentId = parent, let next = scope.shapes[parentId], hops < 40 {
            transform = transform.concatenating(localToParent(next, scope: scope))
            parent = next.parentId
            hops += 1
        }
        return transform
    }

    public static func pagePoint(shape: ShapeNode, local: (Double, Double), scope: EvalScope) -> (x: Double, y: Double) {
        let point = CGPoint(x: local.0, y: local.1).applying(localToPage(shape, scope: scope))
        return (Double(point.x), Double(point.y))
    }

    public static func apply(_ transform: CGAffineTransform, _ point: CGPoint) -> CGPoint {
        point.applying(transform)
    }
}

enum PathBuilder {
    static func localPath(shape: ShapeNode, scope: EvalScope) -> (fill: CGPath, stroke: CGPath) {
        let fill = CGMutablePath()
        let stroke = CGMutablePath()
        let width = scope.number(shape: shape, cell: "Width")
        let height = scope.number(shape: shape, cell: "Height")
        let rounding = scope.number(shape: shape, cell: "Rounding")
        for section in shape.geometry where !section.noShow {
            let sub = sectionPath(section, shape: shape, scope: scope, width: width, height: height, rounding: rounding)
            if !section.noFill { fill.addPath(sub) }
            if !section.noLine { stroke.addPath(sub) }
        }
        if shape.geometry.isEmpty {
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            if rounding > 0 {
                fill.addRoundedRect(in: rect, cornerWidth: rounding, cornerHeight: rounding)
            } else {
                fill.addRect(rect)
            }
            stroke.addPath(fill)
        }
        return (fill, stroke)
    }

    private static func sectionPath(_ section: GeoSection, shape: ShapeNode, scope: EvalScope, width: Double, height: Double, rounding: Double) -> CGPath {
        let path = CGMutablePath()
        var current = CGPoint.zero
        var polygon: [CGPoint] = []
        var simple = true
        func addPoint(_ point: CGPoint, move: Bool) {
            if move {
                path.move(to: point)
                polygon = [point]
            } else {
                path.addLine(to: point)
                polygon.append(point)
            }
            current = point
        }
        for row in section.rows where !row.deleted {
            switch row.type {
            case "MoveTo":
                addPoint(point(row, shape: shape, scope: scope, relative: false), move: true)
            case "RelMoveTo":
                addPoint(point(row, shape: shape, scope: scope, relative: true, width: width, height: height), move: true)
            case "LineTo":
                addPoint(point(row, shape: shape, scope: scope, relative: false), move: false)
            case "RelLineTo":
                addPoint(point(row, shape: shape, scope: scope, relative: true, width: width, height: height), move: false)
            case "ArcTo":
                simple = false
                let end = point(row, shape: shape, scope: scope, relative: false)
                let bow = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "A"))
                addArc(path, from: current, to: end, bow: bow)
                current = end
            case "EllipticalArcTo", "RelEllipticalArcTo":
                simple = false
                let relative = row.type.hasPrefix("Rel")
                let end = point(row, shape: shape, scope: scope, relative: relative, width: width, height: height)
                var control = CGPoint(
                    x: scope.evalRowNumber(shape: shape, row: row, name: "A"),
                    y: scope.evalRowNumber(shape: shape, row: row, name: "B")
                )
                if relative {
                    control.x *= CGFloat(width)
                    control.y *= CGFloat(height)
                }
                addArcThrough(path, from: current, through: control, to: end)
                current = end
            case "RelCubBezTo", "CubBezTo":
                simple = false
                let relative = row.type.hasPrefix("Rel")
                let end = point(row, shape: shape, scope: scope, relative: relative, width: width, height: height)
                var c1 = CGPoint(x: scope.evalRowNumber(shape: shape, row: row, name: "A"), y: scope.evalRowNumber(shape: shape, row: row, name: "B"))
                var c2 = CGPoint(x: scope.evalRowNumber(shape: shape, row: row, name: "C"), y: scope.evalRowNumber(shape: shape, row: row, name: "D"))
                if relative {
                    c1.x *= CGFloat(width); c1.y *= CGFloat(height)
                    c2.x *= CGFloat(width); c2.y *= CGFloat(height)
                }
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
            case "RelQuadBezTo", "QuadBezTo":
                simple = false
                let relative = row.type.hasPrefix("Rel")
                let end = point(row, shape: shape, scope: scope, relative: relative, width: width, height: height)
                var control = CGPoint(x: scope.evalRowNumber(shape: shape, row: row, name: "A"), y: scope.evalRowNumber(shape: shape, row: row, name: "B"))
                if relative {
                    control.x *= CGFloat(width); control.y *= CGFloat(height)
                }
                path.addQuadCurve(to: end, control: control)
                current = end
            case "Ellipse":
                simple = false
                addEllipse(path, row: row, shape: shape, scope: scope)
            case "NURBSTo":
                simple = false
                let end = point(row, shape: shape, scope: scope, relative: false)
                let controls = nurbsControls(row)
                var previous = current
                for control in controls {
                    path.addLine(to: control)
                    previous = control
                }
                if hypot(end.x - previous.x, end.y - previous.y) > 0.0001 {
                    path.addLine(to: end)
                }
                current = end
            case "PolylineTo":
                simple = false
                let end = point(row, shape: shape, scope: scope, relative: false)
                for control in polylineControls(row) {
                    path.addLine(to: control)
                }
                path.addLine(to: end)
                current = end
            default:
                simple = false
                let end = point(row, shape: shape, scope: scope, relative: row.type.hasPrefix("Rel"))
                path.addLine(to: end)
                current = end
            }
        }
        if simple, rounding > 0.0001, let rounded = roundedPolygon(polygon, radius: CGFloat(rounding)) {
            return rounded
        }
        return path
    }

    private static func point(_ row: GeoRow, shape: ShapeNode, scope: EvalScope, relative: Bool, width: Double = 0, height: Double = 0) -> CGPoint {
        var x = scope.evalRowNumber(shape: shape, row: row, name: "X")
        var y = scope.evalRowNumber(shape: shape, row: row, name: "Y")
        if relative {
            x *= width
            y *= height
        }
        return CGPoint(x: x, y: y)
    }

    private static func nurbsControls(_ row: GeoRow) -> [CGPoint] {
        let formula = row.formula("E") ?? row.raw("E") ?? ""
        let numbers = numbersIn(formula)
        guard numbers.count > 6 else { return [] }
        var points: [CGPoint] = []
        var index = 4
        while index + 1 < numbers.count {
            points.append(CGPoint(x: numbers[index], y: numbers[index + 1]))
            index += 4
        }
        return points
    }

    private static func polylineControls(_ row: GeoRow) -> [CGPoint] {
        let formula = row.formula("A") ?? row.raw("A") ?? ""
        let numbers = numbersIn(formula)
        guard numbers.count >= 4 else { return [] }
        var points: [CGPoint] = []
        var index = 2
        while index + 1 < numbers.count {
            points.append(CGPoint(x: numbers[index], y: numbers[index + 1]))
            index += 2
        }
        return points
    }

    private static func numbersIn(_ formula: String) -> [CGFloat] {
        var numbers: [CGFloat] = []
        var current = ""
        func flush() {
            if let value = Double(current) { numbers.append(CGFloat(value)) }
            current = ""
        }
        for char in formula {
            if char.isNumber || char == "." || (char == "-" && current.isEmpty) {
                current.append(char)
            } else {
                flush()
            }
        }
        flush()
        return numbers
    }

    private static func addArc(_ path: CGMutablePath, from start: CGPoint, to end: CGPoint, bow: CGFloat) {
        if abs(bow) < 0.00001 {
            path.addLine(to: end)
            return
        }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let chord = hypot(dx, dy)
        if chord < 0.00001 { return }
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let through = CGPoint(x: mid.x + (-dy / chord) * bow, y: mid.y + (dx / chord) * bow)
        addArcThrough(path, from: start, through: through, to: end)
    }

    private static func addArcThrough(_ path: CGMutablePath, from start: CGPoint, through: CGPoint, to end: CGPoint) {
        guard let center = circleCenter(start, through, end) else {
            path.addQuadCurve(to: end, control: through)
            return
        }
        let radius = hypot(start.x - center.x, start.y - center.y)
        let a0 = atan2(start.y - center.y, start.x - center.x)
        let a1 = atan2(end.y - center.y, end.x - center.x)
        let am = atan2(through.y - center.y, through.x - center.x)
        let clockwise = !angleContains(start: a0, end: a1, target: am, clockwise: false)
        path.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: clockwise)
    }

    private static func circleCenter(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGPoint? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        if abs(d) < 0.0000001 { return nil }
        let a2 = a.x * a.x + a.y * a.y
        let b2 = b.x * b.x + b.y * b.y
        let c2 = c.x * c.x + c.y * c.y
        let ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
        let uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
        return CGPoint(x: ux, y: uy)
    }

    private static func angleContains(start: CGFloat, end: CGFloat, target: CGFloat, clockwise: Bool) -> Bool {
        func norm(_ angle: CGFloat) -> CGFloat {
            var value = angle
            while value < 0 { value += 2 * .pi }
            while value >= 2 * .pi { value -= 2 * .pi }
            return value
        }
        let s = norm(start)
        let e = norm(end)
        let t = norm(target)
        if !clockwise {
            if s <= e { return t >= s && t <= e }
            return t >= s || t <= e
        }
        if s >= e { return t <= s && t >= e }
        return t <= s || t >= e
    }

    private static func addEllipse(_ path: CGMutablePath, row: GeoRow, shape: ShapeNode, scope: EvalScope) {
        let cx = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "X"))
        let cy = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "Y"))
        let ax = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "A")) - cx
        let ay = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "B")) - cy
        let bx = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "C")) - cx
        let by = CGFloat(scope.evalRowNumber(shape: shape, row: row, name: "D")) - cy
        let steps = 48
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
            let x = cx + ax * cos(t) + bx * sin(t)
            let y = cy + ay * cos(t) + by * sin(t)
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
    }

    private static func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> CGPath? {
        let cleaned = points.count > 1 && points.first == points.last ? Array(points.dropLast()) : points
        guard cleaned.count >= 4, radius > 0 else { return nil }
        let rect = bounds(cleaned)
        guard rect.width > 0.05, rect.height > 0.05 else { return nil }
        for point in cleaned {
            let onX = abs(point.x - rect.minX) < 0.01 || abs(point.x - rect.maxX) < 0.01
            let onY = abs(point.y - rect.minY) < 0.01 || abs(point.y - rect.maxY) < 0.01
            if !onX || !onY { return nil }
        }
        let path = CGMutablePath()
        let r = min(radius, rect.width / 2, rect.height / 2)
        path.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r)
        return path
    }

    private static func bounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var rect = CGRect(origin: first, size: .zero)
        for point in points { rect = rect.union(CGRect(origin: point, size: .zero)) }
        return rect
    }
}

public struct LayoutItem: Equatable {
    public var id: Int
    public var bounds: CGRect
    public var center: CGPoint
    public var is1D: Bool
    public var isGroup: Bool
    public var connections: [CGPoint]
    public var connectionDirs: [CGPoint]
    public var localToPage: CGAffineTransform
    public var parentId: Int?
}

public enum PageLayout {
    public static func items(page: DiagramPage, theme: ThemeColors, colors: [Int: String]) -> [LayoutItem] {
        let scope = EvalScope(page: page, theme: theme, colors: colors)
        var items: [LayoutItem] = []
        func walk(_ shape: ShapeNode) {
            var transform = GeometryMath.localToPage(shape, scope: scope)
            let paths = PathBuilder.localPath(shape: shape, scope: scope)
            let pageFill = withUnsafePointer(to: &transform) { paths.fill.copy(using: $0) }
            let pageStroke = withUnsafePointer(to: &transform) { paths.stroke.copy(using: $0) }
            var box = CGRect.null
            if let pageFill, !pageFill.isEmpty { box = box.union(pageFill.boundingBoxOfPath) }
            if let pageStroke, !pageStroke.isEmpty { box = box.union(pageStroke.boundingBoxOfPath) }
            if box.isNull || box.isEmpty {
                let pin = CGPoint(x: scope.number(shape: shape, cell: "PinX"), y: scope.number(shape: shape, cell: "PinY")).applying(parentTransform(shape, scope: scope))
                box = CGRect(x: pin.x - 0.01, y: pin.y - 0.01, width: 0.02, height: 0.02)
            }
            if shape.is1D {
                box = box.insetBy(dx: -0.04, dy: -0.04)
            }
            let ports = connectionPorts(shape: shape, scope: scope, transform: transform)
            let center = CGPoint(x: box.midX, y: box.midY)
            items.append(LayoutItem(
                id: shape.id,
                bounds: box,
                center: center,
                is1D: shape.is1D,
                isGroup: shape.isGroup,
                connections: ports.map(\.0),
                connectionDirs: ports.map(\.1),
                localToPage: transform,
                parentId: shape.parentId
            ))
            shape.children.forEach(walk)
        }
        page.shapes.forEach(walk)
        return items
    }

    public static func hitTest(page: DiagramPage, point: CGPoint, theme: ThemeColors, colors: [Int: String], slop: CGFloat) -> Int? {
        let scope = EvalScope(page: page, theme: theme, colors: colors)
        var hit: Int?
        func consider(_ shape: ShapeNode) {
            guard shape.kind != "Guide" else { return }
            var transform = GeometryMath.localToPage(shape, scope: scope)
            let paths = PathBuilder.localPath(shape: shape, scope: scope)
            let stroke = withUnsafePointer(to: &transform) { paths.stroke.copy(using: $0) }
            let fill = withUnsafePointer(to: &transform) { paths.fill.copy(using: $0) }
            let wide = stroke?.copy(strokingWithWidth: slop, lineCap: .round, lineJoin: .round, miterLimit: 2)
            let canFill = !shape.is1D && (shape.cell("FillPattern") == nil || shape.cell("FillPattern")?.value != "0")
            if (canFill && fill?.contains(point) == true) || wide?.contains(point) == true {
                hit = shape.id
            }
            shape.children.forEach(consider)
        }
        page.shapes.forEach(consider)
        return hit
    }

    private static func connectionPorts(shape: ShapeNode, scope: EvalScope, transform: CGAffineTransform) -> [(CGPoint, CGPoint)] {
        let angle = scope.number(shape: shape, cell: "Angle")
        func rotate(_ dir: CGPoint) -> CGPoint {
            let c = cos(angle)
            let s = sin(angle)
            return CGPoint(x: dir.x * c - dir.y * s, y: dir.x * s + dir.y * c)
        }
        let stored = shape.connections.filter { !$0.deleted }
        if !stored.isEmpty {
            return stored.map { row in
                let local = CGPoint(x: connectionCoord(shape: shape, row: row, name: "X", scope: scope), y: connectionCoord(shape: shape, row: row, name: "Y", scope: scope))
                let dir = rotate(CGPoint(x: scope.evalRowNumber(shape: shape, row: row, name: "DirX"), y: scope.evalRowNumber(shape: shape, row: row, name: "DirY")))
                let length = max(0.001, hypot(dir.x, dir.y))
                return (local.applying(transform), CGPoint(x: dir.x / length, y: dir.y / length))
            }
        }
        if shape.is1D { return [] }
        let width = scope.number(shape: shape, cell: "Width")
        let height = scope.number(shape: shape, cell: "Height")
        let locals: [(CGPoint, CGPoint)] = [
            (CGPoint(x: width * 0.5, y: 0), CGPoint(x: 0, y: -1)),
            (CGPoint(x: width, y: height * 0.5), CGPoint(x: 1, y: 0)),
            (CGPoint(x: width * 0.5, y: height), CGPoint(x: 0, y: 1)),
            (CGPoint(x: 0, y: height * 0.5), CGPoint(x: -1, y: 0))
        ]
        return locals.map { (local, dir) in
            (local.applying(transform), rotate(dir))
        }
    }

    private static func connectionCoord(shape: ShapeNode, row: GeoRow, name: String, scope: EvalScope) -> Double {
        if let formula = row.formula(name), formula.contains("Width") || formula.contains("Height") {
            let saved = scope.useFormulas
            scope.useFormulas = true
            let value = scope.evalRowNumber(shape: shape, row: row, name: name)
            scope.useFormulas = saved
            return value
        }
        return scope.evalRowNumber(shape: shape, row: row, name: name)
    }

    private static func parentTransform(_ shape: ShapeNode, scope: EvalScope) -> CGAffineTransform {
        guard let parentId = shape.parentId, let parent = scope.shapes[parentId] else { return .identity }
        return GeometryMath.localToPage(parent, scope: scope)
    }
}

public enum PageDrawing {
    public static func draw(page: DiagramPage, theme: ThemeColors, colors: [Int: String], in context: CGContext, pixelsPerInch: CGFloat) {
        let scope = EvalScope(page: page, theme: theme, colors: colors)
        for shape in page.shapes {
            draw(shape, scope: scope, theme: theme, context: context, pixelsPerInch: pixelsPerInch)
        }
    }

    public static func renderPNG(page: DiagramPage, theme: ThemeColors, colors: [Int: String], pixelsPerInch: CGFloat = 96, margin: CGFloat = 16) -> Data? {
        let width = Int((CGFloat(page.width) * pixelsPerInch + margin * 2).rounded(.up))
        let height = Int((CGFloat(page.height) * pixelsPerInch + margin * 2).rounded(.up))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: margin, y: margin)
        context.scaleBy(x: pixelsPerInch, y: pixelsPerInch)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: page.width, height: page.height))
        draw(page: page, theme: theme, colors: colors, in: context, pixelsPerInch: pixelsPerInch)
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private static func draw(_ shape: ShapeNode, scope: EvalScope, theme: ThemeColors, context: CGContext, pixelsPerInch: CGFloat) {
        let layerIndex = Int(scope.number(shape: shape, cell: "LayerMember"))
        if scope.number(shape: shape, cell: "HideShape") != 0 { return }
        _ = layerIndex
        context.saveGState()
        context.concatenate(GeometryMath.localToParent(shape, scope: scope))
        let paths = PathBuilder.localPath(shape: shape, scope: scope)
        if let imageData = shape.imagePNG, let source = CGImageSourceCreateWithData(imageData as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let width = scope.number(shape: shape, cell: "Width")
            let height = scope.number(shape: shape, cell: "Height")
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let fillPattern = shape.cell("FillPattern") == nil && shape.is1D ? 0 : Int(scope.number(shape: shape, cell: "FillPattern"))
        if fillPattern != 0 && !paths.fill.isEmpty {
            let color = scope.colorString(shape: shape, cell: "FillForegnd", fallback: "#FFFFFF")
            let alpha = 1 - scope.number(shape: shape, cell: "FillForegndTrans")
            context.addPath(paths.fill)
            context.setFillColor(paint(color, alpha: alpha))
            context.fillPath(using: .evenOdd)
        }
        let linePattern = Int(scope.number(shape: shape, cell: "LinePattern"))
        if linePattern != 0 && !paths.stroke.isEmpty {
            let color = scope.colorString(shape: shape, cell: "LineColor", fallback: "#000000")
            let alpha = 1 - scope.number(shape: shape, cell: "LineColorTrans")
            var weight = scope.number(shape: shape, cell: "LineWeight")
            if weight <= 0 { weight = 0.75 / Double(pixelsPerInch) }
            weight = max(weight, 0.6 / Double(pixelsPerInch))
            context.addPath(paths.stroke)
            context.setStrokeColor(paint(color, alpha: alpha))
            context.setLineWidth(weight)
            context.setLineJoin(.round)
            context.setLineCap(lineCap(Int(scope.number(shape: shape, cell: "LineCap"))))
            context.setLineDash(phase: 0, lengths: dash(linePattern, weight: weight))
            context.strokePath()
            drawArrows(shape: shape, scope: scope, context: context, color: paint(color, alpha: alpha), weight: weight)
        }
        if scope.number(shape: shape, cell: "HideText") == 0 && !shape.text.isEmpty {
            drawText(shape: shape, scope: scope, context: context)
        }
        for child in shape.children {
            draw(child, scope: scope, theme: theme, context: context, pixelsPerInch: pixelsPerInch)
        }
        context.restoreGState()
    }

    private static func drawArrows(shape: ShapeNode, scope: EvalScope, context: CGContext, color: CGColor, weight: Double) {
        let begin = Int(scope.number(shape: shape, cell: "BeginArrow"))
        let end = Int(scope.number(shape: shape, cell: "EndArrow"))
        guard begin != 0 || end != 0 else { return }
        guard let ends = pathEnds(shape: shape, scope: scope) else { return }
        context.setFillColor(color)
        context.setStrokeColor(color)
        context.setLineWidth(weight)
        context.setLineDash(phase: 0, lengths: [])
        if begin != 0 {
            arrow(context, tip: ends.start, from: ends.startNext, kind: begin, size: scope.number(shape: shape, cell: "BeginArrowSize"), weight: weight)
        }
        if end != 0 {
            arrow(context, tip: ends.end, from: ends.endPrev, kind: end, size: scope.number(shape: shape, cell: "EndArrowSize"), weight: weight)
        }
    }

    private static func pathEnds(shape: ShapeNode, scope: EvalScope) -> (start: CGPoint, startNext: CGPoint, end: CGPoint, endPrev: CGPoint)? {
        guard let section = shape.geometry.first else { return nil }
        var points: [CGPoint] = []
        let width = scope.number(shape: shape, cell: "Width")
        let height = scope.number(shape: shape, cell: "Height")
        for row in section.rows where !row.deleted {
            let relative = row.type.hasPrefix("Rel")
            var x = scope.evalRowNumber(shape: shape, row: row, name: "X")
            var y = scope.evalRowNumber(shape: shape, row: row, name: "Y")
            if relative { x *= width; y *= height }
            points.append(CGPoint(x: x, y: y))
        }
        guard points.count >= 2 else { return nil }
        return (points[0], points[1], points[points.count - 1], points[points.count - 2])
    }

    private static func arrow(_ context: CGContext, tip: CGPoint, from: CGPoint, kind: Int, size: Double, weight: Double) {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let length = CGFloat(0.09 + max(0, size) * 0.025 + weight)
        let width = length * 0.55
        context.saveGState()
        context.translateBy(x: tip.x, y: tip.y)
        context.rotate(by: angle)
        switch kind {
        case 1, 3, 10:
            if kind == 10 {
                context.addEllipse(in: CGRect(x: -length, y: -width / 2, width: length, height: width))
                context.fillPath()
            } else {
                context.move(to: CGPoint(x: -length, y: width / 2))
                context.addLine(to: .zero)
                context.addLine(to: CGPoint(x: -length, y: -width / 2))
                context.strokePath()
            }
        case 5:
            context.move(to: CGPoint(x: 0, y: 0))
            context.addLine(to: CGPoint(x: -length / 2, y: width / 2))
            context.addLine(to: CGPoint(x: -length, y: 0))
            context.addLine(to: CGPoint(x: -length / 2, y: -width / 2))
            context.closePath()
            context.fillPath()
        default:
            context.move(to: .zero)
            context.addLine(to: CGPoint(x: -length, y: width / 2))
            context.addLine(to: CGPoint(x: -length * 0.78, y: 0))
            context.addLine(to: CGPoint(x: -length, y: -width / 2))
            context.closePath()
            context.fillPath()
        }
        context.restoreGState()
    }

    private static func drawText(shape: ShapeNode, scope: EvalScope, context: CGContext) {
        let width = scope.number(shape: shape, cell: "Width")
        let height = scope.number(shape: shape, cell: "Height")
        let box: CGRect
        if shape.cell("TxtWidth") != nil && shape.cell("TxtHeight") != nil {
            let pinX = scope.number(shape: shape, cell: "TxtPinX")
            let pinY = scope.number(shape: shape, cell: "TxtPinY")
            let locX = scope.number(shape: shape, cell: "TxtLocPinX")
            let locY = scope.number(shape: shape, cell: "TxtLocPinY")
            let textWidth = scope.number(shape: shape, cell: "TxtWidth")
            let textHeight = scope.number(shape: shape, cell: "TxtHeight")
            box = CGRect(x: pinX - locX, y: pinY - locY, width: textWidth, height: textHeight)
        } else {
            let left = shape.cell("LeftMargin").flatMap { Format.parseDouble($0.value) } ?? 0.04
            let right = shape.cell("RightMargin").flatMap { Format.parseDouble($0.value) } ?? 0.04
            let bottom = shape.cell("BottomMargin").flatMap { Format.parseDouble($0.value) } ?? 0.04
            let top = shape.cell("TopMargin").flatMap { Format.parseDouble($0.value) } ?? 0.04
            box = CGRect(x: left, y: bottom, width: max(0.05, width - left - right), height: max(0.05, height - top - bottom))
        }
        guard box.width > 0.01, box.height > 0.01 else { return }
        let fontName = shape.character.first?.raw("Font") ?? shape.cell("Font")?.value ?? "Calibri"
        var fontSize = Format.parseDouble(shape.character.first?.raw("Size")) ?? scope.number(shape: shape, cell: "Char.Size")
        if fontSize <= 0 { fontSize = 12.0 / 72.0 }
        let styleBits = Int(Format.parseDouble(shape.character.first?.raw("Style")) ?? 0)
        let colorName = shape.character.first?.raw("Color") ?? "#000000"
        let color = colorName.hasPrefix("#") ? colorName : scope.colorString(shape: shape, cell: "Color", fallback: "#000000")
        let hAlign = Int(Format.parseDouble(shape.paragraph.first?.raw("HorzAlign")) ?? scope.number(shape: shape, cell: "HorzAlign"))
        let vAlign = Int(scope.number(shape: shape, cell: "VerticalAlign"))
        let font = makeFont(name: fontName, size: fontSize, bits: styleBits)
        let rgb = ColorMath.rgb(color)
        let cgColor = CGColor(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
        let lines = shape.text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let drawn = lines.map { line -> (CTLine, CGFloat, CGFloat, CGFloat) in
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: cgColor
            ]
            let attributed = CFAttributedStringCreate(nil, line as CFString, attributes as CFDictionary)!
            let ctLine = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, nil))
            return (ctLine, width, ascent, descent)
        }
        let lineHeight = drawn.map { $0.2 + $0.3 }.max() ?? CGFloat(fontSize * 1.2)
        let blockHeight = lineHeight * CGFloat(max(drawn.count, 1))
        let top: CGFloat
        switch vAlign {
        case 0: top = box.maxY
        case 2: top = box.minY + blockHeight
        default: top = box.midY + blockHeight / 2
        }
        for (index, line) in drawn.enumerated() {
            let baseline = top - lineHeight * CGFloat(index) - line.2
            let x: CGFloat
            switch hAlign {
            case 0: x = box.minX
            case 2: x = box.maxX - line.1
            default: x = box.midX - line.1 / 2
            }
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line.0, context)
        }
    }

    private static func makeFont(name: String, size: Double, bits: Int) -> CTFont {
        let base = CTFontCreateWithName(name as CFString, CGFloat(size), nil)
        var traits = CTFontSymbolicTraits()
        if bits & 1 != 0 { traits.insert(.traitBold) }
        if bits & 2 != 0 { traits.insert(.traitItalic) }
        if traits.isEmpty { return base }
        return CTFontCreateCopyWithSymbolicTraits(base, CGFloat(size), nil, traits, traits) ?? base
    }

    private static func paint(_ hex: String, alpha: Double) -> CGColor {
        let rgb = ColorMath.rgb(hex.hasPrefix("#") ? hex : "#000000")
        return CGColor(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: CGFloat(max(0, min(1, alpha))))
    }

    private static func lineCap(_ value: Int) -> CGLineCap {
        switch value {
        case 1: return .square
        case 2: return .butt
        default: return .round
        }
    }

    private static func dash(_ pattern: Int, weight: Double) -> [CGFloat] {
        let dot = CGFloat(max(weight * 1.2, 0.02))
        let dash = CGFloat(max(weight * 4, 0.08))
        let gap = CGFloat(max(weight * 2.2, 0.05))
        switch pattern {
        case 2: return [dash, gap]
        case 3: return [dot, gap]
        case 4: return [dash, gap, dot, gap]
        case 5: return [dash, gap, dot, gap, dot, gap]
        case 6, 7, 8, 9: return [dash, gap]
        default: return []
        }
    }
}
