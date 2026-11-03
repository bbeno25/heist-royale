import SwiftUI

extension Path {
    /// Builds a path from SVG path data ("M0 540 L0 400 Q136 318 152 350 Z"), so shapes can be
    /// copied straight from the design files. Handles M, L, H, V, C, S, Q, T and Z in absolute and
    /// relative form; the designs use no arcs.
    init(svg data: String) {
        self.init()
        var reader = SVGPathReader(data)
        var point = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var op: UInt8 = 0

        while true {
            if let next = reader.command() {
                op = next
            } else if op == 0 || op == UInt8(ascii: "Z") || op == UInt8(ascii: "z") || !reader.hasNumber() {
                break  // end of data, or stray numbers
            }
            let relative = op >= UInt8(ascii: "a")
            let base = point
            func readPoint() -> CGPoint {
                let x = reader.number()
                let y = reader.number()
                return relative ? CGPoint(x: base.x + x, y: base.y + y) : CGPoint(x: x, y: y)
            }
            func reflected(_ control: CGPoint?) -> CGPoint {
                guard let control else { return base }
                return CGPoint(x: 2 * base.x - control.x, y: 2 * base.y - control.y)
            }
            var cubicControl: CGPoint?
            var quadControl: CGPoint?

            switch op | 0x20 {  // lowercase
            case UInt8(ascii: "m"):
                point = readPoint()
                subpathStart = point
                move(to: point)
                op = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")  // further pairs are lines
            case UInt8(ascii: "l"):
                point = readPoint()
                addLine(to: point)
            case UInt8(ascii: "h"):
                let x = reader.number()
                point.x = relative ? base.x + x : x
                addLine(to: point)
            case UInt8(ascii: "v"):
                let y = reader.number()
                point.y = relative ? base.y + y : y
                addLine(to: point)
            case UInt8(ascii: "c"):
                let control1 = readPoint()
                let control2 = readPoint()
                point = readPoint()
                addCurve(to: point, control1: control1, control2: control2)
                cubicControl = control2
            case UInt8(ascii: "s"):
                let control1 = reflected(lastCubicControl)
                let control2 = readPoint()
                point = readPoint()
                addCurve(to: point, control1: control1, control2: control2)
                cubicControl = control2
            case UInt8(ascii: "q"):
                let control = readPoint()
                point = readPoint()
                addQuadCurve(to: point, control: control)
                quadControl = control
            case UInt8(ascii: "t"):
                let control = reflected(lastQuadControl)
                point = readPoint()
                addQuadCurve(to: point, control: control)
                quadControl = control
            case UInt8(ascii: "z"):
                closeSubpath()
                point = subpathStart
            default:
                return  // unsupported command (arcs)
            }
            lastCubicControl = cubicControl
            lastQuadControl = quadControl
        }
    }
}

/// Reads commands and numbers out of SVG path data.
private struct SVGPathReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ text: String) {
        bytes = Array(text.utf8)
    }

    /// The next command letter, if one comes next.
    mutating func command() -> UInt8? {
        skipSeparators()
        guard index < bytes.count else { return nil }
        let byte = bytes[index]
        guard (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) else { return nil }
        index += 1
        return byte
    }

    mutating func hasNumber() -> Bool {
        skipSeparators()
        guard index < bytes.count else { return false }
        let byte = bytes[index]
        return Self.isDigit(byte) || byte == 0x2D || byte == 0x2B || byte == 0x2E
    }

    /// The next number; numbers may run together ("1.5-2", ".5.5").
    mutating func number() -> CGFloat {
        skipSeparators()
        let start = index
        if index < bytes.count, bytes[index] == 0x2D || bytes[index] == 0x2B { index += 1 }
        var sawDot = false
        while index < bytes.count {
            let byte = bytes[index]
            if Self.isDigit(byte) {
                index += 1
            } else if byte == 0x2E, !sawDot {
                sawDot = true
                index += 1
            } else if byte == 0x65 || byte == 0x45 {  // exponent
                index += 1
                if index < bytes.count, bytes[index] == 0x2D || bytes[index] == 0x2B { index += 1 }
            } else {
                break
            }
        }
        return CGFloat(Double(String(decoding: bytes[start..<index], as: UTF8.self)) ?? 0)
    }

    private mutating func skipSeparators() {
        while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x2C || (0x09...0x0D).contains(bytes[index]) {
            index += 1
        }
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
    }
}

/// A small piece of vector art from SVG path data, scaled from its view box to fit the frame.
struct SVGShape: Shape {
    let path: Path
    let viewBox: CGRect

    init(_ data: String, viewBox: CGRect = CGRect(x: 0, y: 0, width: 24, height: 24)) {
        path = Path(svg: data)
        self.viewBox = viewBox
    }

    func path(in rect: CGRect) -> Path {
        let transform = CGAffineTransform(translationX: -viewBox.minX, y: -viewBox.minY)
            .concatenating(CGAffineTransform(scaleX: rect.width / viewBox.width, y: rect.height / viewBox.height))
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return path.applying(transform)
    }
}
