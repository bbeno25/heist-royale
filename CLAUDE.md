# Heist Royale

Two-player, simultaneous-move thief vs police game on a hidden hex board. Native iOS app in Swift and a Swift game server for live matches (Google Cloud), both on the shared HeistCore engine.

- The single plan is the claude.ai doc "Heist Royale — Master Plan": https://claude.ai/artifact/JkvYDWBx9QvSf8285RWdiB. Tabs: Overview (status, review, decisions, open decisions), Roadmap and tasks, Game logic, Cards, Matches and ranking, Server and connection, AI bots, Economy world and platform, Setup and accounts. Read it with the Claude Docs tools before changing plans; tick tasks there when they are done.
- The older "Heist Royale — Game Design Document" (https://claude.ai/artifact/JofUgZb1gGgntvyHVz2Dpe) is archived.
- `prototype/index.html` is the playable HTML prototype (v1 rules) and the reference for every chase rule. Port from it; don't invent rules. New 2.0 rules (prep stage, cards, match formats) come from the master plan.
- Decided 3 Nov 2026: one Swift rules engine in HeistCore, shared by the app and a custom Swift server (not TypeScript or Nakama). Online play is the Tournament format (3 + 3 rounds, first to 4, two-round extension, else a draw), rated with Elo; a bot fills an empty queue after 10 s and bot matches are rated too.
- Engine code stays deterministic: every random choice goes through `SeededRandom`'s own helpers (not the standard library's random APIs), and anything iterated from a `Set` is sorted first. Bump `Round.rulesVersion` when a rule changes.
- The server sends each player only `Round.view(for:)` of their role; bots decide from that view too. Never put hidden state in a message.

## Layout

- `HeistCore/`: Swift package, no UI code. Hex geometry, the round engine (`Round`: prep and chase, ported from the app's `SampleRound` plus map walls), map generator, dealer, the bot, the `Tournament` series rules and the wire protocol (`Protocol.swift`), with tests.
- `Server/`: the game server package. `ServerCore` (matchmaker, match rooms, Elo, player store; no network code, tested with in-memory links), `HeistServer` (Hummingbird WebSocket at `/ws`, `/health`), `heist-client` (a command-line player for end-to-end runs). Data goes to `DATA_DIR` (default `./data`) as JSON files.
- `App/`: the iOS app (SwiftUI; RealityKit board). It doesn't use the server yet.
- `project.yml`: XcodeGen spec. `HeistRoyale.xcodeproj` is generated from it and committed so it opens without XcodeGen.

## Commands

```bash
xcodegen generate                         # after editing project.yml or adding/removing files
(cd HeistCore && swift test)              # engine tests, on the Mac
(cd Server && swift test)                 # server tests (matches play out at 1/100 speed)
(cd Server && swift run HeistServer)      # local server on :8080; PORT, DATA_DIR, TIMER_SCALE=0.05 for fast timers
(cd Server && swift run heist-client --name Ada --url ws://localhost:8080/ws)   # plays one whole match; run two to meet each other
xcodebuild -project HeistRoyale.xcodeproj -scheme HeistRoyale -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build
xcrun simctl launch booted com.benostudio.heistroyale -timeOfDay night   # debug builds: force morning/evening/night downtown
SIMCTL_CHILD_TZ=Asia/Tokyo xcrun simctl launch booted com.benostudio.heistroyale   # or test the real clock via a time zone
```

The home scenery and logos are drawn in code from the design files; characters and game icons are SVGs in `App/Assets.xcassets`. Fonts (Bungee, Fredoka, Nunito Sans, Baloo 2; OFL) live in `App/Fonts` and are registered through `UIAppFonts`.

## Match screens

- PLAY on home opens a Classic sample match against a bot (best of 8, first to 5): coin flip, role reveal, rounds, round result with a 3D replay, series scoreboard and match end. `App/Match/SampleRound.swift` is a stand-in rules engine; the real one is HeistCore's `Round`, which the app moves to when it goes online. Don't grow the stand-in. Until then the app's own `Role`, `CardID` and similar types shadow HeistCore's.
- The board is a live RealityKit scene (`App/Match/Board3D`) built to match the design's 3D renders; meeple tokens and card faces are the design's renders (`Assets.xcassets/Renders`). Tags, taps and VoiceOver sit on top using the same camera maths (`BoardCamera`).
- Don't put `accessibilityChildren` (or similar synthesised-accessibility modifiers) on a container around the RealityView: it stops the 3D view from getting a drawable and the board renders blank.
- Only one board RealityView at a time: one created while another is still in the view tree (e.g. fading out) gets no drawables and stays blank. `LiveBoards` counts them; the round result's replay waits for the round's board to leave.
- Debug launch arguments: `-openMatch YES` (straight into a match), `-matchRole thief|police`, `-matchTimerScale 6` (slower timers for testing), `-matchTurns 3` (short chase), `-matchRounds 2` (short series), `-matchJumpToResult YES` (skip to round 1's result).

## Settings

- Minimum iOS 26, iPhone only, portrait. Swift 6 language mode.
- Apple team `TNBCR36YPJ`, automatic signing. Game Center entitlement on.
- App Store name "Heist Royale: Thief vs Police"; the home-screen name is "Heist Royale".
