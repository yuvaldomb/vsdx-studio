import AppKit
import UniformTypeIdentifiers
import VSDXCore

@objc(StudioDocument)
final class StudioDocument: NSDocument {
    var diagram = Diagram.blank()

    override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }

    override init() {
        super.init()
        fileType = StudioDocumentController.drawingType
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        if let vsdx = UTType(filenameExtension: "vsdx") {
            savePanel.allowedContentTypes = [vsdx]
        }
        savePanel.allowedFileTypes = ["vsdx"]
        savePanel.nameFieldStringValue = (fileURL?.deletingPathExtension().lastPathComponent ?? "Drawing")
        return true
    }

    override func makeWindowControllers() {
        let controller = StudioWindowController(document: self)
        addWindowController(controller)
        controller.showWindow(nil)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        diagram = try VsdxIO.read(data)
    }

    override func data(ofType typeName: String) throws -> Data {
        try VsdxIO.write(diagram)
    }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        "vsdx"
    }

    func mutate(_ name: String, _ body: (inout Diagram) -> Void) {
        let before = diagram
        body(&diagram)
        undoManager?.registerUndo(withTarget: self) { document in
            document.restore(before, name: name)
        }
        undoManager?.setActionName(name)
        updateChangeCount(.changeDone)
        refreshEditors(full: true)
    }

    func restore(_ snapshot: Diagram, name: String) {
        let current = diagram
        undoManager?.registerUndo(withTarget: self) { document in
            document.restore(current, name: name)
        }
        undoManager?.setActionName(name)
        diagram = snapshot
        updateChangeCount(.changeDone)
        refreshEditors(full: true)
    }

    func replaceWithoutUndo(_ diagram: Diagram) {
        self.diagram = diagram
        refreshEditors(full: false)
    }

    private func refreshEditors(full: Bool) {
        for controller in windowControllers {
            (controller as? StudioWindowController)?.syncFromDocument(rebuildPanels: full)
        }
    }
}
