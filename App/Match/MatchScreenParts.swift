import SwiftUI

// Pieces shared by the full-screen match screens (coin flip, role reveal, round result, series, match end),
// sized in design points times the stage scale.

/// A full-screen match screen: its background fills the display, its content sits on the 393×852 stage.
struct StageScreen<Background: View, Content: View>: View {
    let stage: Stage
    @ViewBuilder let background: Background
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            content
                .environment(\.stageScale, stage.scale)
                .frame(width: stage.size.width, height: stage.size.height, alignment: .topLeading)
                .offset(x: stage.origin.x, y: stage.origin.y)
        }
    }
}

/// The small rounded label at the top of a screen, such as "CLASSIC · BEST OF 8 · RANKED".
struct ScreenPill: View {
    let text: String

    @Environment(\.stageScale) private var s

    var body: some View {
        Text(text)
            .font(BrandFont.nunito(12 * s, 900))
            .tracking(1.4 * s)
            .foregroundStyle(.white)
            .padding(.horizontal, 12 * s)
            .padding(.vertical, 4 * s)
            .background(.black.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

/// THIEF or POLICE with its emblem, in the role's colours.
struct RoleChip: View {
    let role: Role
    var height: CGFloat = 26

    @Environment(\.stageScale) private var s

    var body: some View {
        let k = height / 26
        HStack(spacing: 5 * k * s) {
            SVGShape(role.emblem).fill(role.color).frame(width: 16 * k * s, height: 16 * k * s)
            Text(role.title.uppercased())
                .font(BrandFont.nunito(11 * k * s, 900))
                .tracking(1.1 * k * s)
                .foregroundStyle(role == .thief ? Color(hex: 0xFFD592) : Color(hex: 0xBFE0FF))
        }
        .padding(.leading, 5 * k * s)
        .padding(.trailing, 9 * k * s)
        .frame(height: height * s)
        .background(role.color.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(role.color, lineWidth: 1.5 * s))
        .accessibilityElement()
        .accessibilityLabel(role.title)
    }
}

/// A round portrait: the raccoon or the hound face on its role colour.
struct FaceAvatar: View {
    let role: Role
    let size: CGFloat
    var ring: Color = .white
    var ringWidth: CGFloat = 2

    @Environment(\.stageScale) private var s

    var body: some View {
        Image(role == .thief ? "art-faceThief" : "art-facePolice")
            .resizable()
            .frame(width: size * 0.86 * s, height: size * 0.86 * s)
            .frame(width: size * s, height: size * s)
            .background(RadialGradient(
                colors: role == .thief ? [Color(hex: 0x8A64D6), Color(hex: 0x3A2178)] : [Color(hex: 0x4C7FD6), Color(hex: 0x142E66)],
                center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: size * 0.6 * s
            ))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(ring, lineWidth: ringWidth * s))
            .accessibilityHidden(true)
    }
}

/// "BOT", next to the sample opponent's name.
struct BotTag: View {
    @Environment(\.stageScale) private var s

    var body: some View {
        Text("BOT")
            .font(BrandFont.nunito(9 * s, 900))
            .tracking(0.8 * s)
            .foregroundStyle(Color(hex: 0x17123A))
            .padding(.horizontal, 5 * s)
            .padding(.vertical, 1 * s)
            .background(Color(hex: 0xC8BDE6), in: RoundedRectangle(cornerRadius: 4 * s))
            .accessibilityLabel("bot")
    }
}

/// The rank badge: a gold diamond with the thief's mask, or a blue shield with a star, and the division numeral.
struct RankBadge: View {
    let role: Role
    let division: String
    let size: CGFloat

    var body: some View {
        let k = size / 38
        let dark = role == .thief ? Color(hex: 0x2A1A06) : Color(hex: 0x0E1E44)
        ZStack(alignment: .bottom) {
            ZStack {
                switch role {
                case .thief:
                    SVGShape("M19 1.5L36.5 19 19 36.5 1.5 19z", viewBox: Self.box).fill(Color(hex: 0x8A5A12))
                    SVGShape("M19 3.5L34.5 19 19 34.5 3.5 19z", viewBox: Self.box).fill(Color(hex: 0xFFB547))
                    SVGShape("M19 3.5L34.5 19 19 19 3.5 19z", viewBox: Self.box).fill(.white.opacity(0.22))
                    SVGShape("M10.5 16.8Q14.5 13.8 19 16.8Q23.5 13.8 27.5 16.8Q27.5 20.6 23.8 20.9Q21 20.6 19 19Q17 20.6 14.2 20.9Q10.5 20.6 10.5 16.8Z", viewBox: Self.box).fill(dark)
                case .police:
                    SVGShape("M19 1L34 7v11c0 9-6.5 15-15 18.5C10.5 33 4 27 4 18V7z", viewBox: Self.box).fill(Color(hex: 0x1F4FA0))
                    SVGShape("M19 3.2L32 8.4v9.6c0 7.9-5.7 13.2-13 16.3C11.7 31.2 6 25.9 6 18V8.4z", viewBox: Self.box).fill(Color(hex: 0x5AA2FF))
                    SVGShape("M19 3.2L32 8.4v9.6H6V8.4z", viewBox: Self.box).fill(.white.opacity(0.2))
                    SVGShape("M19 10l2.2 4.6 5 .6-3.7 3.4 1 5-4.5-2.5-4.5 2.5 1-5-3.7-3.4 5-.6z", viewBox: Self.box).fill(dark)
                }
            }
            .frame(width: size, height: size)
            Text(division)
                .font(BrandFont.nunito(9 * k, 900))
                .foregroundStyle(role == .thief ? Color(hex: 0xFFC977) : Color(hex: 0x9CC6FF))
                .padding(.horizontal, 4 * k)
                .background(dark, in: RoundedRectangle(cornerRadius: 5 * k))
                .offset(y: 3 * k)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let box = CGRect(x: 0, y: 0, width: 38, height: 38)
}

/// A rating change chip: green for a gain, red for a loss.
struct DeltaChip: View {
    let delta: Int

    @Environment(\.stageScale) private var s

    var body: some View {
        Text(delta >= 0 ? "+\(delta)" : "−\(-delta)")
            .font(BrandFont.nunito(14 * s, 900))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 8 * s)
            .padding(.vertical, 3 * s)
            .background(delta >= 0 ? Color(hex: 0x1E9A4A) : Color(hex: 0xC43A4A), in: RoundedRectangle(cornerRadius: 9 * s))
    }
}

/// "Briefing in 2 s" with a bar running down to the next screen.
struct CountdownBar: View {
    let label: String
    let fraction: Double
    var trailing: String?

    @Environment(\.stageScale) private var s

    var body: some View {
        VStack(spacing: 6 * s) {
            HStack {
                Text(label)
                if let trailing {
                    Spacer()
                    Text(trailing).foregroundStyle(Color(hex: 0xDCD3F2))
                }
            }
            .font(BrandFont.nunito(13 * s, 800))
            .foregroundStyle(trailing == nil ? Color(hex: 0xDCD3F2) : .white)
            .frame(maxWidth: .infinity, alignment: trailing == nil ? .center : .leading)
            Capsule()
                .fill(.white.opacity(0.14))
                .frame(height: 6 * s)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color(hex: 0xFFE15C))
                            .frame(width: geometry.size.width * max(0, min(1, fraction)))
                            .animation(.linear(duration: 1), value: fraction)
                    }
                }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Light rays fanning out from a point, slowly turning (still under Reduce Motion).
struct Sunburst: View {
    let center: UnitPoint
    let color: Color
    var ray: Double = 8
    var gap: Double = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let turn = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120) / 120 * 360
            Canvas { context, size in
                let origin = CGPoint(x: size.width * center.x, y: size.height * center.y)
                let reach = hypot(size.width, size.height)
                var rays = Path()
                var angle = turn
                while angle < turn + 360 {
                    rays.move(to: origin)
                    rays.addArc(center: origin, radius: reach, startAngle: .degrees(angle), endAngle: .degrees(angle + ray), clockwise: false)
                    rays.closeSubpath()
                    angle += ray + gap
                }
                context.fill(rays, with: .color(color))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Confetti drifting down over a win.
struct Confetti: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors = [Color(hex: 0xFFC94D), Color(hex: 0xFF7AA8), Color(hex: 0x6EE7FF), Color(hex: 0xB7F36B), Color(hex: 0xFFE15C)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for index in 0..<36 {
                    let seed = Double(index)
                    let fall = 26 + (seed * 7).truncatingRemainder(dividingBy: 22)
                    let y = ((time * fall + seed * 97).truncatingRemainder(dividingBy: Double(size.height) + 40)) - 20
                    let x = (seed * 61).truncatingRemainder(dividingBy: Double(size.width)) + sin(time * 1.3 + seed) * 10
                    var piece = context
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(time * (1 + seed.truncatingRemainder(dividingBy: 3)) + seed))
                    let shape = index % 3 == 0 ? Path(ellipseIn: CGRect(x: -3, y: -3, width: 7, height: 7)) : Path(roundedRect: CGRect(x: -4, y: -7, width: 8, height: 13), cornerRadius: 2)
                    piece.fill(shape, with: .color(Self.colors[index % Self.colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
