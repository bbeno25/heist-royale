import SwiftUI

/// The one-line HEIST 🚨 ROYALE logo for the top of the home screen. The words are drawn once;
/// only the siren between them keeps swinging and flashing.
struct LineLogo: View {
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Height for a given width, from the design's 196-unit-tall view box.
    static func height(forWidth width: CGFloat) -> CGFloat {
        width * 196 / Layout.shared.viewWidth
    }

    var body: some View {
        let layout = Layout.shared
        let unit = width / layout.viewWidth
        // The view box runs from y = 80 to 276; the extra room lets the rays swing past it.
        let space = LogoSpace(unit: unit, bounds: CGRect(x: -100, y: -20, width: layout.viewWidth + 200, height: 396))
        Color.clear
            .frame(width: width, height: 196 * unit)
            .overlay(alignment: .topLeading) {
                TimelineView(.animation(paused: reduceMotion)) { timeline in
                    let siren = Siren(style: .line, time: timeline.date.timeIntervalSinceReferenceDate, still: reduceMotion)
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            space.enter(&context)
                            context.translateBy(x: layout.sirenX, y: 190)
                            context.scaleBy(x: 0.8, y: 0.8)
                            siren.drawLights(in: context)
                        }
                        WordmarkLayer(word: .heist, space: space, center: CGPoint(x: layout.heistX, y: 232), scale: Layout.heistScale, shadowDepth: 16, rimDepth: 11)
                            .equatable()
                        Canvas { context, _ in
                            space.enter(&context)
                            context.translateBy(x: layout.sirenX, y: 190)
                            context.scaleBy(x: 0.8, y: 0.8)
                            siren.drawBody(in: context)
                        }
                        WordmarkLayer(word: .royale, space: space, center: CGPoint(x: layout.royaleX, y: 232), shadowDepth: 16, rimDepth: 11)
                            .equatable()
                    }
                    .frame(width: space.size.width, height: space.size.height)
                }
                .offset(x: space.boxOffset.width, y: space.boxOffset.height - 80 * unit)
            }
            .accessibilityElement()
            .accessibilityLabel("Heist Royale")
            .accessibilityAddTraits(.isImage)
    }

    /// Where the words and siren sit, worked out from the measured word widths as in the design:
    /// HEIST is scaled up to ROYALE's letter height, with a 160-unit siren slot and 40-unit gaps.
    struct Layout {
        static let heistScale: CGFloat = 146 / 136
        static let shared = Layout()

        let heistX: CGFloat
        let sirenX: CGFloat
        let royaleX: CGFloat
        let viewWidth: CGFloat

        private init() {
            let heistWidth = WordmarkWord.heist.width * Self.heistScale
            let royaleWidth = WordmarkWord.royale.width
            let gap: CGFloat = 40
            let sirenWidth: CGFloat = 160
            let padding: CGFloat = 30
            heistX = padding + heistWidth / 2
            sirenX = padding + heistWidth + gap + sirenWidth / 2
            royaleX = padding + heistWidth + gap + sirenWidth + gap + royaleWidth / 2
            viewWidth = padding * 2 + heistWidth + gap * 2 + sirenWidth + royaleWidth
        }
    }
}
