# Heist Royale

Two-player, simultaneous-move thief vs police game on a hidden hex board. Native iOS app in Swift and a Swift game server for live matches (Google Cloud), both on the shared HeistCore engine.

- The single plan is the claude.ai doc "Heist Royale — Master Plan": https://claude.ai/artifact/JkvYDWBx9QvSf8285RWdiB. Tabs: Overview (status, review, decisions, open decisions), Roadmap and tasks, Game logic, Cards, Matches and ranking, Server and connection, AI bots, Economy world and platform, Setup and accounts. Read it with the Claude Docs tools before changing plans; tick tasks there when they are done.
- The older "Heist Royale — Game Design Document" (https://claude.ai/artifact/JofUgZb1gGgntvyHVz2Dpe) is archived.
- `prototype/index.html` is the playable HTML prototype (v1 rules) and the reference for every chase rule. Port from it; don't invent rules. New 2.0 rules (prep stage, cards, match formats) come from the master plan.
- Decided 3 Nov 2026: one Swift rules engine in HeistCore, shared by the app and a custom Swift server (not TypeScript or Nakama). Online play is the Tournament format (3 + 3 rounds, first to 4, two-round extension, else a draw), rated with Elo; a bot fills an empty queue after 10 s and bot matches are rated too.
- Engine code stays deterministic: every random choice goes through `SeededRandom`'s own helpers (not the standard library's random APIs), and anything iterated from a `Set` is sorted first. Bump `Round.rulesVersion` when a rule changes.
- The server sends each player only `Round.view(for:)` of their role; bots decide from that view too. Never put hidden state in a message.

## Layout

- `HeistCore/`: Swift package, no UI code, two libraries. `HeistCore`: hex geometry, the round engine (`Round`: prep and chase plus map walls), map generator, dealer, the bot, the `Tournament` series rules, Elo and the wire protocol (`Protocol.swift`). `ServerCore`: the server's logic without the network (matchmaker, match rooms, player store), tested with in-memory links; the app also runs it in-process for the offline match.
- `Server/`: the game server executable, `HeistServer` (Hummingbird WebSocket at `/ws`, `/health`), and `heist-client` (a command-line player for end-to-end runs). Data goes to `DATA_DIR` (default `./data`) as JSON files. `Server/deploy/` ships it to the dev VM.
- `App/`: the iOS app (SwiftUI; RealityKit board). `App/Online` holds the server connection (`GameConnection`) and the guest token in the Keychain.
- `project.yml`: XcodeGen spec. `HeistRoyale.xcodeproj` is generated from it and committed so it opens without XcodeGen.

## Commands

```bash
xcodegen generate                         # after editing project.yml or adding/removing files
(cd HeistCore && swift test)              # engine and server-logic tests (matches play out at 1/100 speed)
(cd Server && swift run HeistServer)      # local server on :8080; PORT, DATA_DIR, TIMER_SCALE=0.05 for fast timers
(cd Server && swift run heist-client --name Ada --url ws://localhost:8080/ws)   # plays one whole match; run two to meet each other
Server/deploy/deploy.sh                   # ship Server/ + HeistCore/ to the dev server (Cloud Build image, then VM restart; ~12 min)
curl https://136-64-123-56.sslip.io/health   # dev server (e2-micro VM, Caddy HTTPS); play it with --url wss://136-64-123-56.sslip.io/ws
xcodebuild -project HeistRoyale.xcodeproj -scheme HeistRoyale -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build
xcrun simctl launch booted com.benostudio.heistroyale -timeOfDay night   # debug builds: force morning/evening/night downtown
SIMCTL_CHILD_TZ=Asia/Tokyo xcrun simctl launch booted com.benostudio.heistroyale   # or test the real clock via a time zone
```

The home scenery and logos are drawn in code from the design files; characters and game icons are SVGs in `App/Assets.xcassets`. Fonts (Bungee, Fredoka, Nunito Sans, Baloo 2; OFL) live in `App/Fonts` and are registered through `UIAppFonts`.

## Match screens

- PLAY on home joins the Tournament queue on the dev server (another player, or a bot after 10 s): finding an opponent, coin flip, role reveal, rounds, round result with a 3D replay, series scoreboard and match end. `MatchModel` turns server messages into screens, paced by the server's deadlines (each envelope carries the server clock); the board is drawn from the player's `PlayerView` only. The app uses HeistCore's `Role`, `CardID` and other types; their app-only looks (colours, art, effect text) are extensions in `MatchRules.swift`. Notes are worded by the app (`MatchNotes.swift`) with its own tile names.
- The board is a live RealityKit scene (`App/Match/Board3D`) built to match the design's 3D renders; meeple tokens and card faces are the design's renders (`Assets.xcassets/Renders`). Tags, taps and VoiceOver sit on top using the same camera maths (`BoardCamera`).
- Don't put `accessibilityChildren` (or similar synthesised-accessibility modifiers) on a container around the RealityView: it stops the 3D view from getting a drawable and the board renders blank.
- Only one board RealityView at a time: one created while another is still in the view tree (e.g. fading out) gets no drawables and stays blank. `LiveBoards` counts them; the round result's replay waits for the round's board to leave.
- Debug launch arguments: `-openMatch YES` (straight into a match), `-serverURL ws://localhost:8080/ws` (a server on this Mac; run it with `TIMER_SCALE=0.25` for quick full matches), `-offlineMatch YES` (play the in-app server against a bot, no network), `-matchTimerScale 6` (slower timers for the offline match), `-playerName Ada` (the name to sign up with).

## Settings

- Minimum iOS 26, iPhone only, portrait. Swift 6 language mode.
- Apple team `TNBCR36YPJ`, automatic signing. Game Center entitlement on.
- App Store name "Heist Royale: Thief vs Police"; the home-screen name is "Heist Royale".
