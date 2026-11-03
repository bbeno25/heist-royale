import SwiftUI

/// The stacked HEIST / ROYALE logo with its intro, as in the design's animated logo: the siren drops
/// in, HEIST falls and bounces, ROYALE pops up, and two strips of hazard tape slide across. After
/// that the siren keeps swinging and flashing and a sheen runs over the words.
/// Drawn in a 1000×620 design box scaled to `width`; the tape runs wider than the box.
struct StackedLogo: View {
    /// Seconds until every part has landed (the second tape strip arrives last).
    static let introDuration: Double = 2.05

    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now

    var body: some View {
        let space = LogoSpace(unit: width / 1000, bounds: CGRect(x: -500, y: -200, width: 2000, height: 1000))
        Color.clear
            .frame(width: width, height: width * 0.62)
            .overlay(alignment: .topLeading) {
                TimelineView(.animation(paused: reduceMotion)) { timeline in
                    // Reduce Motion shows the landed logo with a steady siren.
                    let time = reduceMotion ? Self.introDuration : timeline.date.timeIntervalSince(start)
                    stage(space: space, time: time)
                }
                .offset(space.boxOffset)
            }
            .accessibilityElement()
            .accessibilityLabel("Heist Royale")
            .accessibilityAddTraits(.isImage)
    }

    private func stage(space: LogoSpace, time: Double) -> some View {
        let unit = space.unit
        return ZStack(alignment: .topLeading) {
            TapeLayer(space: space, center: CGPoint(x: 500, y: 412), angle: .degrees(-7), opacity: 1)
                .equatable()
                .offset(x: Self.frontTape.value(at: time) * unit)
            TapeLayer(space: space, center: CGPoint(x: 500, y: 470), angle: .degrees(5), opacity: 0.55)
                .equatable()
                .offset(x: Self.backTape.value(at: time) * unit)

            Canvas { context, _ in
                space.enter(&context)
                context.translateBy(x: 500, y: Self.sirenDrop.value(at: time))
                let siren = Siren(style: .stacked, time: time, still: reduceMotion)
                siren.drawLights(in: context)
                siren.drawBody(in: context)
            }

            WordmarkLayer(word: .heist, space: space, center: CGPoint(x: 500, y: 318), shadowDepth: 18, rimDepth: 12)
                .equatable()
                .offset(y: (Self.heistDrop.value(at: time) - 318) * unit)
            WordmarkLayer(word: .royale, space: space, center: CGPoint(x: 500, y: 492), shadowDepth: 18, rimDepth: 12)
                .equatable()
                .scaleEffect(Self.royalePop.value(at: time), anchor: space.anchor(CGPoint(x: 500, y: 492)))

            if !reduceMotion {
                Canvas { context, _ in
                    space.enter(&context)
                    var heist = context
                    heist.translateBy(x: 500, y: 318)
                    WordmarkWord.heist.drawShine(in: heist, time: time, begin: 2.2, travel: 900, band: CGRect(x: -35, y: -160, width: 70, height: 240))
                    var royale = context
                    royale.translateBy(x: 500, y: 492)
                    WordmarkWord.royale.drawShine(in: royale, time: time, begin: 2.9, travel: 1100, band: CGRect(x: -40, y: -170, width: 80, height: 250))
                }
            }
        }
        .frame(width: space.size.width, height: space.size.height)
        .compositingGroup()
        .shadow(color: .black.opacity(0.55), radius: 12 * unit, y: 16 * unit)
    }

    // The design's keyframes, with easing so falls accelerate and landings settle.
    private static let sirenDrop = Keyframes(begin: 0.15, duration: 0.7, values: [-260, 142, 122, 130], times: [0, 0.6, 0.82, 1], curves: [.easeIn, .easeOut, .easeInOut])
    private static let heistDrop = Keyframes(begin: 0.55, duration: 0.65, values: [-320, 334, 308, 318], times: [0, 0.6, 0.82, 1], curves: [.easeIn, .easeOut, .easeInOut])
    private static let royalePop = Keyframes(begin: 0.95, duration: 0.55, values: [0, 1.16, 0.95, 1], times: [0, 0.55, 0.8, 1], curves: [.easeOut, .easeInOut, .easeInOut])
    private static let frontTape = Keyframes(begin: 1.35, duration: 0.55, values: [-1400, 40, 0], times: [0, 0.75, 1], curves: [.easeOut, .easeInOut])
    private static let backTape = Keyframes(begin: 1.5, duration: 0.55, values: [1400, -40, 0], times: [0, 0.75, 1], curves: [.easeOut, .easeInOut])
}

/// One strip of hazard tape, drawn once and slid into place.
private struct TapeLayer: View, Equatable {
    let space: LogoSpace
    let center: CGPoint
    let angle: Angle
    let opacity: Double

    var body: some View {
        Canvas { context, _ in
            space.enter(&context)
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: angle)
            context.opacity = opacity
            HazardTape.draw(in: context)
        }
        .frame(width: space.size.width, height: space.size.height)
    }
}

/// A value moving through keyframes over time, like an SVG `values`/`keyTimes` animation,
/// with an easing curve for each segment. Holds the first value before `begin` and the last after.
struct Keyframes: Sendable {
    let begin: Double
    let duration: Double
    let values: [CGFloat]
    /// Fractions of `duration`, starting at 0 and ending at 1, one per value.
    let times: [Double]
    let curves: [UnitCurve]

    func value(at time: Double) -> CGFloat {
        let progress = (time - begin) / duration
        guard progress > 0 else { return values[0] }
        guard progress < 1 else { return values[values.count - 1] }
        for index in 1..<times.count where progress <= times[index] {
            let local = (progress - times[index - 1]) / (times[index] - times[index - 1])
            let eased = curves[index - 1].value(at: local)
            return values[index - 1] + (values[index] - values[index - 1]) * eased
        }
        return values[values.count - 1]
    }
}
