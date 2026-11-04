import SwiftUI

/// The home screen: the player's thief and police on stage in front of downtown, with the logo on
/// top, menu buttons down both sides and PLAY at the bottom. Downtown follows the device clock
/// (morning, evening or night). PLAY starts an online match and the Leaderboards tile opens the boards;
/// the other buttons come later.
struct HomeView: View {
    var player = PlayerSummary.sample
    var onPlay: () -> Void = {}
    var onLeaderboards: () -> Void = {}

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            HomeScene(time: TimeOfDay(date: timeline.date), player: player, onPlay: onPlay, onLeaderboards: onLeaderboards)
        }
    }
}

private struct HomeScene: View {
    let time: TimeOfDay
    let player: PlayerSummary
    let onPlay: () -> Void
    let onLeaderboards: () -> Void

    private static let design = CGSize(width: 393, height: 852)

    var body: some View {
        GeometryReader { geometry in
            let stage = Stage(designSize: Self.design, screen: geometry.size)
            ZStack(alignment: .topLeading) {
                DowntownBackdrop(time: time, placement: stage.backdrop(screen: geometry.size, anchorY: 556))
                    .id(time)
                    .transition(.opacity)
                HomeStage(skin: HomeSkin(time), player: player, onPlay: onPlay, onLeaderboards: onLeaderboards)
                    .environment(\.stageScale, stage.scale)
                    .frame(width: stage.size.width, height: stage.size.height, alignment: .topLeading)
                    .offset(x: stage.origin.x, y: stage.origin.y)
            }
            .animation(.easeInOut(duration: 1.5), value: time)
        }
        .ignoresSafeArea()
    }
}

/// Everything in front of the scenery, positioned in the design's 393×852 points.
private struct HomeStage: View {
    let skin: HomeSkin
    let player: PlayerSummary
    let onPlay: () -> Void
    let onLeaderboards: () -> Void

    @Environment(\.stageScale) private var scale

    var body: some View {
        let s = scale
        ZStack(alignment: .topLeading) {
            Pedestals(skin: skin)

            Character(asset: "character-thief", idleDelay: 0)
                .stageFrame(x: 64, y: 340, width: 140, height: 238, scale: s)
                .accessibilityLabel("Your thief: Rook the raccoon")
            Character(asset: "character-police", idleDelay: 0.8)
                .stageFrame(x: 189, y: 340, width: 140, height: 238, scale: s)
                .accessibilityLabel("Your police: Sergeant Bix the hound")

            HStack(alignment: .center) {
                ProfileChip(player: player, skin: skin)
                Spacer(minLength: 6 * s)
                HStack(spacing: 6 * s) {
                    CurrencyCounter(icon: "icon-coin", amount: player.coins, name: "Coins", skin: skin)
                    CurrencyCounter(icon: "icon-gem", amount: player.gems, name: "Gems", skin: skin)
                }
            }
            .padding(.horizontal, 12 * s)
            .frame(width: 393 * s)
            .offset(y: 58 * s)

            VStack(spacing: 6 * s) {
                LineLogo(width: 320 * s)
                Text("Thief vs Police")
                    .font(BrandFont.nunito(11 * s, 900))
                    .tracking(2.4 * s)
                    .textCase(.uppercase)
                    .foregroundStyle(skin.subtitle)
                    .padding(.top, 2 * s)
                SeasonPill(name: player.season, skin: skin)
            }
            .frame(width: 393 * s)
            .offset(y: 122 * s)

            VStack(spacing: 6 * s) {
                ForEach(SideTile.Kind.left) { kind in
                    SideTile(kind: kind, player: player, skin: skin, action: kind == .ranks ? onLeaderboards : {})
                }
            }
            .offset(x: 6 * s, y: 174 * s)
            VStack(spacing: 6 * s) {
                ForEach(SideTile.Kind.right) { SideTile(kind: $0, player: player, skin: skin) }
            }
            .offset(x: 321 * s, y: 174 * s)

            RatingPlate(role: .thief, rank: player.thief, skin: skin)
                .offset(x: 70 * s, y: 584 * s)
            RatingPlate(role: .police, rank: player.police, skin: skin)
                .offset(x: 199 * s, y: 584 * s)

            ModeSelector(skin: skin)
                .offset(x: 62 * s, y: 648 * s)

            PlayButton(skin: skin, action: onPlay)
                .offset(x: 44 * s, y: 708 * s)
        }
    }
}

/// A placeholder character from the design, gently breathing while it waits.
private struct Character: View {
    let asset: String
    let idleDelay: Double

    @Environment(\.stageScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inhale = false

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .shadow(color: .black.opacity(0.28), radius: 2.5 * scale, y: 3 * scale)
            .scaleEffect(x: 1, y: inhale ? 1.018 : 1, anchor: .bottom)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.7).repeatForever().delay(idleDelay)) {
                    inhale = true
                }
            }
    }
}

/// The two lit discs the characters stand on.
private struct Pedestals: View {
    let skin: HomeSkin

    @Environment(\.stageScale) private var scale

    var body: some View {
        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            for (x, ring, light) in [(CGFloat(134), skin.thiefRing, Color(hex: 0xFFB547)), (259, skin.policeRing, Color(hex: 0x5AA2FF))] {
                var glow = context
                glow.translateBy(x: x, y: 574)
                glow.scaleBy(x: 1, y: 30.0 / 90)
                glow.fill(Path(ellipseIn: CGRect(x: -90, y: -90, width: 180, height: 180)), with: .radialGradient(
                    Gradient(colors: [light.opacity(skin.pedestalGlow), light.opacity(0)]),
                    center: .zero, startRadius: 0, endRadius: 90
                ))
                let disc = Path(ellipseIn: CGRect(x: x - 58, y: 561, width: 116, height: 22))
                context.fill(disc, with: .color(skin.pedestal))
                context.stroke(disc, with: .color(ring), lineWidth: 2.5)
            }
        }
        .frame(width: 393 * scale, height: 852 * scale)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What the home screen shows about the player. Name and ratings come from the saved account
/// (`PlayerAccount.summary`); level, coins, season and pass are the design's sample values until the
/// economy exists.
struct PlayerSummary {
    struct Rank {
        let rating: Int
        let title: String
        /// Roman numeral shown on the rank badge.
        let division: String
    }

    var name: String
    var level: Int
    /// Progress to the next level, 0 to 1.
    var levelProgress: Double
    var rating: Int
    var coins: Int
    var gems: Int
    var thief: Rank
    var police: Rank
    var season: String
    var passTier: Int
    /// Progress to the next pass tier, 0 to 1.
    var passProgress: Double
    var friendsOnline: Int

    static let sample = PlayerSummary(
        name: "Rowan", level: 14, levelProgress: 0.62, rating: 1436, coins: 12_480, gems: 320,
        thief: Rank(rating: 1482, title: "Pickpocket", division: "II"),
        police: Rank(rating: 1390, title: "Cadet", division: "III"),
        season: "Season 1 · Grand Opening", passTier: 12, passProgress: 0.68, friendsOnline: 2
    )
}
