import SwiftUI

/// The match: full-screen screens between rounds (coin flip, role reveal, round result, series, match end),
/// and in a round the top bar, the 3D board and the panel for the current phase, laid out on the mockups'
/// 393×852 points. Chat bubbles, quick chat and the leave dialog sit on top.
struct MatchView: View {
    let model: MatchModel

    @State private var showsLeave = false
    @State private var showsChat = false

    private static let design = CGSize(width: 393, height: 852)

    var body: some View {
        GeometryReader { geometry in
            let stage = Stage(designSize: Self.design, screen: geometry.size)
            let s = stage.scale
            ZStack(alignment: .topLeading) {
                if model.phase.isInterstitial {
                    interstitial(stage)
                        .transition(.opacity)
                } else {
                    roundScreen(stage)
                        .transition(.opacity)
                }

                Group {
                    ChatBubbles(model: model)
                    if showsChat {
                        QuickChatOverlay(model: model) { withAnimation(.spring(duration: 0.35)) { showsChat = false } }
                            .transition(.opacity)
                    }
                    if showsLeave {
                        LeaveOverlay(model: model) { withAnimation(.easeOut(duration: 0.25)) { showsLeave = false } }
                            .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    }
                }
                .environment(\.stageScale, s)
                .frame(width: stage.size.width, height: stage.size.height, alignment: .topLeading)
                .offset(x: stage.origin.x, y: stage.origin.y)
            }
            .animation(.easeInOut(duration: 0.4), value: model.phase.isInterstitial)
        }
        .ignoresSafeArea()
        .background(Color(hex: 0x060F1E))
        .task { model.start() }
        .sensoryFeedback(trigger: model.feedback) { _, new in
            switch new.kind {
            case .selection: .selection
            case .lock: .impact(weight: .medium)
            case .alert: .warning
            case .success: .success
            case .failure: .error
            }
        }
    }

    @ViewBuilder private func interstitial(_ stage: Stage) -> some View {
        switch model.phase {
        case .coinFlip: CoinFlipScreen(model: model, stage: stage)
        case .roleReveal: RoleRevealScreen(model: model, stage: stage)
        case .roundResult: RoundResultScreen(model: model, stage: stage)
        case .series: SeriesScreen(model: model, stage: stage, onChat: openChat)
        default: MatchEndScreen(model: model, stage: stage)
        }
    }

    private func roundScreen(_ stage: Stage) -> some View {
        let s = stage.scale
        return ZStack(alignment: .topLeading) {
            SeaBackground(role: model.role, chase: model.phase == .chase || model.phase == .resolving)

            ZStack(alignment: .topLeading) {
                HarborBoard(scene: model.board) { model.tap($0) }
                    .stageFrame(x: 0, y: 116, width: 393, height: 327, scale: s)

                MatchTopBar(model: model, onMenu: { withAnimation(.easeOut(duration: 0.25)) { showsLeave = true } })
                    .stageFrame(x: 0, y: 50, width: 393, height: 72, scale: s)

                NoteBanner(note: model.toast)
                    .frame(width: 393 * s)
                    .offset(y: 130 * s)

                lowerPanel
                    .frame(width: 361 * s, height: 384 * s, alignment: .top)
                    .offset(x: 16 * s, y: 452 * s)
            }
            .environment(\.stageScale, s)
            .frame(width: stage.size.width, height: stage.size.height, alignment: .topLeading)
            .offset(x: stage.origin.x, y: stage.origin.y)
        }
    }

    private func openChat() {
        withAnimation(.spring(duration: 0.35)) { showsChat = true }
    }

    @ViewBuilder private var lowerPanel: some View {
        switch model.phase {
        case .briefing:
            BriefingPanel(model: model)
        case .prep, .prepLocked:
            PrepPanel(model: model)
        case .intel:
            IntelPanel(model: model)
        default:
            ChasePanel(model: model, onChat: openChat)
        }
    }
}

/// The sea behind the board: harbour teal at the top fading to night at the bottom (purple while the
/// thief is on the move, navy otherwise), as in the mockups.
private struct SeaBackground: View {
    let role: Role
    let chase: Bool

    var body: some View {
        let thiefChase = chase && role == .thief
        LinearGradient(stops: [
            .init(color: Color(hex: 0x11748E), location: 0),
            .init(color: Color(hex: 0x178BA4), location: 0.352),
            .init(color: Color(hex: 0x0E5A74), location: 0.534),
            .init(color: thiefChase ? Color(hex: 0x160C30) : Color(hex: 0x081C30), location: 0.657),
            .init(color: thiefChase ? Color(hex: 0x0C0720) : Color(hex: 0x060F1E), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .animation(.easeInOut(duration: 0.6), value: thiefChase)
    }
}

/// Menu, role chip and round, the phase, and the countdown ring.
private struct MatchTopBar: View {
    let model: MatchModel
    let onMenu: () -> Void

    @Environment(\.stageScale) private var s

    var body: some View {
        let role = model.role
        HStack(spacing: 8 * s) {
            Button(action: onMenu) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 19 * s, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44 * s, height: 44 * s)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14 * s))
                    .overlay(RoundedRectangle(cornerRadius: 14 * s).strokeBorder(.white.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Match menu: leave match")

            VStack(alignment: .leading, spacing: 3 * s) {
                HStack(spacing: 6 * s) {
                    SVGShape(role.emblem).fill(role.color).frame(width: 18 * s, height: 18 * s)
                    Text(role.title.uppercased())
                        .font(BrandFont.nunito(12 * s, 900))
                        .tracking(1.2 * s)
                        .foregroundStyle(role == .thief ? Color(hex: 0xFFD592) : Color(hex: 0xBFE0FF))
                }
                .padding(.leading, 4 * s)
                .padding(.trailing, 9 * s)
                .frame(height: 26 * s)
                .background(role.color.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(role.color, lineWidth: 1.5 * s))
                Text(model.roundLabel)
                    .font(BrandFont.nunito(11 * s, 700))
                    .foregroundStyle(Color(hex: 0xC9D3E8))
                    .lineLimit(1)
            }
            .frame(width: 100 * s, alignment: .leading)
            .accessibilityElement(children: .combine)

            VStack(spacing: 1 * s) {
                Text(title)
                    .font(BrandFont.baloo(18 * s, 800))
                    .lineLimit(1)
                Text(subtitle)
                    .font(BrandFont.nunito(11.5 * s, 700))
                    .foregroundStyle(Color(hex: 0xC9D3E8))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
            .accessibilityElement(children: .combine)

            TimerRing(seconds: model.secondsLeft, total: model.phaseLength, ticking: model.phase == .resolving || model.phase == .prepLocked)
        }
        .padding(.horizontal, 12 * s)
        .frame(maxHeight: .infinity)
        .background {
            LinearGradient(colors: [Color(hex: 0x080A1C, opacity: 0.78), Color(hex: 0x080A1C, opacity: 0.55)], startPoint: .top, endPoint: .bottom)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
        }
    }

    private var title: String {
        switch model.phase {
        case .briefing: return "Briefing"
        case .prep:
            guard let card = model.selectedCard else { return model.role == .police ? "Place security" : "Plan the heist" }
            if model.selectedIsPlaced { return card.name }
            return card == .blueprintScan ? "Aim your scan" : card.target == .none ? card.name : "Place \(card.name)"
        case .prepLocked: return "Locked in"
        case .intel: return "Intel reveal"
        case .chase, .resolving: return "Turn \(model.round.turn) of \(MatchRules.chaseTurns)"
        default: return ""
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .briefing: return "Pirate Harbor · new map"
        case .prep:
            guard let card = model.selectedCard, !model.selectedIsPlaced else {
                return "\(model.pointsLeft) of \(MatchRules.prepPoints) points left"
            }
            let tile = model.targetTile.map { Harbor.name($0) }
            if case .area(let radius) = card.target { return "Radius \(radius)" + (tile.map { " · on \($0)" } ?? " · tap the centre") }
            if card.target == .none { return "No target needed" }
            return "Tap a tile" + (tile.map { " · \($0)" } ?? "")
        case .prepLocked: return "Waiting for the \(model.role.other.title.lowercased())"
        case .intel: return "What your cards found"
        case .chase: return "Both move blind"
        case .resolving: return "Moves play out"
        default: return model.roundLabel
        }
    }
}

/// The countdown ring: yellow, red when time runs low, cyan while a turn resolves.
private struct TimerRing: View {
    let seconds: Int
    let total: Int
    let ticking: Bool

    @Environment(\.stageScale) private var s

    var body: some View {
        let fraction = ticking ? 1 : max(0, min(1, Double(seconds) / Double(max(total, 1))))
        let low = !ticking && seconds <= max(5, total / 4)
        let color = ticking ? Color(hex: 0x9FF0FF) : low ? Color(hex: 0xFF6B6B) : Color(hex: 0xFFE15C)
        ZStack {
            Circle().fill(.black.opacity(0.45)).frame(width: 48 * s, height: 48 * s)
            Circle().stroke(.white.opacity(0.15), lineWidth: 4.5 * s).frame(width: 44 * s, height: 44 * s)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 4.5 * s, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 44 * s, height: 44 * s)
                .animation(.linear(duration: 1), value: fraction)
            Text(ticking ? "TICK" : "\(seconds)")
                .font(BrandFont.baloo((ticking ? 12 : 20) * s, 800))
                .foregroundStyle(color)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: seconds)
        }
        .frame(width: 54 * s, height: 54 * s)
        .accessibilityElement()
        .accessibilityLabel(ticking ? "Resolving" : "\(seconds) seconds left")
    }
}

/// Alarms, pings and finds during the chase, just under the top bar.
private struct NoteBanner: View {
    let note: MatchNote?

    @Environment(\.stageScale) private var s

    var body: some View {
        VStack(spacing: 6 * s) {
            if let note {
                let tint = switch note.tone {
                case .alert: Color(hex: 0xFF6B81)
                case .good: Color(hex: 0x5BD07A)
                case .info: Color(hex: 0x6EE7FF)
                }
                HStack(spacing: 8 * s) {
                    Image(systemName: note.tone == .alert ? "exclamationmark.triangle.fill" : note.tone == .good ? "sparkles" : "info.circle.fill")
                        .font(.system(size: 14 * s, weight: .bold))
                        .foregroundStyle(tint)
                    Text(note.text)
                        .font(BrandFont.nunito(13 * s, 800))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14 * s)
                .padding(.vertical, 9 * s)
                .glassEffect(.regular.tint(Color(hex: 0x060A1C, opacity: 0.7)), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.7), lineWidth: 1.5 * s))
                .id(note.id)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.horizontal, 16 * s)
        .allowsHitTesting(false)
    }
}
