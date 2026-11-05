import Foundation

public struct Cell: Equatable {
    public var value: String
    public var formula: String?
    public var units: String?

    public init(value: String, formula: String? = nil, units: String? = nil) {
        self.value = value
        self.formula = formula
        self.units = units
    }
}

public struct GeoRow: Equatable {
    public var type: String
    public var ix: Int
    public var cells: [String: Cell]
    public var deleted: Bool

    public init(type: String, ix: Int, cells: [String: Cell] = [:], deleted: Bool = false) {
        self.type = type
        self.ix = ix
        self.cells = cells
        self.deleted = deleted
    }

    public func raw(_ name: String) -> String? { cells[name]?.value }
    public func formula(_ name: String) -> String? { cells[name]?.formula }
}

public struct GeoSection: Equatable {
    public var ix: Int
    public var noFill: Bool
    public var noLine: Bool
    public var noShow: Bool
    public var rows: [GeoRow]

    public init(ix: Int = 0, noFill: Bool = false, noLine: Bool = false, noShow: Bool = false, rows: [GeoRow] = []) {
        self.ix = ix
        self.noFill = noFill
        self.noLine = noLine
        self.noShow = noShow
        self.rows = rows
    }
}

public struct PropRow: Equatable {
    public var name: String
    public var label: String
    public var value: String
    public var type: String

    public init(name: String, label: String, value: String, type: String = "0") {
        self.name = name
        self.label = label
        self.value = value
        self.type = type
    }
}

public struct ShapeConnect: Equatable {
    public var fromId: Int
    public var fromCell: String
    public var fromPart: Int
    public var toId: Int
    public var toCell: String
    public var toPart: Int

    public init(fromId: Int, fromCell: String, fromPart: Int, toId: Int, toCell: String, toPart: Int) {
        self.fromId = fromId
        self.fromCell = fromCell
        self.fromPart = fromPart
        self.toId = toId
        self.toCell = toCell
        self.toPart = toPart
    }

    public var isBegin: Bool { fromCell.hasPrefix("Begin") }
}

public struct LayerInfo: Equatable {
    public var index: Int
    public var name: String
    public var visible: Bool
    public var locked: Bool

    public init(index: Int, name: String, visible: Bool = true, locked: Bool = false) {
        self.index = index
        self.name = name
        self.visible = visible
        self.locked = locked
    }
}

public struct GuideLine: Equatable, Identifiable {
    public var id: Int
    public var horizontal: Bool
    public var position: Double

    public init(id: Int, horizontal: Bool, position: Double) {
        self.id = id
        self.horizontal = horizontal
        self.position = position
    }
}

public struct ShapeNode: Equatable, Identifiable {
    public var id: Int
    public var kind: String
    public var name: String
    public var nameU: String
    public var masterId: Int?
    public var masterShapeId: Int?
    public var parentId: Int?
    public var formulaKey: Int
    public var scope: [Int: Int]
    public var cells: [String: Cell]
    public var geometry: [GeoSection]
    public var connections: [GeoRow]
    public var character: [GeoRow]
    public var paragraph: [GeoRow]
    public var properties: [PropRow]
    public var text: String
    public var hasText: Bool
    public var hideText: Bool
    public var children: [ShapeNode]
    public var extras: [XMLElem]
    public var original: XMLElem?
    public var detached: Bool
    public var imagePNG: Data?

    public init(id: Int, kind: String = "Shape") {
        self.id = id
        self.kind = kind
        self.name = ""
        self.nameU = ""
        self.formulaKey = id
        self.parentId = nil
        self.scope = [:]
        self.cells = [:]
        self.geometry = []
        self.connections = []
        self.character = []
        self.paragraph = []
        self.properties = []
        self.text = ""
        self.hasText = false
        self.hideText = false
        self.children = []
        self.extras = []
        self.detached = false
    }

    public var isGroup: Bool { kind == "Group" || !children.isEmpty }
    public var is1D: Bool { cells["BeginX"] != nil && cells["EndX"] != nil }
    public var isGuide: Bool { kind == "Guide" }

    public func cell(_ name: String) -> Cell? { cells[name] }

    public mutating func setCell(_ name: String, value: String, formula: String? = nil, clearFormula: Bool = false, units: String? = nil) {
        var cell = cells[name] ?? Cell(value: value)
        cell.value = value
        if clearFormula {
            cell.formula = nil
        } else if let formula {
            cell.formula = formula
        }
        if let units { cell.units = units }
        cells[name] = cell
        if original != nil && !detached {
            original?.setCell(name: name, value: value, formula: formula, clearFormula: clearFormula, units: units)
        }
    }

    public mutating func setNumber(_ name: String, _ number: Double, clearFormula: Bool = false) {
        setCell(name, value: Format.number(number), clearFormula: clearFormula)
    }

    public mutating func setTextContent(_ value: String) {
        text = value
        hasText = true
        if var element = original, !detached {
            element.setPlainText(value)
            original = element
        } else {
            detached = true
            original = nil
        }
    }
}

public struct DiagramPage: Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var nameU: String
    public var width: Double
    public var height: Double
    public var shapes: [ShapeNode]
    public var connects: [ShapeConnect]
    public var layers: [LayerInfo]
    public var guides: [GuideLine]
    public var partName: String
    public var pageSheet: XMLElem?
    public var background: Bool

    public init(id: Int, name: String, width: Double = 11, height: Double = 8.5) {
        self.id = id
        self.name = name
        self.nameU = name
        self.width = width
        self.height = height
        self.shapes = []
        self.connects = []
        self.layers = []
        self.guides = []
        self.partName = "visio/pages/page1.xml"
        self.background = false
    }

    public func nextShapeId() -> Int {
        var maxId = 0
        func walk(_ shape: ShapeNode) {
            maxId = max(maxId, shape.id)
            shape.children.forEach(walk)
        }
        shapes.forEach(walk)
        for connect in connects {
            maxId = max(maxId, connect.fromId, connect.toId)
        }
        for guide in guides { maxId = max(maxId, guide.id) }
        return maxId + 1
    }

    public func shape(id: Int) -> ShapeNode? {
        func walk(_ shapes: [ShapeNode]) -> ShapeNode? {
            for shape in shapes {
                if shape.id == id { return shape }
                if let found = walk(shape.children) { return found }
            }
            return nil
        }
        return walk(shapes)
    }

    public mutating func updateShape(id: Int, _ body: (inout ShapeNode) -> Void) {
        func walk(_ shapes: inout [ShapeNode]) -> Bool {
            for index in shapes.indices {
                if shapes[index].id == id {
                    body(&shapes[index])
                    return true
                }
                if walk(&shapes[index].children) { return true }
            }
            return false
        }
        _ = walk(&shapes)
    }

    public mutating func removeShapes(ids: Set<Int>) {
        func walk(_ shapes: inout [ShapeNode]) {
            shapes.removeAll { ids.contains($0.id) }
            for index in shapes.indices { walk(&shapes[index].children) }
        }
        walk(&shapes)
        connects.removeAll { ids.contains($0.fromId) || ids.contains($0.toId) }
    }
}

public struct MasterShape: Equatable {
    public var id: Int
    public var name: String
    public var nameU: String
    public var root: ShapeNode?
    public var partName: String
}

public struct ThemeColors: Equatable {
    public init() {}
    public var accent1: String = "#4472C4"
    public var accent2: String = "#ED7D31"
    public var accent3: String = "#A5A5A5"
    public var accent4: String = "#FFC000"
    public var accent5: String = "#5B9BD5"
    public var accent6: String = "#70AD47"
    public var dk1: String = "#000000"
    public var lt1: String = "#FFFFFF"
    public var dk2: String = "#44546A"
    public var lt2: String = "#E7E6E6"
    public var background: String = "#FFFFFF"

    public func named(_ key: String) -> String? {
        switch key.lowercased() {
        case "accentcolor", "accentcolor1", "accent1": return accent1
        case "accentcolor2", "accent2": return accent2
        case "accentcolor3", "accent3": return accent3
        case "accentcolor4", "accent4": return accent4
        case "accentcolor5", "accent5": return accent5
        case "accentcolor6", "accent6": return accent6
        case "dark", "dk1", "textcolor": return dk1
        case "light", "lt1", "backgroundcolor": return lt1
        case "dk2": return dk2
        case "lt2": return lt2
        case "fillcolor": return accent1
        case "fillcolor2": return accent2
        case "linecolor": return dk1
        default: return nil
        }
    }
}

public struct Diagram: Equatable {
    public var pages: [DiagramPage]
    public var masters: [MasterShape]
    public var theme: ThemeColors
    public var colors: [Int: String]
    public var package: [String: Data]
    public var activePageIndex: Int

    public init() {
        let page = DiagramPage(id: 0, name: "Page-1")
        pages = [page]
        masters = []
        theme = ThemeColors()
        colors = [:]
        package = [:]
        activePageIndex = 0
    }

    public var activePage: DiagramPage {
        get {
            guard pages.indices.contains(activePageIndex) else { return pages[0] }
            return pages[activePageIndex]
        }
        set {
            guard pages.indices.contains(activePageIndex) else { return }
            pages[activePageIndex] = newValue
        }
    }

    public static func blank() -> Diagram { Diagram() }
}

public enum Format {
    public static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if abs(value) < 0.0000005 { return "0" }
        var text = String(format: "%.8f", value)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            text.removeLast()
        }
        if text == "-0" { return "0" }
        return text
    }

    public static func parseDouble(_ text: String?) -> Double? {
        guard var raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("#") { return nil }
        let units = ["IN_F", "IN", "PT", "MM", "CM", "DL", "DEG", "RAD", "FT"]
        var factor = 1.0
        let upper = raw.uppercased()
        for unit in units where upper.hasSuffix(unit) {
            raw = String(raw.dropLast(unit.count))
            switch unit {
            case "PT": factor = 1.0 / 72.0
            case "MM": factor = 1.0 / 25.4
            case "CM": factor = 1.0 / 2.54
            case "FT": factor = 12
            case "DEG": factor = Double.pi / 180
            default: factor = 1
            }
            break
        }
        guard let number = Double(raw) else { return nil }
        return number * factor
    }
}
