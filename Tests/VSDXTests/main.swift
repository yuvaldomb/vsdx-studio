import CoreGraphics
import Foundation
import VSDXCore

var failures: [String] = []

func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures.append(message)
        fputs("FAIL \(message)\n", stderr)
    }
}

func testFormula() {
    var shape = ShapeNode(id: 1)
    shape.setCell("Width", value: "4")
    var page = DiagramPage(id: 0, name: "P", width: 11, height: 8.5)
    page.shapes = [shape]
    let scope = EvalScope(page: page, theme: ThemeColors(), colors: [:])
    let value = scope.number(shape: shape, cell: "Width")
    check(abs(value - 4) < 0.0001, "width cell is 4, got \(value)")
}

func testTransform() {
    var shape = ShapeNode(id: 1)
    shape.setCell("PinX", value: "5")
    shape.setCell("PinY", value: "6")
    shape.setCell("Width", value: "2")
    shape.setCell("Height", value: "1")
    shape.setCell("LocPinX", value: "1", formula: "Width*0.5")
    shape.setCell("LocPinY", value: "0.5", formula: "Height*0.5")
    shape.setCell("Angle", value: "0")
    var page = DiagramPage(id: 0, name: "P")
    page.shapes = [shape]
    let scope = EvalScope(page: page, theme: ThemeColors(), colors: [:])
    let transform = GeometryMath.localToParent(shape, scope: scope)
    let center = CGPoint(x: 1, y: 0.5).applying(transform)
    let origin = CGPoint.zero.applying(transform)
    check(abs(center.x - 5) < 0.001 && abs(center.y - 6) < 0.001, "pin maps to center \(center)")
    check(abs(origin.x - 4) < 0.001 && abs(origin.y - 5.5) < 0.001, "origin maps \(origin)")
}

func testRoundTrip() {
    var diagram = Diagram.blank()
    var page = diagram.pages[0]
    let box = StencilCatalog.make(id: "process", shapeId: 1, center: CGPoint(x: 4, y: 5))
    var diamond = StencilCatalog.make(id: "decision", shapeId: 2, center: CGPoint(x: 7, y: 5))
    diamond.setTextContent("Review")
    let line = StencilCatalog.make(id: "connector", shapeId: 3, center: CGPoint(x: 5.5, y: 5))
    page.shapes = [box, diamond, line]
    page.connects = [
        ShapeConnect(fromId: 3, fromCell: "BeginX", fromPart: 9, toId: 1, toCell: "Connections.X2", toPart: 101),
        ShapeConnect(fromId: 3, fromCell: "EndX", fromPart: 12, toId: 2, toCell: "Connections.X4", toPart: 103)
    ]
    var page2 = DiagramPage(id: 1, name: "Page-2", width: 8.5, height: 11)
    page2.partName = "visio/pages/page2.xml"
    page2.shapes = [StencilCatalog.make(id: "database", shapeId: 1, center: CGPoint(x: 4, y: 6))]
    diagram.pages = [page, page2]
    do {
        let data = try VsdxIO.write(diagram)
        let loaded = try VsdxIO.read(data)
        check(loaded.pages.count == 2, "two pages round trip")
        check(loaded.pages[0].shapes.count == 3, "three shapes, got \(loaded.pages[0].shapes.count)")
        check(loaded.pages[0].shapes.contains { $0.text == "Process" }, "process text")
        check(loaded.pages[0].shapes.contains { $0.text == "Review" }, "edited text")
        check(abs(loaded.pages[0].width - 11) < 0.01, "page width")
        check(loaded.pages[1].name == "Page-2", "second page name")
        let again = try VsdxIO.write(loaded)
        let loaded2 = try VsdxIO.read(again)
        check(loaded2.pages[0].shapes.count == 3, "second round trip")
    } catch {
        check(false, "round trip threw \(error)")
    }
}

func testSample() {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/visio-basic-example.vsdx")
    guard let data = try? Data(contentsOf: url) else {
        check(false, "missing fixture \(url.path)")
        return
    }
    do {
        let diagram = try VsdxIO.read(data)
        check(!diagram.pages.isEmpty, "sample has pages")
        let page = diagram.pages[0]
        check(page.shapes.count >= 5, "sample shapes \(page.shapes.count)")
        let texts = page.shapes.map(\.text).joined(separator: " | ")
        check(texts.contains("Public Cloud"), "public cloud text in \(texts)")
        check(texts.contains("My EC2"), "ec2 text in \(texts)")
        let group = page.shapes.first { $0.text.contains("My EC2") }
        check((group?.children.count ?? 0) >= 3, "ec2 children \(group?.children.count ?? 0)")
        if let png = PageDrawing.renderPNG(page: page, theme: diagram.theme, colors: diagram.colors, pixelsPerInch: 80) {
            let out = URL(fileURLWithPath: "/tmp/vsdx-sample.png")
            try png.write(to: out)
            check(png.count > 1000, "png bytes \(png.count)")
        } else {
            check(false, "png render failed")
        }
        var edited = diagram
        edited.pages[0].updateShape(id: page.shapes[0].id) { shape in
            shape.setTextContent("Edited Cloud")
            shape.setNumber("PinX", 3.5, clearFormula: true)
        }
        let saved = try VsdxIO.write(edited)
        let reloaded = try VsdxIO.read(saved)
        check(reloaded.pages[0].shapes.contains { $0.text.contains("Edited Cloud") }, "edited sample text survived")
        if let png = PageDrawing.renderPNG(page: reloaded.pages[0], theme: reloaded.theme, colors: reloaded.colors, pixelsPerInch: 80) {
            try png.write(to: URL(fileURLWithPath: "/tmp/vsdx-sample-edited.png"))
        }
    } catch {
        check(false, "sample read threw \(error)")
    }
}

func testOwnRender() {
    var page = DiagramPage(id: 0, name: "Draw", width: 11, height: 8.5)
    page.shapes = [
        StencilCatalog.make(id: "process", shapeId: 1, center: CGPoint(x: 2.2, y: 6)),
        StencilCatalog.make(id: "decision", shapeId: 2, center: CGPoint(x: 5, y: 6)),
        StencilCatalog.make(id: "terminator", shapeId: 3, center: CGPoint(x: 8, y: 6)),
        StencilCatalog.make(id: "database", shapeId: 4, center: CGPoint(x: 2.2, y: 3.2)),
        StencilCatalog.make(id: "document", shapeId: 5, center: CGPoint(x: 5, y: 3.2)),
        StencilCatalog.make(id: "arrow-right", shapeId: 6, center: CGPoint(x: 8, y: 3.2))
    ]
    page.shapes[0].setTextContent("Start work")
    if let png = PageDrawing.renderPNG(page: page, theme: ThemeColors(), colors: [:], pixelsPerInch: 90) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/vsdx-own.png"))
        check(png.count > 1000, "own png")
    } else {
        check(false, "own render failed")
    }
}

func testSnapToGrid() {
    let bounds = CGRect(x: 1.06, y: 2.14, width: 1.5, height: 1)
    let moved = GridSnap.translation(bounds: bounds, dx: 0.02, dy: 0.02)
    let minX = 1.06 + moved.0
    let minY = 2.14 + moved.1
    check(abs(minX - 1.1) < 0.001, "snap x \(minX)")
    check(abs(minY - 2.2) < 0.001, "snap y \(minY)")
}

func testOrthogonalConnector() {
    let straight = ConnectorRoute.route(
        style: .elbow,
        start: CGPoint(x: 2.75, y: 5),
        startDir: CGPoint(x: 1, y: 0),
        end: CGPoint(x: 4.25, y: 5),
        endDir: CGPoint(x: -1, y: 0)
    )
    check(straight.count == 2, "facing ports make a straight line, got \(straight.count)")
    let bent = ConnectorRoute.route(
        style: .elbow,
        start: CGPoint(x: 2.75, y: 5),
        startDir: CGPoint(x: 1, y: 0),
        end: CGPoint(x: 4.25, y: 6.2),
        endDir: CGPoint(x: -1, y: 0)
    )
    check(bent.count >= 4, "offset ports bend, got \(bent.count)")
    for index in 1..<bent.count {
        let dx = abs(bent[index].x - bent[index - 1].x)
        let dy = abs(bent[index].y - bent[index - 1].y)
        check(dx < 0.001 || dy < 0.001, "segment \(index) is orthogonal")
    }
}

func portNear(_ item: LayoutItem, _ point: CGPoint) -> Int? {
    item.connections.enumerated().min {
        hypot($0.element.x - point.x, $0.element.y - point.y) < hypot($1.element.x - point.x, $1.element.y - point.y)
    }.flatMap { hypot($0.element.x - point.x, $0.element.y - point.y) < 0.03 ? $0.offset : nil }
}

func testOutlinePorts() {
    func ports(for id: String) -> LayoutItem {
        var page = DiagramPage(id: 0, name: "P", width: 8, height: 6)
        page.shapes = [StencilCatalog.make(id: id, shapeId: 1, center: CGPoint(x: 3, y: 3))]
        return PageLayout.items(page: page, theme: ThemeColors(), colors: [:])[0]
    }
    let box = ports(for: "rectangle")
    check(box.connections.count == 8, "rectangle has 8 ports, got \(box.connections.count)")
    let corner = CGPoint(x: box.bounds.minX, y: box.bounds.minY)
    let mid = CGPoint(x: box.bounds.midX, y: box.bounds.minY)
    check(portNear(box, corner) != nil, "rectangle corner snaps")
    check(portNear(box, mid) != nil, "rectangle edge midpoint snaps")
    let triangle = ports(for: "triangle")
    check(triangle.connections.count == 6, "triangle has 6 ports, got \(triangle.connections.count)")
    let pentagon = ports(for: "pentagon")
    check(pentagon.connections.count == 10, "pentagon has 10 ports, got \(pentagon.connections.count)")
    let circle = ports(for: "circle")
    check(circle.connections.count == 8, "circle has 8 ports, got \(circle.connections.count)")
    let star = ports(for: "star5")
    check(star.connections.count == 20, "star has 20 ports, got \(star.connections.count)")
}

func testConnectorFollowsShape() {
    var page = DiagramPage(id: 0, name: "P", width: 11, height: 8.5)
    let left = StencilCatalog.make(id: "process", shapeId: 1, center: CGPoint(x: 2, y: 5))
    let right = StencilCatalog.make(id: "process", shapeId: 2, center: CGPoint(x: 5, y: 5))
    page.shapes = [left, right]
    let items = PageLayout.items(page: page, theme: ThemeColors(), colors: [:])
    let fromItem = items.first { $0.id == 1 }!
    let toItem = items.first { $0.id == 2 }!
    let fromPort = portNear(fromItem, CGPoint(x: fromItem.bounds.maxX, y: fromItem.bounds.midY)) ?? 0
    let toPort = portNear(toItem, CGPoint(x: toItem.bounds.minX, y: toItem.bounds.midY)) ?? 0
    check(fromItem.connections.count == 8, "process has 8 ports")
    _ = DiagramEdit.addGluedConnector(page: &page, fromShape: 1, fromPort: fromPort, toShape: 2, toPort: toPort, theme: ThemeColors(), colors: [:])
    let before = Format.parseDouble(page.shape(id: 3)?.cell("EndX")?.value) ?? 0
    DiagramEdit.translate(page: &page, ids: [2], dx: 1, dy: 0)
    DiagramEdit.reroute(page: &page, moved: [2], theme: ThemeColors(), colors: [:])
    let after = Format.parseDouble(page.shape(id: 3)?.cell("EndX")?.value) ?? 0
    check(after > before + 0.7, "connector end follows shape \(before) -> \(after)")
    let ports = PageLayout.items(page: page, theme: ThemeColors(), colors: [:]).first { $0.id == 1 }
    check(ports?.connections.count == 8, "layout exposes 8 ports")
}

func testCurveKeepsControl() {
    var shape = StencilCatalog.make(id: "curve", shapeId: 1, center: CGPoint(x: 1, y: 1))
    let points = ConnectorRoute.route(
        style: .curve,
        start: CGPoint(x: 1, y: 1),
        startDir: CGPoint(x: 1, y: 0),
        end: CGPoint(x: 3, y: 2),
        endDir: CGPoint(x: 1, y: 0)
    )
    check(points.count == 3, "curve route has a control point")
    ConnectorRoute.apply(points: points, to: &shape, style: .curve)
    check(shape.geometry.first?.rows.contains { $0.type == "QuadBezTo" } == true, "curve stores a bezier")
    let back = ConnectorRoute.pagePoints(shape)
    check(back.count == 3, "curve reloads the control point, got \(back.count)")
    let simple = ConnectorRoute.route(
        style: .simple,
        start: CGPoint(x: 0, y: 0),
        startDir: CGPoint(x: 1, y: 0),
        end: CGPoint(x: 2, y: 1),
        endDir: CGPoint(x: 0, y: 1)
    )
    check(simple.count == 3, "simple route has one corner, got \(simple.count)")
    if let icon = PageDrawing.renderIconPNG(page: StencilCatalog.previewPage(id: "diamond"), theme: ThemeColors(), colors: [:]) {
        check(icon.count > 400, "diamond icon renders")
    } else {
        check(false, "diamond icon renders")
    }
}

testCurveKeepsControl()
testSnapToGrid()
testOrthogonalConnector()
testOutlinePorts()
testConnectorFollowsShape()
testFormula()
testTransform()
testRoundTrip()
testOwnRender()
testSample()

if failures.isEmpty {
    print("OK")
    exit(0)
} else {
    fputs("\(failures.count) failure(s)\n", stderr)
    exit(1)
}
