import SwiftUI

/// The launch screen: the animated stacked logo over a night-time fairground, with a loading bar,
/// a tip and the app version.
struct SplashView: View {
    let launch: LaunchModel

    private static let design = CGSize(width: 390, height: 844)

    var body: some View {
        GeometryReader { geometry in
            let stage = Stage(designSize: Self.design, screen: geometry.size)
            let scale = stage.scale
            ZStack(alignment: .topLeading) {
                SplashBackdrop(placement: stage.backdrop(screen: geometry.size, anchorY: 700))

                ZStack(alignment: .top) {
                    StackedLogo(width: 340 * scale)
                        .padding(.top, 200 * scale)
                    VStack(spacing: 12 * scale) {
                        Spacer()
                        Text("Cracking the vault…")
                            .font(BrandFont.fredoka(16 * scale, 600))
                            .foregroundStyle(Brand.cream)
                        LoadingBar(progress: launch.progress, scale: scale)
                        Text("Tip: the police never find out which areas you scanned during prep.")
                            .font(BrandFont.fredoka(13 * scale, 500))
                            .foregroundStyle(Color(hex: 0xC9C1EA))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3 * scale)
                            .frame(maxWidth: 300 * scale)
                        Text("Version \(Self.version)")
                            .font(.system(size: 11 * scale, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x8E86B8))
                            .padding(.top, 6 * scale)
                    }
                    .padding(.bottom, 58 * scale)
                }
                .frame(width: stage.size.width, height: stage.size.height)
                .offset(x: stage.origin.x, y: stage.origin.y)
            }
        }
        .ignoresSafeArea()
        .background(Color(hex: 0x120D2B))
    }

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
}

/// The orange loading bar under the logo.
private struct LoadingBar: View {
    let progress: Double
    let scale: CGFloat

    var body: some View {
        let width = 280 * scale
        let inset = 3 * scale
        Capsule()
            .fill(Brand.ink)
            .strokeBorder(Color(hex: 0x3A3170), lineWidth: 2 * scale)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Brand.thief)
                    .frame(width: max(0, (width - inset * 2) * progress), height: 10 * scale)
                    .padding(.leading, inset)
            }
            .frame(width: width, height: 16 * scale)
            .animation(.linear(duration: 0.1), value: progress)
            .accessibilityElement()
            .accessibilityLabel("Loading")
            .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// The fairground at night behind the splash logo: twinkling stars, two sweeping searchlights,
/// a turning Ferris wheel, a roller-coaster track and rooftops with the thief and police flags.
private struct SplashBackdrop: View {
    let placement: Stage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x120D2B)))
                placement.apply(to: &context)
                draw(in: context, time: time)
            }
        }
    }

    private func draw(in context: GraphicsContext, time: Double) {
        // Sky, running up past the top of the design for taller screens.
        context.fill(Path(CGRect(x: 0, y: -600, width: 390, height: 1444)), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(hex: 0x100B26), location: 0),
                .init(color: Color(hex: 0x140E31), location: 0.4),
                .init(color: Color(hex: 0x1C1544), location: 0.72),
                .init(color: Color(hex: 0x1E1648), location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: 844)
        ))

        for star in Self.stars {
            var layer = context
            layer.opacity = star.opacity(at: time)
            layer.fill(Path(ellipseIn: CGRect(x: star.x - star.r, y: star.y - star.r, width: star.r * 2, height: star.r * 2)), with: .color(Brand.cream))
        }

        searchlight(in: context, at: CGPoint(x: 70, y: 700), angle: -4 - 18 * cos(2 * .pi * time / 6))
        searchlight(in: context, at: CGPoint(x: 320, y: 700), angle: 2 + 18 * cos(2 * .pi * time / 7))

        // Ferris wheel: the wheel turns once every 40 s on fixed legs.
        let structure = Color(hex: 0x2C2266)
        var wheel = context
        wheel.translateBy(x: 286, y: 600)
        wheel.stroke(Path(svg: "M-10 0 L-36 104 M10 0 L36 104"), with: .color(structure), lineWidth: 6)
        wheel.rotate(by: .degrees(time / 40 * 360))
        wheel.stroke(Path(ellipseIn: CGRect(x: -78, y: -78, width: 156, height: 156)), with: .color(structure), lineWidth: 5)
        wheel.stroke(Self.spokes, with: .color(structure), lineWidth: 3)
        for car in Self.cars {
            wheel.fill(Path(ellipseIn: CGRect(x: car.x - car.r, y: car.y - car.r, width: car.r * 2, height: car.r * 2)), with: .color(car.color))
        }

        context.stroke(Self.coaster, with: .color(structure), lineWidth: 5)
        context.fill(Self.rooftops, with: .color(Color(hex: 0x221A4E)))
        context.fill(Path(CGRect(x: 0, y: 844, width: 390, height: 600)), with: .color(Color(hex: 0x221A4E)))
        context.fill(Path(svg: "M44 600 L44 584 L60 590 L44 596"), with: .color(Brand.thief))
        context.fill(Path(svg: "M120 616 L120 598 L136 604 L120 610"), with: .color(Brand.police))
        for window in Self.windows {
            context.fill(Path(CGRect(x: window.x, y: window.y, width: 6, height: 8)), with: .color(Brand.gold.opacity(window.opacity)))
        }
        context.fill(Path(CGRect(x: 0, y: 700, width: 390, height: 144)), with: .linearGradient(
            Gradient(colors: [Color(hex: 0x120D2B, opacity: 0), Color(hex: 0x120D2B)]),
            startPoint: CGPoint(x: 0, y: 700), endPoint: CGPoint(x: 0, y: 844)
        ))
    }

    private func searchlight(in context: GraphicsContext, at base: CGPoint, angle: Double) {
        var beam = context
        beam.translateBy(x: base.x, y: base.y)
        beam.rotate(by: .degrees(angle))
        beam.fill(Path(svg: "M-26 0 L26 0 L0 -520 Z"), with: .linearGradient(
            Gradient(colors: [Brand.cream.opacity(0.22), Brand.cream.opacity(0)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: -520)
        ))
    }

    private struct Star {
        let x: CGFloat, y: CGFloat, r: CGFloat
        /// Opacity swing (from, to) and its period in seconds, or nil for a steady star.
        var twinkle: (from: Double, to: Double, period: Double)?

        func opacity(at time: Double) -> Double {
            guard let twinkle else { return 1 }
            let wave = 0.5 - 0.5 * cos(2 * .pi * time / twinkle.period)
            return twinkle.from + (twinkle.to - twinkle.from) * wave
        }
    }

    private static let stars = [
        Star(x: 40, y: 80, r: 1.6, twinkle: (1, 0.2, 2.6)),
        Star(x: 110, y: 140, r: 1.2),
        Star(x: 300, y: 70, r: 1.8, twinkle: (0.3, 1, 3.1)),
        Star(x: 350, y: 160, r: 1.2),
        Star(x: 200, y: 40, r: 1.4, twinkle: (1, 0.3, 2.2)),
        Star(x: 70, y: 420, r: 1.2),
        Star(x: 330, y: 430, r: 1.6, twinkle: (0.4, 1, 2.8)),
        Star(x: 250, y: 470, r: 1.1),
        Star(x: 20, y: 250, r: 1.3),
        Star(x: 372, y: 300, r: 1.3),
    ]

    private static let cars: [(x: CGFloat, y: CGFloat, r: CGFloat, color: Color)] = [
        (0, -78, 7, Brand.gold), (78, 0, 7, Brand.police), (0, 78, 7, Brand.thief), (-78, 0, 7, Brand.gold),
        (55, -55, 6, Brand.thief), (-55, 55, 6, Brand.police), (55, 55, 6, Brand.gold), (-55, -55, 6, Brand.thief),
    ]

    private static let windows: [(x: CGFloat, y: CGFloat, opacity: Double)] = [
        (36, 630, 0.8), (48, 630, 0.5), (186, 640, 0.7), (198, 640, 0.4),
    ]

    private static let spokes = Path(svg: "M-78 0 L78 0 M0 -78 L0 78 M-55 -55 L55 55 M-55 55 L55 -55")
    private static let coaster = Path(svg: "M0 640 Q60 560 110 610 Q150 650 190 590 Q220 548 250 600 L250 700 L0 700 Z")
    private static let rooftops = Path(svg: "M0 704 L0 650 L30 650 L30 620 L44 600 L58 620 L58 650 L96 650 L120 616 L144 650 L176 650 L176 630 L210 630 L210 662 L262 662 L262 690 L390 690 L390 844 L0 844 Z")
}
