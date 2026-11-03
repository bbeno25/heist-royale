import SwiftUI

// Overlays on the match screens from the design: 3.18 leave match and 3.14 quick chat, plus the chat
// bubbles. Laid out in the mockups' 393×852 points on the stage.

/// "Leave the match?": a forfeit warning over the dimmed match, with the other menu items under it.
struct LeaveOverlay: View {
    let model: MatchModel
    let onKeepPlaying: () -> Void

    @Environment(\.stageScale) private var s

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 4 / 255, green: 6 / 255, blue: 18 / 255, opacity: 0.72)
                .background(.ultraThinMaterial)
                .onTapGesture(perform: onKeepPlaying)
                .accessibilityHidden(true)

            VStack(spacing: 12 * s) {
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 26 * s, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64 * s, height: 64 * s)
                    .background(RadialGradient(colors: [Color(hex: 0xFF8FA3), Color(hex: 0xC42E3A)], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 40 * s), in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3 * s))
                    .shadow(color: Color(hex: 0xC42E3A, opacity: 0.45), radius: 8 * s, y: 6 * s)
                    .accessibilityHidden(true)
                Text("Leave the match?").font(BrandFont.baloo(26 * s, 800))
                Text("You'll forfeit the rest of the rounds and the match counts as a loss.")
                    .font(BrandFont.nunito(14.5 * s, 700))
                    .foregroundStyle(Color(hex: 0xE2EAF8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 8 * s) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Color(hex: 0x9CC6FF))
                    Text("Leaving often lowers your matchmaking priority for a while.")
                        .font(BrandFont.nunito(12.5 * s, 700))
                        .foregroundStyle(Color(hex: 0xD6E4F2))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12 * s)
                .padding(.vertical, 10 * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14 * s))
                Text("Classic · Round \(model.roundNumber) of \(MatchRules.rounds) · Score \(model.score.you)–\(model.score.bot)")
                    .font(BrandFont.nunito(12 * s, 800))
                    .foregroundStyle(Color(hex: 0xA9BEDD))
                Button("Keep playing", action: onKeepPlaying)
                    .buttonStyle(ChunkyButtonStyle.gold(s))
                    .padding(.top, 4 * s)
                Button { model.leave() } label: {
                    Text("Leave and forfeit")
                        .font(BrandFont.nunito(15 * s, 900))
                        .foregroundStyle(Color(hex: 0xFFC2CC))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48 * s)
                        .overlay(RoundedRectangle(cornerRadius: 16 * s).strokeBorder(Color(hex: 0xFF8FA3), lineWidth: 2 * s))
                        .contentShape(RoundedRectangle(cornerRadius: 16 * s))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Leave and forfeit the match")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20 * s)
            .padding(.top, 22 * s)
            .padding(.bottom, 20 * s)
            .background(LinearGradient(colors: [Color(hex: 0x1C2D5E), Color(hex: 0x0E1838)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 26 * s))
            .overlay(RoundedRectangle(cornerRadius: 26 * s).strokeBorder(.white.opacity(0.2), lineWidth: 1.5 * s))
            .shadow(color: .black.opacity(0.55), radius: 25 * s, y: 24 * s)
            .padding(.horizontal, 28 * s)
            .padding(.top, 214 * s)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)

            VStack(spacing: 8 * s) {
                Text("ALSO IN THE MENU")
                    .font(BrandFont.nunito(11 * s, 900))
                    .tracking(1.3 * s)
                    .foregroundStyle(Color(hex: 0xA9BEDD))
                HStack(spacing: 8 * s) {
                    menuButton("Rules", label: "Card rules")
                    menuButton("Sound", label: "Sound and haptics")
                    menuButton("Report", label: "Report player")
                }
                Text("The timer keeps running while this is open.")
                    .font(BrandFont.nunito(12 * s, 700))
                    .foregroundStyle(Color(hex: 0xA9BEDD))
            }
            .padding(.horizontal, 28 * s)
            .padding(.top, 640 * s)
        }
    }

    private func menuButton(_ title: String, label: String) -> some View {
        Button {} label: {
            Text(title)
                .font(BrandFont.nunito(13 * s, 800))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48 * s)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14 * s))
                .overlay(RoundedRectangle(cornerRadius: 14 * s).strokeBorder(.white.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Quick chat: preset phrases and emotes only, with a mute switch for the opponent's messages.
struct QuickChatOverlay: View {
    let model: MatchModel
    let onClose: () -> Void

    @Environment(\.stageScale) private var s

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 5 / 255, green: 4 / 255, blue: 15 / 255, opacity: 0.55)
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12 * s) {
                Capsule().fill(.white.opacity(0.35)).frame(width: 40 * s, height: 5 * s).frame(maxWidth: .infinity)
                HStack {
                    VStack(alignment: .leading, spacing: 1 * s) {
                        Text("Quick chat").font(BrandFont.baloo(22 * s, 800))
                        Text("Preset messages only · safe for all ages")
                            .font(BrandFont.nunito(12 * s, 700))
                            .foregroundStyle(Color(hex: 0xC8BDE6))
                    }
                    Spacer()
                    Toggle(isOn: Binding(get: { model.muted }, set: { _ in model.toggleMute() })) {
                        Text("Mute").font(BrandFont.nunito(13 * s, 800))
                    }
                    .toggleStyle(.switch)
                    .tint(Color(hex: 0xFF8FA3))
                    .fixedSize()
                    .padding(.leading, 10 * s)
                    .padding(.trailing, 4 * s)
                    .frame(height: 44 * s)
                    .background(.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                    .accessibilityLabel("Mute \(model.opponent.name)'s messages")
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8 * s), GridItem(.flexible(), spacing: 8 * s)], spacing: 8 * s) {
                    ForEach(MatchModel.chatPhrases, id: \.self) { phrase in
                        Button { send(.phrase(phrase)) } label: {
                            Text(phrase)
                                .font(BrandFont.baloo(17 * s, 800))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48 * s)
                                .background(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 14 * s))
                                .overlay(RoundedRectangle(cornerRadius: 14 * s).strokeBorder(.white.opacity(0.22), lineWidth: 1.5 * s))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Send: \(phrase)")
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("EMOTES")
                        .font(BrandFont.nunito(11 * s, 900))
                        .tracking(1.3 * s)
                        .foregroundStyle(Color(hex: 0xFFD592))
                    Spacer()
                    Text("More in the Wardrobe")
                        .font(BrandFont.nunito(12 * s, 700))
                        .foregroundStyle(Color(hex: 0xC8BDE6))
                }
                HStack(spacing: 8 * s) {
                    ForEach(Emote.allCases, id: \.self) { emote in
                        Button { send(.emote(emote)) } label: {
                            EmoteIcon(emote: emote, size: 30 * s)
                                .frame(maxWidth: .infinity)
                                .frame(height: 60 * s)
                                .background(RadialGradient(colors: emote.colors, center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 50 * s), in: RoundedRectangle(cornerRadius: 16 * s))
                                .overlay(RoundedRectangle(cornerRadius: 16 * s).strokeBorder(.white.opacity(0.3), lineWidth: 2 * s))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Send emote: \(emote.label)")
                    }
                    Button {} label: {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20 * s, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .frame(height: 60 * s)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16 * s))
                            .overlay(RoundedRectangle(cornerRadius: 16 * s).strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 2 * s, dash: [6 * s, 4 * s])))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Locked emote. Get it in the Wardrobe")
                }
                Text("Short pause between messages. Muting hides their messages for the rest of the match.")
                    .font(BrandFont.nunito(11.5 * s, 700))
                    .foregroundStyle(Color(hex: 0xB8AEDA))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16 * s)
            .padding(.top, 8 * s)
            .frame(width: 393 * s, height: 430 * s, alignment: .top)
            .background(LinearGradient(colors: [Color(hex: 0x2A1C55), Color(hex: 0x160F33)], startPoint: .top, endPoint: .bottom), in: UnevenRoundedRectangle(topLeadingRadius: 28 * s, topTrailingRadius: 28 * s))
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.18)).frame(height: 1).padding(.horizontal, 20 * s) }
            .shadow(color: .black.opacity(0.45), radius: 15 * s, y: -12 * s)
            .padding(.top, 422 * s)
            .transition(.move(edge: .bottom))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func send(_ message: ChatMessage) {
        guard model.canChat else { return }
        model.send(message)
        onClose()
    }
}

/// An emote's picture: an SF Symbol, or "GG".
struct EmoteIcon: View {
    let emote: Emote
    let size: CGFloat

    var body: some View {
        if let symbol = emote.symbol {
            Image(systemName: symbol).font(.system(size: size * 0.9, weight: .bold)).foregroundStyle(.white)
        } else {
            Text("GG").font(BrandFont.baloo(size * 0.75, 800)).foregroundStyle(.white)
        }
    }
}

/// The two latest chat messages: yours at the top left, the opponent's at the top right.
struct ChatBubbles: View {
    let model: MatchModel

    @Environment(\.stageScale) private var s

    var body: some View {
        ZStack(alignment: .top) {
            if let bubble = model.myBubble {
                bubbleView(bubble, name: "YOU", role: model.role)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18 * s)
                    .transition(.scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity))
            }
            if let bubble = model.theirBubble {
                bubbleView(bubble, name: model.opponent.name.uppercased(), role: model.role.other)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 18 * s)
                    .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .padding(.top, 140 * s)
        .allowsHitTesting(false)
    }

    private func bubbleView(_ bubble: ChatBubble, name: String, role: Role) -> some View {
        let mine = bubble.fromYou
        let shape = UnevenRoundedRectangle(topLeadingRadius: 16 * s, bottomLeadingRadius: mine ? 4 * s : 16 * s, bottomTrailingRadius: mine ? 16 * s : 4 * s, topTrailingRadius: 16 * s)
        let content = VStack(alignment: .leading, spacing: 1 * s) {
            HStack(spacing: 4 * s) {
                SVGShape(role.emblem).fill(role.color).frame(width: 11 * s, height: 11 * s)
                Text(name).font(BrandFont.nunito(10.5 * s, 900)).tracking(0.6 * s)
            }
            .foregroundStyle(role == .thief ? Color(hex: 0x8A5A12) : Color(hex: 0x1F4FA0))
            switch bubble.message {
            case .phrase(let text):
                Text(text).font(BrandFont.baloo(18 * s, 800)).foregroundStyle(Color(hex: 0x13294B))
            case .emote(let emote):
                EmoteIcon(emote: emote, size: 22 * s)
                    .frame(width: 40 * s, height: 32 * s)
                    .background(RadialGradient(colors: emote.colors, center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 30 * s), in: RoundedRectangle(cornerRadius: 10 * s))
            }
        }
        .padding(.horizontal, 12 * s)
        .padding(.top, 8 * s)
        .padding(.bottom, 9 * s)
        .background(.white, in: shape)
        .shadow(color: .black.opacity(0.4), radius: 9 * s, y: 8 * s)
        .frame(maxWidth: 220 * s, alignment: mine ? .leading : .trailing)

        return HStack(alignment: .bottom, spacing: 6 * s) {
            if mine { FaceAvatar(role: role, size: 40) }
            content
            if !mine { FaceAvatar(role: role, size: 40) }
        }
        .accessibilityElement(children: .combine)
    }
}
