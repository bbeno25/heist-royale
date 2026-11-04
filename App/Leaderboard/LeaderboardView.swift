import HeistCore
import SwiftUI

/// The leaderboards: overall, thief and police, worldwide or for the phone's country, with the player's
/// own place pinned at the bottom. There is no design for it yet, so it borrows the match screens' look:
/// dark panels, role colours, Baloo titles and Nunito text.
struct LeaderboardView: View {
    let account: PlayerAccount

    @State private var model: LeaderboardModel
    @Environment(\.dismiss) private var dismiss

    init(account: PlayerAccount) {
        self.account = account
        _model = State(initialValue: LeaderboardModel(account: account))
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            BoardPicker(selection: $model.board)
                .padding(.horizontal, 16)
            scopePicker
                .padding(.horizontal, 16)
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { yourPlace }
        .foregroundStyle(.white)
        .background {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: 0x2A1A5E), Color(hex: 0x100B26)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [model.board.accent.opacity(0.28), .clear], center: .top, startRadius: 0, endRadius: 320)
                    .frame(height: 320)
                    .animation(.easeInOut(duration: 0.4), value: model.board)
            }
            .ignoresSafeArea()
        }
        .task { model.load() }
        .onDisappear { model.stop() }
        .sensoryFeedback(.selection, trigger: model.board)
        .sensoryFeedback(.selection, trigger: model.scope)
    }

    // MARK: Header and pickers

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("LEADERBOARDS")
                    .font(BrandFont.baloo(30, 800))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(BrandFont.nunito(13, 700))
                    .foregroundStyle(Color(hex: 0xDCD3F2))
                    .contentTransition(.numericText())
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private var subtitle: String {
        guard let page = model.page else { return "Tournament · ranked" }
        let place = page.scope == .country ? (page.country.map(Flag.name) ?? "Your country") : "Worldwide"
        return "\(place) · \(page.players) ranked \(page.players == 1 ? "player" : "players")"
    }

    @ViewBuilder private var scopePicker: some View {
        HStack(spacing: 8) {
            ScopeChip(text: "Global", symbol: "globe", selected: model.scope == .global, accent: model.board.accent) {
                model.scope = .global
            }
            if let region = model.region {
                ScopeChip(text: Flag.name(region), flag: Flag.emoji(region), selected: model.scope == .country, accent: model.board.accent) {
                    model.scope = .country
                }
            }
            Spacer()
        }
    }

    // MARK: The board

    @ViewBuilder private var content: some View {
        if let page = model.page, !page.entries.isEmpty {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let problem = model.problem {
                        Text(problem)
                            .font(BrandFont.nunito(12.5, 700))
                            .foregroundStyle(Color(hex: 0xFFB4B4))
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(page.entries, id: \.playerId) { entry in
                        LeaderboardRow(entry: entry, board: page.board, isYou: entry.playerId == (page.you?.playerId ?? account.saved?.id))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.reload() }
        } else if model.page != nil {
            message(image: "icon-trophy", title: "No one is ranked here yet",
                    text: "Finish a ranked match to put your name on the board.")
        } else if let problem = model.problem {
            VStack(spacing: 14) {
                message(symbol: "wifi.exclamationmark", title: "Leaderboards didn't load", text: problem)
                Button("Try again") { model.load() }
                    .font(BrandFont.nunito(15, 900))
                    .buttonStyle(.glassProminent)
                    .tint(Color(hex: 0x6A4BC4))
            }
            .frame(maxHeight: .infinity)
        } else {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .frame(maxHeight: .infinity)
                .accessibilityLabel("Loading the leaderboard")
        }
    }

    private func message(image: String? = nil, symbol: String? = nil, title: String, text: String) -> some View {
        VStack(spacing: 8) {
            if let image {
                Image(image).resizable().frame(width: 72, height: 72).accessibilityHidden(true)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: 40, weight: .semibold)).foregroundStyle(Color(hex: 0xC9BFE6)).accessibilityHidden(true)
            }
            Text(title).font(BrandFont.baloo(21, 800))
            Text(text)
                .font(BrandFont.nunito(14, 700))
                .foregroundStyle(Color(hex: 0xC9BFE6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Your place

    @ViewBuilder private var yourPlace: some View {
        if let page = model.page {
            let board = page.board
            Group {
                if let you = page.you {
                    HStack(spacing: 12) {
                        badge(board: board, rating: you.rating)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("YOUR PLACE")
                                .font(BrandFont.nunito(10, 900))
                                .tracking(1.2)
                                .foregroundStyle(board.accent)
                            Text("#\(you.rank) of \(page.players)")
                                .font(BrandFont.baloo(22, 800))
                                .monospacedDigit()
                            if let line = statsLine(board) {
                                Text(line)
                                    .font(BrandFont.nunito(12, 700))
                                    .foregroundStyle(Color(hex: 0xE2DAF6))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(you.rating, format: .number.grouping(.never))
                                .font(BrandFont.nunito(22, 900))
                                .monospacedDigit()
                                .foregroundStyle(board.accent)
                            Text(board.role.map { RankLadder.rank(for: you.rating, role: $0) }.map { "\($0.title) \($0.division)" } ?? "Overall")
                                .font(BrandFont.nunito(11.5, 800))
                                .foregroundStyle(Color(hex: 0xE2DAF6))
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    HStack(spacing: 10) {
                        Image("icon-target").resizable().frame(width: 36, height: 36).accessibilityHidden(true)
                        Text(board == .overall ? "Play a ranked match to get on this board." : "Play a round as \(board.title.lowercased()) to get on this board.")
                            .font(BrandFont.nunito(14, 800))
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [board.accent.opacity(0.24), Color(red: 12 / 255, green: 8 / 255, blue: 30 / 255, opacity: 0.92)],
                               startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5)),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(board.accent, lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private func badge(board: LeaderboardBoard, rating: Int) -> some View {
        if let role = board.role {
            RankBadge(role: role, division: RankLadder.rank(for: rating, role: role).division, size: 44)
        } else {
            Image(systemName: "crown.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0xFFE15C))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.3), in: Circle())
                .accessibilityHidden(true)
        }
    }

    /// The player's own record for this board, from the account the server last sent.
    private func statsLine(_ board: LeaderboardBoard) -> String? {
        guard let stats = account.saved?.stats else { return nil }
        switch board {
        case .overall:
            return "\(stats.wins) W · \(stats.losses) L · \(stats.draws) D"
        case .thief:
            guard stats.thiefRounds > 0 else { return nil }
            let average = stats.escapes > 0 ? " · avg. turn \(Int((Double(stats.escapeTurns) / Double(stats.escapes)).rounded()))" : ""
            return "Escaped \(stats.escapes) of \(stats.thiefRounds) rounds\(average)"
        case .police:
            guard stats.policeRounds > 0 else { return nil }
            return "Won \(stats.policeWins) of \(stats.policeRounds) rounds · \(stats.catches) \(stats.catches == 1 ? "catch" : "catches")"
        }
    }
}

// MARK: - Parts

/// Overall, Thief or Police, as a sliding pill in the board's colour.
private struct BoardPicker: View {
    @Binding var selection: LeaderboardBoard

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LeaderboardBoard.allCases, id: \.self) { board in
                let selected = board == selection
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { selection = board }
                } label: {
                    HStack(spacing: 6) {
                        board.icon
                            .frame(width: 16, height: 16)
                        Text(board.title)
                            .font(BrandFont.nunito(14, 900))
                    }
                    .foregroundStyle(selected ? board.ink : .white.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background {
                        if selected {
                            Capsule()
                                .fill(board.accent)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(board.title) leaderboard")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.black.opacity(0.32), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }
}

/// Global, or the phone's country.
private struct ScopeChip: View {
    let text: String
    var symbol: String?
    var flag: String?
    let selected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let flag {
                    Text(flag).font(.system(size: 14))
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                }
                Text(text)
                    .font(BrandFont.nunito(13, 900))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .foregroundStyle(selected ? .white : .white.opacity(0.75))
            .background(selected ? accent.opacity(0.22) : .black.opacity(0.25), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? accent : .white.opacity(0.14), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One player on the board.
private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let board: LeaderboardBoard
    let isYou: Bool

    var body: some View {
        HStack(spacing: 12) {
            RankMark(rank: entry.rank)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(BrandFont.nunito(16, 900))
                        .lineLimit(1)
                    if let flag = entry.country.flatMap(Flag.emoji) {
                        Text(flag).font(.system(size: 13))
                    }
                    if isYou {
                        Text("YOU")
                            .font(BrandFont.nunito(9.5, 900))
                            .tracking(0.8)
                            .foregroundStyle(board.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(board.accent, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(detail)
                    .font(BrandFont.nunito(12, 700))
                    .foregroundStyle(Color(hex: 0xC9BFE6))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(entry.rating, format: .number.grouping(.never))
                .font(BrandFont.nunito(18, 900))
                .monospacedDigit()
                .foregroundStyle(board.accent)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(minHeight: 58)
        .background(Color(red: 12 / 255, green: 8 / 255, blue: 30 / 255, opacity: isYou ? 0.9 : 0.6), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isYou ? board.accent : .white.opacity(0.08), lineWidth: isYou ? 2 : 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var detail: String {
        if let role = board.role {
            let rank = RankLadder.rank(for: entry.rating, role: role)
            return "\(rank.title) \(rank.division) · \(entry.games) \(entry.games == 1 ? "round" : "rounds")"
        }
        return "\(entry.games) \(entry.games == 1 ? "match" : "matches")"
    }

    private var accessibilityText: String {
        var parts = ["Rank \(entry.rank)", isYou ? "\(entry.name), you" : entry.name]
        if let country = entry.country { parts.append(Flag.name(country)) }
        parts.append("rating \(entry.rating)")
        parts.append(detail)
        return parts.joined(separator: ", ")
    }
}

/// The place number; the top three get gold, silver and bronze.
private struct RankMark: View {
    let rank: Int

    var body: some View {
        let medal: Color? = switch rank {
        case 1: Color(hex: 0xFFD23F)
        case 2: Color(hex: 0xC9D3E6)
        case 3: Color(hex: 0xE09A5A)
        default: nil
        }
        Text(rank, format: .number.grouping(.never))
            .font(BrandFont.nunito(medal == nil ? 15 : 16, 900))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(medal == nil ? .white.opacity(0.8) : Color(hex: 0x2A1A06))
            .frame(width: 36, height: 36)
            .background {
                if let medal {
                    Circle()
                        .fill(medal.gradient)
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                        .shadow(color: medal.opacity(0.5), radius: 6)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Looks

extension LeaderboardBoard {
    var title: String {
        switch self {
        case .overall: "Overall"
        case .thief: "Thief"
        case .police: "Police"
        }
    }

    var role: Role? {
        switch self {
        case .overall: nil
        case .thief: .thief
        case .police: .police
        }
    }

    var accent: Color {
        switch self {
        case .overall: Color(hex: 0xFFE15C)
        case .thief: Color(hex: 0xFFB547)
        case .police: Color(hex: 0x5AA2FF)
        }
    }

    /// Text on the accent colour.
    var ink: Color {
        switch self {
        case .overall: Color(hex: 0x3A2400)
        case .thief: Color(hex: 0x2A1A06)
        case .police: Color(hex: 0x0E1E44)
        }
    }

    @ViewBuilder var icon: some View {
        if let role {
            SVGShape(role.emblem).fill(.foreground)
        } else {
            Image(systemName: "crown.fill").font(.system(size: 13, weight: .bold))
        }
    }
}

/// Country flags and names from region codes.
enum Flag {
    static func emoji(_ code: String) -> String? {
        guard let code = cleanRegion(code) else { return nil }
        let scalars = code.unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 + $0.value - 0x41) }
        return String(String.UnicodeScalarView(scalars))
    }

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}
