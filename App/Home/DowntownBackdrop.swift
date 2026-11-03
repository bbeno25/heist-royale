import SwiftUI

/// The downtown scenery behind the home screen, drawn in code from the design's Downtown Sunset
/// skyline and lit for the time of day: a bright morning with drifting clouds, the sunset, or night
/// with stars, searchlights and neon. A train runs along the elevated track in every version.
/// Still layers are drawn once; only the small moving parts redraw each frame.
struct DowntownBackdrop: View {
    let time: TimeOfDay
    /// Full-bleed placement of the 393×852 design space.
    let placement: Stage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let scene = DowntownScene(time: time)
        ZStack {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(scene.palette.floorBottom))
                placement.apply(to: &context)
                scene.drawSky(in: context)
            }
            animated { context, clock in scene.drawSkyLife(in: context, time: clock) }
            Canvas { context, _ in
                placement.apply(to: &context)
                scene.drawCity(in: context)
            }
            animated { context, clock in scene.drawStreetLife(in: context, time: clock) }
            Canvas { context, _ in
                placement.apply(to: &context)
                scene.drawGround(in: context)
            }
        }
        .accessibilityHidden(true)
    }

    /// A canvas redrawn every frame (or held still under Reduce Motion), in design coordinates.
    private func animated(_ draw: @escaping (GraphicsContext, Double) -> Void) -> some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let clock = reduceMotion ? 6 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, _ in
                placement.apply(to: &context)
                draw(context, clock)
            }
        }
    }
}

/// Drawing for one version of downtown, in the design's 393×852 coordinates (horizon at y = 556).
private struct DowntownScene {
    let time: TimeOfDay
    let palette: DowntownPalette

    init(time: TimeOfDay) {
        self.time = time
        palette = DowntownPalette(time)
    }

    // MARK: Sky

    func drawSky(in context: GraphicsContext) {
        // The sky runs up past the top of the design for taller screens.
        context.fill(Path(CGRect(x: 0, y: -800, width: 393, height: 1360)), with: .linearGradient(
            Gradient(stops: [
                .init(color: palette.skyTop, location: 0),
                .init(color: palette.skyMid, location: 0.55),
                .init(color: palette.skyHorizon, location: 1),
            ]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: 560)
        ))

        switch time {
        case .morning:
            glow(in: context, center: CGPoint(x: 292, y: 262), radius: 130, color: Color(hex: 0xFFF6D8), stops: [(0, 0.95), (1, 0)])
            context.fill(circle(CGPoint(x: 292, y: 262), 24), with: .color(Color(hex: 0xFFFBEA)))
        case .evening:
            glow(in: context, center: CGPoint(x: 196, y: 470), radius: 190, color: Color(hex: 0xFFE2A6), stops: [(0, 1), (0.35, 0.6), (1, 0)])
        case .night:
            context.fill(circle(CGPoint(x: 286, y: 262), 40), with: .color(Color(hex: 0xEAF2FF, opacity: 0.08)))
            context.fill(circle(CGPoint(x: 286, y: 262), 22), with: .color(Color(hex: 0xEAF2FF, opacity: 0.92)))
            context.fill(circle(CGPoint(x: 278, y: 256), 5), with: .color(Color(hex: 0xC9D6EE, opacity: 0.6)))
            context.fill(circle(CGPoint(x: 293, y: 270), 3.5), with: .color(Color(hex: 0xC9D6EE, opacity: 0.5)))
        }
    }

    func drawSkyLife(in context: GraphicsContext, time clock: Double) {
        switch time {
        case .morning:
            for cloud in Self.clouds {
                let span: CGFloat = 393 + 220
                let x = (cloud.x + CGFloat(clock) * cloud.speed).truncatingRemainder(dividingBy: span) - 110
                var puff = context
                puff.translateBy(x: x, y: cloud.y)
                puff.opacity = 0.85
                for part in cloud.parts {
                    puff.fill(Path(ellipseIn: CGRect(x: part.x - part.width, y: part.y - part.height, width: part.width * 2, height: part.height * 2)), with: .color(.white))
                }
            }
            for (index, bird) in Self.birds.enumerated() {
                let flap = 2 + 2 * sin(clock * 6 + Double(index) * 1.7)
                let x = bird.x + CGFloat(sin(clock / 9 + Double(index))) * 14
                let y = bird.y + CGFloat(cos(clock / 7 + Double(index))) * 4
                var wings = Path()
                wings.move(to: CGPoint(x: x, y: y))
                wings.addLine(to: CGPoint(x: x + bird.size, y: y + flap * bird.size / 6))
                wings.addLine(to: CGPoint(x: x + bird.size * 2, y: y))
                context.stroke(wings, with: .color(Color(hex: 0x1B2B4A, opacity: 0.7)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        case .evening:
            // Sun rays slowly turning about the sun.
            var rays = context
            rays.translateBy(x: 196, y: 470)
            rays.rotate(by: .degrees(3 * sin(clock / 5)))
            rays.translateBy(x: -196, y: -470)
            for ray in Self.sunRays {
                rays.fill(ray, with: .color(.white.opacity(0.07)))
            }
        case .night:
            for (index, star) in Self.stars.enumerated() {
                let twinkle = 0.65 + 0.35 * sin(clock * (1.1 + Double(index % 4) * 0.37) + Double(index) * 2.3)
                var layer = context
                layer.opacity = star.opacity * twinkle
                layer.fill(circle(CGPoint(x: star.x, y: star.y), star.r), with: .color(.white))
            }
            searchlight(in: context, base: CGPoint(x: 30, y: 560), shape: Self.leftBeam, angle: 7 * sin(clock / 1.5))
            searchlight(in: context, base: CGPoint(x: 363, y: 560), shape: Self.rightBeam, angle: -7 * sin(clock / 1.8 + 1))
        }
    }

    private func searchlight(in context: GraphicsContext, base: CGPoint, shape: Path, angle: Double) {
        var beam = context
        beam.translateBy(x: base.x, y: base.y)
        beam.rotate(by: .degrees(angle))
        beam.translateBy(x: -base.x, y: -base.y)
        beam.fill(shape, with: .linearGradient(
            Gradient(colors: [Color(hex: 0x9FE8FF, opacity: 0.22), Color(hex: 0x9FE8FF, opacity: 0)]),
            startPoint: CGPoint(x: 0, y: 560), endPoint: .zero
        ))
    }

    // MARK: City

    func drawCity(in context: GraphicsContext) {
        context.fill(Self.farSkyline, with: .color(palette.far))
        var farLights = context
        farLights.opacity = palette.farWindows
        for (index, window) in Self.farWindows.enumerated() {
            farLights.fill(Path(CGRect(x: window.x, y: window.y, width: 4, height: 6)), with: .color(index % 3 == 1 ? palette.windowAlt : palette.window))
        }

        // The tree on the left, with string lights after dark.
        context.fill(Self.trunk, with: .color(palette.trunk))
        for leaf in [(42.0, 360.0, 34.0), (16, 384, 20), (70, 386, 22)] {
            context.fill(circle(CGPoint(x: leaf.0, y: leaf.1), leaf.2), with: .color(palette.canopy))
        }
        if time != .morning {
            for bulb in [(30.0, 356.0), (50, 346), (58, 372), (22, 384), (42, 420), (42, 440)] {
                context.fill(circle(CGPoint(x: bulb.0, y: bulb.1), 2.5), with: .color(palette.window))
            }
        }

        // Nearer buildings: one silhouette in the evening and at night; painted fronts in daylight.
        context.fill(Self.midSkyline, with: .color(palette.mid))
        if time == .morning {
            for (index, block) in Self.blocks.enumerated() {
                let face = Self.facades[index % Self.facades.count]
                context.fill(Path(CGRect(x: block.left, y: block.top, width: block.right - block.left, height: 560 - block.top)), with: .color(face))
                context.fill(Path(CGRect(x: block.left - 1, y: block.top - 4, width: block.right - block.left + 2, height: 5)), with: .color(Color(hex: 0xB5533C)))
            }
            for window in Self.midWindows {
                context.fill(Path(roundedRect: CGRect(x: window.x, y: window.y, width: 6, height: 8), cornerRadius: 1), with: .color(palette.window.opacity(0.9)))
                context.fill(Path(CGRect(x: window.x, y: window.y, width: 6, height: 3)), with: .color(Color(hex: 0x9AD6F6, opacity: 0.6)))
            }
        } else {
            for (index, window) in Self.midWindows.enumerated() {
                context.fill(Path(roundedRect: CGRect(x: window.x, y: window.y, width: 6, height: 8), cornerRadius: 1), with: .color(index % 4 == 2 ? palette.windowAlt : palette.window))
            }
        }

        // Elevated rail line.
        context.fill(Path(CGRect(x: 0, y: 494, width: 393, height: 6)), with: .color(palette.track))
        context.fill(Path(CGRect(x: 60, y: 500, width: 6, height: 60)), with: .color(palette.track))
        context.fill(Path(CGRect(x: 320, y: 500, width: 6, height: 60)), with: .color(palette.track))
    }

    func drawStreetLife(in context: GraphicsContext, time clock: Double) {
        if time == .night {
            neonSign(in: context, text: "DINER", frame: CGRect(x: 116, y: 312, width: 40, height: 18), color: Color(hex: 0xFF5FA2), lit: Self.flicker(clock, offset: 0))
            neonSign(in: context, text: "24/7", frame: CGRect(x: 232, y: 316, width: 36, height: 18), color: Color(hex: 0x6EE7FF), lit: Self.flicker(clock, offset: 3.7))
        }

        // The train crosses every 18 s, gliding left to right at 50 pt/s, then the track stays empty.
        let cycle = clock.truncatingRemainder(dividingBy: 18)
        if cycle < 11 {
            let x = -140 + CGFloat(cycle) * 50
            context.fill(Path(roundedRect: CGRect(x: x, y: 472, width: 130, height: 22), cornerRadius: 11), with: .color(palette.train))
            context.fill(Path(roundedRect: CGRect(x: x + 10, y: 477, width: 104, height: 7), cornerRadius: 3.5), with: .color(palette.trainWindows))
            context.fill(Path(CGRect(x: x, y: 488, width: 130, height: 3)), with: .color(palette.trainStripe))
        }

        if time == .evening {
            // Soft bokeh drifting in the warm air.
            for (index, dot) in Self.bokeh.enumerated() {
                let y = dot.y + CGFloat(sin(clock / 3 + Double(index) * 1.9)) * 6
                context.fill(circle(CGPoint(x: dot.x, y: y), dot.r), with: .color(.white.opacity(0.14)))
            }
        }
    }

    private func neonSign(in context: GraphicsContext, text: String, frame: CGRect, color: Color, lit: Double) {
        let outline = Path(roundedRect: frame, cornerRadius: 4)
        var sign = context
        sign.opacity = lit
        sign.drawLayer { glow in
            glow.addFilter(.blur(radius: 3))
            glow.stroke(outline, with: .color(color), lineWidth: 3)
        }
        sign.fill(outline, with: .color(Color(hex: 0x05071A, opacity: 0.6)))
        sign.stroke(outline, with: .color(color), lineWidth: 1.5)
        sign.draw(Text(text).font(BrandFont.baloo(11, 800)).foregroundStyle(color), at: CGPoint(x: frame.midX, y: frame.midY + 1))
        // Posts holding the sign up on the rooftops.
        sign.fill(Path(CGRect(x: frame.minX + 8, y: frame.maxY, width: 2, height: 6)), with: .color(Color(hex: 0x0B1030)))
        sign.fill(Path(CGRect(x: frame.maxX - 10, y: frame.maxY, width: 2, height: 6)), with: .color(Color(hex: 0x0B1030)))
    }

    /// Neon that mostly holds steady but stutters briefly every few seconds.
    private static func flicker(_ clock: Double, offset: Double) -> Double {
        let phase = (clock + offset).truncatingRemainder(dividingBy: 7.3)
        return (2.0..<2.07).contains(phase) || (2.14..<2.2).contains(phase) ? 0.35 : 1
    }

    // MARK: Ground

    func drawGround(in context: GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 556, width: 393, height: 296)), with: .linearGradient(
            Gradient(colors: [palette.floorTop, palette.floorBottom]),
            startPoint: CGPoint(x: 0, y: 556), endPoint: CGPoint(x: 0, y: 852)
        ))
        context.stroke(Self.floorLines, with: .color(palette.floorLine), lineWidth: 1.5)

        if time == .night {
            // Streaks of light on the wet pavement.
            context.stroke(Path(svg: "M20 640 L120 640 M270 720 L380 720 M40 800 L130 800"), with: .color(.white.opacity(0.08)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }

        context.fill(Path(CGRect(x: 0, y: -800, width: 393, height: 1000)), with: .linearGradient(
            Gradient(colors: [palette.topShade, palette.topShade.opacity(0)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: 200)
        ))
    }

    // MARK: Helpers

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func glow(in context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color, stops: [(location: CGFloat, opacity: Double)]) {
        context.fill(circle(center, radius), with: .radialGradient(
            Gradient(stops: stops.map { .init(color: color.opacity($0.opacity), location: $0.location) }),
            center: center, startRadius: 0, endRadius: radius
        ))
    }

    // MARK: Artwork (from the Downtown Sunset and Night Patrol designs)

    private static let farSkyline = Path(svg: "M0 540 L0 400 L22 400 L22 360 L40 360 L40 330 L58 330 L58 380 L80 380 L80 300 L86 288 L92 300 L92 380 L120 380 L120 350 Q136 318 152 350 L152 400 L172 400 L172 262 L184 246 L196 232 L208 246 L220 262 L220 400 L236 400 L236 340 L262 340 L262 296 L274 296 L274 380 L300 380 L300 322 Q318 294 336 322 L336 390 L360 390 L360 348 L393 348 L393 540 Z")
    private static let midSkyline = Path(svg: "M0 560 L0 470 L64 470 L64 420 L104 420 L104 456 L132 456 L132 430 L160 430 L160 476 L240 476 L240 436 L270 436 L270 410 L310 410 L310 452 L340 452 L340 430 L393 430 L393 560 Z")
    private static let trunk = Path(svg: "M30 480 L36 380 L48 380 L54 480 Z")
    private static let floorLines = Path(svg: "M196 556 L-80 852 M196 556 L60 852 M196 556 L196 852 M196 556 L332 852 M196 556 L472 852 M0 610 L393 610 M0 680 L393 680 M0 770 L393 770")
    private static let sunRays = [
        Path(svg: "M196 470 L40 0 L110 0 Z"),
        Path(svg: "M196 470 L250 0 L320 0 Z"),
        Path(svg: "M196 470 L393 80 L393 170 Z"),
    ]
    private static let leftBeam = Path(svg: "M30 560 L120 0 L190 0 Z")
    private static let rightBeam = Path(svg: "M363 560 L250 0 L310 0 Z")

    private static let farWindows: [CGPoint] = [
        (182, 270), (192, 270), (202, 270), (182, 290), (202, 290), (192, 310), (182, 330), (202, 330),
        (84, 310), (84, 330), (266, 306), (266, 326), (44, 340), (306, 336), (322, 336), (364, 360),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    private static let midWindows: [CGPoint] = [
        (72, 430), (86, 430), (72, 446), (140, 440), (246, 446), (278, 420), (292, 420),
        (278, 436), (350, 440), (366, 440), (366, 456), (86, 446), (292, 436), (350, 456),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    /// The nearer buildings' outlines, for painting their fronts in daylight.
    private static let blocks: [(left: CGFloat, right: CGFloat, top: CGFloat)] = [
        (0, 64, 470), (64, 104, 420), (104, 132, 456), (132, 160, 430), (160, 240, 476),
        (240, 270, 436), (270, 310, 410), (310, 340, 452), (340, 393, 430),
    ]
    private static let facades = [
        Color(hex: 0xF4E6CF), Color(hex: 0xE8735A), Color(hex: 0xE8B04B), Color(hex: 0x3FA7A0),
    ]

    private static let clouds: [(x: CGFloat, y: CGFloat, speed: CGFloat, parts: [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)])] = [
        (190, 250, 5, [(0, 0, 46, 12), (24, -8, 24, 12)]),
        (360, 300, 3, [(0, 0, 38, 9), (18, -6, 18, 9)]),
        (520, 132, 4, [(0, 0, 40, 10), (-20, -6, 22, 11)]),
    ]
    private static let birds: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [(150, 262, 6), (176, 278, 5), (232, 240, 5)]
    private static let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, opacity: Double)] = [
        (30, 80, 1.2, 0.6), (110, 130, 1, 0.5), (200, 96, 1.4, 0.7), (260, 140, 1, 0.5), (370, 96, 1.3, 0.6),
        (60, 220, 1.2, 0.6), (250, 210, 1, 0.5), (150, 60, 1.1, 0.6), (340, 250, 1, 0.5), (14, 160, 1.1, 0.5),
    ]
    private static let bokeh: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [(30, 250, 10), (360, 230, 14), (330, 520, 8), (62, 530, 6)]
}
