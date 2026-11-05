import Foundation

extension VsdxIO {
    public static func write(_ diagram: Diagram) throws -> Data {
        var parts = diagram.package
        let pages = diagram.pages.isEmpty ? [DiagramPage(id: 0, name: "Page-1")] : diagram.pages
        if parts["visio/document.xml"] == nil { parts["visio/document.xml"] = documentXML() }
        if parts["_rels/.rels"] == nil { parts["_rels/.rels"] = rootRels() }
        if parts["visio/_rels/document.xml.rels"] == nil { parts["visio/_rels/document.xml.rels"] = documentRels() }
        if parts["docProps/app.xml"] == nil { parts["docProps/app.xml"] = appXML(pages: pages) }
        parts["docProps/core.xml"] = coreXML()

        var storedPages = pages
        for index in storedPages.indices {
            if storedPages[index].partName.isEmpty || !storedPages[index].partName.contains("visio/pages/page") {
                storedPages[index].partName = "visio/pages/page\(index + 1).xml"
            }
            parts[storedPages[index].partName] = XMLTree.data(pageXML(storedPages[index]))
        }
        let keep = Set(storedPages.map(\.partName))
        for key in parts.keys where key.hasPrefix("visio/pages/page") && key.hasSuffix(".xml") && !keep.contains(key) {
            parts.removeValue(forKey: key)
        }
        parts["visio/pages/pages.xml"] = XMLTree.data(pagesXML(storedPages))
        parts["visio/pages/_rels/pages.xml.rels"] = XMLTree.data(pageRels(storedPages))
        let active = storedPages.indices.contains(diagram.activePageIndex) ? storedPages[diagram.activePageIndex] : storedPages[0]
        parts["visio/windows.xml"] = XMLTree.data(windowsXML(active))
        parts["[Content_Types].xml"] = XMLTree.data(contentTypes(existing: parts["[Content_Types].xml"], pages: storedPages))
        return try ZipArchive.write(parts)
    }

    static func pageXML(_ page: DiagramPage) -> XMLElem {
        var root = XMLElem(name: "PageContents", attrs: visioAttrs)
        var shapes = XMLElem(name: "Shapes")
        for shape in page.shapes {
            shapes.append(emitShape(shape))
        }
        root.append(shapes)
        if !page.connects.isEmpty {
            var connects = XMLElem(name: "Connects")
            for connect in page.connects {
                connects.append(XMLElem(name: "Connect", attrs: [
                    "FromSheet": String(connect.fromId),
                    "FromCell": connect.fromCell,
                    "FromPart": String(connect.fromPart),
                    "ToSheet": String(connect.toId),
                    "ToCell": connect.toCell,
                    "ToPart": String(connect.toPart)
                ]))
            }
            root.append(connects)
        }
        return root
    }

    public static func emitShape(_ shape: ShapeNode) -> XMLElem {
        let dirtyChild = shape.children.contains { $0.detached || $0.original == nil }
        if let original = shape.original, !shape.detached, !dirtyChild {
            return original
        }
        var element = XMLElem(name: "Shape", attrs: [
            "ID": String(shape.id),
            "NameU": shape.nameU.isEmpty ? shape.name : shape.nameU,
            "Name": shape.name,
            "Type": shape.children.isEmpty ? (shape.kind == "Guide" ? "Guide" : "Shape") : "Group",
            "LineStyle": "0",
            "FillStyle": "0",
            "TextStyle": "0"
        ])
        if shape.name.isEmpty {
            element.setAttr("Name", nil)
            element.setAttr("NameU", nil)
        }
        let preferred = ["PinX", "PinY", "Width", "Height", "LocPinX", "LocPinY", "Angle", "FlipX", "FlipY", "BeginX", "BeginY", "EndX", "EndY", "FillForegnd", "FillBkgnd", "FillPattern", "FillForegndTrans", "LineColor", "LineWeight", "LinePattern", "LineCap", "BeginArrow", "EndArrow", "BeginArrowSize", "EndArrowSize", "Rounding", "VerticalAlign", "HideText", "ObjType", "ShapeRouteStyle", "TxtPinX", "TxtPinY", "TxtWidth", "TxtHeight", "TxtLocPinX", "TxtLocPinY", "LeftMargin", "RightMargin", "TopMargin", "BottomMargin"]
        var written = Set<String>()
        for name in preferred {
            guard let cell = shape.cells[name] else { continue }
            element.setCell(name: name, value: cell.value, formula: cell.formula, units: cell.units)
            written.insert(name)
        }
        for name in shape.cells.keys.sorted() where !written.contains(name) {
            let cell = shape.cells[name]!
            element.setCell(name: name, value: cell.value, formula: cell.formula, units: cell.units)
        }
        for section in shape.geometry {
            element.append(geometrySection(section))
        }
        if !shape.connections.isEmpty {
            var section = XMLElem(name: "Section", attrs: ["N": "Connection"])
            for (index, row) in shape.connections.enumerated() where !row.deleted {
                section.append(rowElement(row, fallbackIX: index))
            }
            element.append(section)
        }
        if !shape.character.isEmpty {
            var section = XMLElem(name: "Section", attrs: ["N": "Character"])
            for (index, row) in shape.character.enumerated() {
                section.append(rowElement(row, fallbackIX: index))
            }
            element.append(section)
        }
        if !shape.paragraph.isEmpty {
            var section = XMLElem(name: "Section", attrs: ["N": "Paragraph"])
            for (index, row) in shape.paragraph.enumerated() {
                section.append(rowElement(row, fallbackIX: index))
            }
            element.append(section)
        }
        if !shape.properties.isEmpty {
            var section = XMLElem(name: "Section", attrs: ["N": "Property"])
            for prop in shape.properties {
                var row = XMLElem(name: "Row", attrs: ["N": prop.name])
                row.setCell(name: "Value", value: prop.value)
                row.setCell(name: "Label", value: prop.label)
                row.setCell(name: "Type", value: prop.type)
                section.append(row)
            }
            element.append(section)
        }
        for extra in shape.extras { element.append(extra) }
        if shape.hasText || !shape.text.isEmpty {
            element.setPlainText(shape.text)
        }
        if !shape.children.isEmpty {
            var container = XMLElem(name: "Shapes")
            for child in shape.children { container.append(emitShape(child)) }
            element.append(container)
        }
        return element
    }

    private static func geometrySection(_ section: GeoSection) -> XMLElem {
        var element = XMLElem(name: "Section", attrs: ["N": "Geometry", "IX": String(section.ix)])
        element.setCell(name: "NoFill", value: section.noFill ? "1" : "0")
        element.setCell(name: "NoLine", value: section.noLine ? "1" : "0")
        element.setCell(name: "NoShow", value: section.noShow ? "1" : "0")
        for row in section.rows where !row.deleted {
            element.append(rowElement(row, fallbackIX: row.ix))
        }
        return element
    }

    private static func rowElement(_ row: GeoRow, fallbackIX: Int) -> XMLElem {
        var element = XMLElem(name: "Row", attrs: ["T": row.type, "IX": String(row.ix == 0 ? fallbackIX : row.ix)])
        if row.type.isEmpty { element.setAttr("T", nil) }
        let order = ["X", "Y", "A", "B", "C", "D", "E", "Font", "Color", "Style", "Size", "HorzAlign", "DirX", "DirY", "Type"]
        var written = Set<String>()
        for name in order {
            guard let cell = row.cells[name] else { continue }
            element.setCell(name: name, value: cell.value, formula: cell.formula, units: cell.units)
            written.insert(name)
        }
        for name in row.cells.keys.sorted() where !written.contains(name) && !name.isEmpty {
            let cell = row.cells[name]!
            element.setCell(name: name, value: cell.value, formula: cell.formula, units: cell.units)
        }
        return element
    }

    private static func pagesXML(_ pages: [DiagramPage]) -> XMLElem {
        var root = XMLElem(name: "Pages", attrs: visioAttrs)
        for (index, page) in pages.enumerated() {
            var element = XMLElem(name: "Page", attrs: [
                "ID": String(page.id),
                "NameU": page.nameU.isEmpty ? page.name : page.nameU,
                "Name": page.name,
                "ViewScale": "-1",
                "ViewCenterX": Format.number(page.width / 2),
                "ViewCenterY": Format.number(page.height / 2)
            ])
            var sheet = page.pageSheet ?? XMLElem(name: "PageSheet", attrs: ["LineStyle": "0", "FillStyle": "0", "TextStyle": "0"])
            sheet.setCell(name: "PageWidth", value: Format.number(page.width))
            sheet.setCell(name: "PageHeight", value: Format.number(page.height))
            sheet.setCell(name: "PageScale", value: "1", units: "IN")
            sheet.setCell(name: "DrawingScale", value: "1", units: "IN")
            sheet.setCell(name: "DrawingSizeType", value: "1")
            sheet.setCell(name: "DrawingScaleType", value: "0")
            if page.width >= page.height {
                sheet.setCell(name: "PrintPageOrientation", value: "2")
            }
            element.append(sheet)
            element.append(XMLElem(name: "Rel", attrs: ["r:id": "rId\(index + 1)"]))
            root.append(element)
        }
        return root
    }

    private static func pageRels(_ pages: [DiagramPage]) -> XMLElem {
        var root = XMLElem(name: "Relationships", attrs: ["xmlns": relNS])
        for (index, page) in pages.enumerated() {
            let file = page.partName.split(separator: "/").last.map(String.init) ?? "page\(index + 1).xml"
            root.append(XMLElem(name: "Relationship", attrs: [
                "Id": "rId\(index + 1)",
                "Type": "http://schemas.microsoft.com/visio/2010/relationships/page",
                "Target": file
            ]))
        }
        return root
    }

    private static func contentTypes(existing: Data?, pages: [DiagramPage]) -> XMLElem {
        var root = existing.flatMap { XMLTree.parse($0) } ?? XMLElem(name: "Types", attrs: ["xmlns": "http://schemas.openxmlformats.org/package/2006/content-types"])
        func ensureDefault(ext: String, type: String) {
            if root.elements(named: "Default").contains(where: { $0.attr("Extension") == ext }) { return }
            root.items.insert(.elem(XMLElem(name: "Default", attrs: ["Extension": ext, "ContentType": type])), at: 0)
        }
        func ensure(_ part: String, _ type: String) {
            let name = part.hasPrefix("/") ? part : "/" + part
            if root.elements(named: "Override").contains(where: { $0.attr("PartName")?.caseInsensitiveCompare(name) == .orderedSame }) { return }
            root.append(XMLElem(name: "Override", attrs: ["PartName": name, "ContentType": type]))
        }
        ensureDefault(ext: "rels", type: "application/vnd.openxmlformats-package.relationships+xml")
        ensureDefault(ext: "xml", type: "application/xml")
        ensure("visio/document.xml", "application/vnd.ms-visio.drawing.main+xml")
        ensure("visio/pages/pages.xml", "application/vnd.ms-visio.pages+xml")
        ensure("visio/windows.xml", "application/vnd.ms-visio.windows+xml")
        ensure("docProps/core.xml", "application/vnd.openxmlformats-package.core-properties+xml")
        ensure("docProps/app.xml", "application/vnd.openxmlformats-officedocument.extended-properties+xml")
        for page in pages {
            ensure(page.partName, "application/vnd.ms-visio.page+xml")
        }
        return root
    }

    private static func windowsXML(_ page: DiagramPage) -> XMLElem {
        var root = XMLElem(name: "Windows", attrs: visioAttrs.merging(["ClientWidth": "1600", "ClientHeight": "900"]))
        var window = XMLElem(name: "Window", attrs: [
            "ID": "0",
            "WindowType": "Drawing",
            "WindowState": "1073741824",
            "WindowLeft": "0",
            "WindowTop": "0",
            "WindowWidth": "1600",
            "WindowHeight": "900",
            "ContainerType": "Page",
            "Page": String(page.id),
            "ViewScale": "-1",
            "ViewCenterX": Format.number(page.width / 2),
            "ViewCenterY": Format.number(page.height / 2)
        ])
        for (name, value) in [("ShowRulers", "1"), ("ShowGrid", "1"), ("ShowPageBreaks", "0"), ("ShowGuides", "1"), ("ShowConnectionPoints", "1"), ("GlueSettings", "9"), ("SnapSettings", "65847"), ("SnapExtensions", "34"), ("DynamicGridEnabled", "1"), ("TabSplitterPos", "0.5")] {
            window.append(XMLElem(name: name, attrs: [:], children: [], text: value))
        }
        root.append(window)
        return root
    }

    private static func documentXML() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <VisioDocument xmlns="http://schemas.microsoft.com/office/visio/2012/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xml:space="preserve">
        <DocumentSettings TopPage="0" DefaultTextStyle="0" DefaultLineStyle="0" DefaultFillStyle="0" DefaultGuideStyle="0">
        <GlueSettings>9</GlueSettings><SnapSettings>65847</SnapSettings><SnapExtensions>34</SnapExtensions><DynamicGridEnabled>1</DynamicGridEnabled>
        <ProtectStyles>0</ProtectStyles><ProtectShapes>0</ProtectShapes><ProtectMasters>0</ProtectMasters><ProtectBkgnds>0</ProtectBkgnds>
        </DocumentSettings>
        <Colors>
        <ColorEntry IX="0" RGB="#000000"/><ColorEntry IX="1" RGB="#FFFFFF"/><ColorEntry IX="2" RGB="#FF0000"/><ColorEntry IX="3" RGB="#00FF00"/><ColorEntry IX="4" RGB="#0000FF"/>
        </Colors>
        <FaceNames>
        <FaceName NameU="Calibri" ID="0"/><FaceName NameU="Segoe UI" ID="1"/><FaceName NameU="Arial" ID="2"/>
        </FaceNames>
        </VisioDocument>
        """
        return Data(xml.utf8)
    }

    private static func rootRels() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="\(relNS)">
        <Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/document" Target="visio/document.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
        return Data(xml.utf8)
    }

    private static func documentRels() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="\(relNS)">
        <Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/pages" Target="pages/pages.xml"/>
        <Relationship Id="rId2" Type="http://schemas.microsoft.com/visio/2010/relationships/windows" Target="windows.xml"/>
        </Relationships>
        """
        return Data(xml.utf8)
    }

    private static func coreXML() -> Data {
        let now = ISO8601DateFormatter().string(from: Date())
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <dc:title></dc:title><dc:creator>VSDX Studio</dc:creator><cp:lastModifiedBy>VSDX Studio</cp:lastModifiedBy>
        <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
        return Data(xml.utf8)
    }

    private static func appXML(pages: [DiagramPage]) -> Data {
        let names = pages.map { "<vt:lpstr>\(XMLTree.escape($0.name, attribute: false))</vt:lpstr>" }.joined()
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
        <Application>VSDX Studio</Application><AppVersion>16.0000</AppVersion>
        <HeadingPairs><vt:vector size="2" baseType="variant"><vt:variant><vt:lpstr>Pages</vt:lpstr></vt:variant><vt:variant><vt:i4>\(pages.count)</vt:i4></vt:variant></vt:vector></HeadingPairs>
        <TitlesOfParts><vt:vector size="\(pages.count)" baseType="lpstr">\(names)</vt:vector></TitlesOfParts>
        </Properties>
        """
        return Data(xml.utf8)
    }

    private static let relNS = "http://schemas.openxmlformats.org/package/2006/relationships"
    private static let visioAttrs = [
        "xmlns": "http://schemas.microsoft.com/office/visio/2012/main",
        "xmlns:r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
        "xml:space": "preserve"
    ]
}

private extension Dictionary where Key == String, Value == String {
    func merging(_ other: [String: String]) -> [String: String] {
        var copy = self
        for (key, value) in other { copy[key] = value }
        return copy
    }
}
