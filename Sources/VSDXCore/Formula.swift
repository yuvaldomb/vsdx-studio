import Foundation

public enum VisioValue: Equatable {
    case num(Double)
    case str(String)
    case point(Double, Double)

    public var number: Double? {
        if case .num(let value) = self { return value }
        if case .str(let value) = self { return Format.parseDouble(value) }
        return nil
    }

    public var text: String {
        switch self {
        case .num(let value): return Format.number(value)
        case .str(let value): return value
        case .point(let x, let y): return "\(Format.number(x)),\(Format.number(y))"
        }
    }
}

indirect enum Expr {
    case num(Double)
    case str(String)
    case name(String)
    case sheet(Int, String)
    case page(String)
    case call(String, [Expr])
    case binary(String, Expr, Expr)
    case unary(String, Expr)
}

enum FormulaParse {
    static func parse(_ source: String) -> Expr? {
        var lexer = Lexer(source)
        guard let expr = lexer.parseExpr() else { return nil }
        return expr
    }
}

private struct Lexer {
    let chars: [Character]
    var index: Int = 0

    init(_ source: String) { chars = Array(source) }

    mutating func parseExpr() -> Expr? { parseOr() }

    mutating func parseOr() -> Expr? {
        guard var left = parseAnd() else { return nil }
        while matchWord("OR") {
            guard let right = parseAnd() else { return nil }
            left = .binary("OR", left, right)
        }
        return left
    }

    mutating func parseAnd() -> Expr? {
        guard var left = parseCmp() else { return nil }
        while matchWord("AND") {
            guard let right = parseCmp() else { return nil }
            left = .binary("AND", left, right)
        }
        return left
    }

    mutating func parseCmp() -> Expr? {
        guard var left = parseSum() else { return nil }
        let ops = ["<>", "<=", ">=", "=", "<", ">"]
        while let op = matchAny(ops) {
            guard let right = parseSum() else { return nil }
            left = .binary(op, left, right)
        }
        return left
    }

    mutating func parseSum() -> Expr? {
        guard var left = parseTerm() else { return nil }
        while let op = matchAny(["+", "-", "&"]) {
            guard let right = parseTerm() else { return nil }
            left = .binary(op, left, right)
        }
        return left
    }

    mutating func parseTerm() -> Expr? {
        guard var left = parsePower() else { return nil }
        while let op = matchAny(["*", "/"]) {
            guard let right = parsePower() else { return nil }
            left = .binary(op, left, right)
        }
        return left
    }

    mutating func parsePower() -> Expr? {
        guard var left = parseUnary() else { return nil }
        if matchAny(["^"]) != nil {
            guard let right = parseUnary() else { return nil }
            left = .binary("^", left, right)
        }
        return left
    }

    mutating func parseUnary() -> Expr? {
        if matchAny(["-"]) != nil {
            guard let value = parseUnary() else { return nil }
            return .unary("-", value)
        }
        if matchWord("NOT") {
            guard let value = parseUnary() else { return nil }
            return .unary("NOT", value)
        }
        return parsePrimary()
    }

    mutating func parsePrimary() -> Expr? {
        skip()
        if matchAny(["("]) != nil {
            guard let value = parseExpr(), matchAny([")"]) != nil else { return nil }
            return value
        }
        if peek() == "\"" {
            return .str(readString())
        }
        if let number = readNumber() {
            return .num(number)
        }
        if let ident = readIdent() {
            if matchAny(["!"]) != nil {
                guard let cell = readIdent() else { return nil }
                if ident.caseInsensitiveCompare("ThePage") == .orderedSame {
                    return .page(cell)
                }
                if ident.lowercased().hasPrefix("sheet.") {
                    let idText = ident.dropFirst(6)
                    if let id = Int(idText) { return .sheet(id, cell) }
                }
                return .name(ident + "!" + cell)
            }
            if matchAny(["("]) != nil {
                var args: [Expr] = []
                skip()
                if matchAny([")"]) == nil {
                    while true {
                        guard let arg = parseExpr() else { return nil }
                        args.append(arg)
                        if matchAny([","]) != nil { continue }
                        if matchAny([")"]) != nil { break }
                        return nil
                    }
                }
                return .call(ident.uppercased(), args)
            }
            return .name(ident)
        }
        return nil
    }

    mutating func skip() {
        while index < chars.count, chars[index].isWhitespace { index += 1 }
    }

    func peek() -> Character? { index < chars.count ? chars[index] : nil }

    mutating func matchAny(_ tokens: [String]) -> String? {
        skip()
        for token in tokens.sorted(by: { $0.count > $1.count }) {
            if matches(token) {
                index += token.count
                return token
            }
        }
        return nil
    }

    mutating func matchWord(_ word: String) -> Bool {
        skip()
        guard matches(word) else { return false }
        let end = index + word.count
        if end < chars.count, chars[end].isLetter || chars[end] == "_" { return false }
        if end < chars.count, chars[end] == "(" { return false }
        index = end
        return true
    }

    func matches(_ token: String) -> Bool {
        let tokenChars = Array(token)
        guard index + tokenChars.count <= chars.count else { return false }
        for offset in tokenChars.indices {
            if chars[index + offset].uppercased() != tokenChars[offset].uppercased() { return false }
        }
        return true
    }

    mutating func readString() -> String {
        index += 1
        var out = ""
        while index < chars.count {
            let char = chars[index]
            index += 1
            if char == "\"" {
                if peek() == "\"" {
                    index += 1
                    out.append("\"")
                } else {
                    break
                }
            } else {
                out.append(char)
            }
        }
        return out
    }

    mutating func readNumber() -> Double? {
        skip()
        let start = index
        if peek()?.isNumber == true || (peek() == "." && index + 1 < chars.count && chars[index + 1].isNumber) {
            while peek()?.isNumber == true { index += 1 }
            if peek() == "." {
                index += 1
                while peek()?.isNumber == true { index += 1 }
            }
            if peek() == "e" || peek() == "E" {
                index += 1
                if peek() == "+" || peek() == "-" { index += 1 }
                while peek()?.isNumber == true { index += 1 }
            }
            let raw = String(chars[start..<index])
            guard var number = Double(raw) else { return nil }
            let unitStart = index
            while peek()?.isLetter == true || peek() == "_" { index += 1 }
            if index > unitStart {
                let unit = String(chars[unitStart..<index]).uppercased()
                switch unit {
                case "PT": number /= 72
                case "MM": number /= 25.4
                case "CM": number /= 2.54
                case "FT": number *= 12
                case "DEG": number *= Double.pi / 180
                case "IN", "IN_F", "DL", "RAD": break
                default:
                    index = unitStart
                }
            }
            return number
        }
        return nil
    }

    mutating func readIdent() -> String? {
        skip()
        guard let first = peek(), first.isLetter || first == "_" else { return nil }
        let start = index
        index += 1
        while let char = peek(), char.isLetter || char.isNumber || char == "_" || char == "." {
            index += 1
        }
        return String(chars[start..<index])
    }
}

public final class EvalScope {
    public var shapes: [Int: ShapeNode]
    public var pageWidth: Double
    public var pageHeight: Double
    public var theme: ThemeColors
    public var colors: [Int: String]
    public var useFormulas = false
    private var memo: [String: VisioValue] = [:]
    private var stack: Set<String> = []

    public init(page: DiagramPage, theme: ThemeColors, colors: [Int: String]) {
        var map: [Int: ShapeNode] = [:]
        func walk(_ shape: ShapeNode) {
            map[shape.id] = shape
            shape.children.forEach(walk)
        }
        page.shapes.forEach(walk)
        shapes = map
        pageWidth = page.width
        pageHeight = page.height
        self.theme = theme
        self.colors = colors
    }

    public func number(shape: ShapeNode, cell: String, preferValue: Bool = false) -> Double {
        if !useFormulas || preferValue, let cached = Format.parseDouble(shape.cell(cell)?.value) {
            return cached
        }
        if let evaluated = value(shape: shape, cell: cell).number { return evaluated }
        return Format.parseDouble(shape.cell(cell)?.value) ?? 0
    }

    public func value(shape: ShapeNode, cell: String) -> VisioValue {
        let key = "\(shape.id)#\(cell)"
        if let cached = memo[key] { return cached }
        if stack.contains(key) {
            return .num(Format.parseDouble(shape.cell(cell)?.value) ?? 0)
        }
        stack.insert(key)
        defer { stack.remove(key) }
        let result = evaluateCell(shape: shape, cell: cell)
        memo[key] = result
        return result
    }

    private func evaluateCell(shape: ShapeNode, cell: String) -> VisioValue {
        if cell.hasPrefix("Connections.") {
            return connectionValue(shape: shape, cell: cell, pageSpace: false)
        }
        if cell.hasPrefix("Geometry") {
            return geometryValue(shape: shape, name: cell)
        }
        guard let stored = shape.cell(cell) else {
            return .num(defaultNumber(shape: shape, cell: cell))
        }
        if let formula = stored.formula, !formula.isEmpty, formula != "Inh", formula != "No Formula" {
            if let parsed = FormulaParse.parse(formula), let value = eval(parsed, shape: shape, cell: cell) {
                return value
            }
        }
        if let number = Format.parseDouble(stored.value) { return .num(number) }
        if stored.value.hasPrefix("#") || stored.value == "Themed" { return .str(stored.value) }
        return .str(stored.value)
    }

    private func defaultNumber(shape: ShapeNode, cell: String) -> Double {
        switch cell {
        case "LocPinX": return number(shape: shape, cell: "Width") * 0.5
        case "LocPinY": return number(shape: shape, cell: "Height") * 0.5
        case "Angle", "FillForegndTrans", "LineColorTrans": return 0
        case "FillPattern", "LinePattern": return 1
        case "LineWeight": return 0.0104166667
        default: return 0
        }
    }

    private func eval(_ expr: Expr, shape: ShapeNode, cell: String) -> VisioValue? {
        switch expr {
        case .num(let value):
            return .num(value)
        case .str(let value):
            return .str(value)
        case .name(let name):
            if name.caseInsensitiveCompare("TRUE") == .orderedSame { return .num(1) }
            if name.caseInsensitiveCompare("FALSE") == .orderedSame { return .num(0) }
            if name.caseInsensitiveCompare("PI") == .orderedSame { return .num(Double.pi) }
            if name.hasPrefix("Geometry") || name.hasPrefix("Connections.") {
                return value(shape: shape, cell: name)
            }
            return value(shape: shape, cell: name)
        case .sheet(let id, let name):
            return sheetValue(from: shape, sheet: id, cell: name)
        case .page(let name):
            if name == "PageWidth" { return .num(pageWidth) }
            if name == "PageHeight" { return .num(pageHeight) }
            return .num(0)
        case .unary(let op, let inner):
            guard let value = eval(inner, shape: shape, cell: cell) else { return nil }
            if op == "-" { return .num(-(value.number ?? 0)) }
            if op == "NOT" { return .num((value.number ?? 0) == 0 ? 1 : 0) }
            return nil
        case .binary(let op, let lhs, let rhs):
            guard let left = eval(lhs, shape: shape, cell: cell), let right = eval(rhs, shape: shape, cell: cell) else { return nil }
            return binary(op, left, right)
        case .call(let name, let args):
            let values = args.compactMap { eval($0, shape: shape, cell: cell) }
            if values.count != args.count { return nil }
            return call(name, values, cell: cell)
        }
    }

    private func binary(_ op: String, _ left: VisioValue, _ right: VisioValue) -> VisioValue {
        switch op {
        case "+": return .num((left.number ?? 0) + (right.number ?? 0))
        case "-": return .num((left.number ?? 0) - (right.number ?? 0))
        case "*": return .num((left.number ?? 0) * (right.number ?? 0))
        case "/":
            let divisor = right.number ?? 0
            return .num(divisor == 0 ? 0 : (left.number ?? 0) / divisor)
        case "^": return .num(pow(left.number ?? 0, right.number ?? 0))
        case "&": return .str(left.text + right.text)
        case "=": return .num(same(left, right) ? 1 : 0)
        case "<>": return .num(same(left, right) ? 0 : 1)
        case "<": return .num((left.number ?? 0) < (right.number ?? 0) ? 1 : 0)
        case ">": return .num((left.number ?? 0) > (right.number ?? 0) ? 1 : 0)
        case "<=": return .num((left.number ?? 0) <= (right.number ?? 0) ? 1 : 0)
        case ">=": return .num((left.number ?? 0) >= (right.number ?? 0) ? 1 : 0)
        case "AND": return .num((left.number ?? 0) != 0 && (right.number ?? 0) != 0 ? 1 : 0)
        case "OR": return .num((left.number ?? 0) != 0 || (right.number ?? 0) != 0 ? 1 : 0)
        default: return .num(0)
        }
    }

    private func same(_ left: VisioValue, _ right: VisioValue) -> Bool {
        if let a = left.number, let b = right.number { return abs(a - b) < 0.0000001 }
        return left.text == right.text
    }

    private func call(_ name: String, _ args: [VisioValue], cell: String) -> VisioValue? {
        let nums = args.compactMap(\.number)
        switch name {
        case "GUARD", "THEMEGUARD", "ABS":
            return args.first
        case "MIN":
            return .num(nums.min() ?? 0)
        case "MAX":
            return .num(nums.max() ?? 0)
        case "IF":
            guard args.count >= 3 else { return args.last }
            return (args[0].number ?? 0) != 0 ? args[1] : args[2]
        case "AND":
            return .num(nums.allSatisfy { $0 != 0 } ? 1 : 0)
        case "OR":
            return .num(nums.contains { $0 != 0 } ? 1 : 0)
        case "NOT":
            return .num((nums.first ?? 0) == 0 ? 1 : 0)
        case "SQRT":
            return .num(sqrt(max(0, nums.first ?? 0)))
        case "SIN": return .num(sin(nums.first ?? 0))
        case "COS": return .num(cos(nums.first ?? 0))
        case "TAN": return .num(tan(nums.first ?? 0))
        case "ATAN2":
            if nums.count >= 2 { return .num(atan2(nums[0], nums[1])) }
            return .num(0)
        case "HYPOT":
            if nums.count >= 2 { return .num(hypot(nums[0], nums[1])) }
            return .num(abs(nums.first ?? 0))
        case "MAGNITUDE":
            if nums.count >= 2 { return .num(hypot(nums[0], nums[1])) }
            return .num(abs(nums.first ?? 0))
        case "INT": return .num(floor(nums.first ?? 0))
        case "ROUND":
            let digits = nums.count > 1 ? nums[1] : 0
            let factor = pow(10, digits)
            return .num((nums.first ?? 0) * factor / factor)
        case "FLOOR": return .num(floor(nums.first ?? 0))
        case "CEILING": return .num(ceil(nums.first ?? 0))
        case "SIGN":
            let value = nums.first ?? 0
            return .num(value < 0 ? -1 : (value > 0 ? 1 : 0))
        case "RGB":
            if nums.count >= 3 { return .str(ColorMath.hex(nums[0], nums[1], nums[2])) }
            return nil
        case "THEME", "THEMEVAL":
            if let first = args.first, case .str(let key) = first {
                if key.isEmpty { return .str(theme.dk1) }
                if let color = theme.named(key) { return .str(color) }
            }
            if args.count >= 2 { return args[1] }
            if let key = args.first?.text, let color = theme.named(key) { return .str(color) }
            return args.last
        case "MSOTINT", "TINT":
            guard args.count >= 2 else { return args.first }
            return .str(ColorMath.tint(args[0].text, percent: args[1].number ?? 0))
        case "SHADE":
            guard args.count >= 2 else { return args.first }
            return .str(ColorMath.shade(args[0].text, amount: args[1].number ?? 0))
        case "LUMDIFF":
            return .num(0.2)
        case "PNT":
            if nums.count >= 2 { return .point(nums[0], nums[1]) }
            return nil
        case "PAR":
            guard let point = args.first, case .point(let x, let y) = point else { return args.first }
            if cell.hasSuffix("Y") || cell == "PinY" || cell == "BeginY" || cell == "EndY" || cell == "LocPinY" {
                return .num(y)
            }
            return .num(x)
        case "DEG":
            return .num((nums.first ?? 0) * Double.pi / 180)
        case "RAD":
            return .num(nums.first ?? 0)
        default:
            return args.last
        }
    }

    private func sheetValue(from shape: ShapeNode, sheet: Int, cell: String) -> VisioValue {
        let targetId = shape.scope[sheet] ?? sheet
        guard let target = shapes[targetId] else { return .num(0) }
        if cell.hasPrefix("Connections.") {
            return connectionValue(shape: target, cell: cell, pageSpace: target.id != shape.id)
        }
        return value(shape: target, cell: cell)
    }

    private func connectionValue(shape: ShapeNode, cell: String, pageSpace: Bool) -> VisioValue {
        let isY = cell.contains(".Y")
        let digits = cell.filter(\.isNumber)
        let index = (Int(digits) ?? 1) - 1
        guard shape.connections.indices.contains(index) else { return .num(0) }
        let row = shape.connections[index]
        let localX = evalRowNumber(shape: shape, row: row, name: "X")
        let localY = evalRowNumber(shape: shape, row: row, name: "Y")
        if !pageSpace { return .num(isY ? localY : localX) }
        let point = GeometryMath.pagePoint(shape: shape, local: (localX, localY), scope: self)
        return .num(isY ? point.y : point.x)
    }

    private func geometryValue(shape: ShapeNode, name: String) -> VisioValue {
        let parts = name.split(separator: ".")
        guard parts.count == 2 else { return .num(0) }
        let sectionText = parts[0]
        let cellText = String(parts[1])
        let sectionNumber = Int(sectionText.filter(\.isNumber)) ?? 1
        let rowNumber = Int(cellText.filter(\.isNumber)) ?? 1
        let cellName = cellText.prefix { !$0.isNumber }
        guard let section = shape.geometry.first(where: { $0.ix == sectionNumber - 1 }) ?? shape.geometry[safe: sectionNumber - 1] else {
            return .num(0)
        }
        guard let row = section.rows.first(where: { $0.ix == rowNumber }) ?? section.rows[safe: rowNumber - 1] else {
            return .num(0)
        }
        return .num(evalRowNumber(shape: shape, row: row, name: String(cellName)))
    }

    public func evalRowNumber(shape: ShapeNode, row: GeoRow, name: String) -> Double {
        let raw = row.raw(name) ?? "0"
        if !useFormulas, let number = Format.parseDouble(raw) { return number }
        if let formula = row.formula(name), !formula.isEmpty, formula != "Inh", formula != "No Formula" {
            if let parsed = FormulaParse.parse(formula), let value = eval(parsed, shape: shape, cell: name)?.number {
                return value
            }
        }
        if raw == "Inh" || raw == "No Formula" { return 0 }
        if let number = Format.parseDouble(raw) { return number }
        if let parsed = FormulaParse.parse(raw), let value = eval(parsed, shape: shape, cell: name)?.number {
            return value
        }
        return 0
    }

    public func colorString(shape: ShapeNode, cell: String, fallback: String) -> String {
        if let raw = shape.cell(cell)?.value, raw.hasPrefix("#") { return ColorMath.normalize(raw) }
        let value = value(shape: shape, cell: cell)
        if case .str(let text) = value, text.hasPrefix("#") { return ColorMath.normalize(text) }
        if let raw = shape.cell(cell)?.value, let index = Int(raw), let mapped = colors[index] { return mapped }
        if let raw = shape.cell(cell)?.value, raw == "0" { return "#000000" }
        if let raw = shape.cell(cell)?.value, raw == "1" { return "#FFFFFF" }
        return fallback
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

public enum ColorMath {
    public static func normalize(_ text: String) -> String {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.hasPrefix("#") { raw = "#" + raw }
        if raw.count == 4 {
            let chars = Array(raw.dropFirst())
            return "#" + chars.map { "\($0)\($0)" }.joined()
        }
        return raw.lowercased()
    }

    public static func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
        func byte(_ value: Double) -> Int { max(0, min(255, Int(value.rounded()))) }
        return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
    }

    public static func rgb(_ hex: String) -> (Double, Double, Double) {
        var raw = hex
        if raw.hasPrefix("#") { raw.removeFirst() }
        if raw.count == 3 { raw = raw.map { "\($0)\($0)" }.joined() }
        guard raw.count >= 6, let value = Int(raw.prefix(6), radix: 16) else { return (0, 0, 0) }
        return (Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255))
    }

    public static func tint(_ color: String, percent: Double) -> String {
        let (r, g, b) = rgb(color.hasPrefix("#") ? color : "#000000")
        let t = max(0, min(100, percent)) / 100
        return hex(r + (255 - r) * t, g + (255 - g) * t, b + (255 - b) * t)
    }

    public static func shade(_ color: String, amount: Double) -> String {
        let (r, g, b) = rgb(color.hasPrefix("#") ? color : "#000000")
        let factor = max(0, min(1, 1 - amount))
        return hex(r * factor, g * factor, b * factor)
    }
}
