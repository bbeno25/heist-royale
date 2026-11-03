import SwiftUI

/// A card as in the "full-art 3D" mockup: the design's render filling the face, the gold cost gem (prep)
/// or a CHASE pill, the role emblem, and the type and name at the bottom. Designed at 160×228 and scaled.
struct MatchCard: View {
    enum Look { case normal, selected, locked, placed }

    let card: CardID
    /// Whose hand it is in (Run belongs to both roles).
    let role: Role
    var look: Look = .normal
    var width: CGFloat = 160
    var showsEffect = false

    var body: some View {
        let k = width / 160
        let style = CardStyle(role: card.role ?? role)
        let outer = RoundedRectangle(cornerRadius: 17 * k)
        let inner = RoundedRectangle(cornerRadius: 15 * k)

        ZStack {
            outer.fill(LinearGradient(colors: style.frame, startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1)))
            ZStack(alignment: .topLeading) {
                style.base
                Image(card.render(for: role))
                    .resizable()
                    .scaledToFill()
                    .frame(width: 155 * k, height: 223 * k)
                    .clipped()
                LinearGradient(colors: [Color(hex: 0x04040E, opacity: 0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 56 * k)
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(stops: [
                        .init(color: Color(hex: 0x060512, opacity: 0), location: 0),
                        .init(color: Color(hex: 0x060512, opacity: 0.78), location: 0.45),
                        .init(color: Color(hex: 0x060512, opacity: 0.96), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120 * k)
                }
                LinearGradient(colors: [.clear, style.glow.opacity(0.5)], startPoint: UnitPoint(x: 0.5, y: 0.8), endPoint: .bottom)

                if card.isChase {
                    HStack(spacing: 3 * k) {
                        SVGShape("M13 2L4 14h7l-1 8 9-12h-7z").fill(Color(hex: 0xFFE15C)).frame(width: 12 * k, height: 12 * k)
                        Text("CHASE").font(BrandFont.nunito(10 * k, 900)).tracking(0.8 * k)
                    }
                    .padding(.leading, 5 * k)
                    .padding(.trailing, 8 * k)
                    .frame(height: 22 * k)
                    .background(.black.opacity(0.5), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: max(0.5, k)))
                    .offset(x: 8 * k, y: 8 * k)
                } else {
                    CostGem(cost: card.cost, scale: k)
                        .offset(x: 7 * k, y: 7 * k)
                }

                SVGShape(style.emblem)
                    .fill(style.accent)
                    .frame(width: 16 * k, height: 16 * k)
                    .frame(width: 26 * k, height: 26 * k)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: max(0.5, k)))
                    .offset(x: (160 - 5 - 8 - 26) * k, y: 8 * k)

                VStack(alignment: .leading, spacing: 2 * k) {
                    Spacer()
                    Text(card.category)
                        .font(BrandFont.nunito(max(9 * k, 6.5), 900))
                        .tracking(1.4 * k)
                        .foregroundStyle(style.accent)
                    Text(card.name)
                        .font(BrandFont.baloo((card.name.count > 12 ? 17 : 20) * k, 800))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .shadow(color: .black.opacity(0.6), radius: 3 * k, y: 2 * k)
                    if showsEffect {
                        Text(card.effect)
                            .font(BrandFont.nunito(10.5 * k, 700))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineSpacing(1.5 * k)
                            .padding(.top, 3 * k)
                    }
                }
                .foregroundStyle(.white)
                .padding(10 * k)
            }
            .clipShape(inner)
            .overlay(inner.strokeBorder(.white.opacity(0.22), lineWidth: max(0.5, k)))
            .padding(2.5 * k)
        }
        .frame(width: width, height: 228 * k)
        .compositingGroup()
        .grayscale(look == .locked ? 0.9 : 0)
        .colorMultiply(look == .locked ? Color(white: 0.62) : .white)
        .shadow(color: look == .selected ? Color(hex: 0xFFE15C, opacity: 0.7) : .black.opacity(0.5), radius: look == .selected ? 15 * k : 11 * k, y: look == .selected ? 0 : 10 * k)
        .overlay {
            if look == .selected {
                outer.strokeBorder(Color(hex: 0xFFE15C), lineWidth: max(2, 3 * k)).padding(-max(2, 3 * k))
            }
        }
        .overlay(alignment: .top) { badge(k: k) }
        .offset(y: look == .selected ? -14 : 0)
        .animation(.spring(duration: 0.3, bounce: 0.4), value: look)
    }

    @ViewBuilder private func badge(k: CGFloat) -> some View {
        switch look {
        case .locked:
            HStack(spacing: 6 * k) {
                Image(systemName: "lock.fill").font(.system(size: 15 * k, weight: .black))
                Text("Needs \(card.cost)").font(BrandFont.nunito(16 * k, 900))
            }
            .foregroundStyle(.white)
            .fixedSize()
            .padding(.leading, 9 * k)
            .padding(.trailing, 12 * k)
            .padding(.vertical, 6 * k)
            .background(Color(hex: 0x060512, opacity: 0.9), in: RoundedRectangle(cornerRadius: 14 * k))
            .overlay(RoundedRectangle(cornerRadius: 14 * k).strokeBorder(.white.opacity(0.75), lineWidth: 2 * k))
            .padding(.top, 74 * k)
        case .placed:
            Image(systemName: "checkmark")
                .font(.system(size: 26 * k, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 58 * k, height: 58 * k)
                .background(LinearGradient(colors: [Color(hex: 0x5BD07A), Color(hex: 0x17803A)], startPoint: .top, endPoint: .bottom), in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 3 * k))
                .shadow(color: .black.opacity(0.45), radius: 9 * k, y: 8 * k)
                .padding(.top, 70 * k)
        default:
            EmptyView()
        }
    }
}

/// The gold hexagon with the card's cost in prep points.
struct CostGem: View {
    let cost: Int
    var scale: CGFloat = 1

    var body: some View {
        let box = CGRect(x: 0, y: 0, width: 38, height: 42)
        ZStack {
            SVGShape("M19 1.5L35.5 11v20L19 40.5 2.5 31V11z", viewBox: box).fill(Color(hex: 0x4A2C04))
            SVGShape("M19 3.6L33.6 12.1v17.8L19 38.4 4.4 29.9V12.1z", viewBox: box)
                .fill(LinearGradient(stops: [
                    .init(color: Color(hex: 0xFFF4C2), location: 0),
                    .init(color: Color(hex: 0xFFC94A), location: 0.45),
                    .init(color: Color(hex: 0xB97A12), location: 1),
                ], startPoint: .top, endPoint: .bottom))
            SVGShape("M19 3.6L33.6 12.1 19 21 4.4 12.1z", viewBox: box).fill(.white.opacity(0.28))
            Text("\(cost)")
                .font(BrandFont.baloo(24 * scale, 800))
                .foregroundStyle(Color(hex: 0x3A2200))
                .padding(.top, 3 * scale)
        }
        .frame(width: 38 * scale, height: 42 * scale)
    }
}

/// Role colours for cards: gold frame and purple stage for the thief, silver-blue and navy for the police.
struct CardStyle {
    let frame: [Color]
    let base: Color
    let accent: Color
    let glow: Color
    let emblem: String

    init(role: Role) {
        switch role {
        case .thief:
            frame = [Color(hex: 0xFFF0C8), Color(hex: 0xF5B54A), Color(hex: 0xA8650C), Color(hex: 0xFFD98A)]
            base = Color(hex: 0x120826)
            accent = Color(hex: 0xFFC977)
            glow = Color(red: 1, green: 170 / 255, blue: 60 / 255)
        case .police:
            frame = [Color(hex: 0xF0F7FF), Color(hex: 0x8CBCFF), Color(hex: 0x1E4A9A), Color(hex: 0xBFDCFF)]
            base = Color(hex: 0x04102A)
            accent = Color(hex: 0x9CC6FF)
            glow = Color(red: 90 / 255, green: 162 / 255, blue: 1)
        }
        emblem = role.emblem
    }
}
