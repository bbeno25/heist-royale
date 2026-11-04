import HeistCore
import SwiftUI

/// Before a match: connecting to the server, finding an opponent (another player, or a bot after 10 s),
/// or why the match can't start. Laid out on the 393×852 stage like the other match screens.
struct LobbyScreen: View {
    let model: MatchModel
    let stage: Stage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let s = stage.scale
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
                    ScreenPill(text: "TOURNAMENT · RANKED")
                    Text(title).font(BrandFont.baloo(32 * s, 800))
                }
                .padding(.top, 60 * s)

                HStack(spacing: 18 * s) {
                    character("character-thief", role: .thief)
                    Text("VS").font(BrandFont.baloo(28 * s, 800)).foregroundStyle(Color(hex: 0xC8BDE6))
                    character("character-police", role: .police)
                }
                .padding(.top, 190 * s)
                .scaleEffect(pulse ? 1.03 : 1)
                .animation(reduceMotion || model.phase == .failed ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)

                VStack(spacing: 10 * s) {
                    Text(detail)
                        .font(BrandFont.nunito(16 * s, 800))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(hex: 0xE2DAF6))
                        .fixedSize(horizontal: false, vertical: true)
                    if model.phase != .failed {
                        ProgressView().tint(.white).controlSize(.large)
                    }
                }
                .padding(.horizontal, 32 * s)
                .padding(.top, 520 * s)

                buttons
                    .padding(.horizontal, 16 * s)
                    .padding(.top, 758 * s)
            }
            .foregroundStyle(.white)
        }
        .onAppear { pulse = true }
    }

    private var title: String {
        switch model.phase {
        case .failed: "Can't start the match"
        case .connecting: "Connecting…"
        default: model.opponentFound ? "Opponent found!" : "Finding an opponent"
        }
    }

    private var detail: String {
        switch model.phase {
        case .failed:
            return model.problem
        case .connecting:
            return "Reaching the game server."
        default:
            if model.opponentFound {
                let opponent = model.opponent
                return "\(opponent.name)\(opponent.isBot ? " (bot)" : "") · rating \(opponent.ratings.combined)\nGet ready…"
            }
            let wait = model.waitedSeconds
            return "Searching for \(wait) s. If no one is free, a bot takes the other seat after \(model.botAfterSeconds) s."
        }
    }

    @ViewBuilder private var buttons: some View {
        let s = stage.scale
        if model.phase == .failed {
            HStack(spacing: 10 * s) {
                Button("Home") { model.leave() }
                    .buttonStyle(OutlineButtonStyle(scale: s))
                    .frame(width: 118 * s)
                Button("Try again") { model.retry() }
                    .buttonStyle(ChunkyButtonStyle.gold(s))
            }
        } else {
            Button("Cancel") { model.leave() }
                .buttonStyle(OutlineButtonStyle(scale: s))
                .disabled(model.opponentFound)
                .opacity(model.opponentFound ? 0.4 : 1)
                .accessibilityHint("Stops searching and goes back home")
        }
    }

    private func character(_ image: String, role: Role) -> some View {
        let s = stage.scale
        return VStack(spacing: 8 * s) {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: 120 * s, height: 200 * s)
            RoleChip(role: role)
        }
        .accessibilityHidden(true)
    }
}
