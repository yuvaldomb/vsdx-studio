import Foundation

public enum VsdxReadError: LocalizedError {
    case notAPackage
    case missingDocument

    public var errorDescription: String? {
        switch self {
        case .notAPackage: return "This file is not a Visio .vsdx drawing."
        case .missingDocument: return "This Visio file has no drawing document."
        }
    }
}

public enum VsdxIO {
    public static func read(_ data: Data) throws -> Diagram {
        let parts = try ZipArchive.read(data)
        guard !parts.isEmpty else { throw VsdxReadError.notAPackage }
        var diagram = Diagram()
        diagram.package = parts
        let rootRels = relationships(parts["_rels/.rels"])
        guard let documentTarget = rootRels.first(where: { $0.type.contains("relationships/document") })?.target else {
            throw VsdxReadError.missingDocument
        }
        let documentPath = normalize(base: "", target: documentTarget)
        if let documentXML = parts[documentPath], let document = XMLTree.parse(documentXML) {
            diagram.colors = parseColors(document)
            diagram.theme = themeFromPackage(parts, documentRels: relationships(parts[relsPath(documentPath)]))
        }
        let documentRels = relationships(parts[relsPath(documentPath)])
        let masterMap = loadMasters(parts: parts, documentPath: documentPath, rels: documentRels)
        diagram.masters = masterMap.values.sorted { $0.id < $1.id }
        let masterShapes = Dictionary(uniqueKeysWithValues: masterMap.compactMap { id, master in master.root.map { (id, $0) } })
        guard let pagesTarget = documentRels.first(where: { $0.type.contains("relationships/pages") })?.target else {
            return diagram
        }
        let pagesPath = normalize(base: baseFolder(documentPath), target: pagesTarget)
        guard let pagesXML = parts[pagesPath], let pagesRoot = XMLTree.parse(pagesXML) else { return diagram }
        let pageRels = relationships(parts[relsPath(pagesPath)])
        var pages: [DiagramPage] = []
        for pageElem in pagesRoot.elements(named: "Page") {
            let rel = pageElem.first(named: "Rel")?.attr("r:id") ?? pageElem.first(named: "Rel")?.attr("id")
            let target = pageRels.first { $0.id == rel }?.target
            let pagePath = target.map { normalize(base: baseFolder(pagesPath), target: $0) } ?? ""
            pages.append(parsePage(pageElem, partName: pagePath, xml: parts[pagePath], masters: masterShapes, parts: parts))
        }
        if !pages.isEmpty { diagram.pages = pages }
        diagram.activePageIndex = 0
        return diagram
    }

    private static func parsePage(_ element: XMLElem, partName: String, xml: Data?, masters: [Int: ShapeNode], parts: [String: Data]) -> DiagramPage {
        let id = Int(element.attr("ID") ?? "0") ?? 0
        let name = element.attr("Name") ?? "Page-\(id + 1)"
        var page = DiagramPage(id: id, name: name)
        page.nameU = element.attr("NameU") ?? name
        page.partName = partName
        page.background = element.attr("Background") == "1"
        if let sheet = element.first(named: "PageSheet") {
            page.pageSheet = sheet
            if let width = Format.parseDouble(sheet.cellValue("PageWidth")) { page.width = width }
            if let height = Format.parseDouble(sheet.cellValue("PageHeight")) { page.height = height }
            page.layers = parseLayers(sheet)
        }
        guard let xml, let root = XMLTree.parse(xml) else { return page }
        let parsed = root.elements(named: "Shapes").flatMap { $0.elements(named: "Shape") }.map { parseShape($0, parentId: nil) }
        page.shapes = parsed.map { instantiate($0, masters: masters) }
        repairTree(&page)
        if let connects = root.first(named: "Connects") {
            page.connects = connects.elements(named: "Connect").map { connect in
                ShapeConnect(
                    fromId: Int(connect.attr("FromSheet") ?? "0") ?? 0,
                    fromCell: connect.attr("FromCell") ?? "BeginX",
                    fromPart: Int(connect.attr("FromPart") ?? "0") ?? 0,
                    toId: Int(connect.attr("ToSheet") ?? "0") ?? 0,
                    toCell: connect.attr("ToCell") ?? "PinX",
                    toPart: Int(connect.attr("ToPart") ?? "0") ?? 0
                )
            }
        }
        let imageRels = relationships(parts[relsPath(partName)])
        attachImages(&page.shapes, rels: imageRels, pagePath: partName, parts: parts)
        return page
    }

    private static func parseLayers(_ sheet: XMLElem) -> [LayerInfo] {
        guard let section = sheet.elements(named: "Section").first(where: { $0.attr("N") == "Layer" }) else { return [] }
        return section.elements(named: "Row").enumerated().map { offset, row in
            let cells = Dictionary(uniqueKeysWithValues: row.elements(named: "Cell").map { ($0.attr("N") ?? "", $0.attr("V") ?? "") })
            let index = Int(row.attr("IX") ?? "") ?? offset
            return LayerInfo(index: index, name: cells["Name"] ?? "Layer \(index + 1)", visible: cells["Visible"] != "0", locked: cells["Lock"] == "1")
        }
    }

    private static func loadMasters(parts: [String: Data], documentPath: String, rels: [Relationship]) -> [Int: MasterShape] {
        guard let target = rels.first(where: { $0.type.contains("relationships/masters") })?.target else { return [:] }
        let mastersPath = normalize(base: baseFolder(documentPath), target: target)
        guard let xml = parts[mastersPath], let root = XMLTree.parse(xml) else { return [:] }
        let masterRels = relationships(parts[relsPath(mastersPath)])
        var map: [Int: MasterShape] = [:]
        for element in root.elements(named: "Master") {
            let id = Int(element.attr("ID") ?? "") ?? 0
            let rel = element.first(named: "Rel")?.attr("r:id") ?? element.first(named: "Rel")?.attr("id") ?? ""
            let file = masterRels.first { $0.id == rel }?.target ?? ""
            let path = normalize(base: baseFolder(mastersPath), target: file)
            var master = MasterShape(id: id, name: element.attr("Name") ?? "", nameU: element.attr("NameU") ?? "", root: nil, partName: path)
            if let data = parts[path], let masterXML = XMLTree.parse(data) {
                let shapes = masterXML.elements(named: "Shapes").flatMap { $0.elements(named: "Shape") }
                master.root = shapes.first.map { parseShape($0, parentId: nil) }
            }
            map[id] = master
        }
        return map
    }

    private static func themeFromPackage(_ parts: [String: Data], documentRels: [Relationship]) -> ThemeColors {
        var theme = ThemeColors()
        for rel in documentRels where rel.type.contains("/theme") || rel.type.contains("relationships/theme") {
            let path = normalize(base: "visio/", target: rel.target)
            if let data = parts[path] ?? parts[normalize(base: "visio", target: rel.target)], let xml = XMLTree.parse(data) {
                applyTheme(xml, to: &theme)
            }
        }
        return theme
    }

    private static func applyTheme(_ element: XMLElem, to theme: inout ThemeColors) {
        func color(_ element: XMLElem) -> String? {
            if element.name == "srgbClr", let value = element.attr("val") { return "#" + value }
            for child in element.elements {
                if let found = color(child) { return found }
            }
            return nil
        }
        func walk(_ element: XMLElem) {
            if let value = color(element) {
                switch element.name {
                case "accent1": theme.accent1 = value
                case "accent2": theme.accent2 = value
                case "accent3": theme.accent3 = value
                case "accent4": theme.accent4 = value
                case "accent5": theme.accent5 = value
                case "accent6": theme.accent6 = value
                case "dk1": theme.dk1 = value
                case "lt1": theme.lt1 = value
                case "dk2": theme.dk2 = value
                case "lt2": theme.lt2 = value
                case "bkgnd": theme.background = value
                default: break
                }
            }
            element.elements.forEach(walk)
        }
        walk(element)
    }

    private static func parseColors(_ document: XMLElem) -> [Int: String] {
        var colors: [Int: String] = [0: "#000000", 1: "#FFFFFF"]
        guard let table = document.first(named: "Colors") else { return colors }
        for entry in table.elements where entry.name == "ColorEntry" {
            if let index = Int(entry.attr("IX") ?? ""), let rgb = entry.attr("RGB") {
                colors[index] = rgb.hasPrefix("#") ? rgb : "#" + rgb
            }
        }
        return colors
    }

    private static func instantiate(_ shape: ShapeNode, masters: [Int: ShapeNode]) -> ShapeNode {
        guard let masterId = shape.masterId, let master = masters[masterId] else {
            var copy = shape
            copy.children = shape.children.map { instantiate($0, masters: masters) }
            return copy
        }
        var merged = merge(master: master, instance: shape, masters: masters)
        var map: [Int: Int] = [:]
        collectScope(master: master, instance: merged, into: &map)
        applyScope(&merged, map: map)
        return merged
    }

    private static func merge(master: ShapeNode, instance: ShapeNode, masters: [Int: ShapeNode]) -> ShapeNode {
        var result = master
        result.id = instance.id
        result.kind = instance.kind
        result.name = instance.name.isEmpty ? master.name : instance.name
        result.nameU = instance.nameU.isEmpty ? master.nameU : instance.nameU
        result.masterId = instance.masterId
        result.masterShapeId = instance.masterShapeId
        result.formulaKey = master.formulaKey == 0 ? master.id : master.formulaKey
        result.parentId = instance.parentId
        result.original = instance.original
        result.detached = false
        result.imagePNG = instance.imagePNG ?? master.imagePNG
        for (name, cell) in instance.cells {
            overlayCell(into: &result, name: name, cell: cell)
        }
        if instance.hasText {
            result.text = instance.text
            result.hasText = true
        }
        if !instance.geometry.isEmpty {
            result.geometry = mergeSections(master: master.geometry, instance: instance.geometry)
        }
        if !instance.connections.isEmpty {
            result.connections = zipRows(master: master.connections, instance: instance.connections)
        }
        if !instance.character.isEmpty {
            result.character = zipRows(master: master.character, instance: instance.character)
        }
        if !instance.paragraph.isEmpty {
            result.paragraph = zipRows(master: master.paragraph, instance: instance.paragraph)
        }
        if !instance.properties.isEmpty { result.properties = instance.properties }
        if !instance.children.isEmpty {
            result.children = instance.children.map { child in
                if let masterId = child.masterId, let nested = masters[masterId] {
                    return merge(master: nested, instance: child, masters: masters)
                }
                if let masterChild = master.children.first(where: { $0.id == child.masterShapeId || $0.id == child.formulaKey }) {
                    return merge(master: masterChild, instance: child, masters: masters)
                }
                return child
            }
        } else {
            result.children = master.children.enumerated().map { offset, child in
                var copy = child
                copy.formulaKey = child.id
                copy.parentId = result.id
                copy.masterId = nil
                copy.original = nil
                if copy.id == result.id || copy.id < 1000 {
                    copy.id = 1_000_000 + result.id * 100 + offset
                }
                return copy
            }
        }
        result.hideText = (result.cells["HideText"]?.value == "1")
        return result
    }

    private static func overlayCell(into shape: inout ShapeNode, name: String, cell: Cell) {
        let formula = cell.formula ?? ""
        if formula.isEmpty || formula == "No Formula" {
            shape.cells[name] = Cell(value: cell.value, formula: nil, units: cell.units)
            return
        }
        if formula != "Inh" {
            shape.cells[name] = cell
            return
        }
        if var existing = shape.cells[name], let inherited = existing.formula, !inherited.isEmpty, inherited != "Inh", inherited != "No Formula" {
            existing.value = cell.value.isEmpty ? existing.value : cell.value
            shape.cells[name] = existing
        } else {
            shape.cells[name] = Cell(value: cell.value, formula: nil, units: cell.units)
        }
    }

    private static func mergeSections(master: [GeoSection], instance: [GeoSection]) -> [GeoSection] {
        instance.enumerated().map { index, section in
            var merged = section
            let source = master.first { $0.ix == section.ix } ?? master[safe: index]
            guard let source else { return section }
            if section.rows.isEmpty { return source }
            merged.rows = zipRows(master: source.rows, instance: section.rows)
            return merged
        }
    }

    private static func zipRows(master: [GeoRow], instance: [GeoRow]) -> [GeoRow] {
        guard !instance.isEmpty else { return master }
        return instance.enumerated().map { index, row in
            let source = master.first { $0.ix == row.ix && $0.type == row.type } ?? master[safe: index]
            guard let source else { return row }
            var merged = source
            merged.ix = row.ix
            merged.type = row.type.isEmpty ? source.type : row.type
            merged.deleted = row.deleted || source.deleted
            for (name, cell) in row.cells {
                let formula = cell.formula ?? ""
                if formula.isEmpty || formula == "No Formula" {
                    merged.cells[name] = Cell(value: cell.value, formula: nil, units: cell.units)
                } else if formula != "Inh" {
                    merged.cells[name] = cell
                } else if var existing = merged.cells[name] {
                    if existing.formula == nil || existing.formula == "Inh" {
                        merged.cells[name] = Cell(value: cell.value, formula: nil, units: cell.units)
                    } else {
                        existing.value = cell.value
                        merged.cells[name] = existing
                    }
                } else {
                    merged.cells[name] = Cell(value: cell.value, formula: nil, units: cell.units)
                }
            }
            return merged
        }
    }

    private static func collectScope(master: ShapeNode, instance: ShapeNode, into map: inout [Int: Int]) {
        map[master.id] = instance.id
        if master.formulaKey != master.id { map[master.formulaKey] = instance.id }
        for child in instance.children {
            if let masterChild = master.children.first(where: { $0.id == child.formulaKey || $0.id == child.masterShapeId }) {
                collectScope(master: masterChild, instance: child, into: &map)
            }
        }
    }

    private static func applyScope(_ shape: inout ShapeNode, map: [Int: Int]) {
        shape.scope = map
        for index in shape.children.indices {
            shape.children[index].parentId = shape.id
            applyScope(&shape.children[index], map: map)
        }
    }

    private static func repairTree(_ page: inout DiagramPage) {
        var seen = Set<Int>()
        var next = (page.shapes.map(\.id).max() ?? 0) + 1
        func walk(_ shapes: inout [ShapeNode], parent: Int?) {
            for index in shapes.indices {
                let oldId = shapes[index].id
                if oldId == 0 || seen.contains(oldId) {
                    while seen.contains(next) { next += 1 }
                    shapes[index].id = next
                    rewriteScope(&shapes[index], from: oldId, to: next)
                    next += 1
                }
                seen.insert(shapes[index].id)
                shapes[index].parentId = parent
                walk(&shapes[index].children, parent: shapes[index].id)
            }
        }
        walk(&page.shapes, parent: nil)
    }

    private static func rewriteScope(_ shape: inout ShapeNode, from oldId: Int, to newId: Int) {
        shape.scope = shape.scope.mapValues { $0 == oldId ? newId : $0 }
        for index in shape.children.indices {
            rewriteScope(&shape.children[index], from: oldId, to: newId)
        }
    }

    private static func attachImages(_ shapes: inout [ShapeNode], rels: [Relationship], pagePath: String, parts: [String: Data]) {
        func walk(_ shape: inout ShapeNode) {
            if let original = shape.original, let foreign = original.elements.first(where: { $0.name == "ForeignData" }) {
                let relId = foreign.first(named: "Rel")?.attr("r:id") ?? foreign.first(named: "Rel")?.attr("id")
                if let relId, let target = rels.first(where: { $0.id == relId })?.target {
                    let path = normalize(base: baseFolder(pagePath), target: target)
                    shape.imagePNG = parts[path]
                }
            }
            for index in shape.children.indices {
                walk(&shape.children[index])
            }
        }
        for index in shapes.indices { walk(&shapes[index]) }
    }

    public static func parseShape(_ element: XMLElem, parentId: Int?) -> ShapeNode {
        var shape = ShapeNode(id: Int(element.attr("ID") ?? "0") ?? 0, kind: element.attr("Type") ?? "Shape")
        shape.name = element.attr("Name") ?? ""
        shape.nameU = element.attr("NameU") ?? shape.name
        shape.masterId = Int(element.attr("Master") ?? "")
        shape.masterShapeId = Int(element.attr("MasterShape") ?? "")
        shape.formulaKey = shape.id
        shape.parentId = parentId
        shape.original = element
        for cell in element.elements(named: "Cell") {
            let name = cell.attr("N") ?? ""
            guard !name.isEmpty else { continue }
            shape.cells[name] = Cell(value: cell.attr("V") ?? "", formula: cell.attr("F"), units: cell.attr("U"))
        }
        for section in element.elements(named: "Section") {
            switch section.attr("N") ?? "" {
            case "Geometry":
                shape.geometry.append(parseGeometry(section))
            case "Connection":
                shape.connections = section.elements(named: "Row").map(parseRow)
            case "Character":
                shape.character = section.elements(named: "Row").map(parseRow)
            case "Paragraph":
                shape.paragraph = section.elements(named: "Row").map(parseRow)
            case "Property":
                shape.properties = section.elements(named: "Row").map { row in
                    let cells = Dictionary(uniqueKeysWithValues: row.elements(named: "Cell").map { ($0.attr("N") ?? "", $0.attr("V") ?? "") })
                    let rowName = row.attr("N") ?? cells["Label"] ?? "Property"
                    return PropRow(name: rowName, label: cells["Label"] ?? rowName, value: cells["Value"] ?? "", type: cells["Type"] ?? "0")
                }
            default:
                shape.extras.append(section)
            }
        }
        if let text = element.first(named: "Text") {
            shape.text = plainText(text).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            shape.hasText = true
        }
        if let container = element.first(named: "Shapes") {
            shape.children = container.elements(named: "Shape").map { parseShape($0, parentId: shape.id) }
        }
        return shape
    }

    private static func parseGeometry(_ section: XMLElem) -> GeoSection {
        var geometry = GeoSection(ix: Int(section.attr("IX") ?? "0") ?? 0)
        for cell in section.elements(named: "Cell") {
            switch cell.attr("N") {
            case "NoFill": geometry.noFill = cell.attr("V") == "1"
            case "NoLine": geometry.noLine = cell.attr("V") == "1"
            case "NoShow": geometry.noShow = cell.attr("V") == "1"
            default: break
            }
        }
        geometry.rows = section.elements(named: "Row").map(parseRow)
        return geometry
    }

    private static func parseRow(_ row: XMLElem) -> GeoRow {
        var cells: [String: Cell] = [:]
        for cell in row.elements(named: "Cell") {
            cells[cell.attr("N") ?? ""] = Cell(value: cell.attr("V") ?? "", formula: cell.attr("F"), units: cell.attr("U"))
        }
        return GeoRow(type: row.attr("T") ?? row.attr("N") ?? "LineTo", ix: Int(row.attr("IX") ?? "0") ?? 0, cells: cells, deleted: row.attr("Del") == "1")
    }

    private static func plainText(_ element: XMLElem) -> String {
        var text = ""
        for item in element.items {
            switch item {
            case .text(let value):
                text += value
            case .elem(let child):
                if ["cp", "pp", "tp", "fld"].contains(child.name) { continue }
                text += plainText(child)
            }
        }
        return text
    }
}

struct Relationship {
    var id: String
    var type: String
    var target: String
}

func relationships(_ data: Data?) -> [Relationship] {
    guard let data, let xml = XMLTree.parse(data) else { return [] }
    return xml.elements(named: "Relationship").map {
        Relationship(id: $0.attr("Id") ?? "", type: $0.attr("Type") ?? "", target: $0.attr("Target") ?? "")
    }
}

func relsPath(_ part: String) -> String {
    let url = part.split(separator: "/").map(String.init)
    guard let file = url.last else { return part }
    let folder = url.dropLast().joined(separator: "/")
    if folder.isEmpty { return "_rels/\(file).rels" }
    return folder + "/_rels/\(file).rels"
}

func baseFolder(_ part: String) -> String {
    let parts = part.split(separator: "/").map(String.init)
    return parts.dropLast().joined(separator: "/")
}

func normalize(base: String, target: String) -> String {
    if target.hasPrefix("/") { return String(target.dropFirst()) }
    var parts = base.split(separator: "/").map(String.init)
    for piece in target.split(separator: "/") {
        if piece == ".." { if !parts.isEmpty { parts.removeLast() } }
        else if piece != "." && !piece.isEmpty { parts.append(String(piece)) }
    }
    return parts.joined(separator: "/")
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
