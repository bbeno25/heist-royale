import CoreText
import SwiftUI

/// One word of the logo as Bungee glyph outlines, with the design's bouncy per-letter offsets and
/// tilts (the SVG `dy` and `rotate` lists). Centred on x = 0 with the first letter's baseline on y = 0.
struct WordmarkWord: Sendable {
    let outline: Path
    /// The text box the design's gradients span: font ascent to descent around the bounced letters.
    let box: CGRect
    /// Advance width with letter spacing, like the browser's `getComputedTextLength()`.
    let width: CGFloat

    static let heist = WordmarkWord("HEIST", size: 136, dy: [0, -5, 7, -6, 5], rotate: [-3, 2, -2, 3, -2])
    static let royale = WordmarkWord("ROYALE", size: 146, dy: [0, -7, 9, -7, 8, -6], rotate: [-2, 3, -2, 3, -2, 2])

    private init(_ text: String, size: CGFloat, dy: [CGFloat], rotate: [CGFloat], letterSpacing: CGFloat = 4) {
        let font = CTFontCreateWithName(BrandFont.bungee as CFString, size, nil)
        let string = CFAttributedStringCreate(nil, text as CFString, [kCTFontAttributeName: font] as CFDictionary)!
        let line = CTLineCreateWithAttributedString(string)

        var glyphs: [CGGlyph] = []
        var positions: [CGPoint] = []
        var advances: [CGSize] = []
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var runGlyphs = [CGGlyph](repeating: 0, count: count)
            var runPositions = [CGPoint](repeating: .zero, count: count)
            var runAdvances = [CGSize](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &runGlyphs)
            CTRunGetPositions(run, CFRange(), &runPositions)
            CTRunGetAdvances(run, CFRange(), &runAdvances)
            glyphs += runGlyphs
            positions += runPositions
            advances += runAdvances
        }

        let width = (positions.last?.x ?? 0) + (advances.last?.width ?? 0) + letterSpacing * CGFloat(glyphs.count)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        var outline = Path()
        var baseline: CGFloat = 0
        var top = CGFloat.infinity
        var bottom = -CGFloat.infinity
        for index in glyphs.indices {
            // SVG dy shifts accumulate; rotate turns each letter about its own baseline origin.
            baseline += index < dy.count ? dy[index] : 0
            top = min(top, baseline - ascent)
            bottom = max(bottom, baseline + descent)
            guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
            let degrees = index < rotate.count ? rotate[index] : 0
            let x = positions[index].x + letterSpacing * CGFloat(index) - width / 2
            let transform = CGAffineTransform(scaleX: 1, y: -1)  // font space is y-up
                .concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180))
                .concatenating(CGAffineTransform(translationX: x, y: baseline))
            outline.addPath(Path(glyph), transform: transform)
        }
        self.outline = outline
        self.width = width
        box = CGRect(x: -width / 2, y: top, width: width, height: bottom - top)
    }

    /// Draws the layered lettering at the context's origin: hard drop shadow, dark rim, ink outline,
    /// cream rim, gradient face and gloss.
    func draw(in context: GraphicsContext, style: WordmarkStyle, shadowDepth: CGFloat, rimDepth: CGFloat) {
        func outlined(_ color: Color, lineWidth: CGFloat, dropping dy: CGFloat = 0) {
            var layer = context
            layer.translateBy(x: 0, y: dy)
            layer.fill(outline, with: .color(color))
            layer.stroke(outline, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
        }
        outlined(Brand.ink, lineWidth: 28, dropping: shadowDepth)
        outlined(style.deep, lineWidth: 18, dropping: rimDepth)
        outlined(Brand.ink, lineWidth: 26)
        outlined(Brand.cream, lineWidth: 11)
        let top = CGPoint(x: 0, y: box.minY)
        let bottom = CGPoint(x: 0, y: box.maxY)
        context.fill(outline, with: .linearGradient(style.face, startPoint: top, endPoint: bottom))
        context.fill(outline, with: .linearGradient(WordmarkStyle.gloss, startPoint: top, endPoint: bottom))
    }

    /// A white sheen sweeping across the letters, repeating every 3.4 s from `begin`.
    func drawShine(in context: GraphicsContext, time: Double, begin: Double, travel: CGFloat, band: CGRect) {
        guard time >= begin else { return }
        let progress = ((time - begin) / 3.4).truncatingRemainder(dividingBy: 1)
        let x = -travel + 2 * travel * progress
        var shine = context
        shine.clip(to: outline)
        shine.concatenate(CGAffineTransform(a: 1, b: 0, c: tan(-20 * .pi / 180), d: 1, tx: 0, ty: 0))
        shine.fill(Path(band.offsetBy(dx: x, dy: 0)), with: .color(.white.opacity(0.6)))
    }
}

/// The two colourways of the lettering: HEIST is the thief's orange, ROYALE the police blue.
enum WordmarkStyle {
    case thief, police

    var face: Gradient {
        switch self {
        case .thief: Gradient(stops: [.init(color: Color(hex: 0xFFD9A0), location: 0), .init(color: Brand.thief, location: 0.5), .init(color: Color(hex: 0xC33A0C), location: 1)])
        case .police: Gradient(stops: [.init(color: Color(hex: 0xB5DCFF), location: 0), .init(color: Brand.police, location: 0.5), .init(color: Color(hex: 0x123C96), location: 1)])
        }
    }

    var deep: Color {
        switch self {
        case .thief: Color(hex: 0x7A2A0A)
        case .police: Color(hex: 0x0B2A66)
        }
    }

    static let gloss = Gradient(stops: [
        .init(color: .white.opacity(0.75), location: 0),
        .init(color: .white.opacity(0.18), location: 0.42),
        .init(color: .white.opacity(0), location: 0.48),
        .init(color: .white.opacity(0), location: 1),
    ])

    static let steel = Gradient(stops: [
        .init(color: Color(hex: 0xF2F5FF), location: 0),
        .init(color: Color(hex: 0xA9B3CF), location: 0.5),
        .init(color: Color(hex: 0x5B6584), location: 1),
    ])
}

/// The siren between the words: an orange and blue dome on a steel base, with light rays that swing
/// and flash. `drawLights` goes behind the lettering and `drawBody` in front, as in the design.
/// Contexts arrive translated to the siren's centre, in design units.
struct Siren {
    enum Style { case stacked, line }

    let style: Style
    /// 1 when the orange (left) side is lit, 0 when the blue side is.
    let flash: Double
    let swing: Angle

    /// The siren at a moment of its loop; `still` holds a steady half-lit pose (Reduce Motion).
    init(style: Style, time: Double, still: Bool) {
        self.style = style
        if still {
            flash = 0.5
            swing = .zero
        } else {
            flash = 0.5 + 0.5 * cos(2 * .pi * time / 0.9)
            swing = .degrees((style == .stacked ? 7 : 8) * sin(2 * .pi * time / 1.8))
        }
    }

    func drawLights(in context: GraphicsContext) {
        let stacked = style == .stacked
        let reach: CGFloat = stacked ? 500 : 620
        let rayTop: CGFloat = stacked ? -150 : -130
        let rayBottom: CGFloat = stacked ? 110 : 100
        let strength = stacked ? 0.6 : 0.85
        let dim = stacked ? 0.12 : 0.1

        var rays = context
        rays.rotate(by: swing)
        for side in [CGFloat(-1), 1] {
            let color = side < 0 ? Brand.thief : Brand.police
            let lit = side < 0 ? flash : 1 - flash
            var ray = Path()
            ray.move(to: CGPoint(x: 50 * side, y: -14))
            ray.addLine(to: CGPoint(x: reach * side, y: rayTop))
            ray.addLine(to: CGPoint(x: reach * side, y: rayBottom))
            ray.closeSubpath()
            var layer = rays
            layer.opacity = dim + (1 - dim) * lit
            layer.fill(ray, with: .linearGradient(
                Gradient(colors: [color.opacity(strength), color.opacity(0)]),
                startPoint: CGPoint(x: 50 * side, y: 0),
                endPoint: CGPoint(x: reach * side, y: 0)
            ))
        }

        let strokes = stacked ? Self.stackedFlickers : Self.lineFlickers
        for (index, flicker) in strokes.enumerated() {
            var layer = context
            layer.opacity = index == 0 ? flash : 1 - flash
            layer.stroke(flicker, with: .color(Brand.cream), style: StrokeStyle(lineWidth: stacked ? 7 : 9, lineCap: .round))
        }
    }

    func drawBody(in context: GraphicsContext) {
        let stacked = style == .stacked
        let outline = StrokeStyle(lineWidth: stacked ? 7 : 8, lineJoin: .round)

        let cap = Path(roundedRect: CGRect(x: -18, y: -82, width: 36, height: 18), cornerRadius: 5)
        context.fill(cap, with: Self.steel(from: -82, to: -64))
        context.stroke(cap, with: .color(Brand.ink), lineWidth: stacked ? 6 : 7)

        context.fill(Self.domeLeft, with: .linearGradient(WordmarkStyle.thief.face, startPoint: CGPoint(x: 0, y: -68), endPoint: CGPoint(x: 0, y: 24)))
        context.stroke(Self.domeLeft, with: .color(Brand.ink), style: outline)
        context.fill(Self.domeRight, with: .linearGradient(WordmarkStyle.police.face, startPoint: CGPoint(x: 0, y: -68), endPoint: CGPoint(x: 0, y: 24)))
        context.stroke(Self.domeRight, with: .color(Brand.ink), style: outline)

        let glow = stacked ? 0.55 : 0.6
        var left = context
        left.opacity = glow * flash
        left.fill(Self.flashLeft, with: .color(Brand.cream))
        var right = context
        right.opacity = glow * (1 - flash)
        right.fill(Self.flashRight, with: .color(Brand.cream))

        if stacked {
            context.stroke(Self.highlight, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        }

        let base = Path(roundedRect: CGRect(x: -100, y: 20, width: 200, height: 36), cornerRadius: 9)
        context.fill(base, with: Self.steel(from: 20, to: 56))
        context.stroke(base, with: .color(Brand.ink), lineWidth: stacked ? 7 : 8)

        if stacked {
            for x in [CGFloat(-78), 78] {
                context.fill(Path(ellipseIn: CGRect(x: x - 5, y: 33, width: 10, height: 10)), with: .color(Color(hex: 0x5B6584)))
            }
        }
    }

    private static func steel(from top: CGFloat, to bottom: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(WordmarkStyle.steel, startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))
    }

    private static let domeLeft = Path(svg: "M-74 24 Q-74 -68 0 -68 L0 24 Z")
    private static let domeRight = Path(svg: "M0 -68 Q74 -68 74 24 L0 24 Z")
    private static let flashLeft = Path(svg: "M-70 22 Q-70 -64 -2 -64 L-2 22 Z")
    private static let flashRight = Path(svg: "M2 -64 Q70 -64 70 22 L2 22 Z")
    private static let highlight = Path(svg: "M-48 -4 Q-46 -42 -16 -50")
    private static let stackedFlickers = [
        Path(svg: "M-60 -60 L-120 -118 M-74 -28 L-150 -50"),
        Path(svg: "M60 -60 L120 -118 M74 -28 L150 -50"),
    ]
    private static let lineFlickers = [
        Path(svg: "M-64 -62 L-118 -112 M-80 -30 L-150 -50"),
        Path(svg: "M64 -62 L118 -112 M80 -30 L150 -50"),
    ]
}

/// A strip of yellow and black hazard tape, centred on the context origin.
enum HazardTape {
    static func draw(in context: GraphicsContext) {
        let strip = Path(CGRect(x: -620, y: -34, width: 1240, height: 68))
        var tape = context
        tape.clip(to: strip)
        tape.fill(strip, with: .color(Color(hex: 0xFFD23F)))
        tape.rotate(by: .degrees(35))
        for index in -16...16 {
            tape.fill(Path(CGRect(x: CGFloat(index) * 44, y: -700, width: 20, height: 1400)), with: .color(Color(hex: 0x17122B)))
        }
        context.stroke(strip, with: .color(Brand.ink), lineWidth: 7)
        context.fill(Path(CGRect(x: -620, y: -34, width: 1240, height: 10)), with: .color(.white.opacity(0.25)))
    }
}

/// A design-unit drawing area for a logo, with room around the logo box for parts that swing or
/// fly in from outside it. Canvases inside it draw in the logo's own design coordinates.
struct LogoSpace: Equatable {
    /// Screen points per design unit.
    let unit: CGFloat
    /// The drawing area in design units; the logo box starts at (0, 0) inside it.
    let bounds: CGRect

    var size: CGSize {
        CGSize(width: bounds.width * unit, height: bounds.height * unit)
    }

    /// Where the logo box's corner sits inside the drawing area, in points.
    var boxOffset: CGSize {
        CGSize(width: bounds.minX * unit, height: bounds.minY * unit)
    }

    func anchor(_ point: CGPoint) -> UnitPoint {
        UnitPoint(x: (point.x - bounds.minX) / bounds.width, y: (point.y - bounds.minY) / bounds.height)
    }

    func enter(_ context: inout GraphicsContext) {
        context.scaleBy(x: unit, y: unit)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
    }
}

/// One finished word drawn once and then only moved around, so animating it costs no redraws.
struct WordmarkLayer: View, Equatable {
    let word: Word
    let space: LogoSpace
    /// Baseline centre in design units.
    let center: CGPoint
    var scale: CGFloat = 1
    let shadowDepth: CGFloat
    let rimDepth: CGFloat

    enum Word { case heist, royale }

    var body: some View {
        Canvas { context, _ in
            space.enter(&context)
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: scale, y: scale)
            switch word {
            case .heist: WordmarkWord.heist.draw(in: context, style: .thief, shadowDepth: shadowDepth, rimDepth: rimDepth)
            case .royale: WordmarkWord.royale.draw(in: context, style: .police, shadowDepth: shadowDepth, rimDepth: rimDepth)
            }
        }
        .frame(width: space.size.width, height: space.size.height)
    }
}
