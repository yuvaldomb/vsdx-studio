import AppKit
import VSDXCore

enum SelfTest {
    static func run(fixture: String) -> Int32 {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if condition {
                print("PASS \(message)")
            } else {
                print("FAIL \(message)")
                failures.append(message)
            }
        }

        let controller = NSDocumentController.shared
        check(controller is StudioDocumentController, "document controller is StudioDocumentController")
        check(controller.defaultType == StudioDocumentController.drawingType, "default type is \(controller.defaultType ?? "nil")")

        let newItem = NSMenuItem(title: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        newItem.target = controller
        let openItem = NSMenuItem(title: "Open", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        openItem.target = controller
        check(controller.validateMenuItem(newItem), "New menu item is enabled")
        check(controller.validateMenuItem(openItem), "Open menu item is enabled")

        let before = controller.documents.count
        controller.newDocument(nil)
        check(controller.documents.count == before + 1, "New creates a document")
        let created = controller.documents.last
        guard let document = created as? StudioDocument,
              let windowController = document.windowControllers.first as? StudioWindowController else {
            check(false, "new document has a window")
            return finish(failures)
        }
        check(document.windowControllers.first?.window != nil, "new document window exists")
        check(document.diagram.pages.count == 1, "new document has one page")
        windowController.window?.layoutIfNeeded()
        windowController.placeShapeForTest("process")
        let page = document.diagram.pages[0]
        check(page.shapes.count == 1, "stamp adds one shape, count \(page.shapes.count)")
        check(page.shapes.first?.text == "Process", "stamped shape text is Process")
        let shapeID = page.shapes.first?.id ?? 0
        document.mutate("Text") { diagram in
            diagram.pages[0].updateShape(id: shapeID) { $0.setTextContent("Hello Visio") }
        }
        check(document.diagram.pages[0].shapes.first?.text == "Hello Visio", "text edit sticks")
        windowController.placeShapeForTest("process")
        let rightID = document.diagram.pages[0].shapes.last?.id ?? 0
        let placed = PageLayout.items(page: document.diagram.pages[0], theme: document.diagram.theme, colors: document.diagram.colors)
        func portIndex(_ id: Int, _ point: CGPoint) -> Int {
            guard let item = placed.first(where: { $0.id == id }) else { return 0 }
            var best = 0
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for (index, connection) in item.connections.enumerated() {
                let distance = hypot(connection.x - point.x, connection.y - point.y)
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
            }
            return best
        }
        let fromItem = placed.first { $0.id == shapeID }
        let toItem = placed.first { $0.id == rightID }
        let fromPort = portIndex(shapeID, CGPoint(x: fromItem?.bounds.maxX ?? 0, y: fromItem?.bounds.midY ?? 0))
        let toPort = portIndex(rightID, CGPoint(x: toItem?.bounds.minX ?? 0, y: toItem?.bounds.midY ?? 0))
        document.mutate("Connect") { diagram in
            DiagramEdit.translate(page: &diagram.pages[0], ids: [rightID], dx: 3, dy: 0)
            _ = DiagramEdit.addGluedConnector(
                page: &diagram.pages[0],
                fromShape: shapeID,
                fromPort: fromPort,
                toShape: rightID,
                toPort: toPort,
                theme: diagram.theme,
                colors: diagram.colors
            )
        }
        func drop(_ id: String, dx: Double, dy: Double) {
            windowController.placeShapeForTest(id)
            let newID = document.diagram.pages[0].shapes.last?.id ?? 0
            document.mutate("Move") { diagram in
                DiagramEdit.translate(page: &diagram.pages[0], ids: [newID], dx: dx, dy: dy)
            }
        }
        drop("triangle", dx: -2.4, dy: 1.6)
        drop("circle", dx: 2.4, dy: 1.6)
        drop("diamond", dx: -2.4, dy: -1.6)
        drop("star5", dx: 2.4, dy: -1.6)
        windowController.showConnections = true
        windowController.selection = [shapeID]
        windowController.window?.setFrame(NSRect(x: 80, y: 80, width: 1280, height: 820), display: true)
        windowController.window?.layoutIfNeeded()
        for tab in 0..<4 {
            windowController.showRibbonTabForTest(tab)
            windowController.writeGUISnapshot(to: URL(fileURLWithPath: "/tmp/vsdx-gui-\(tab).png"))
        }

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vsdx-self-test-\(UUID().uuidString).vsdx")
        do {
            try document.write(to: url, ofType: StudioDocumentController.drawingType, for: .saveOperation, originalContentsURL: nil)
            check(FileManager.default.fileExists(atPath: url.path), "save writes a file")
        } catch {
            check(false, "save threw \(error.localizedDescription)")
            return finish(failures)
        }
        document.updateChangeCount(.changeCleared)
        document.close()

        do {
            try (controller as? StudioDocumentController)?.openVSDX(url)
            let reopened = controller.document(for: url) as? StudioDocument
            check(reopened != nil, "Open loads the saved file")
            check(reopened?.diagram.pages.first?.shapes.first?.text == "Hello Visio", "saved text reloads")
            reopened?.updateChangeCount(.changeCleared)
            reopened?.close()
        } catch {
            check(false, "reopen threw \(error.localizedDescription)")
        }

        let fixtureURL = URL(fileURLWithPath: fixture)
        do {
            try (controller as? StudioDocumentController)?.openVSDX(fixtureURL)
            let sample = controller.document(for: fixtureURL) as? StudioDocument
            let texts = sample?.diagram.pages.first?.shapes.map(\.text).joined(separator: " | ") ?? ""
            check(sample != nil, "sample file opens")
            check(texts.contains("Public Cloud"), "sample contains Public Cloud")
            check(texts.contains("My EC2"), "sample contains My EC2")
            check((sample?.diagram.pages.first?.shapes.count ?? 0) >= 5, "sample has shapes")
            if let page = sample?.diagram.pages.first, let png = PageDrawing.renderPNG(page: page, theme: sample?.diagram.theme ?? ThemeColors(), colors: sample?.diagram.colors ?? [:], pixelsPerInch: 40) {
                check(png.count > 1000, "sample renders")
            } else {
                check(false, "sample renders")
            }
            if let sampleWindow = sample?.windowControllers.first as? StudioWindowController {
                sampleWindow.window?.setFrame(NSRect(x: 80, y: 80, width: 1280, height: 820), display: true)
                sampleWindow.writeGUISnapshot(to: URL(fileURLWithPath: "/tmp/vsdx-gui-sample.png"))
            }
            sample?.updateChangeCount(.changeCleared)
            sample?.close()
        } catch {
            check(false, "sample open threw \(error.localizedDescription)")
        }

        controller.newDocument(nil)
        if let second = controller.documents.last as? StudioDocument,
           let host = second.windowControllers.first as? StudioWindowController {
            host.addPage(nil)
            check(second.diagram.pages.count == 2, "insert page")
            host.placeShapeForTest("decision")
            host.placeShapeForTest("terminator")
            let ids = second.diagram.pages[host.pageIndex].shapes.map(\.id)
            check(ids.count == 2, "two shapes on the new page")
            if ids.count == 2 {
                second.mutate("Group") { diagram in
                    _ = DiagramEdit.group(page: &diagram.pages[host.pageIndex], ids: ids, theme: diagram.theme, colors: diagram.colors)
                }
                check(second.diagram.pages[host.pageIndex].shapes.count == 1, "group makes one shape")
                check(second.undoManager?.canUndo == true, "undo is available")
            }
            second.updateChangeCount(.changeCleared)
            second.close()
        } else {
            check(false, "second document")
        }

        let ribbon = RibbonBar(frame: NSRect(x: 0, y: 0, width: 1280, height: 128))
        ribbon.translatesAutoresizingMaskIntoConstraints = false
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        host.contentView?.addSubview(ribbon)
        if let content = host.contentView {
            NSLayoutConstraint.activate([
                ribbon.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                ribbon.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                ribbon.topAnchor.constraint(equalTo: content.topAnchor),
                ribbon.heightAnchor.constraint(equalToConstant: 128)
            ])
        }
        ribbon.install(target: NSObject())
        for tab in 0..<4 {
            ribbon.showTab(tab)
            host.layoutIfNeeded()
            let clashes = ribbon.overlappingButtons()
            check(clashes.isEmpty, "ribbon tab \(tab) \(ribbon.groupDebug()) \(clashes.prefix(2).joined(separator: ", "))")
        }

        try? FileManager.default.removeItem(at: url)
        return finish(failures)
    }

    private static func finish(_ failures: [String]) -> Int32 {
        if failures.isEmpty {
            print("SELFTEST OK")
            return 0
        }
        print("SELFTEST \(failures.count) FAILURES")
        return 1
    }
}
