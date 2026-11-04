import HeistCore
import SwiftUI

/// Everything the board draws, from one player's point of view.
struct BoardScene: Equatable {
    /// Illustration on each tile the player knows about.
    var props: [Hex: String] = [:]
    /// Wall pieces on tile edges.
    var walls: [Wall] = []
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

/// The Pirate Harbor look for the pieces of a map: rocks are barrels, bushes are fishing nets, a tunnel
/// is a pair of sea caves.
enum HarborArt {
    static let rock = "art-barrel"
    static let bush = "art-net"
    static let plantedBush = "art-sapling"
    static let tunnel = "art-cave"
    static let exit = "art-exit"
    static let box = "art-mystery"

    static func chest(robbed: Bool, reinforced: Bool) -> String {
        robbed ? "art-chestopen" : reinforced ? "art-reinforced" : "art-chest"
    }

    static func security(_ kind: Round.SecurityKind) -> String {
        switch kind {
        case .camera: "art-camera"
        case .dummyCamera: "art-dummycam"
        case .motionDetector: "art-detector"
        }
    }
}

extension MatchModel {
    var board: BoardScene {
        var scene = BoardScene()
        let view = view
        scene.walls = view.walls

        // Terrain everyone knows from the briefing.
        for tile in view.rocks { scene.props[tile] = HarborArt.rock }
        for tile in view.bushes { scene.props[tile] = HarborArt.bush }
        for tunnel in view.tunnels {
            scene.props[tunnel.a] = HarborArt.tunnel
            scene.props[tunnel.b] = HarborArt.tunnel
        }
        for tile in view.boxes { scene.props[tile] = HarborArt.box }

        // Secrets each side holds; the view only carries this player's.
        for tile in view.exits { scene.props[tile] = HarborArt.exit }
        for chest in view.chests { scene.props[chest.tile] = HarborArt.chest(robbed: chest.robbed, reinforced: chest.reinforced) }
        for item in view.security { scene.props[item.tile] = HarborArt.security(item.kind) }
        for tile in view.lookouts { scene.props[tile] = "art-lookout" }
        for tile in view.smokeCaches { scene.props[tile] = "art-smokebomb" }
        // Map bushes keep the net look; only ones planted this round show as saplings.
        for tile in view.bushes where !mapBushes.contains(tile) { scene.props[tile] = HarborArt.plantedBush }

        switch phase {
        case .briefing:
            scene.overlays[view.thiefStart] = .thiefStart
            scene.overlays[view.policeStart] = .policeStart
            scene.pawns = [BoardPawn(role: role, tile: view.position)]
        case .prep, .prepLocked:
            prepScene(&scene)
        case .intel:
            intelScene(&scene)
        case .chase, .resolving:
            chaseScene(&scene)
        default:
            // Full-screen screens cover the board.
            scene.pawns = [BoardPawn(role: role, tile: view.position)]
        }
        return scene
    }

    private func prepScene(_ scene: inout BoardScene) {
        scene.overlays[view.thiefStart] = .thiefStart
        scene.overlays[view.policeStart] = .policeStart
        scene.pawns = [BoardPawn(role: role, tile: view.position)]

        // Cards already placed show on the board before they are built.
        for play in plays {
            guard let tile = play.tile else { continue }
            switch play.card {
            case .blueprintScan:
                for area in view.board.cells where area.distance(to: tile) <= 2 && scene.overlays[area] == nil {
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
            for area in view.board.cells where area.distance(to: tile) <= radius { scene.overlays[area] = .scan }
            scene.overlays[tile] = nil
            scene.glow = TileGlow(tile: tile, color: Color(hex: 0x6EE7FF), fill: Color(hex: 0x6EE7FF, opacity: 0.3))
            scene.tag = TileTag(tile: tile, text: "Scan · \(Harbor.name(tile))", background: Color(hex: 0x6EE7FF), foreground: Color(hex: 0x06222A))
        default:
            if card == .camera {
                for near in view.board.neighbors(of: tile) { scene.overlays[near] = .vision }
            }
            scene.overlays[tile] = nil
            scene.props[tile] = card == .reinforcedChest ? "art-reinforced" : card.art
            scene.glow = TileGlow(tile: tile, color: Color(hex: 0xFFE15C), fill: Color(hex: 0xFFE15C, opacity: 0.28))
            scene.tag = TileTag(tile: tile, text: "\(card.name) · \(Harbor.name(tile))", background: Color(hex: 0xFFE15C), foreground: Color(hex: 0x2A1A06))
        }
    }

    private func intelScene(_ scene: inout BoardScene) {
        scene.pawns = [BoardPawn(role: role, tile: view.position)]
        switch role {
        case .thief:
            for play in plays where play.card == .blueprintScan {
                guard let center = play.tile else { continue }
                for tile in view.board.cells where tile.distance(to: center) <= 2 { scene.overlays[tile] = .scan }
            }
            for chest in view.chests { scene.overlays[chest.tile] = .watched }
        case .police:
            for camera in view.security where camera.kind == .camera {
                for tile in view.board.cells where tile.distance(to: camera.tile) <= 1 { scene.overlays[tile] = .vision }
            }
        }
    }

    private func chaseScene(_ scene: inout BoardScene) {
        scene.fog = Set(view.board.cells).subtracting(view.visible)
        scene.pawns = [BoardPawn(role: role, tile: view.position)]
        if let seen = view.opponent {
            scene.pawns.append(BoardPawn(role: role.other, tile: seen.tile, ghost: !view.opponentVisible))
        }
        if role == .police, let alarm = view.alarm {
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

extension PlayerView {
    /// A blank board, until the first round's briefing arrives.
    static let empty = PlayerView(
        role: .thief, stage: .prep, turn: 1, turnLimit: MatchRules.chaseTurns, radius: Harbor.board.radius,
        position: .origin, thiefStart: .origin, policeStart: .origin, rocks: [], bushes: [], walls: [], tunnels: [],
        exits: [], chests: [], security: [], lookouts: [], smokeCaches: [], boxes: [], visible: Harbor.tiles, seen: [],
        opponent: nil, opponentVisible: false, alarm: nil, hasLoot: false, cracking: nil, smokeThrough: 0,
        lockdownThrough: 0, camerasOffThrough: 0, cards: [], instantUsed: false
    )

    /// This view with the whole board shown, once the round is over: both pieces, every chest and exit.
    func revealing(_ reveal: RoundReveal) -> PlayerView {
        var view = self
        view.stage = .over
        view.exits = reveal.map.exits
        view.chests = reveal.map.chests.map { Chest(tile: $0, robbed: reveal.robbed.contains($0), reinforced: reveal.reinforced.contains($0)) }
        view.visible = Harbor.tiles
        view.opponent = Sighting(tile: role == .thief ? reveal.police : reveal.thief, turn: turn)
        view.opponentVisible = true
        view.position = role == .thief ? reveal.thief : reveal.police
        return view
    }
}

/// Everything needed to play a finished round back on the board, with nothing hidden.
struct RoundReplay {
    let thiefTrail: [Hex]
    let policeTrail: [Hex]
    let robbed: Sighting?
    let end: RoundEnd
    let walls: [Wall]
    private let props: [Hex: String]

    init(_ reveal: RoundReveal, result: RoundResult) {
        thiefTrail = reveal.thiefTrail ?? [reveal.thief]
        policeTrail = reveal.policeTrail ?? [reveal.police]
        robbed = reveal.robbedAt
        end = RoundEnd(result)
        walls = reveal.map.walls
        var props: [Hex: String] = [:]
        let map = reveal.map
        for tile in map.rocks { props[tile] = HarborArt.rock }
        for tile in map.bushes { props[tile] = HarborArt.bush }
        for tunnel in map.tunnels {
            props[tunnel.a] = HarborArt.tunnel
            props[tunnel.b] = HarborArt.tunnel
        }
        for tile in map.exits { props[tile] = HarborArt.exit }
        for tile in map.chests { props[tile] = HarborArt.chest(robbed: false, reinforced: reveal.reinforced.contains(tile)) }
        for tile in reveal.cameras { props[tile] = HarborArt.security(.camera) }
        for tile in reveal.dummyCameras { props[tile] = HarborArt.security(.dummyCamera) }
        for tile in reveal.motionDetectors { props[tile] = HarborArt.security(.motionDetector) }
        for tile in reveal.plantedBushes { props[tile] = HarborArt.plantedBush }
        for tile in reveal.lookouts { props[tile] = "art-lookout" }
        self.props = props
    }

    var steps: Int { max(thiefTrail.count, policeTrail.count) }

    /// The board after `step` turns (0 is the start).
    func scene(at step: Int) -> BoardScene {
        var scene = BoardScene()
        scene.props = props
        scene.walls = walls
        if let robbed, step >= robbed.turn { scene.props[robbed.tile] = HarborArt.chest(robbed: true, reinforced: false) }
        let thief = thiefTrail[min(step, thiefTrail.count - 1)]
        let police = policeTrail[min(step, policeTrail.count - 1)]
        scene.pawns = [BoardPawn(role: .thief, tile: thief), BoardPawn(role: .police, tile: police)]
        if step >= steps - 1 {
            switch end {
            case .caught(let tile):
                scene.glow = TileGlow(tile: tile, color: Color(hex: 0xFF6B6B), fill: Color(hex: 0xFF5F7E, opacity: 0.3))
            case .escaped(let tile):
                scene.glow = TileGlow(tile: tile, color: Color(hex: 0x5BD07A), fill: Color(hex: 0x5BD07A, opacity: 0.3))
            case .time:
                break
            }
        }
        return scene
    }
}
