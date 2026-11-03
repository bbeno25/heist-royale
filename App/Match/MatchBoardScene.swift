import HeistCore
import SwiftUI

/// Everything the board draws, from one player's point of view.
struct BoardScene: Equatable {
    /// Illustration on each tile the player knows about.
    var props: [Hex: String] = [:]
    var overlays: [Hex: TileOverlay] = [:]
    /// Tiles the player can't see into right now.
    var fog: Set<Hex> = []
    var glow: TileGlow?
    var tag: TileTag?
    var pawns: [BoardPawn] = []
}

/// Tile highlights, styled as in the board mockup.
enum TileOverlay: Equatable {
    case valid, vision, scan, reach, watched, thiefStart, policeStart
}

struct TileGlow: Equatable {
    let tile: Hex
    let color: Color
    let fill: Color
}

struct TileTag: Equatable {
    let tile: Hex
    let text: String
    let background: Color
    let foreground: Color
}

struct BoardPawn: Equatable, Identifiable {
    let role: Role
    let tile: Hex
    /// The opponent's last known spot, drawn faded.
    var ghost = false

    var id: String { "\(role)\(ghost ? "-ghost" : "")" }
}

extension MatchModel {
    var board: BoardScene {
        var scene = BoardScene()
        let round = round

        // Terrain everyone knows from the briefing.
        for tile in round.rocks { scene.props[tile] = "art-barrel" }
        for tile in Harbor.bushes { scene.props[tile] = "art-net" }
        scene.props[Harbor.caves.0] = "art-cave"
        scene.props[Harbor.caves.1] = "art-cave"
        for tile in round.boxes { scene.props[tile] = "art-mystery" }

        // Secrets each side holds.
        switch role {
        case .thief:
            for tile in round.exits { scene.props[tile] = "art-exit" }
            for tile in round.thiefKnownChests { scene.props[tile] = chestArt(tile) }
            for (tile, art) in round.thiefKnownSecurity { scene.props[tile] = art }
            for tile in round.plantedBushes { scene.props[tile] = "art-sapling" }
            for tile in round.lookouts { scene.props[tile] = "art-lookout" }
            for tile in round.smokeCaches { scene.props[tile] = "art-smokebomb" }
        case .police:
            for tile in round.chests { scene.props[tile] = chestArt(tile) }
            for tile in round.cameras { scene.props[tile] = "art-camera" }
            for tile in round.dummyCameras { scene.props[tile] = "art-dummycam" }
            for tile in round.detectors { scene.props[tile] = "art-detector" }
            for tile in round.policeKnownBushes { scene.props[tile] = "art-sapling" }
            if case .escaped(let exit) = round.end { scene.props[exit] = "art-exit" }
        }

        switch phase {
        case .briefing:
            scene.overlays[Harbor.thiefStart] = .thiefStart
            scene.overlays[Harbor.policeStart] = .policeStart
            scene.pawns = [BoardPawn(role: role, tile: round.position(of: role))]
        case .prep, .prepLocked:
            prepScene(&scene)
        case .intel:
            intelScene(&scene)
        case .chase, .resolving:
            chaseScene(&scene)
        case .coinFlip, .roleReveal, .roundResult, .series, .matchOver:
            // Full-screen screens cover the board.
            scene.pawns = [BoardPawn(role: role, tile: round.position(of: role))]
        }
        return scene
    }

    private func chestArt(_ tile: Hex) -> String {
        if round.robbed.contains(tile) { return "art-chestopen" }
        let reinforcedKnown = role == .police || round.thiefKnownChests.contains(tile)
        return round.reinforced.contains(tile) && reinforcedKnown ? "art-reinforced" : "art-chest"
    }

    private func prepScene(_ scene: inout BoardScene) {
        scene.overlays[Harbor.thiefStart] = .thiefStart
        scene.overlays[Harbor.policeStart] = .policeStart
        scene.pawns = [BoardPawn(role: role, tile: round.position(of: role))]

        // Cards already placed show on the board before they are built.
        for play in plays {
            guard let tile = play.tile else { continue }
            switch play.card {
            case .blueprintScan:
                for area in Harbor.tiles where area.distance(to: tile) <= 2 && scene.overlays[area] == nil {
                    scene.overlays[area] = .scan
                }
            case .reinforcedChest: scene.props[tile] = "art-reinforced"
            default: scene.props[tile] = play.card.art
            }
        }

        guard let card = selectedCard else { return }
        if selectedIsPlaced {
            if let tile = targetTile {
                scene.glow = TileGlow(tile: tile, color: Color(hex: 0x5BD07A), fill: Color(hex: 0x5BD07A, opacity: 0.25))
            }
            return
        }
        for tile in validTargets where scene.overlays[tile] == nil {
            scene.overlays[tile] = .valid
        }
        guard let tile = targetTile else { return }
        switch card.target {
        case .area(let radius):
            for area in Harbor.tiles where area.distance(to: tile) <= radius { scene.overlays[area] = .scan }
            scene.overlays[tile] = nil
            scene.glow = TileGlow(tile: tile, color: Color(hex: 0x6EE7FF), fill: Color(hex: 0x6EE7FF, opacity: 0.3))
            scene.tag = TileTag(tile: tile, text: "Scan · \(Harbor.name(tile))", background: Color(hex: 0x6EE7FF), foreground: Color(hex: 0x06222A))
        default:
            if card == .camera {
                for near in Harbor.board.neighbors(of: tile) { scene.overlays[near] = .vision }
            }
            scene.overlays[tile] = nil
            scene.props[tile] = card == .reinforcedChest ? "art-reinforced" : card.art
            scene.glow = TileGlow(tile: tile, color: Color(hex: 0xFFE15C), fill: Color(hex: 0xFFE15C, opacity: 0.28))
            scene.tag = TileTag(tile: tile, text: "\(card.name) · \(Harbor.name(tile))", background: Color(hex: 0xFFE15C), foreground: Color(hex: 0x2A1A06))
        }
    }

    private func intelScene(_ scene: inout BoardScene) {
        scene.pawns = [BoardPawn(role: role, tile: round.position(of: role))]
        switch role {
        case .thief:
            for play in plays where play.card == .blueprintScan {
                guard let center = play.tile else { continue }
                for tile in Harbor.tiles where tile.distance(to: center) <= 2 { scene.overlays[tile] = .scan }
            }
            for tile in round.thiefKnownChests { scene.overlays[tile] = .watched }
        case .police:
            for camera in round.cameras {
                for tile in Harbor.tiles where tile.distance(to: camera) <= 1 { scene.overlays[tile] = .vision }
            }
        }
    }

    private func chaseScene(_ scene: inout BoardScene) {
        let visible = round.visibleTiles(for: role)
        scene.fog = Set(Harbor.tiles).subtracting(visible)

        let me = round.position(of: role)
        scene.pawns = [BoardPawn(role: role, tile: me)]
        let seesOther = role == .thief ? round.thiefSeesPolice() : round.policeSeesThief()
        if seesOther {
            scene.pawns.append(BoardPawn(role: role.other, tile: round.position(of: role.other)))
        } else if let last = role == .thief ? round.thiefSawPolice : round.policeSawThief {
            scene.pawns.append(BoardPawn(role: role.other, tile: last.tile, ghost: true))
        }

        if role == .police, let alarm = round.alarm {
            scene.overlays[alarm.tile] = .watched
        }
        guard phase == .chase else { return }
        for tile in reach.keys { scene.overlays[tile] = .reach }
        if case .tile(let tile) = move {
            scene.overlays[tile] = nil
            scene.glow = TileGlow(tile: tile, color: Color(hex: 0xFFD66B), fill: Color(hex: 0xFFC94D, opacity: 0.4))
            scene.tag = TileTag(tile: tile, text: "Move · \(Harbor.name(tile))", background: Color(hex: 0xFFE15C), foreground: Color(hex: 0x2A1A06))
        }
    }
}
