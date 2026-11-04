import HeistCore
import SwiftUI

// The full-screen match screens from the design (3.01 coin flip, 3.02 role reveal, 3.15 round result,
// 3.16 series scoreboard, 3.17 match end), laid out in the mockups' 393×852 points.

private let seriesPill = "TOURNAMENT · FIRST TO \(MatchRules.winsNeeded) · RANKED"

// MARK: - 3.01 Coin flip

/// Who is Player 1 (the thief first), with the coin tossed and the roles for the whole series.
struct CoinFlipScreen: View {
    let model: MatchModel
    let stage: Stage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        let s = stage.scale
        let youFirst = model.userIsPlayer1
        let firstRole = model.role(inRound: 1)
        StageScreen(stage: stage) {
            ZStack {
                RadialGradient(stops: [
                    .init(color: Color(hex: 0x5B3AA8), location: 0),
                    .init(color: Color(hex: 0x2A1A5E), location: 0.42),
                    .init(color: Color(hex: 0x0B0820), location: 1),
                ], center: UnitPoint(x: 0.5, y: 0.44), startRadius: 0, endRadius: 520 * s)
                Sunburst(center: UnitPoint(x: 0.5, y: 0.44), color: .white.opacity(0.05))
            }
        } content: {
            ZStack(alignment: .top) {
                VStack(spacing: 6 * s) {
                    ScreenPill(text: seriesPill)
                    Text("Coin flip").font(BrandFont.baloo(32 * s, 800))
                }
                .padding(.top, 60 * s)

                HStack(spacing: 8 * s) {
                    playerChip(name: model.player.name, detail: "You · \(model.startRatings.combined)", role: firstRole, first: youFirst, bot: false)
                    Text("VS").font(BrandFont.baloo(20 * s, 800)).foregroundStyle(Color(hex: 0xC8BDE6))
                    playerChip(name: model.opponent.name, detail: String(model.opponent.ratings.combined), role: firstRole.other, first: !youFirst, bot: model.opponent.isBot)
                }
                .padding(.horizontal, 16 * s)
                .padding(.top, 146 * s)

                CoinToss(face: youFirst ? .thief : .police, landed: landed)
                    .frame(width: 220 * s, height: 240 * s)
                    .padding(.top, 230 * s)

                VStack(spacing: 8 * s) {
                    Text("\(youFirst ? model.player.name : model.opponent.name) is Player 1")
                        .font(BrandFont.baloo(30 * s, 800))
                        .shadow(color: .black.opacity(0.35), radius: 0, y: 3 * s)
                    HStack(spacing: 6 * s) {
                        SVGShape(firstRole.emblem).fill(firstRole.color).frame(width: 18 * s, height: 18 * s)
                        Text("You start as the \(firstRole.title.lowercased())")
                            .font(BrandFont.nunito(14 * s, 900))
                            .foregroundStyle(firstRole == .thief ? Color(hex: 0xFFE3B0) : Color(hex: 0xBFE0FF))
                    }
                    .padding(.leading, 8 * s)
                    .padding(.trailing, 14 * s)
                    .frame(height: 32 * s)
                    .background(firstRole.color.opacity(0.2), in: Capsule())
                    .overlay(Capsule().strokeBorder(firstRole.color, lineWidth: 1.5 * s))
                }
                .padding(.top, 482 * s)
                .opacity(landed ? 1 : 0)
                .offset(y: landed ? 0 : 12 * s)

                rolesPanel
                    .padding(.horizontal, 16 * s)
                    .padding(.top, 580 * s)
                    .opacity(landed ? 1 : 0)

                CountdownBar(label: "Role reveal in \(model.secondsLeft) s", fraction: Double(model.secondsLeft) / Double(max(model.phaseLength, 1)))
                    .padding(.horizontal, 16 * s)
                    .padding(.top, 782 * s)
            }
            .foregroundStyle(.white)
            .frame(width: 393 * s, height: 852 * s, alignment: .top)
        }
        .task {
            if !reduceMotion { try? await Task.sleep(for: .seconds(1.7)) }
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { landed = true }
        }
    }

    private func playerChip(name: String, detail: String, role: Role, first: Bool, bot: Bool) -> some View {
        let s = stage.scale
        let highlight = first && landed
        return HStack(spacing: 8 * s) {
            FaceAvatar(role: role, size: 48)
            VStack(alignment: .leading, spacing: 1 * s) {
                Text(name).font(BrandFont.nunito(15 * s, 900)).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 4 * s) {
                    if bot { BotTag() }
                    Text(detail)
                        .font(BrandFont.nunito(12 * s, 700))
                        .foregroundStyle(bot ? Color(hex: 0xC8D6F0) : Color(hex: 0xFFE3B0))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 6 * s)
        .padding(.trailing, 10 * s)
        .padding(.vertical, 6 * s)
        .background((highlight ? Brand.gold.opacity(0.16) : .white.opacity(0.07)), in: RoundedRectangle(cornerRadius: 18 * s))
        .overlay(RoundedRectangle(cornerRadius: 18 * s).strokeBorder(highlight ? Color(hex: 0xFFB547) : .white.opacity(0.22), lineWidth: 2 * s))
        .shadow(color: highlight ? Color(hex: 0xFFB547, opacity: 0.35) : .clear, radius: 10 * s)
        .overlay(alignment: .top) {
            if highlight {
                Text("PLAYER 1")
                    .font(BrandFont.nunito(10 * s, 900))
                    .tracking(0.8 * s)
                    .foregroundStyle(Color(hex: 0x2A1A06))
                    .padding(.horizontal, 8 * s)
                    .padding(.vertical, 1 * s)
                    .background(Color(hex: 0xFFB547), in: RoundedRectangle(cornerRadius: 6 * s))
                    .offset(y: -11 * s)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The roles for the series, grouped into runs ("Rounds 1–3"), with single rounds at the end shared on one line.
    private var rolesPanel: some View {
        let s = stage.scale
        var runs: [(first: Int, last: Int, role: Role)] = []
        for number in 1...MatchRules.rounds {
            let role = model.role(inRound: number)
            if let last = runs.last, last.role == role, last.last == number - 1 {
                runs[runs.count - 1].last = number
            } else {
                runs.append((number, number, role))
            }
        }
        var rows: [(label: String, roles: [Role])] = []
        var singles: [(Int, Role)] = []
        for run in runs {
            if run.first == run.last {
                singles.append((run.first, run.role))
            } else {
                if !singles.isEmpty { rows.append((singles.map { "Round \($0.0)" }.joined(separator: " · "), singles.map(\.1))); singles = [] }
                rows.append(("Rounds \(run.first)–\(run.last)", [run.role]))
            }
        }
        if !singles.isEmpty { rows.append((singles.map { "Round \($0.0)" }.joined(separator: " · "), singles.map(\.1))) }

        return VStack(alignment: .leading, spacing: 8 * s) {
            Text("YOUR ROLES THIS SERIES")
                .font(BrandFont.nunito(11 * s, 900))
                .tracking(1.3 * s)
                .foregroundStyle(Color(hex: 0xC8BDE6))
            ForEach(rows.indices, id: \.self) { index in
                HStack {
                    Text(rows[index].label).font(BrandFont.nunito(14 * s, 800))
                    Spacer()
                    HStack(spacing: 6 * s) {
                        ForEach(rows[index].roles.indices, id: \.self) { RoleChip(role: rows[index].roles[$0]) }
                    }
                }
            }
            Divider().overlay(.white.opacity(0.12))
            Text("First to \(MatchRules.winsNeeded) round wins takes the match. At 3–3 after six rounds come two extra rounds: win both to take it, or it's a draw.")
                .font(BrandFont.nunito(12.5 * s, 700))
                .foregroundStyle(Color(hex: 0xDCD3F2))
        }
        .padding(.horizontal, 14 * s)
        .padding(.vertical, 12 * s)
        .background(Color(red: 8 / 255, green: 6 / 255, blue: 24 / 255, opacity: 0.62), in: RoundedRectangle(cornerRadius: 18 * s))
        .overlay(RoundedRectangle(cornerRadius: 18 * s).strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }
}

/// The gold coin, tossed and spinning, landing on the thief's diamond or the police shield.
private struct CoinToss: View {
    let face: Role
    let landed: Bool

    @Environment(\.stageScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tossed = false

    private struct Pose {
        var spin: Double = 0
        var lift: CGFloat = 0
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFE58A, opacity: 0.55), .clear], center: .center, startRadius: 0, endRadius: 108 * s))
                .frame(width: 216 * s, height: 216 * s)
                .opacity(landed ? 1 : 0.4)
            Ellipse()
                .fill(.black.opacity(0.35))
                .frame(width: 116 * s, height: 16 * s)
                .offset(y: 110 * s)
            if reduceMotion {
                CoinFace(role: face).frame(width: 160 * s, height: 168 * s)
            } else {
                KeyframeAnimator(initialValue: Pose(), trigger: tossed) { pose in
                    let front = cos(pose.spin * .pi / 180) >= 0
                    CoinFace(role: front ? face : face.other)
                        .frame(width: 160 * s, height: 168 * s)
                        .scaleEffect(x: 1, y: front ? 1 : -1)
                        .rotation3DEffect(.degrees(pose.spin), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                        .offset(y: pose.lift)
                } keyframes: { _ in
                    KeyframeTrack(\.spin) {
                        CubicKeyframe(360 * 5, duration: 1.5)
                    }
                    KeyframeTrack(\.lift) {
                        CubicKeyframe(-140 * s, duration: 0.6)
                        CubicKeyframe(0, duration: 0.6)
                        SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                    }
                }
            }
        }
        .onAppear { tossed = true }
        .accessibilityElement()
        .accessibilityLabel(landed ? "The coin landed on the \(face.title.lowercased()) side" : "The coin is spinning")
    }
}

/// One face of the coin: gold rim and face with the role's emblem.
private struct CoinFace: View {
    let role: Role

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            ZStack {
                Ellipse()
                    .fill(LinearGradient(colors: [Color(hex: 0x8A5A0E), Color(hex: 0xC98A1A), Color(hex: 0x7A4A08)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: w, height: h * 0.93)
                    .offset(y: h * 0.07)
                Ellipse()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFF4BC), Color(hex: 0xFFC94A), Color(hex: 0xD98A1A)], center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: w * 0.8))
                    .overlay(Ellipse().strokeBorder(Color(hex: 0xB9801A), lineWidth: w * 0.012))
                    .frame(width: w, height: h * 0.93)
                    .offset(y: -h * 0.0)
                Ellipse()
                    .strokeBorder(Color(hex: 0xC98A1A), lineWidth: w * 0.03)
                    .frame(width: w * 0.8, height: h * 0.74)
                Group {
                    switch role {
                    case .thief:
                        ZStack {
                            SVGShape("M110 78 L152 120 L110 162 L68 120 Z", viewBox: Self.box).fill(Color(hex: 0xFFB547))
                            SVGShape("M110 78 L152 120 L110 162 L68 120 Z", viewBox: Self.box).stroke(Color(hex: 0x8A5A12), style: StrokeStyle(lineWidth: 3.5 * w / 160, lineJoin: .round))
                            SVGShape("M110 78 L152 120 L68 120 Z", viewBox: Self.box).fill(.white.opacity(0.2))
                            SVGShape("M86 116 Q98 106 110 116 Q122 106 134 116 Q134 129 123 130 Q115 129 110 124 Q105 129 97 130 Q86 129 86 116 Z", viewBox: Self.box).fill(Color(hex: 0x2A1A06))
                        }
                    case .police:
                        ZStack {
                            SVGShape("M110 74 L150 90 V118 C150 142 132 158 110 166 C88 158 70 142 70 118 V90 Z", viewBox: Self.box).fill(Color(hex: 0x5AA2FF))
                            SVGShape("M110 74 L150 90 V118 C150 142 132 158 110 166 C88 158 70 142 70 118 V90 Z", viewBox: Self.box).stroke(Color(hex: 0x1F4FA0), style: StrokeStyle(lineWidth: 3.5 * w / 160, lineJoin: .round))
                            SVGShape("M110 98 l7 14 15 2 -11 10 3 15 -14 -8 -14 8 3 -15 -11 -10 15 -2 z", viewBox: Self.box).fill(Color(hex: 0x0E1E44))
                        }
                    }
                }
                .frame(width: w * 220 / 160, height: h * 240 / 168)
                .offset(y: -h * 0.03)
                Ellipse()
                    .trim(from: 0.55, to: 0.72)
                    .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: w * 0.04, lineCap: .round))
                    .frame(width: w * 0.9, height: h * 0.83)
            }
            .frame(width: w, height: h)
        }
    }

    private static let box = CGRect(x: 0, y: 0, width: 220, height: 240)
}

// MARK: - 3.02 Role reveal

/// This round's role, the meeple, and the goal.
struct RoleRevealScreen: View {
    let model: MatchModel
    let stage: Stage

    @State private var shown = false

    var body: some View {
        let s = stage.scale
        let role = model.role
        let thief = role == .thief
        StageScreen(stage: stage) {
            ZStack {
                RadialGradient(stops: thief
                    ? [.init(color: Color(hex: 0x8A64D6), location: 0), .init(color: Color(hex: 0x3A2178), location: 0.4), .init(color: Color(hex: 0x120A2A), location: 1)]
                    : [.init(color: Color(hex: 0x4C7FD6), location: 0), .init(color: Color(hex: 0x173A80), location: 0.4), .init(color: Color(hex: 0x07122A), location: 1)],
                    center: UnitPoint(x: 0.5, y: 0.48), startRadius: 0, endRadius: 520 * s)
                Sunburst(center: UnitPoint(x: 0.5, y: 0.48), color: thief ? Color(hex: 0xFFC94D, opacity: 0.09) : Color(hex: 0x9CC6FF, opacity: 0.09), ray: 7, gap: 11)
            }
        } content: {
            ZStack(alignment: .top) {
                VStack(spacing: 4 * s) {
                    ScreenPill(text: model.isExtension ? "EXTRA ROUND \(model.roundNumber - MatchRules.regularRounds) OF 2 · TOURNAMENT" : "ROUND \(model.roundNumber) · TOURNAMENT")
                    Text("YOU ARE THE")
                        .font(BrandFont.nunito(14 * s, 900))
                        .tracking(4.2 * s)
                        .foregroundStyle(thief ? Color(hex: 0xFFE3B0) : Color(hex: 0xBFE0FF))
                        .padding(.top, 6 * s)
                    HStack(spacing: 10 * s) {
                        SVGShape(role.emblem).fill(role.color).frame(width: 46 * s, height: 46 * s)
                        Text(role.title.uppercased())
                            .font(BrandFont.baloo(72 * s, 800))
                            .tracking(2.8 * s)
                            .foregroundStyle(thief ? Color(hex: 0xFFC94D) : Color(hex: 0x9CC6FF))
                            .shadow(color: thief ? Color(hex: 0x8A4A0A) : Color(hex: 0x1F3F80), radius: 0, y: 4 * s)
                            .shadow(color: .black.opacity(0.5), radius: 15 * s, y: 12 * s)
                    }
                    .scaleEffect(shown ? 1 : 0.7)
                    .opacity(shown ? 1 : 0)
                }
                .padding(.top, 60 * s)

                Ellipse()
                    .fill(RadialGradient(colors: [role.color.opacity(0.7), .clear], center: .center, startRadius: 0, endRadius: 130 * s))
                    .frame(width: 260 * s, height: 58 * s)
                    .padding(.top, 548 * s)

                Image(thief ? "meeple-thief" : "meeple-police")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 360 * s)
                    .shadow(color: .black.opacity(0.35), radius: 14 * s, y: 12 * s)
                    .padding(.top, 212 * s)
                    .scaleEffect(shown ? 1 : 0.6, anchor: .bottom)
                    .opacity(shown ? 1 : 0)
                    .accessibilityHidden(true)

                goalPanel
                    .padding(.horizontal, 16 * s)
                    .padding(.top, 598 * s)

                HStack {
                    HStack(spacing: 6 * s) {
                        Text("vs \(model.opponent.name)").font(BrandFont.nunito(13 * s, 800))
                        if model.opponent.isBot { BotTag() }
                        RoleChip(role: role.other, height: 24)
                    }
                    Spacer()
                    Text("Briefing in \(max(1, model.secondsLeft - MatchRules.briefingSeconds)) s")
                        .font(BrandFont.nunito(13 * s, 800))
                        .foregroundStyle(Color(hex: 0xDCD3F2))
                }
                .padding(.horizontal, 16 * s)
                .padding(.top, 806 * s)
            }
            .foregroundStyle(.white)
            .frame(width: 393 * s, height: 852 * s, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { model.skipAhead() }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.35).delay(0.1)) { shown = true }
        }
        .accessibilityAction(named: "Continue") { model.skipAhead() }
    }

    private var goalPanel: some View {
        let s = stage.scale
        let thief = model.role == .thief
        let rows: [(icon: String, dim: Bool, text: String)] = thief
            ? [("art-exit", false, "You can see the \(model.view.exits.count) exits."), ("art-chest", true, "The police can see the chests. You can't."), ("clock", false, "\(model.view.turnLimit) turns, \(MatchRules.chaseTurnSeconds) seconds each.")]
            : [("art-chest", false, "You can see the \(model.view.chests.count) chests."), ("art-exit", true, "The thief can see the exits. You can't."), ("clock", false, "\(model.view.turnLimit) turns, \(MatchRules.chaseTurnSeconds) seconds each.")]
        return VStack(alignment: .leading, spacing: 6 * s) {
            Text("YOUR GOAL")
                .font(BrandFont.nunito(11 * s, 900))
                .tracking(1.3 * s)
                .foregroundStyle(thief ? Color(hex: 0xFFD592) : Color(hex: 0xBFE0FF))
            Text(thief ? "Rob a chest, then escape." : "Catch the thief before turn \(MatchRules.chaseTurns) ends.")
                .font(BrandFont.baloo(21 * s, 800))
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 10 * s) {
                    Group {
                        if rows[index].icon == "clock" {
                            Image(systemName: "timer").font(.system(size: 20 * s, weight: .bold)).foregroundStyle(Brand.gold)
                        } else {
                            Image(rows[index].icon).resizable()
                        }
                    }
                    .frame(width: 26 * s, height: 26 * s)
                    .opacity(rows[index].dim ? 0.6 : 1)
                    Text(rows[index].text).font(BrandFont.nunito(13 * s, 700))
                }
            }
        }
        .padding(.horizontal, 14 * s)
        .padding(.vertical, 12 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 12 / 255, green: 8 / 255, blue: 30 / 255, opacity: 0.78), in: RoundedRectangle(cornerRadius: 18 * s))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18 * s))
        .overlay(RoundedRectangle(cornerRadius: 18 * s).strokeBorder(model.role.color.opacity(0.7), lineWidth: 1.5 * s))
    }
}

// MARK: - 3.15 Round result

/// Who won the round, a 3D replay of it, the rating change and the series so far.
struct RoundResultScreen: View {
    let model: MatchModel
    let stage: Stage

    var body: some View {
        let s = stage.scale
        if let record = model.lastRecord {
            let won = record.won
            StageScreen(stage: stage) {
                ZStack {
                    RadialGradient(stops: won
                        ? [.init(color: Color(hex: 0x7A57E6), location: 0), .init(color: Color(hex: 0x3A2178), location: 0.4), .init(color: Color(hex: 0x0B0820), location: 1)]
                        : [.init(color: Color(hex: 0x3A4370), location: 0), .init(color: Color(hex: 0x1C2046), location: 0.4), .init(color: Color(hex: 0x080A1C), location: 1)],
                        center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 600 * s)
                    if won { Confetti() }
                }
            } content: {
                ZStack(alignment: .top) {
                    VStack(spacing: 4 * s) {
                        ScreenPill(text: record.number > MatchRules.regularRounds ? "EXTRA ROUND \(record.number - MatchRules.regularRounds) OF 2 · TOURNAMENT" : "ROUND \(record.number) · TOURNAMENT")
                        HStack(spacing: 8 * s) {
                            SVGShape(record.role.emblem).fill(record.role.color).frame(width: 32 * s, height: 32 * s)
                            Text(record.headline)
                                .font(BrandFont.baloo(44 * s, 800))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .foregroundStyle(won ? Color(hex: 0xFFC94D) : Color(hex: 0xC8D6F0))
                                .shadow(color: won ? Color(hex: 0x8A4A0A) : Color(hex: 0x1F2A50), radius: 0, y: 3 * s)
                        }
                        .padding(.top, 4 * s)
                        Text(record.detail)
                            .font(BrandFont.nunito(13 * s, 700))
                            .foregroundStyle(Color(hex: 0xE2DAF6))
                    }
                    .padding(.horizontal, 16 * s)
                    .padding(.top, 52 * s)

                    ReplayCard(replay: record.replay)
                        .frame(width: 301 * s, height: 300 * s)
                        .padding(.top, 194 * s)

                    ratingRow(record)
                        .padding(.horizontal, 16 * s)
                        .padding(.top, 520 * s)

                    SeriesStrip(model: model)
                        .padding(.horizontal, 16 * s)
                        .padding(.top, 594 * s)

                    nextRow
                        .padding(.horizontal, 16 * s)
                        .padding(.top, 728 * s)
                }
                .foregroundStyle(.white)
                .frame(width: 393 * s, height: 852 * s, alignment: .top)
            }
        }
    }

    private func ratingRow(_ record: RoundRecord) -> some View {
        let s = stage.scale
        let rank = record.role == .thief ? model.player.thief : model.player.police
        return HStack(spacing: 10 * s) {
            RankBadge(role: record.role, division: rank.division, size: 40 * s)
            VStack(alignment: .leading, spacing: 1 * s) {
                Text("\(record.role.title.uppercased()) RATING")
                    .font(BrandFont.nunito(10 * s, 900))
                    .tracking(1.2 * s)
                    .foregroundStyle(record.role == .thief ? Color(hex: 0xFFD592) : Color(hex: 0xBFE0FF))
                Text(verbatim: "\(record.ratingBefore) → \(record.ratingAfter)")
                    .font(BrandFont.nunito(16 * s, 900))
                    .monospacedDigit()
            }
            Spacer()
            DeltaChip(delta: record.ratingAfter - record.ratingBefore)
        }
        .padding(.leading, 8 * s)
        .padding(.trailing, 12 * s)
        .frame(height: 60 * s)
        .background(Color(red: 12 / 255, green: 8 / 255, blue: 30 / 255, opacity: 0.78), in: RoundedRectangle(cornerRadius: 16 * s))
        .overlay(RoundedRectangle(cornerRadius: 16 * s).strokeBorder(record.role.color.opacity(0.7), lineWidth: 1.5 * s))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var nextRow: some View {
        let s = stage.scale
        let fraction = Double(model.secondsLeft) / Double(max(model.phaseLength, 1))
        VStack(spacing: 8 * s) {
            HStack(spacing: 6 * s) {
                if isFinal {
                    Text("Series over · results").font(BrandFont.nunito(13.5 * s, 800))
                } else {
                    Text("Next: Round \(model.roundNumber + 1) · you're the").font(BrandFont.nunito(13.5 * s, 800))
                    RoleChip(role: model.nextRole, height: 24)
                }
                Spacer()
                Text("in \(model.secondsLeft) s").font(BrandFont.nunito(13 * s, 800)).foregroundStyle(Color(hex: 0xDCD3F2))
            }
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
        .contentShape(Rectangle())
        .onTapGesture { model.skipAhead() }
        .accessibilityAction(named: "Continue") { model.skipAhead() }
    }

    private var isFinal: Bool { model.isDecided }
}

/// The round played back on a small 3D board, both players visible, with a replay button.
private struct ReplayCard: View {
    let replay: RoundReplay

    @Environment(\.stageScale) private var s
    @State private var step = 0
    @State private var run = 0
    @State private var showsBoard = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22 * s)
        VStack(spacing: 0) {
            ZStack {
                if showsBoard {
                    HarborBoard(scene: replay.scene(at: step)) { _ in }
                        .transition(.opacity)
                }
            }
            .frame(width: 301 * s, height: 250 * s)
            .accessibilityHidden(true)
            HStack(spacing: 8 * s) {
                Text(step == 0 ? "Start" : "Turn \(step)")
                    .font(BrandFont.nunito(12 * s, 900))
                    .monospacedDigit()
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(height: 5 * s)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(Color(hex: 0xFF5F7E))
                                .frame(width: geometry.size.width * Double(step) / Double(max(replay.steps - 1, 1)))
                                .animation(.linear(duration: 0.5), value: step)
                        }
                    }
                Text("of \(replay.steps - 1)")
                    .font(BrandFont.nunito(12 * s, 800))
                    .foregroundStyle(Color(hex: 0xC8BDE6))
            }
            .padding(.horizontal, 12 * s)
            .frame(height: 50 * s)
        }
        .background(RadialGradient(colors: [Color(hex: 0x2C9CC0), Color(hex: 0x0A2A44)], center: .center, startRadius: 0, endRadius: 220 * s))
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 2 * s))
        .shadow(color: .black.opacity(0.45), radius: 15 * s, y: 12 * s)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 5 * s) {
                Circle().fill(Color(hex: 0xFF5F7E)).frame(width: 8 * s, height: 8 * s)
                Text("HIGHLIGHT REPLAY").font(BrandFont.nunito(11 * s, 900)).tracking(0.9 * s)
            }
            .padding(.leading, 6 * s)
            .padding(.trailing, 9 * s)
            .padding(.vertical, 3 * s)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8 * s))
            .padding(10 * s)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                run += 1
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 17 * s, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44 * s, height: 44 * s)
                    .background(.black.opacity(0.5), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5 * s))
            }
            .buttonStyle(PressableStyle())
            .padding(8 * s)
            .accessibilityLabel("Play the replay again")
        }
        // The round's board is still fading out when this screen arrives; start this one once it's gone.
        .onChange(of: LiveBoards.shared.count, initial: true) { _, count in
            if count == 0 { withAnimation(.easeOut(duration: 0.3)) { showsBoard = true } }
        }
        // Plays once the board is up, and again from the replay button.
        .task(id: showsBoard ? run : nil) {
            guard showsBoard else { return }
            step = 0
            try? await Task.sleep(for: .seconds(0.8))
            while step < replay.steps - 1 {
                try? await Task.sleep(for: .seconds(0.55))
                if Task.isCancelled { return }
                step += 1
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Highlight replay, turn \(step) of \(replay.steps - 1)")
    }
}

/// "SERIES · FIRST TO 5", the score, and one pip per round: won, lost, next or still to come.
struct SeriesStrip: View {
    let model: MatchModel

    @Environment(\.stageScale) private var s

    var body: some View {
        VStack(spacing: 10 * s) {
            HStack(alignment: .firstTextBaseline) {
                Text("SERIES · FIRST TO \(MatchRules.winsNeeded)")
                    .font(BrandFont.nunito(11 * s, 900))
                    .tracking(1.3 * s)
                    .foregroundStyle(Color(hex: 0xC8BDE6))
                Spacer()
                Text("You \(model.score.you) – \(model.score.bot) \(model.opponent.name)")
                    .font(BrandFont.baloo(20 * s, 800))
            }
            HStack {
                ForEach(1...MatchRules.rounds, id: \.self) { number in
                    pip(number)
                    if number < MatchRules.rounds { Spacer(minLength: 0) }
                }
            }
        }
        .padding(.horizontal, 14 * s)
        .padding(.vertical, 12 * s)
        .background(Color(red: 12 / 255, green: 8 / 255, blue: 30 / 255, opacity: 0.7), in: RoundedRectangle(cornerRadius: 18 * s))
        .overlay(RoundedRectangle(cornerRadius: 18 * s).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private struct PipStyle {
        let label: String
        let labelColor: Color
        let fill: AnyShapeStyle
        let border: Color
        let emblem: Color
        var dashed = false
    }

    private func pipStyle(_ number: Int, role: Role) -> PipStyle {
        let record = model.records.first { $0.number == number }
        let decided = model.isDecided
        if let record, record.won {
            return PipStyle(label: "Won", labelColor: Color(hex: 0xFFE3B0),
                            fill: AnyShapeStyle(RadialGradient(colors: [Color(hex: 0xFFF1A8), Color(hex: 0xF5B52E), Color(hex: 0xB9801A)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 20 * s)),
                            border: .white, emblem: Color(hex: 0x2A1A06))
        }
        if record != nil {
            return PipStyle(label: "Lost", labelColor: Color(hex: 0xFFC2CC), fill: AnyShapeStyle(Color(hex: 0x2A1E44)), border: Color(hex: 0xFF8FA3), emblem: Color(hex: 0x8F86AE))
        }
        if number == model.roundNumber + 1 && !decided {
            return PipStyle(label: "Next", labelColor: role == .thief ? Color(hex: 0xFFE3B0) : Color(hex: 0xBFE0FF), fill: AnyShapeStyle(role.color.opacity(0.2)), border: role.color, emblem: role.color)
        }
        return PipStyle(label: "R\(number)", labelColor: Color(hex: 0xA89FC8), fill: AnyShapeStyle(Color.clear), border: .white.opacity(0.35), emblem: role.color, dashed: true)
    }

    private func pip(_ number: Int) -> some View {
        let role = model.role(inRound: number)
        let style = pipStyle(number, role: role)
        return VStack(spacing: 3 * s) {
            SVGShape(role.emblem)
                .fill(style.emblem)
                .frame(width: 16 * s, height: 16 * s)
                .frame(width: 34 * s, height: 34 * s)
                .background(style.fill, in: Circle())
                .overlay(Circle().strokeBorder(style.border, style: StrokeStyle(lineWidth: 2 * s, dash: style.dashed ? [4 * s, 3 * s] : [])))
            Text(style.label).font(BrandFont.nunito(10 * s, 800)).foregroundStyle(style.labelColor)
        }
    }
}

// MARK: - 3.16 Series scoreboard

/// The series between rounds: the score, what each round came to, and the next round.
struct SeriesScreen: View {
    let model: MatchModel
    let stage: Stage
    let onChat: () -> Void

    var body: some View {
        let s = stage.scale
        let next = model.roundNumber + 1
        let nextRole = model.nextRole
        StageScreen(stage: stage) {
            RadialGradient(stops: [
                .init(color: Color(hex: 0x2A3A7A), location: 0),
                .init(color: Color(hex: 0x141A44), location: 0.45),
                .init(color: Color(hex: 0x070A1E), location: 1),
            ], center: .top, startRadius: 0, endRadius: 900 * s)
        } content: {
            ZStack(alignment: .top) {
                ScreenPill(text: seriesPill).padding(.top, 58 * s)

                HStack {
                    player(name: "\(model.player.name) (you)", role: nextRole, bot: false)
                    Spacer()
                    HStack(spacing: 12 * s) {
                        Text("\(model.score.you)").font(BrandFont.baloo(64 * s, 800)).foregroundStyle(Color(hex: 0xFFC94D)).shadow(color: Color(hex: 0x8A4A0A), radius: 0, y: 3 * s)
                        Text("–").font(BrandFont.baloo(30 * s, 800)).foregroundStyle(Color(hex: 0x8F96C2))
                        Text("\(model.score.bot)").font(BrandFont.baloo(64 * s, 800)).foregroundStyle(Color(hex: 0xBFE0FF)).shadow(color: Color(hex: 0x1F3F80), radius: 0, y: 3 * s)
                    }
                    .monospacedDigit()
                    .accessibilityElement()
                    .accessibilityLabel("Score: you \(model.score.you), \(model.opponent.name) \(model.score.bot)")
                    Spacer()
                    player(name: model.opponent.name, role: nextRole.other, bot: model.opponent.isBot)
                }
                .padding(.horizontal, 16 * s)
                .padding(.top, 96 * s)

                VStack(spacing: 6 * s) {
                    Text(model.roundNumber >= MatchRules.regularRounds ? "Extra rounds: win both to take the match" : "First to \(MatchRules.winsNeeded) round wins · 3–3 goes to two extra rounds")
                        .font(BrandFont.nunito(13 * s, 800))
                        .foregroundStyle(Color(hex: 0xD6E0F5))
                    HStack(spacing: 8 * s) {
                        needs(need(you: true), .thief)
                        needs(need(you: false), .police)
                    }
                }
                .padding(.top, 196 * s)

                VStack(spacing: 6 * s) {
                    HStack(spacing: 8 * s) {
                        Text("RND").frame(width: 34 * s, alignment: .leading)
                        Text("YOUR ROLE").frame(width: 94 * s, alignment: .leading)
                        Text("WHAT HAPPENED").frame(maxWidth: .infinity, alignment: .leading)
                        Text("RESULT").frame(width: 58 * s, alignment: .trailing)
                    }
                    .font(BrandFont.nunito(10.5 * s, 900))
                    .tracking(1 * s)
                    .foregroundStyle(Color(hex: 0x8F96C2))
                    .padding(.horizontal, 12 * s)
                    ForEach(1...MatchRules.rounds, id: \.self) { number in
                        row(number, next: next)
                    }
                }
                .padding(.horizontal, 16 * s)
                .padding(.top, 262 * s)

                HStack(spacing: 10 * s) {
                    Button(action: onChat) {
                        Image(systemName: "ellipsis.bubble").font(.system(size: 21 * s, weight: .semibold))
                    }
                    .buttonStyle(OutlineButtonStyle(scale: s))
                    .frame(width: 52 * s)
                    .accessibilityLabel("Quick chat")
                    // The server starts the next round for both players at once.
                    Button("Round \(next) in \(model.secondsLeft) s") {}
                        .buttonStyle(ChunkyButtonStyle(colors: [Color(hex: 0xEE6A2A), Color(hex: 0xC23A16)], edge: Color(hex: 0x7E2410), text: .white, scale: s))
                        .allowsHitTesting(false)
                        .accessibilityLabel("Round \(next) starts in \(model.secondsLeft) seconds")
                }
                .padding(.horizontal, 16 * s)
                .padding(.top, 758 * s)
            }
            .foregroundStyle(.white)
            .frame(width: 393 * s, height: 852 * s, alignment: .top)
        }
    }

    private func player(name: String, role: Role, bot: Bool) -> some View {
        let s = stage.scale
        return VStack(spacing: 4 * s) {
            FaceAvatar(role: role, size: 60, ring: role.color, ringWidth: 3)
            HStack(spacing: 4 * s) {
                Text(name).font(BrandFont.nunito(14 * s, 900)).lineLimit(1).minimumScaleFactor(0.8)
                if bot { BotTag() }
            }
        }
        .frame(width: 104 * s)
    }

    private func needs(_ text: String, _ role: Role) -> some View {
        let s = stage.scale
        return Text(text)
            .font(BrandFont.nunito(12 * s, 800))
            .foregroundStyle(role == .thief ? Color(hex: 0xFFE3B0) : Color(hex: 0xBFE0FF))
            .padding(.horizontal, 10 * s)
            .padding(.vertical, 3 * s)
            .background(role.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10 * s))
            .overlay(RoundedRectangle(cornerRadius: 10 * s).strokeBorder(role.color, lineWidth: 1))
    }

    /// What each side still needs: wins to reach 4, or in the extension both extra rounds.
    private func need(you: Bool) -> String {
        let name = you ? "You" : model.opponent.name
        let verb = you ? "need" : "needs"
        guard model.roundNumber >= MatchRules.regularRounds else {
            let wins = MatchRules.winsNeeded - (you ? model.score.you : model.score.bot)
            return "\(name) \(verb) \(wins) more"
        }
        guard let first = model.records.first(where: { $0.number > MatchRules.regularRounds }) else {
            return "\(name) \(verb) both extra rounds"
        }
        return first.won == you ? "\(name) \(verb) round 8 too" : "\(name) can only draw now"
    }

    private func row(_ number: Int, next: Int) -> some View {
        let s = stage.scale
        let record = model.records.first { $0.number == number }
        let isNext = number == next
        let (result, text): (String, String) = if let record {
            (record.won ? "WON" : "LOST", record.summary)
        } else if isNext {
            ("NEXT", "Up next · prep in \(model.secondsLeft) s")
        } else {
            ("—", number > MatchRules.regularRounds ? "Only at 3–3" : "If needed")
        }
        let style: (row: Color, border: Color, chip: Color, chipBorder: Color, chipText: Color, text: Color) = switch result {
        case "WON": (Color(hex: 0x5BD07A, opacity: 0.1), Color(hex: 0x5BD07A, opacity: 0.35), Color(hex: 0x5BD07A), Color(hex: 0x5BD07A), Color(hex: 0x062A12), .white)
        case "LOST": (.white.opacity(0.05), .white.opacity(0.1), Color(hex: 0xFF8FA3, opacity: 0.12), Color(hex: 0xFF8FA3), Color(hex: 0xFFC2CC), Color(hex: 0xD6E0F5))
        case "NEXT": (Color(hex: 0xFFE15C, opacity: 0.12), Color(hex: 0xFFE15C), Color(hex: 0xFFE15C), Color(hex: 0xFFE15C), Color(hex: 0x2A1A06), Color(hex: 0xFFF1B8))
        default: (.clear, .white.opacity(0.12), .clear, .white.opacity(0.2), Color(hex: 0x8F96C2), Color(hex: 0x9AA2CC))
        }
        return HStack(spacing: 8 * s) {
            Text("R\(number)")
                .font(BrandFont.baloo(17 * s, 800))
                .foregroundStyle(isNext ? Color(hex: 0xFFE15C) : style.text)
                .frame(width: 34 * s, alignment: .leading)
            RoleChip(role: model.role(inRound: number), height: 24)
                .opacity(result == "—" ? 0.55 : 1)
                .frame(width: 94 * s, alignment: .leading)
            Text(text)
                .font(BrandFont.nunito(12.5 * s, 700))
                .foregroundStyle(style.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(result)
                .font(BrandFont.nunito(11 * s, 900))
                .tracking(0.7 * s)
                .foregroundStyle(style.chipText)
                .padding(.horizontal, 8 * s)
                .padding(.vertical, 3 * s)
                .background(style.chip, in: RoundedRectangle(cornerRadius: 8 * s))
                .overlay(RoundedRectangle(cornerRadius: 8 * s).strokeBorder(style.chipBorder, lineWidth: 1))
                .frame(width: 58 * s, alignment: .trailing)
        }
        .padding(.horizontal, 12 * s)
        .frame(height: 50 * s)
        .background(style.row, in: RoundedRectangle(cornerRadius: 14 * s))
        .overlay(RoundedRectangle(cornerRadius: 14 * s).strokeBorder(style.border, lineWidth: 1.5 * s))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 3.17 Match end

/// Victory, defeat or a draw, with all three rating changes and the rewards.
struct MatchEndScreen: View {
    let model: MatchModel
    let stage: Stage

    var body: some View {
        let s = stage.scale
        let outcome = model.outcome
        StageScreen(stage: stage) {
            ZStack {
                RadialGradient(stops: outcome == .win
                    ? [.init(color: Color(hex: 0xC77A1E), location: 0), .init(color: Color(hex: 0x6A3A8A), location: 0.38), .init(color: Color(hex: 0x1A0F38), location: 0.72), .init(color: Color(hex: 0x0B0820), location: 1)]
                    : [.init(color: Color(hex: 0x3A4A8A), location: 0), .init(color: Color(hex: 0x232A5A), location: 0.38), .init(color: Color(hex: 0x10122E), location: 0.72), .init(color: Color(hex: 0x070A1E), location: 1)],
                    center: UnitPoint(x: 0.5, y: 0.26), startRadius: 0, endRadius: 700 * s)
                if outcome == .win {
                    Sunburst(center: UnitPoint(x: 0.5, y: 0.3), color: Color(hex: 0xFFE15C, opacity: 0.1), ray: 6, gap: 10)
                    Confetti()
                }
            }
        } content: {
            ZStack(alignment: .top) {
                VStack(spacing: 2 * s) {
                    ScreenPill(text: "TOURNAMENT · RANKED")
                    Text(outcome == .win ? "VICTORY!" : outcome == .loss ? "DEFEAT" : "DRAW")
                        .font(BrandFont.baloo(58 * s, 800))
                        .foregroundStyle(outcome == .win ? Color(hex: 0xFFE15C) : outcome == .loss ? Color(hex: 0xC8D6F0) : Color(hex: 0xFFE3B0))
                        .shadow(color: outcome == .win ? Color(hex: 0x8A4A0A) : Color(hex: 0x1F2A50), radius: 0, y: 4 * s)
                        .padding(.top, 4 * s)
                    Text(subtitle)
                        .font(BrandFont.nunito(14 * s, 800))
                        .foregroundStyle(Color(hex: 0xFFF1D6))
                }
                .padding(.top, 56 * s)

                Ellipse()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFE15C, opacity: 0.6), .clear], center: .center, startRadius: 0, endRadius: 116 * s))
                    .frame(width: 233 * s, height: 40 * s)
                    .padding(.top, 344 * s)
                HStack(alignment: .bottom, spacing: 13 * s) {
                    Image("meeple-thief").resizable().scaledToFit().frame(width: 120 * s, height: 200 * s)
                    Image("meeple-police").resizable().scaledToFit().frame(width: 120 * s, height: 200 * s)
                }
                .shadow(color: .black.opacity(0.35), radius: 10 * s, y: 8 * s)
                .padding(.top, 166 * s)
                .accessibilityHidden(true)

                VStack(spacing: 8 * s) {
                    ratingRow(role: .thief)
                    ratingRow(role: .police)
                    combinedRow
                }
                .padding(.horizontal, 16 * s)
                .padding(.top, 386 * s)

                HStack(spacing: 8 * s) {
                    reward(icon: "icon-coin", value: "+\(model.rewards.coins)", caption: "Coins")
                    reward(icon: "icon-pass", value: "+\(model.rewards.xp) XP", caption: model.rewards.xp >= 500 ? "Pass · tier \(model.player.passTier) → \(model.player.passTier + 1)" : "Pass · tier \(model.player.passTier)")
                }
                .padding(.horizontal, 16 * s)
                .padding(.top, 600 * s)

                Button {} label: {
                    HStack(spacing: 8 * s) {
                        Image(systemName: "play.rectangle.fill")
                        Text("Double coins · watch a short ad")
                        Text("OPTIONAL")
                            .font(BrandFont.nunito(10.5 * s, 900))
                            .tracking(0.6 * s)
                            .foregroundStyle(Color(hex: 0xE2DAF6))
                            .padding(.horizontal, 6 * s)
                            .padding(.vertical, 1 * s)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6 * s))
                    }
                    .font(BrandFont.nunito(14 * s, 800))
                    .foregroundStyle(Color(hex: 0xFFF1B8))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48 * s)
                    .background(Color(hex: 0xFFE15C, opacity: 0.08), in: RoundedRectangle(cornerRadius: 16 * s))
                    .overlay(RoundedRectangle(cornerRadius: 16 * s).strokeBorder(Color(hex: 0xFFE15C, opacity: 0.8), style: StrokeStyle(lineWidth: 1.5 * s, dash: [6 * s, 4 * s])))
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, 16 * s)
                .padding(.top, 664 * s)
                .accessibilityLabel("Optional: watch a short ad to double your coins")

                HStack(spacing: 10 * s) {
                    Button("Home") { model.leave() }
                        .buttonStyle(OutlineButtonStyle(scale: s))
                        .frame(width: 110 * s)
                    Button("PLAY AGAIN") { model.playAgain() }
                        .buttonStyle(ChunkyButtonStyle(colors: [Color(hex: 0xEE6A2A), Color(hex: 0xC23A16)], edge: Color(hex: 0x7E2410), text: .white, scale: s))
                        .accessibilityLabel("Play again: Tournament, ranked")
                }
                .padding(.horizontal, 16 * s)
                .padding(.top, 748 * s)
            }
            .foregroundStyle(.white)
            .frame(width: 393 * s, height: 852 * s, alignment: .top)
        }
    }

    private var subtitle: String {
        let score = model.score
        switch model.outcome {
        case .win: return "You won the series \(score.you)–\(score.bot) against \(model.opponent.name)"
        case .loss: return "\(model.opponent.name) won the series \(score.bot)–\(score.you)"
        case .draw: return "The series ended \(score.you)–\(score.bot)"
        }
    }

    private func ratingRow(role: Role) -> some View {
        let s = stage.scale
        let rank = role == .thief ? model.player.thief : model.player.police
        let rounds = model.records.filter { $0.role == role }.count
        let before = model.startRatings[role], after = model.ratings[role]
        return HStack(spacing: 10 * s) {
            RankBadge(role: role, division: rank.division, size: 40 * s)
            VStack(alignment: .leading, spacing: 1 * s) {
                Text("\(role.title.uppercased()) RATING")
                    .font(BrandFont.nunito(10 * s, 900))
                    .tracking(1.2 * s)
                    .foregroundStyle(role == .thief ? Color(hex: 0xFFD592) : Color(hex: 0xBFE0FF))
                Text("\(rank.title) \(rank.division) · \(rounds) \(rounds == 1 ? "round" : "rounds")")
                    .font(BrandFont.nunito(12.5 * s, 700))
                    .foregroundStyle(Color(hex: 0xE2DAF6))
            }
            Spacer()
            Text(verbatim: "\(before) → \(after)").font(BrandFont.nunito(15 * s, 900)).monospacedDigit().lineLimit(1)
            DeltaChip(delta: after - before)
        }
        .padding(.leading, 8 * s)
        .padding(.trailing, 12 * s)
        .frame(height: 58 * s)
        .background(Color(red: 12 / 255, green: 8 / 255, blue: 30 / 255, opacity: 0.78), in: RoundedRectangle(cornerRadius: 16 * s))
        .overlay(RoundedRectangle(cornerRadius: 16 * s).strokeBorder(role.color.opacity(0.8), lineWidth: 1.5 * s))
        .accessibilityElement(children: .combine)
    }

    private var combinedRow: some View {
        let s = stage.scale
        let before = model.startRatings.combined, after = model.ratings.combined
        return HStack(spacing: 10 * s) {
            Image(systemName: "crown.fill")
                .font(.system(size: 22 * s, weight: .bold))
                .foregroundStyle(Color(hex: 0xFFE15C))
                .frame(width: 40 * s, height: 40 * s)
            VStack(alignment: .leading, spacing: 1 * s) {
                Text("COMBINED · MAIN RANK")
                    .font(BrandFont.nunito(10 * s, 900))
                    .tracking(1.2 * s)
                    .foregroundStyle(Color(hex: 0xFFE15C))
                Text("Used for matchmaking")
                    .font(BrandFont.nunito(12.5 * s, 700))
                    .foregroundStyle(Color(hex: 0xFFF1D6))
            }
            Spacer()
            Text(verbatim: "\(before) → \(after)").font(BrandFont.nunito(16 * s, 900)).monospacedDigit().lineLimit(1)
            DeltaChip(delta: after - before)
        }
        .padding(.leading, 8 * s)
        .padding(.trailing, 12 * s)
        .frame(height: 64 * s)
        .background(LinearGradient(colors: [Color(hex: 0xFFE15C, opacity: 0.22), Color(red: 12 / 255, green: 8 / 255, blue: 30 / 255, opacity: 0.8)], startPoint: .leading, endPoint: UnitPoint(x: 0.6, y: 0.5)), in: RoundedRectangle(cornerRadius: 16 * s))
        .overlay(RoundedRectangle(cornerRadius: 16 * s).strokeBorder(Color(hex: 0xFFE15C), lineWidth: 2 * s))
        .accessibilityElement(children: .combine)
    }

    private func reward(icon: String, value: String, caption: String) -> some View {
        let s = stage.scale
        return HStack(spacing: 8 * s) {
            Image(icon).resizable().frame(width: 34 * s, height: 34 * s)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(BrandFont.nunito(17 * s, 900))
                Text(caption).font(BrandFont.nunito(11 * s, 700)).foregroundStyle(Color(hex: 0xD6CDF0)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8 * s)
        .padding(.trailing, 12 * s)
        .frame(height: 52 * s)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16 * s))
        .overlay(RoundedRectangle(cornerRadius: 16 * s).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
