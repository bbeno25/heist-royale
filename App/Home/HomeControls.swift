import HeistCore
import SwiftUI

// The home screen's controls, sized in design points times the stage scale.
// They are real buttons (VoiceOver, press feedback); only PLAY has an action so far.

/// Avatar with level ring, name and combined rating.
struct ProfileChip: View {
    let player: PlayerSummary
    let skin: HomeSkin

    @Environment(\.stageScale) private var s

    var body: some View {
        Button {} label: {
            HStack(spacing: 8 * s) {
                ZStack {
                    Circle()
                        .inset(by: 3 * s)
                        .stroke(.black.opacity(0.25), lineWidth: 4 * s)
                    Circle()
                        .inset(by: 3 * s)
                        .trim(from: 0, to: player.levelProgress)
                        .stroke(Color(hex: 0x5BD07A), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0x8A64D6), Color(hex: 0x3A2178)], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 24 * s))
                        .overlay {
                            Image("character-thief")
                                .resizable()
                                .frame(width: 70 * s, height: 119 * s)
                                .offset(y: 27.5 * s)
                        }
                        .clipShape(Circle())
                        .frame(width: 40 * s, height: 40 * s)
                    Text(player.level, format: .number)
                        .font(BrandFont.nunito(10 * s, 900))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4 * s)
                        .frame(minWidth: 22 * s, minHeight: 16 * s)
                        .background(Color(hex: 0x1E9A4A), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5 * s))
                        .offset(y: 22 * s)
                }
                .frame(width: 52 * s, height: 52 * s)

                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(player.name)
                        .font(BrandFont.nunito(15 * s, 900))
                    HStack(spacing: 4 * s) {
                        RatingHexagon()
                            .frame(width: 14 * s, height: 14 * s)
                        Text(player.rating, format: .number.grouping(.never))
                            .font(BrandFont.nunito(12 * s, 800))
                            .foregroundStyle(skin.sub)
                    }
                }
            }
            .padding(.trailing, 12 * s)
            .frame(height: 52 * s)
            .foregroundStyle(skin.text)
            .glassEffect(.regular.tint(skin.panel).interactive(), in: Capsule())
            .overlay(Capsule().strokeBorder(skin.panelBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 8 * s, y: 6 * s)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings: \(player.name), level \(player.level), \(Int(player.levelProgress * 100)) percent to level \(player.level + 1), combined rating \(player.rating)")
    }
}

/// The gold hexagon badge beside the combined rating.
private struct RatingHexagon: View {
    var body: some View {
        ZStack {
            SVGShape("M12 2l8.7 5v10L12 22l-8.7-5V7z").fill(Color(hex: 0xE8B04B))
            SVGShape("M12 2l8.7 5v10L12 22l-8.7-5V7z").stroke(Color(hex: 0x8A5A12), lineWidth: 1)
            SVGShape("M12 7l1.4 2.9 3.2.4-2.3 2.2.6 3.1-2.9-1.5-2.9 1.5.6-3.1-2.3-2.2 3.2-.4z").fill(Color(hex: 0xFFF6D8))
        }
    }
}

/// Coin or gem balance with a plus button for the shop.
struct CurrencyCounter: View {
    let icon: String
    let amount: Int
    let name: String
    let skin: HomeSkin

    @Environment(\.stageScale) private var s

    var body: some View {
        Button {} label: {
            ZStack(alignment: .leading) {
                HStack(spacing: 6 * s) {
                    Text(amount, format: .number)
                        .font(BrandFont.nunito(14 * s, 900))
                        .monospacedDigit()
                        .foregroundStyle(skin.text)
                    Image(systemName: "plus")
                        .font(.system(size: 13 * s, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 28 * s, height: 28 * s)
                        .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x5BD07A), Color(hex: 0x1E9A4A)], startPoint: .top, endPoint: .bottom)))
                }
                .padding(.leading, 28 * s)
                .padding(.trailing, 3 * s)
                .frame(height: 34 * s)
                .background(Capsule().fill(skin.counter.shadow(.inner(color: .black.opacity(0.25), radius: 2 * s, y: 2 * s))))
                .overlay(Capsule().strokeBorder(skin.panelBorder, lineWidth: 1))
                .padding(.leading, 12 * s)
                Image(icon)
                    .resizable()
                    .frame(width: 38 * s, height: 38 * s)
                    .offset(x: -2 * s)
            }
            .frame(height: 44 * s)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(name): \(amount.formatted()). Get more in the Shop")
    }
}

/// The current season under the logo.
struct SeasonPill: View {
    let name: String
    let skin: HomeSkin

    @Environment(\.stageScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0xFFE15C), Color(hex: 0xF2A500)], startPoint: .top, endPoint: .bottom))
                .frame(width: 16 * s, height: 16 * s)
            Text(name)
                .font(BrandFont.nunito(12 * s, 800))
                .foregroundStyle(skin.labelText)
        }
        .padding(.leading, 6 * s)
        .padding(.trailing, 10 * s)
        .padding(.vertical, 4 * s)
        .background(skin.label, in: Capsule())
    }
}

/// A round menu button down the side of the home screen.
struct SideTile: View {
    enum Kind: String, Identifiable {
        case ranks, cards, training, friends, shop, wardrobe, pass, daily

        static let left: [Kind] = [.ranks, .cards, .training, .friends]
        static let right: [Kind] = [.shop, .wardrobe, .pass, .daily]

        var id: Self { self }

        var icon: String {
            switch self {
            case .ranks: "icon-trophy"
            case .cards: "icon-cards"
            case .training: "icon-target"
            case .friends: "icon-friends"
            case .shop: "icon-shop"
            case .wardrobe: "icon-wardrobe"
            case .pass: "icon-pass"
            case .daily: "icon-daily"
            }
        }

        var title: String { rawValue.capitalized }
    }

    let kind: Kind
    let player: PlayerSummary
    let skin: HomeSkin

    @Environment(\.stageScale) private var s

    var body: some View {
        Button {} label: {
            VStack(spacing: 5 * s) {
                disc
                Text(kind.title)
                    .font(BrandFont.nunito(11 * s, 800))
                    .fixedSize()
                    .foregroundStyle(skin.labelText)
                    .padding(.horizontal, 7 * s)
                    .padding(.vertical, 1 * s)
                    .background(skin.label, in: RoundedRectangle(cornerRadius: 7 * s))
            }
            .frame(width: 66 * s, height: 82 * s, alignment: .top)
            .overlay(alignment: .topTrailing) { cornerBadge }
            .overlay(alignment: .top) {
                if kind == .shop {
                    Text("NEW")
                        .font(BrandFont.nunito(10 * s, 900))
                        .tracking(0.4 * s)
                        .foregroundStyle(Color(hex: 0x3A2400))
                        .padding(.horizontal, 6 * s)
                        .padding(.vertical, 1 * s)
                        .background(Color(hex: 0xFFD23F), in: RoundedRectangle(cornerRadius: 6 * s))
                        .overlay(RoundedRectangle(cornerRadius: 6 * s).strokeBorder(.white, lineWidth: 1.5 * s))
                        .shadow(color: .black.opacity(0.3), radius: 2 * s, y: 2 * s)
                        .offset(y: -5 * s)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(accessibilityText)
    }

    private var disc: some View {
        ZStack {
            if kind == .daily {
                Circle().fill(Color(hex: 0xFF6B6B, opacity: 0.35)).frame(width: 72 * s, height: 72 * s)
            }
            Circle().fill(skin.rim).frame(width: 63 * s, height: 63 * s)
            Circle()
                .fill(RadialGradient(colors: [skin.tileCenter, skin.tileEdge], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 50 * s))
                .frame(width: 58 * s, height: 58 * s)
            Capsule()
                .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 40 * s, height: 20 * s)
                .offset(y: -16 * s)
            if kind == .pass {
                Circle().stroke(.black.opacity(0.3), lineWidth: 3.5 * s).frame(width: 64 * s, height: 64 * s)
                Circle()
                    .trim(from: 0, to: player.passProgress)
                    .stroke(Color(hex: 0xFFE15C), style: StrokeStyle(lineWidth: 3.5 * s, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 64 * s, height: 64 * s)
            }
            Image(kind.icon)
                .resizable()
                .frame(width: 46 * s, height: 46 * s)
                .offset(y: -1 * s)
            if kind == .pass {
                Text(player.passTier, format: .number)
                    .font(BrandFont.nunito(11 * s, 900))
                    .foregroundStyle(Color(hex: 0xFFE15C))
                    .padding(.horizontal, 4 * s)
                    .frame(minWidth: 22 * s, minHeight: 20 * s)
                    .background(Color(hex: 0x2B1A06), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(hex: 0xFFE15C), lineWidth: 1.5 * s))
                    .offset(x: 25 * s, y: 24 * s)
            }
        }
        .frame(width: 58 * s, height: 58 * s)
        .compositingGroup()
        .shadow(color: .black.opacity(0.38), radius: 7 * s, y: 7 * s)
    }

    @ViewBuilder private var cornerBadge: some View {
        switch kind {
        case .friends:
            redBadge(Text(player.friendsOnline, format: .number))
        case .daily:
            redBadge(Text("!"))
        default:
            EmptyView()
        }
    }

    private func redBadge(_ text: Text) -> some View {
        text
            .font(BrandFont.nunito(11 * s, 900))
            .foregroundStyle(.white)
            .padding(.horizontal, 5 * s)
            .frame(minWidth: 21 * s, minHeight: 21 * s)
            .background(Color(hex: 0xE53950), in: Capsule())
            .overlay(Capsule().strokeBorder(.white, lineWidth: 2 * s))
            .shadow(color: .black.opacity(0.3), radius: 2 * s, y: 2 * s)
            .offset(x: 0, y: -3 * s)
    }

    private var accessibilityText: String {
        switch kind {
        case .ranks: "Leaderboards"
        case .cards: "Card Library"
        case .training: "Training: tutorial and bots"
        case .friends: "Friends: \(player.friendsOnline) online"
        case .shop: "Shop, new items"
        case .wardrobe: "Wardrobe: characters and skins"
        case .pass: "Season pass: tier \(player.passTier)"
        case .daily: "Daily reward, ready to claim"
        }
    }
}

/// The thief's or police's rating, title and division badge under their pedestal.
struct RatingPlate: View {
    let role: Role
    let rank: PlayerSummary.Rank
    let skin: HomeSkin

    @Environment(\.stageScale) private var s

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16 * s)
        Button {} label: {
            HStack(spacing: 6 * s) {
                badge
                VStack(alignment: .leading, spacing: 0) {
                    Text(role == .thief ? "THIEF" : "POLICE")
                        .font(BrandFont.nunito(10 * s, 900))
                        .tracking(1.2 * s)
                        .foregroundStyle(role == .thief ? skin.thiefLabel : skin.policeLabel)
                    Text(rank.rating, format: .number.grouping(.never))
                        .font(BrandFont.nunito(16 * s, 900))
                        .monospacedDigit()
                    Text(rank.title)
                        .font(BrandFont.nunito(10 * s, 700))
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 4 * s)
            .padding(.trailing, 8 * s)
            .frame(width: 124 * s, height: 54 * s, alignment: .leading)
            .foregroundStyle(skin.plateText)
            .glassEffect(.regular.tint(skin.plate).interactive(), in: shape)
            .overlay(shape.strokeBorder(role == .thief ? Color(hex: 0xFFB547) : Color(hex: 0x5AA2FF), lineWidth: 1.5 * s))
            .shadow(color: .black.opacity(0.3), radius: 8 * s, y: 6 * s)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(role == .thief
            ? "Thief: \(rank.title) \(rank.division), rating \(rank.rating). Change in Wardrobe"
            : "Police: \(rank.title) \(rank.division), rating \(rank.rating). Change in Wardrobe")
    }

    private var badge: some View {
        RankBadge(role: role, division: rank.division, size: 38 * s)
    }
}

/// The match mode picked for PLAY.
struct ModeSelector: View {
    let skin: HomeSkin

    @Environment(\.stageScale) private var s

    var body: some View {
        Button {} label: {
            HStack(spacing: 10 * s) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: 0xFFE15C), Color(hex: 0xF2A500)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.3), radius: 3 * s, y: 2 * s)
                    SVGShape("M13 2L4 14h7l-1 8 9-12h-7z").fill(.white)
                        .frame(width: 22 * s, height: 22 * s)
                    SVGShape("M13 2L4 14h7l-1 8 9-12h-7z").stroke(Color(hex: 0x8A5A00), style: StrokeStyle(lineWidth: 1.4 * s, lineJoin: .round))
                        .frame(width: 22 * s, height: 22 * s)
                }
                .frame(width: 38 * s, height: 38 * s)
                VStack(alignment: .leading, spacing: 1 * s) {
                    Text("Tournament")
                        .font(BrandFont.nunito(15 * s, 900))
                    Text("3 + 3 rounds · First to 4 · Ranked")
                        .font(BrandFont.nunito(11 * s, 700))
                        .foregroundStyle(skin.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
                Text("Change")
                    .font(BrandFont.nunito(12 * s, 800))
                    .foregroundStyle(skin.sub)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12 * s, weight: .heavy))
            }
            .padding(.leading, 6 * s)
            .padding(.trailing, 12 * s)
            .frame(width: 269 * s, height: 50 * s)
            .foregroundStyle(skin.text)
            .glassEffect(.regular.tint(skin.panel).interactive(), in: Capsule())
            .overlay(Capsule().strokeBorder(skin.panelBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mode: Tournament, three rounds in each role, first to 4 round wins, ranked. Change mode")
    }
}

/// The big PLAY button: a chunky key that sinks onto its edge when pressed.
struct PlayButton: View {
    let skin: HomeSkin
    var action: () -> Void = {}

    @Environment(\.stageScale) private var s

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12 * s) {
                Image(systemName: "play.fill")
                    .font(.system(size: 26 * s, weight: .black))
                Text("PLAY")
                    .font(BrandFont.baloo(40 * s, 800))
                    .tracking(2.4 * s)
                    .shadow(color: skin.playTextShadow, radius: 0, y: (skin.playText == .white ? 2 : 1) * s)
            }
            .foregroundStyle(skin.playText)
        }
        .buttonStyle(PlayButtonStyle(skin: skin, scale: s))
        .accessibilityLabel("Play classic match")
    }
}

private struct PlayButtonStyle: ButtonStyle {
    let skin: HomeSkin
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let s = scale
        let shape = RoundedRectangle(cornerRadius: 28 * s)
        let sink = configuration.isPressed ? 5 * s : 0
        return configuration.label
            .frame(width: 305 * s, height: 80 * s)
            .background {
                ZStack(alignment: .top) {
                    shape.fill(LinearGradient(colors: [skin.playTop, skin.playBottom], startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 20 * s)
                        .fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .frame(height: 30 * s)
                        .padding(.horizontal, 14 * s)
                        .padding(.top, 4 * s)
                }
            }
            .overlay(shape.strokeBorder(skin.playRim, lineWidth: 3 * s))
            .offset(y: sink)
            .background(shape.fill(skin.playEdge).offset(y: 7 * s))
            .shadow(color: .black.opacity(0.42), radius: 16 * s, y: 16 * s)
            .shadow(color: skin.playGlow, radius: 34 * s)
            .animation(.spring(duration: 0.18, bounce: 0.3), value: configuration.isPressed)
    }
}

/// Shrinks a little while pressed, with a springy release.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.45), value: configuration.isPressed)
    }
}
