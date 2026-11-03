import SwiftUI

/// Shows the splash until launch work is done, then the home screen, and a match on top when one is running.
struct RootView: View {
    @State private var launch = LaunchModel()
    @State private var match: MatchModel?
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
                    HomeView(onPlay: startMatch)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.45), value: match == nil)
        .background(Color(hex: 0x100B26))
        .task { await launch.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                launch.returnedToForeground()
            }
        }
        #if DEBUG
        // Launch with `-openMatch YES` (and `-matchRole thief|police`) to go straight into a match.
        .onChange(of: launch.phase) { _, phase in
            if phase == .home, UserDefaults.standard.bool(forKey: "openMatch") { startMatch() }
        }
        #endif
    }

    private func startMatch() {
        match = MatchModel(onExit: { match = nil }, onPlayAgain: { startMatch() })
    }
}
