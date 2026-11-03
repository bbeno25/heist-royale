import SwiftUI

/// Shows the splash until launch work is done, then the home screen.
struct RootView: View {
    @State private var launch = LaunchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch launch.phase {
            case .splash:
                SplashView(launch: launch)
                    .id(launch.run)
                    .transition(.opacity)
            case .home:
                HomeView()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
            }
        }
        .background(Color(hex: 0x100B26))
        .task { await launch.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                launch.returnedToForeground()
            }
        }
    }
}
