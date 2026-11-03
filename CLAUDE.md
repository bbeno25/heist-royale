# Heist Royale

Two-player, simultaneous-move thief vs police game on a hidden hex board. Native iOS app in Swift; a Swift game server for live matches comes later (phase 3, Google Cloud).

- The single plan is the claude.ai doc "Heist Royale — Master Plan": https://claude.ai/artifact/JkvYDWBx9QvSf8285RWdiB. Tabs: Overview (status, review, decisions, open decisions), Roadmap and tasks, Game logic, Cards, Matches and ranking, Server and connection, AI bots, Economy world and platform, Setup and accounts. Read it with the Claude Docs tools before changing plans; tick tasks there when they are done.
- The older "Heist Royale — Game Design Document" (https://claude.ai/artifact/JofUgZb1gGgntvyHVz2Dpe) is archived.
- `prototype/index.html` is the playable HTML prototype (v1 rules) and the reference for every chase rule. Port from it; don't invent rules. New 2.0 rules (prep stage, cards, match formats) come from the master plan.
- The rules engine language and backend are still open (TypeScript + Nakama recommended vs Swift + custom server). Don't build engine code in HeistCore beyond board geometry until that decision is made.

## Layout

- `HeistCore/`: Swift package, today only board geometry (hex math, tile names) with tests. No UI code. If the engine decision goes to Swift, the rules and AI live here, deterministic with seeded randomness; if it goes to TypeScript, this stays a thin layer of geometry and view models for the app.
- `App/`: the iOS app (SwiftUI; SpriteKit board later).
- `project.yml`: XcodeGen spec. `HeistRoyale.xcodeproj` is generated from it and committed so it opens without XcodeGen.

## Commands

```bash
xcodegen generate                         # after editing project.yml or adding/removing files
(cd HeistCore && swift test)              # rules tests, on the Mac
xcodebuild -project HeistRoyale.xcodeproj -scheme HeistRoyale -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build
xcrun simctl launch booted com.benostudio.heistroyale -timeOfDay night   # debug builds: force morning/evening/night downtown
SIMCTL_CHILD_TZ=Asia/Tokyo xcrun simctl launch booted com.benostudio.heistroyale   # or test the real clock via a time zone
```

The home scenery and logos are drawn in code from the design files; characters and game icons are SVGs in `App/Assets.xcassets`. Fonts (Bungee, Fredoka, Nunito Sans, Baloo 2; OFL) live in `App/Fonts` and are registered through `UIAppFonts`.

## Settings

- Minimum iOS 26, iPhone only, portrait. Swift 6 language mode.
- Apple team `TNBCR36YPJ`, automatic signing. Game Center entitlement on.
- App Store name "Heist Royale: Thief vs Police"; the home-screen name is "Heist Royale".
