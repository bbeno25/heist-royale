import HeistCore
import SwiftUI

// The panels under the board, one per phase. Each is laid out in a 361×384 area starting at y = 452 of
// the mockup: the info panel at the top, the hand at +120, the buttons at +264 and a footnote at +334.

/// The dark rounded box with the current card, move or briefing.
private struct InfoBox<Content: View>: View {
    let role: Role
    var accent: Color?
    @ViewBuilder let content: Content

    @Environment(\.stageScale) private var s

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20 * s)
        VStack(alignment: .leading, spacing: 8 * s) { content }
            .padding(.horizontal, 14 * s)
            .padding(.vertical, 12 * s)
            .frame(width: 361 * s, alignment: .leading)
            .background(role == .thief ? Color(red: 16 / 255, green: 8 / 255, blue: 36 / 255, opacity: 0.84) : Color(red: 6 / 255, green: 14 / 255, blue: 32 / 255, opacity: 0.82), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(accent ?? (role == .thief ? Color(red: 1, green: 214 / 255, blue: 107 / 255, opacity: 0.55) : Color(red: 156 / 255, green: 198 / 255, blue: 1, opacity: 0.35)), lineWidth: 1.5 * s))
            .foregroundStyle(.white)
    }
}

private struct PanelText: View {
    let text: String
    let role: Role

    @Environment(\.stageScale) private var s

    var body: some View {
        Text(text)
            .font(BrandFont.nunito(13 * s, 700))
            .lineSpacing(2.5 * s)
            .foregroundStyle(role == .thief ? Color(hex: 0xE2DAF6) : Color(hex: 0xD6E4F2))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Footnote: View {
    let text: String
    let role: Role

    @Environment(\.stageScale) private var s

    var body: some View {
        Text(text)
            .font(BrandFont.nunito(12 * s, 700))
            .foregroundStyle(role == .thief ? Color(hex: 0xA99FCB) : Color(hex: 0x8FA6C8))
            .multilineTextAlignment(.center)
            .frame(width: 361 * s)
            .offset(y: 334 * s)
    }
}

/// The three prep-point hexagons: spent on other cards (dim), this card's cost (gold), still free (outline).
private struct PointPips: View {
    let spentElsewhere: Int
    let highlighted: Int
    let label: String

    @Environment(\.stageScale) private var s

    var body: some View {
        let box = CGRect(x: 0, y: 0, width: 38, height: 42)
        let hexagon = "M19 3.6L33.6 12.1v17.8L19 38.4 4.4 29.9V12.1z"
        HStack(spacing: 4 * s) {
            ForEach(0..<MatchRules.prepPoints, id: \.self) { index in
                let gold = index >= spentElsewhere && index < spentElsewhere + highlighted
                let spent = index < spentElsewhere
                ZStack {
                    SVGShape(hexagon, viewBox: box).fill(gold ? Color(hex: 0xFFC94A) : .white.opacity(spent ? 0.04 : 0.1))
                    SVGShape(hexagon, viewBox: box).stroke(gold ? Color(hex: 0xFFF1B8) : .white.opacity(spent ? 0.18 : 0.4), lineWidth: 1.4 * s)
                }
                .frame(width: 20 * s, height: 22 * s)
            }
            Text(label)
                .font(BrandFont.nunito(12.5 * s, 900))
                .foregroundStyle(Color(hex: 0xFFE7A8))
                .padding(.leading, 4 * s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// A chunky key that sinks onto its edge when pressed, like PLAY on home.
struct ChunkyButtonStyle: ButtonStyle {
    let colors: [Color]
    let edge: Color
    let text: Color
    let scale: CGFloat

    static func gold(_ scale: CGFloat) -> Self {
        Self(colors: [Color(hex: 0xFFE27A), Color(hex: 0xF2B705)], edge: Color(hex: 0x8A6200), text: Color(hex: 0x2A1A06), scale: scale)
    }

    static func role(_ role: Role, _ scale: CGFloat) -> Self {
        role == .thief
            ? Self(colors: [Color(hex: 0xF27A3A), Color(hex: 0xC23A16)], edge: Color(hex: 0x7E2410), text: .white, scale: scale)
            : Self(colors: [Color(hex: 0x4FA3FF), Color(hex: 0x1F5FD0)], edge: Color(hex: 0x0E3A80), text: .white, scale: scale)
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16 * scale)
        configuration.label
            .font(BrandFont.baloo(19 * scale, 800))
            .foregroundStyle(text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 52 * scale)
            .background(shape.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)))
            .offset(y: configuration.isPressed ? 4 * scale : 0)
            .background(shape.fill(edge).offset(y: 5 * scale))
            .shadow(color: .black.opacity(0.35), radius: 12 * scale, y: 12 * scale)
            .animation(.spring(duration: 0.18, bounce: 0.3), value: configuration.isPressed)
    }
}

/// The quiet outlined button beside the main one.
struct OutlineButtonStyle: ButtonStyle {
    let scale: CGFloat
    var lit = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16 * scale)
        configuration.label
            .font(BrandFont.nunito(15 * scale, 800))
            .foregroundStyle(lit ? Color(hex: 0x2A1A06) : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 52 * scale)
            .background(lit ? AnyShapeStyle(Color(hex: 0xFFE15C)) : AnyShapeStyle(.white.opacity(configuration.isPressed ? 0.16 : 0.08)), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(lit ? 0.9 : 0.3), lineWidth: 1.5 * scale))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}

// MARK: - Briefing

struct BriefingPanel: View {
    let model: MatchModel

    @Environment(\.stageScale) private var s

    var body: some View {
        let role = model.role
        ZStack(alignment: .topLeading) {
            InfoBox(role: role) {
                HStack(alignment: .top, spacing: 12 * s) {
                    VStack(alignment: .leading, spacing: 8 * s) {
                        Text("YOU'RE THE")
                            .font(BrandFont.nunito(11 * s, 900))
                            .tracking(1.4 * s)
                            .foregroundStyle(role == .thief ? Color(hex: 0xFFD592) : Color(hex: 0xBFE0FF))
                        HStack(spacing: 8 * s) {
                            SVGShape(role.emblem).fill(role.color).frame(width: 26 * s, height: 26 * s)
                            Text(role.title.uppercased()).font(BrandFont.baloo(30 * s, 800))
                        }
                        PanelText(text: goal, role: role)
                    }
                    Image(role == .thief ? "character-thief" : "character-police")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92 * s, height: 156 * s)
                        .padding(.bottom, -12 * s)
                        .accessibilityHidden(true)
                }
            }
            .transition(.scale(scale: 0.92).combined(with: .opacity))

            Button("Ready") { model.skipAhead() }
                .buttonStyle(ChunkyButtonStyle.gold(s))
                .frame(width: 361 * s)
                .offset(y: 264 * s)
                .accessibilityHint("Starts prep now")

            Footnote(text: "Prep starts in \(model.secondsLeft) s. \(role == .thief ? "The police" : "The thief") is preparing too.", role: role)
        }
    }

    private var goal: String {
        model.role == .thief
            ? "Rob one chest, then escape by boat through an exit. You know the exits; the chests are hidden. Fishing nets hide you, barrels block the way, and the two sea caves are a tunnel."
            : "Catch the thief before turn \(MatchRules.chaseTurns) ends. You know the chests; the exits are hidden. Fishing nets hide the thief, barrels block the way, and the two sea caves are a tunnel."
    }
}

// MARK: - Prep

struct PrepPanel: View {
    let model: MatchModel

    @Environment(\.stageScale) private var s

    var body: some View {
        let role = model.role
        ZStack(alignment: .topLeading) {
            InfoBox(role: role, accent: model.selectedCard == .blueprintScan ? Color(red: 110 / 255, green: 231 / 255, blue: 1, opacity: 0.45) : nil) {
                HStack(alignment: .center) {
                    Text(title)
                        .font(BrandFont.baloo(19 * s, 800))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8 * s)
                    pips
                }
                if model.phase == .prepLocked {
                    HStack(spacing: 8 * s) {
                        ProgressView().tint(.white)
                        PanelText(text: "Waiting for the \(role.other.title.lowercased()) to lock in…", role: role)
                    }
                } else {
                    PanelText(text: detail, role: role)
                }
            }

            hand
                .offset(y: 120 * s)

            if model.phase == .prep {
                buttons
                    .frame(width: 361 * s)
                    .offset(y: 264 * s)
            }

            Footnote(text: model.selectedCard == .blueprintScan ? "The police never learns which area you scanned." : "Unplayed cards and points are lost when prep ends.", role: role)
        }
    }

    private var spentElsewhere: Int {
        model.plays.filter { $0.card != model.selectedCard }.reduce(0) { $0 + $1.card.cost }
    }

    private var pips: some View {
        let card = model.selectedCard
        let cost = card?.cost ?? 0
        let label: String = if let card, !model.selectedIsPlaced {
            "\(card.cost) of \(model.pointsLeft) left"
        } else {
            "\(model.pointsLeft) of \(MatchRules.prepPoints) left"
        }
        return PointPips(spentElsewhere: spentElsewhere, highlighted: model.selectedIsPlaced ? cost : (card == nil ? 0 : cost), label: label)
    }

    private var title: String {
        if model.phase == .prepLocked { return "Locked in" }
        guard let card = model.selectedCard else { return model.role == .police ? "Place your security" : "Plan your heist" }
        if let tile = model.targetTile { return "\(card.name) on \(Harbor.name(tile))" }
        return card.name
    }

    private var detail: String {
        guard let card = model.selectedCard else {
            return "Pick a card, then tap where it goes on the board. Lock in when you're done; the faster player waits for the other."
        }
        if model.selectedIsPlaced {
            return "Placed. Take it back to get \(card.cost) \(card.cost == 1 ? "point" : "points") back."
        }
        return card.effect
    }

    private var hand: some View {
        HStack(spacing: (361 - 4 * 84) / 3 * s) {
            ForEach(model.hand) { card in
                let placed = model.plays.contains { $0.card == card }
                let look: MatchCard.Look = model.selectedCard == card ? .selected
                    : placed ? .placed
                    : card.cost > model.pointsLeft ? .locked : .normal
                Button { model.select(card) } label: {
                    MatchCard(card: card, role: model.role, look: look, width: 84 * s)
                }
                .buttonStyle(PressableStyle())
                .disabled(model.phase != .prep)
                .accessibilityLabel("\(card.name), \(card.cost) \(card.cost == 1 ? "point" : "points"), \(placed ? "placed" : look == .locked ? "not enough points" : look == .selected ? "selected" : "ready")")
                .accessibilityHint(card.effect)
            }
        }
        .frame(width: 361 * s, height: 134 * s, alignment: .bottom)
        .opacity(model.phase == .prepLocked ? 0.6 : 1)
    }

    @ViewBuilder private var buttons: some View {
        if let card = model.selectedCard {
            HStack(spacing: 10 * s) {
                Button("Cancel") { model.cancelSelection() }
                    .buttonStyle(OutlineButtonStyle(scale: s))
                    .frame(width: 118 * s)
                if model.selectedIsPlaced {
                    Button("Take back") { model.takeBack() }
                        .buttonStyle(ChunkyButtonStyle.gold(s))
                } else {
                    Button(placeLabel(card)) { model.place() }
                        .buttonStyle(ChunkyButtonStyle.gold(s))
                        .disabled(!model.canPlace)
                        .opacity(model.canPlace ? 1 : 0.5)
                }
            }
        } else {
            Button(model.pointsLeft == MatchRules.prepPoints ? "Lock in · nothing placed" : "Lock in") { model.lockInPrep() }
                .buttonStyle(ChunkyButtonStyle.gold(s))
        }
    }

    private func placeLabel(_ card: CardID) -> String {
        if card.target == .none { return "Play \(card.name)" }
        guard let tile = model.targetTile else { return "Tap a tile" }
        return card == .blueprintScan ? "Scan \(Harbor.name(tile))" : "Place on \(Harbor.name(tile))"
    }
}

// MARK: - Intel

struct IntelPanel: View {
    let model: MatchModel

    @Environment(\.stageScale) private var s

    var body: some View {
        let role = model.role
        ZStack(alignment: .topLeading) {
            InfoBox(role: role, accent: Color(red: 110 / 255, green: 231 / 255, blue: 1, opacity: 0.5)) {
                HStack {
                    Text(role == .thief ? "Intel" : "Security report").font(BrandFont.baloo(19 * s, 800))
                    Spacer()
                    Text("CHASE IN \(model.secondsLeft)")
                        .font(BrandFont.nunito(11 * s, 900))
                        .tracking(1.2 * s)
                        .foregroundStyle(Color(hex: 0x9FF0FF))
                        .contentTransition(.numericText(countsDown: true))
                }
                ForEach(model.intel) { line in
                    HStack(alignment: .top, spacing: 10 * s) {
                        if let card = line.card {
                            Image(card.art)
                                .resizable()
                                .frame(width: 34 * s, height: 34 * s)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 2 * s) {
                            if let card = line.card {
                                Text(card.name.uppercased())
                                    .font(BrandFont.nunito(10 * s, 900))
                                    .tracking(1.2 * s)
                                    .foregroundStyle(role.color)
                            }
                            PanelText(text: line.text, role: role)
                        }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            if let card = model.chaseCards.first {
                HStack(spacing: 12 * s) {
                    MatchCard(card: card, role: role, width: 84 * s)
                    VStack(alignment: .leading, spacing: 4 * s) {
                        Text("YOUR CHASE CARD")
                            .font(BrandFont.nunito(11 * s, 900))
                            .tracking(1.3 * s)
                            .foregroundStyle(role == .thief ? Color(hex: 0xFFD592) : Color(hex: 0xBFE0FF))
                        Text(card.name).font(BrandFont.baloo(19 * s, 800)).foregroundStyle(.white)
                        PanelText(text: card.effect, role: role)
                    }
                }
                .frame(width: 361 * s, alignment: .leading)
                .offset(y: 160 * s)
            }

            Footnote(text: role == .thief ? "The police never learns what you scanned." : "The thief's bushes and lookouts stay hidden until you see them.", role: role)
        }
    }
}

// MARK: - Chase

struct ChasePanel: View {
    let model: MatchModel
    let onChat: () -> Void

    @Environment(\.stageScale) private var s

    var body: some View {
        let role = model.role
        let round = model.round
        ZStack(alignment: .topLeading) {
            InfoBox(role: role, accent: role == .thief ? Color(red: 1, green: 214 / 255, blue: 107 / 255, opacity: 0.6) : Color(red: 156 / 255, green: 198 / 255, blue: 1, opacity: 0.5)) {
                HStack {
                    Text(model.phase == .resolving ? "MOVES PLAY OUT" : "YOUR MOVE")
                        .font(BrandFont.nunito(11 * s, 900))
                        .tracking(1.3 * s)
                        .foregroundStyle(role == .thief ? Color(hex: 0xFFD592) : Color(hex: 0xBFE0FF))
                    Spacer()
                    Text("Sight \(MatchRules.sight) · fog beyond")
                        .font(BrandFont.nunito(12 * s, 800))
                        .foregroundStyle(Color(hex: 0xE2DAF6))
                }
                Text(moveText)
                    .font(BrandFont.baloo(22 * s, 800))
                    .contentTransition(.opacity)
                PanelText(text: hint, role: role)
                    .lineLimit(3)
            }

            HStack(alignment: .center, spacing: 12 * s) {
                cards
                VStack(alignment: .leading, spacing: 4 * s) {
                    Text("CHASE CARDS · \(model.chaseCards.count)")
                        .font(BrandFont.nunito(11 * s, 900))
                        .tracking(1.3 * s)
                        .foregroundStyle(role == .thief ? Color(hex: 0xFFD592) : Color(hex: 0xBFE0FF))
                    PanelText(text: cardHint, role: role)
                }
            }
            .frame(width: 361 * s, height: 130 * s, alignment: .leading)
            .offset(y: 122 * s)

            HStack(spacing: 10 * s) {
                Button(action: onChat) {
                    Image(systemName: "ellipsis.bubble")
                        .font(.system(size: 21 * s, weight: .semibold))
                }
                .buttonStyle(OutlineButtonStyle(scale: s))
                .frame(width: 52 * s)
                .accessibilityLabel("Quick chat")

                Button("Wait") { model.chooseWait() }
                    .buttonStyle(OutlineButtonStyle(scale: s, lit: model.move == .wait))
                    .frame(width: 92 * s)
                    .accessibilityLabel("Wait on \(Harbor.name(round.position(of: role))) this turn")

                Button(lockLabel) { model.lockMove() }
                    .buttonStyle(ChunkyButtonStyle.role(role, s))
                    .disabled(model.move == .none || model.phase != .chase)
                    .opacity(model.move == .none || model.phase != .chase ? 0.55 : 1)
            }
            .frame(width: 361 * s)
            .offset(y: 264 * s)
            .disabled(model.phase != .chase)

            let turnsLeft = max(0, MatchRules.chaseTurns - round.turn + 1)
            Footnote(text: "\(turnsLeft) \(turnsLeft == 1 ? "turn" : "turns") left · You \(model.score.you) – \(model.score.bot) Bot", role: role)
        }
    }

    private var cards: some View {
        HStack(spacing: 8 * s) {
            if model.chaseCards.isEmpty {
                RoundedRectangle(cornerRadius: 13 * s)
                    .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5 * s, dash: [6 * s, 5 * s]))
                    .frame(width: 84 * s, height: 120 * s)
                    .overlay(Image(systemName: "questionmark").font(.system(size: 22 * s, weight: .bold)).foregroundStyle(.white.opacity(0.3)))
            }
            ForEach(Array(model.chaseCards.prefix(2).enumerated()), id: \.offset) { _, card in
                Button { model.play(card) } label: {
                    MatchCard(card: card, role: model.role, look: model.armedCard == card ? .selected : (model.instantPlayed || model.armedCard != nil ? .locked : .normal), width: 84 * s)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(card.name). \(card.effect)")
                .accessibilityHint(card.isInstant ? "Plays at once" : "Plays with this turn's move")
            }
        }
    }

    private var moveText: String {
        let here = Harbor.name(model.round.position(of: model.role))
        if model.phase == .resolving { return "Moving…" }
        switch model.move {
        case .none: return "Pick a move"
        case .wait: return "Stay on \(here)"
        case .tile(let tile):
            let path = model.reach[tile] ?? [tile]
            return ([here] + path.map(Harbor.name)).joined(separator: " → ")
        }
    }

    private var lockLabel: String {
        switch model.move {
        case .none: "Pick a tile"
        case .wait: "Lock · wait"
        case .tile(let tile): "Lock move · \(Harbor.name(tile))"
        }
    }

    private var hint: String {
        let round = model.round
        var parts: [String] = []
        switch model.role {
        case .thief:
            if round.hasLoot { parts.append("You have the loot: reach an exit.") }
            if round.thiefSeesPolice() {
                parts.append("The police is on \(Harbor.name(round.police))!")
            } else if let seen = round.thiefSawPolice {
                parts.append("The police was last seen near \(Harbor.name(seen.tile)) \(ago(seen.turn)).")
            } else {
                parts.append("No sign of the police yet.")
            }
        case .police:
            if let alarm = round.alarm { parts.append("Alarm: the chest on \(Harbor.name(alarm.tile)) was robbed \(ago(alarm.turn)).") }
            if round.policeSeesThief() {
                parts.append("The thief is on \(Harbor.name(round.thief))!")
            } else if let seen = round.policeSawThief {
                parts.append("The thief was last seen near \(Harbor.name(seen.tile)) \(ago(seen.turn)).")
            } else {
                parts.append("No sign of the thief yet.")
            }
        }
        if model.phase == .chase { parts.append("Glowing tiles are the moves you can make.") }
        return parts.joined(separator: " ")
    }

    private func ago(_ turn: Int) -> String {
        let turns = model.round.turn - turn
        return turns <= 0 ? "this turn" : turns == 1 ? "1 turn ago" : "\(turns) turns ago"
    }

    private var cardHint: String {
        if let card = model.armedCard { return "\(card.name) is ready: it plays with this move." }
        if model.instantPlayed { return "Card played this turn. One card per turn." }
        if model.chaseCards.isEmpty { return "No chase cards. Mystery boxes deal more." }
        return "Tap to play it this turn. Mystery boxes deal more. One card per turn."
    }
}
