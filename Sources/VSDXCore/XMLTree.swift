import Foundation

public enum XMLItem: Equatable {
    case text(String)
    case elem(XMLElem)
}

public struct XMLElem: Equatable {
    public var name: String
    public var attrs: [String: String]
    public var items: [XMLItem]

    public init(name: String, attrs: [String: String] = [:], items: [XMLItem] = []) {
        self.name = name
        self.attrs = attrs
        self.items = items
    }

    public init(name: String, attrs: [String: String] = [:], children: [XMLElem], text: String = "") {
        var items: [XMLItem] = []
        if !text.isEmpty { items.append(.text(text)) }
        items.append(contentsOf: children.map { .elem($0) })
        self.init(name: name, attrs: attrs, items: items)
    }

    public func attr(_ key: String) -> String? { attrs[key] }

    public mutating func setAttr(_ key: String, _ value: String?) {
        if let value {
            attrs[key] = value
        } else {
            attrs.removeValue(forKey: key)
        }
    }

    public var elements: [XMLElem] {
        items.compactMap { item in
            if case .elem(let element) = item { return element }
            return nil
        }
    }

    public var text: String {
        items.compactMap { item in
            if case .text(let value) = item { return value }
            return nil
        }.joined()
    }

    public func elements(named name: String) -> [XMLElem] {
        elements.filter { $0.name == name }
    }

    public func first(named name: String) -> XMLElem? {
        elements.first { $0.name == name }
    }

    public mutating func replaceElements(named name: String, with replacement: [XMLElem]) {
        items.removeAll { item in
            if case .elem(let element) = item { return element.name == name }
            return false
        }
        items.append(contentsOf: replacement.map { .elem($0) })
    }

    public mutating func append(_ element: XMLElem) {
        items.append(.elem(element))
    }
}

public enum XMLTree {
    public static func parse(_ data: Data) -> XMLElem? {
        let parser = XMLParser(data: data)
        let delegate = Builder()
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { return nil }
        return root
    }

    public static func parse(_ string: String) -> XMLElem? {
        parse(Data(string.utf8))
    }

    public static func serialize(_ element: XMLElem, declaration: Bool = true) -> String {
        var text = ""
        if declaration {
            text += "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        }
        write(element, into: &text)
        return text
    }

    public static func data(_ element: XMLElem, declaration: Bool = true) -> Data {
        Data(serialize(element, declaration: declaration).utf8)
    }

    private static func write(_ element: XMLElem, into text: inout String) {
        text += "<"
        text += element.name
        for key in element.attrs.keys.sorted() {
            text += " "
            text += key
            text += "=\""
            text += escape(element.attrs[key] ?? "", attribute: true)
            text += "\""
        }
        if element.items.isEmpty {
            text += "/>"
            return
        }
        text += ">"
        for item in element.items {
            switch item {
            case .text(let value):
                text += escape(value, attribute: false)
            case .elem(let child):
                write(child, into: &text)
            }
        }
        text += "</"
        text += element.name
        text += ">"
    }

    public static func escape(_ string: String, attribute: Bool) -> String {
        var out = ""
        out.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"" where attribute: out += "&quot;"
            case "\n": out += "&#10;"
            case "\r": out += "&#13;"
            default: out.append(Character(scalar))
            }
        }
        return out
    }
}

private final class Builder: NSObject, XMLParserDelegate {
    var root: XMLElem?
    private var stack: [XMLElem] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        stack.append(XMLElem(name: localName(qName ?? elementName), attrs: attributeDict))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].items.append(.text(string))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let finished = stack.popLast() else { return }
        if stack.isEmpty {
            root = finished
        } else {
            stack[stack.count - 1].items.append(.elem(finished))
        }
    }

    private func localName(_ name: String) -> String {
        guard let index = name.lastIndex(of: ":") else { return name }
        return String(name[name.index(after: index)...])
    }
}

extension XMLElem {
    public func cell(_ name: String) -> XMLElem? {
        elements.first { $0.name == "Cell" && $0.attr("N") == name }
    }

    public mutating func setCell(name: String, value: String, formula: String? = nil, clearFormula: Bool = false, units: String? = nil) {
        var cell = self.cell(name) ?? XMLElem(name: "Cell", attrs: ["N": name])
        cell.setAttr("N", name)
        cell.setAttr("V", value)
        if clearFormula {
            cell.setAttr("F", nil)
        } else if let formula {
            cell.setAttr("F", formula)
        }
        if let units { cell.setAttr("U", units) }
        if let index = items.firstIndex(where: { item in
            if case .elem(let element) = item { return element.name == "Cell" && element.attr("N") == name }
            return false
        }) {
            items[index] = .elem(cell)
        } else if let index = items.firstIndex(where: { item in
            if case .elem(let element) = item { return element.name != "Cell" }
            return false
        }) {
            items.insert(.elem(cell), at: index)
        } else {
            items.append(.elem(cell))
        }
    }

    public func cellValue(_ name: String) -> String? { cell(name)?.attr("V") }
    public func cellFormula(_ name: String) -> String? { cell(name)?.attr("F") }

    public mutating func setPlainText(_ value: String) {
        items.removeAll { item in
            if case .elem(let element) = item { return element.name == "Text" }
            return false
        }
        var text = XMLElem(name: "Text")
        text.items = [
            .elem(XMLElem(name: "cp", attrs: ["IX": "0"])),
            .elem(XMLElem(name: "pp", attrs: ["IX": "0"])),
            .text(value)
        ]
        items.append(.elem(text))
    }
}
