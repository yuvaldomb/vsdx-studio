import AppKit
import VSDXCore

enum StudioChrome {
    static let accent = NSColor(srgbRed: 57.0 / 255, green: 85.0 / 255, blue: 163.0 / 255, alpha: 1)
    static let accentSoft = NSColor(srgbRed: 232.0 / 255, green: 236.0 / 255, blue: 248.0 / 255, alpha: 1)
    static let pane = NSColor(srgbRed: 246.0 / 255, green: 245.0 / 255, blue: 244.0 / 255, alpha: 1)
    static let pasteboard = NSColor(srgbRed: 236.0 / 255, green: 236.0 / 255, blue: 236.0 / 255, alpha: 1)
    static let hairline = NSColor(srgbRed: 220.0 / 255, green: 218.0 / 255, blue: 216.0 / 255, alpha: 1)
    static let label = NSColor(srgbRed: 90.0 / 255, green: 88.0 / 255, blue: 86.0 / 255, alpha: 1)
    static let title = NSColor(srgbRed: 32.0 / 255, green: 31.0 / 255, blue: 30.0 / 255, alpha: 1)
}

enum EditorTool: String {
    case pointer, text, rectangle, ellipse, line, connector
}

enum ShapeClipboard {
    static var shapes: [ShapeNode] = []
}

struct QuickStyle {
    var fill: String
    var line: String
    var text: String
}

let quickStyles: [QuickStyle] = [
    QuickStyle(fill: "#FFFFFF", line: "#000000", text: "#000000"),
    QuickStyle(fill: "#4472C4", line: "#2F5496", text: "#FFFFFF"),
    QuickStyle(fill: "#5B9BD5", line: "#2E75B6", text: "#FFFFFF"),
    QuickStyle(fill: "#ED7D31", line: "#C65911", text: "#FFFFFF"),
    QuickStyle(fill: "#70AD47", line: "#548235", text: "#FFFFFF"),
    QuickStyle(fill: "#FFC000", line: "#BF8F00", text: "#000000"),
    QuickStyle(fill: "#7030A0", line: "#4B1F6F", text: "#FFFFFF"),
    QuickStyle(fill: "#00B0F0", line: "#0070C0", text: "#FFFFFF"),
    QuickStyle(fill: "#F2F2F2", line: "#7F7F7F", text: "#000000"),
    QuickStyle(fill: "#000000", line: "#000000", text: "#FFFFFF"),
    QuickStyle(fill: "#FFF2CC", line: "#BF8F00", text: "#000000"),
    QuickStyle(fill: "#DEEBF7", line: "#5B9BD5", text: "#1F4E79")
]

func studioButton(_ title: String, symbol: String, target: AnyObject?, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    button.imagePosition = .imageLeading
    button.bezelStyle = .recessed
    button.controlSize = .small
    button.font = NSFont.systemFont(ofSize: 11)
    button.setButtonType(.momentaryPushIn)
    return button
}

func inchesString(_ value: Double) -> String {
    String(format: "%.3f", value)
}

extension NSColor {
    convenience init?(hex: String) {
        var raw = hex
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}
