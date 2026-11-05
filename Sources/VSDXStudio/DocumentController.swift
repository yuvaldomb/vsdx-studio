import AppKit
import UniformTypeIdentifiers

final class StudioDocumentController: NSDocumentController {
    static let drawingType = "com.yuvald.vsdxstudio.drawing"

    override var defaultType: String? { Self.drawingType }

    override func documentClass(forType typeName: String) -> AnyClass? {
        if Self.isDrawing(typeName) { return StudioDocument.self }
        return super.documentClass(forType: typeName)
    }

    override func typeForContents(of url: URL) throws -> String {
        if url.pathExtension.lowercased() == "vsdx" { return Self.drawingType }
        return try super.typeForContents(of: url)
    }

    override func makeDocument(withContentsOf url: URL, ofType typeName: String) throws -> NSDocument {
        let document = StudioDocument()
        document.fileType = Self.drawingType
        try document.read(from: url, ofType: Self.drawingType)
        return document
    }

    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let document = StudioDocument()
        document.fileType = Self.drawingType
        return document
    }

    @objc override func newDocument(_ sender: Any?) {
        let document = StudioDocument()
        document.fileType = Self.drawingType
        addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
    }

    @objc override func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowsOtherFileTypes = false
        panel.title = "Open Visio Drawing"
        panel.prompt = "Open"
        panel.message = "Choose a .vsdx file."
        var types: [UTType] = [.data]
        if let vsdx = UTType(filenameExtension: "vsdx") { types.insert(vsdx, at: 0) }
        panel.allowedContentTypes = types
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                self.openAndReport(url)
            }
        }
    }

    func openAndReport(_ url: URL) {
        do {
            try openVSDX(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot open \(url.lastPathComponent)"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func openVSDX(_ url: URL) throws {
        if url.pathExtension.lowercased() != "vsdx" {
            throw VsdxOpenError.wrongExtension
        }
        if let existing = document(for: url) {
            existing.showWindows()
            return
        }
        let document = try makeDocument(withContentsOf: url, ofType: Self.drawingType)
        document.fileURL = url
        document.fileType = Self.drawingType
        addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        noteNewRecentDocument(document)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(newDocument(_:)) || menuItem.action == #selector(openDocument(_:)) {
            return true
        }
        return super.validateMenuItem(menuItem)
    }

    private static func isDrawing(_ typeName: String) -> Bool {
        let name = typeName.lowercased()
        return name == drawingType || name == "visio drawing" || name == "vsdx" || name.contains("visio")
    }
}

enum VsdxOpenError: LocalizedError {
    case wrongExtension

    var errorDescription: String? {
        "Choose a file that ends with .vsdx."
    }
}
