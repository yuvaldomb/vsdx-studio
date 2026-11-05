import AppKit

_ = StudioDocumentController()
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !CommandLine.arguments.contains("--self-test")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            (NSDocumentController.shared as? StudioDocumentController)?.openAndReport(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let flag = CommandLine.arguments.firstIndex(of: "--self-test") {
            let fixture = CommandLine.arguments.indices.contains(flag + 1) ? CommandLine.arguments[flag + 1] : ""
            let code = SelfTest.run(fixture: fixture)
            exit(code)
        }
        if NSDocumentController.shared.documents.isEmpty {
            NSDocumentController.shared.newDocument(nil)
        }
        NSColorPanel.shared.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About VSDX Studio", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide VSDX Studio", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit VSDX Studio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let controller = NSDocumentController.shared
        let file = NSMenu(title: "File")
        let newItem = file.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        newItem.target = controller
        let openItem = file.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        openItem.target = controller
        let recentMenu = NSMenu(title: "Open Recent")
        let clearRecent = recentMenu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clearRecent.target = controller
        let recentItem = file.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        file.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        file.addItem(.separator())
        file.addItem(withTitle: "Export PNG…", action: #selector(StudioWindowController.exportPNG(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Export PDF…", action: #selector(StudioWindowController.exportPDF(_:)), keyEquivalent: "")
        fileItem.submenu = file

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(StudioWindowController.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(StudioWindowController.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(StudioWindowController.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Delete", action: #selector(StudioWindowController.deleteShapes(_:)), keyEquivalent: "\u{8}")
        edit.addItem(withTitle: "Select All", action: #selector(StudioWindowController.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Duplicate", action: #selector(StudioWindowController.duplicate(_:)), keyEquivalent: "d")
        editItem.submenu = edit

        let shapeItem = NSMenuItem()
        main.addItem(shapeItem)
        let shape = NSMenu(title: "Shape")
        shape.addItem(withTitle: "Group", action: #selector(StudioWindowController.groupShapes(_:)), keyEquivalent: "g")
        shape.addItem(withTitle: "Ungroup", action: #selector(StudioWindowController.ungroupShapes(_:)), keyEquivalent: "G")
        shape.addItem(.separator())
        shape.addItem(withTitle: "Bring to Front", action: #selector(StudioWindowController.bringToFront(_:)), keyEquivalent: "")
        shape.addItem(withTitle: "Send to Back", action: #selector(StudioWindowController.sendToBack(_:)), keyEquivalent: "")
        shape.addItem(.separator())
        shape.addItem(withTitle: "Align Left", action: #selector(StudioWindowController.alignLeft(_:)), keyEquivalent: "")
        shape.addItem(withTitle: "Align Center", action: #selector(StudioWindowController.alignCenter(_:)), keyEquivalent: "")
        shape.addItem(withTitle: "Align Right", action: #selector(StudioWindowController.alignRight(_:)), keyEquivalent: "")
        shape.addItem(withTitle: "Align Top", action: #selector(StudioWindowController.alignTop(_:)), keyEquivalent: "")
        shape.addItem(withTitle: "Align Middle", action: #selector(StudioWindowController.alignMiddle(_:)), keyEquivalent: "")
        shape.addItem(withTitle: "Align Bottom", action: #selector(StudioWindowController.alignBottom(_:)), keyEquivalent: "")
        shape.addItem(withTitle: "Distribute Horizontally", action: #selector(StudioWindowController.distributeHorizontal(_:)), keyEquivalent: "")
        shape.addItem(withTitle: "Distribute Vertically", action: #selector(StudioWindowController.distributeVertical(_:)), keyEquivalent: "")
        shapeItem.submenu = shape

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Zoom In", action: #selector(StudioWindowController.zoomIn(_:)), keyEquivalent: "=")
        view.addItem(withTitle: "Zoom Out", action: #selector(StudioWindowController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Actual Size", action: #selector(StudioWindowController.zoomActual(_:)), keyEquivalent: "0")
        view.addItem(withTitle: "Fit Page", action: #selector(StudioWindowController.zoomFit(_:)), keyEquivalent: "1")
        view.addItem(.separator())
        view.addItem(withTitle: "Grid", action: #selector(StudioWindowController.toggleGrid(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Rulers", action: #selector(StudioWindowController.toggleRulers(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Snap", action: #selector(StudioWindowController.toggleSnap(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Connection Points", action: #selector(StudioWindowController.toggleConnections(_:)), keyEquivalent: "")
        viewItem.submenu = view

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowItem.submenu = window

        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }
}
