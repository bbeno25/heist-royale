import SwiftUI

/// Shows the splash until launch work is done, then the home screen, and a match on top when one is running.
/// The saved account feeds home its real ratings; it refreshes from the server at launch, on return to
/// the app and after each match (never during one).
struct RootView: View {
    @State private var launch = LaunchModel()
    @State private var account = PlayerAccount()
    @State private var match: MatchModel?
    @State private var showsLeaderboards = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch launch.phase {
            case .splash:
                SplashView(launch: launch)
                    .id(launch.run)
                    .transition(.opacity)
            case .home:
                if let match {
                    MatchView(model: match)
                        .id(ObjectIdentifier(match))
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
                } else {
                    HomeView(player: account.summary, onPlay: startMatch, onLeaderboards: { showsLeaderboards = true })
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.45), value: match == nil)
        .background(Color(hex: 0x100B26))
        .sheet(isPresented: $showsLeaderboards) {
            LeaderboardView(account: account)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: 0x100B26))
        }
        .task {
            account.refresh()
            await launch.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                launch.returnedToForeground()
                if match == nil { account.refresh() }
            }
        }
        #if DEBUG
        // Launch with `-openMatch YES` (and `-matchRole thief|police`) to go straight into a match, or
        // `-openLeaderboards YES` to open the leaderboards.
        .onChange(of: launch.phase) { _, phase in
            guard phase == .home else { return }
            if UserDefaults.standard.bool(forKey: "openMatch") { startMatch() }
            if UserDefaults.standard.bool(forKey: "openLeaderboards") { showsLeaderboards = true }
        }
        #endif
    }

    private func startMatch() {
        showsLeaderboards = false
        match = MatchModel(account: account, onExit: {
            match = nil
            // A moment later, so a forfeit sent on the match's connection lands first.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if match == nil { account.refresh() }
            }
        }, onPlayAgain: { startMatch() })
    }
}
