import SwiftUI

/// Runs the splash: on the first open of each day it syncs with the server, otherwise it only plays
/// the logo. Either way it moves on to home once the logo intro has finished and the sync is done.
@MainActor
@Observable
final class LaunchModel {
    enum Phase { case splash, home }

    private(set) var phase: Phase = .splash
    /// Loading bar fill, 0 to 1.
    private(set) var progress: Double = 0
    /// Changes each time the splash starts over, so its logo replays.
    private(set) var run = 0

    /// Seconds for the logo intro plus a short beat to let it sit before the screen changes.
    static let minimumSplash = StackedLogo.introDuration + 0.35

    private let server: any ServerSyncing
    private let record: DailySyncRecord
    private var isRunning = false

    init(server: any ServerSyncing = ServerSync(), record: DailySyncRecord = DailySyncRecord()) {
        self.server = server
        self.record = record
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let clock = ContinuousClock()
        let started = clock.now
        progress = 0
        if record.needsSync() {
            do {
                try await server.sync { [weak self] value in
                    self?.progress = value
                }
                record.markSynced()
            } catch {
                // Offline or the server is down: carry on (offline play still works); the next open tries again.
            }
        } else {
            withAnimation(.easeInOut(duration: Self.minimumSplash)) {
                progress = 1
            }
        }
        let remaining = .seconds(Self.minimumSplash) - (clock.now - started)
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
        progress = 1
        withAnimation(.easeInOut(duration: 0.7)) {
            phase = .home
        }
    }

    /// Back from the background: if the day has changed since the last sync, that counts as the
    /// day's first open, so show the splash and sync again.
    func returnedToForeground() {
        guard phase == .home, !isRunning, record.needsSync() else { return }
        run += 1
        progress = 0
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .splash
        }
        Task { await start() }
    }
}
