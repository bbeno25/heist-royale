import HeistCore
import RealityKit
import simd
import SwiftUI
import UIKit

/// The live 3D Pirate Harbor board in RealityKit: a hexagonal wooden deck with mooring posts in a
/// turquoise sea, 61 raised plank tiles, 3D props, and the meeples, seen through the design's camera.
/// `update(_:)` brings props, highlights, fog and meeples in line with a `BoardScene`.
@MainActor
final class BoardWorld {
    let root = Entity()

    /// Height of the tile tops; props and pieces stand here.
    nonisolated static let tileTop: Float = 0.16

    private let materials: BoardMaterials

    private let tileLayer = Entity()
    private let propLayer = Entity()
    private let markLayer = Entity()
    private let pawnLayer = Entity()
    private let wallLayer = Entity()
    private var tiles: [Hex: Entity] = [:]
    private var walls: [Wall: Entity] = [:]
    private var props: [Hex: (art: String, entity: Entity)] = [:]
    private var marks: [Hex: (overlay: TileOverlay, entity: Entity)] = [:]
    private var glow: (key: TileGlow, entity: Entity)?
    private var fog: (tiles: Set<Hex>, entity: ModelEntity)?
    private var pawns: [String: Pawn3D] = [:]

    init(materials: BoardMaterials) {
        self.materials = materials
        root.addChild(makeCamera())
        addLights()
        addSea()
        addDock()
        for layer in [tileLayer, wallLayer, propLayer, markLayer, pawnLayer] { root.addChild(layer) }
        addTiles()
    }

    /// World position of a tile's centre on top of the tiles.
    static func top(of tile: Hex) -> SIMD3<Float> {
        let c = BoardCamera.center(tile)
        return SIMD3(Float(c.x), tileTop, Float(c.y))
    }

    // MARK: Updates

    func update(_ scene: BoardScene) {
        updateProps(scene.props)
        updateWalls(scene.walls)
        updateMarks(scene.overlays)
        updateGlow(scene.glow)
        updateFog(scene.fog)
        updatePawns(scene.pawns)
    }

    private func updateProps(_ wanted: [Hex: String]) {
        for (tile, current) in props where wanted[tile] != current.art {
            current.entity.removeFromParent()
            props[tile] = nil
        }
        for (tile, art) in wanted where props[tile] == nil {
            let entity = BoardProp.make(art, materials)
            entity.position = Self.top(of: tile)
            propLayer.addChild(entity)
            props[tile] = (art, entity)
        }
        // An exit, when known, is a water cut-out with a boat instead of a tile.
        for (tile, entity) in tiles {
            entity.isEnabled = wanted[tile] != "art-exit"
        }
    }

    private func updateWalls(_ wanted: [Wall]) {
        let keep = Set(wanted)
        for (wall, entity) in walls where !keep.contains(wall) {
            entity.removeFromParent()
            walls[wall] = nil
        }
        for wall in wanted where walls[wall] == nil {
            let entity = Self.wallPiece(wall, materials)
            wallLayer.addChild(entity)
            walls[wall] = entity
        }
    }

    /// A low wooden wall standing on the edge between two tiles, capped like the mooring posts.
    private static func wallPiece(_ wall: Wall, _ materials: BoardMaterials) -> Entity {
        let a = BoardCamera.center(wall.a), b = BoardCamera.center(wall.b)
        let across = SIMD2(Float(b.x - a.x), Float(b.y - a.y))
        let length = simd_length(across) / Float(3).squareRoot()
        let piece = Entity()
        piece.addChild(BoardProp.model(.generateBox(width: length * 0.92, height: 0.3, depth: 0.16, cornerRadius: 0.03), materials.chestWood, at: [0, 0.15, 0]))
        piece.addChild(BoardProp.model(.generateBox(width: length * 0.98, height: 0.06, depth: 0.22, cornerRadius: 0.02), BoardProp.color(0xC08A55, roughness: 0.7), at: [0, 0.32, 0]))
        piece.position = [Float(a.x + b.x) / 2, tileTop, Float(a.y + b.y) / 2]
        // Turn the piece so its length runs along the shared edge, square to the line between the tiles.
        let along = SIMD2(-across.y, across.x)
        piece.orientation = simd_quatf(angle: atan2(-along.y, along.x), axis: [0, 1, 0])
        return piece
    }

    private func updateMarks(_ wanted: [Hex: TileOverlay]) {
        for (tile, current) in marks where wanted[tile] != current.overlay {
            current.entity.removeFromParent()
            marks[tile] = nil
        }
        for (tile, overlay) in wanted where marks[tile] == nil {
            let entity = decal(materials.highlights[overlay]!, size: 1.7)
            entity.position = Self.top(of: tile) + [0, 0.004, 0]
            markLayer.addChild(entity)
            marks[tile] = (overlay, entity)
        }
    }

    private func updateGlow(_ wanted: TileGlow?) {
        guard glow?.key != wanted else { return }
        glow?.entity.removeFromParent()
        glow = nil
        guard let wanted else { return }
        let group = Entity()
        let tint = UIColor(wanted.color)
        let layers = [
            decal(BoardMaterials.decal(materials.glowHalo, tint: tint), size: 1.7),
            decal(BoardMaterials.decal(materials.glowFill, tint: tint), size: 1.7),
            decal(BoardMaterials.decal(materials.glowOutline), size: 1.7),
        ]
        for (index, layer) in layers.enumerated() {
            layer.position.y = 0.006 + Float(index) * 0.001
            group.addChild(layer)
        }
        group.position = Self.top(of: wanted.tile)
        markLayer.addChild(group)
        glow = (wanted, group)
    }

    private func updateFog(_ wanted: Set<Hex>) {
        guard fog?.tiles != wanted else { return }
        fog?.entity.removeFromParent()
        fog = nil
        guard !wanted.isEmpty else { return }
        let outlines = wanted.map { tile -> [SIMD2<Float>] in
            let c = BoardCamera.center(tile)
            return BoardMesh.hexagon(center: SIMD2(Float(c.x), Float(c.y)), radius: 0.99)
        }
        var mist = UnlitMaterial(color: UIColor(red: 12 / 255, green: 18 / 255, blue: 44 / 255, alpha: 1))
        mist.blending = .transparent(opacity: .init(floatLiteral: 0.72))
        let entity = ModelEntity(mesh: BoardMesh.prisms(outlines, bottom: 0.02, top: 1.0), materials: [mist, mist])
        root.addChild(entity)
        fog = (wanted, entity)
    }

    private func updatePawns(_ wanted: [BoardPawn]) {
        let ids = Set(wanted.map(\.id))
        for (id, pawn) in pawns where !ids.contains(id) {
            pawn.root.removeFromParent()
            pawns[id] = nil
        }
        for piece in wanted {
            if let pawn = pawns[piece.id] {
                if pawn.tile != piece.tile { pawn.move(to: piece.tile) }
            } else {
                let pawn = Pawn3D(piece, materials: materials)
                pawnLayer.addChild(pawn.root)
                pawns[piece.id] = pawn
            }
        }
    }

    // MARK: Building

    /// The design's camera: looking down on the board at about 50°, with a 26° field of view.
    private func makeCamera() -> Entity {
        let camera = Entity()
        let eye = SIMD3<Float>(BoardCamera.eye)
        camera.components.set(PerspectiveCameraComponent(near: 1, far: 120, fieldOfViewInDegrees: Float(BoardCamera.fieldOfView), fieldOfViewOrientation: .vertical))
        camera.position = eye
        camera.orientation = BoardCamera.facing
        return camera
    }

    private func addLights() {
        // A low sun from the back left casts the soft shadows seen in the renders; a cool fill lifts the fronts.
        let sun = Entity()
        sun.components.set(DirectionalLightComponent(color: UIColor(hex: 0xFFEBD0), intensity: 5600))
        sun.components.set(DirectionalLightComponent.Shadow(maximumDistance: 36, depthBias: 1))
        sun.orientation = Self.aimed(from: [-10, 17, -5], at: .zero)
        root.addChild(sun)

        let fill = Entity()
        fill.components.set(DirectionalLightComponent(color: UIColor(hex: 0xBFE8FF), intensity: 300))
        fill.orientation = Self.aimed(from: [6, 10, 14], at: .zero)
        root.addChild(fill)
    }

    /// Rotation that points an entity's -z (the way lights shine) from one point toward another.
    private static func aimed(from position: SIMD3<Float>, at target: SIMD3<Float>) -> simd_quatf {
        let forward = simd_normalize(target - position)
        let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
        return simd_quatf(simd_float3x3(columns: (right, simd_cross(right, forward), -forward)))
    }

    private func addSea() {
        let sea = ModelEntity(mesh: .generatePlane(width: 60, depth: 60), materials: [materials.sea])
        sea.position = [0, -0.35, 0]
        root.addChild(sea)
    }

    /// The hexagonal deck under the tiles, with mooring posts at the corners and along the edges.
    private func addDock() {
        let outline = (0..<6).map { corner -> SIMD2<Float> in
            let angle = Float(corner) * .pi / 3 + .pi / 6
            return BoardMaterials.dockRadius * SIMD2(cos(angle), sin(angle))
        }
        root.addChild(ModelEntity(mesh: BoardMesh.prisms([outline], bottom: -0.55, top: 0, textureSize: 3), materials: [materials.deckTop, materials.deckSide]))

        let post = BoardProp.color(0xA97443, roughness: 0.75)
        let cap = BoardProp.color(0xC08A55, roughness: 0.7)
        let rope = BoardProp.color(0xF4EFE4, roughness: 0.9)
        var spots: [SIMD2<Float>] = []
        for (index, corner) in outline.enumerated() {
            spots.append(corner * 0.99)
            spots.append((corner + outline[(index + 1) % 6]) / 2 * 0.99)
        }
        for spot in spots {
            let bollard = Entity()
            bollard.addChild(BoardProp.model(.generateCylinder(height: 0.8, radius: 0.27), post, at: [0, 0.05, 0]))
            let top = BoardProp.model(.generateSphere(radius: 0.27), cap, at: [0, 0.45, 0])
            top.scale = [1, 0.45, 1]
            bollard.addChild(top)
            bollard.addChild(BoardProp.model(.generateCylinder(height: 0.09, radius: 0.3), rope, at: [0, 0.2, 0]))
            bollard.position = [spot.x, 0, spot.y]
            root.addChild(bollard)
        }
    }

    /// The 61 raised plank tiles. Plank directions vary from tile to tile, as in the renders.
    private func addTiles() {
        for tile in Harbor.tiles {
            let c = BoardCamera.center(tile)
            let variant = abs(tile.q * 5 + tile.r * 3) % 3
            let angle = Float(variant) * .pi / 3 + .pi / 6
            let mesh = BoardMesh.prisms([BoardMesh.hexagon(center: SIMD2(Float(c.x), Float(c.y)), radius: 0.91)], bottom: -0.05, top: Self.tileTop, textureSize: 1.9, textureAngle: angle)
            let entity = ModelEntity(mesh: mesh, materials: [materials.tileTops[variant], materials.tileSide])
            tileLayer.addChild(entity)
            tiles[tile] = entity
        }
    }

    /// A flat, see-through square lying on the tiles, for highlights and rings.
    private func decal(_ material: UnlitMaterial, size: Float) -> ModelEntity {
        let entity = ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [material])
        entity.components.set(DynamicLightShadowComponent(castsShadow: false))
        return entity
    }
}

/// A meeple: the design's 3D render of the raccoon or hound, standing upright toward the camera like a
/// cut-out, on a coloured ring. It hops when it moves; a last-seen ghost is faded with a dashed ring.
@MainActor
private final class Pawn3D {
    let root = Entity()
    private(set) var tile: Hex
    private let lift = Entity()
    private let figure: ModelEntity

    init(_ piece: BoardPawn, materials: BoardMaterials) {
        tile = piece.tile
        let ring = Self.decal(materials.ring(piece.role, ghost: piece.ghost), size: 1.32)
        ring.position.y = 0.01
        let shadow = Self.decal(materials.blobShadow, size: 0.95)
        shadow.position.y = 0.009
        root.addChild(shadow)
        root.addChild(ring)

        figure = ModelEntity(mesh: .generatePlane(width: 1, height: 1), materials: [materials.token(piece.role)])
        figure.components.set(DynamicLightShadowComponent(castsShadow: false))
        lift.addChild(figure)
        root.addChild(lift)
        if piece.ghost { root.components.set(OpacityComponent(opacity: 0.5)) }
        place(on: piece.tile)
    }

    func move(to target: Hex) {
        tile = target
        var transform = root.transform
        transform.translation = BoardWorld.top(of: target)
        root.move(to: transform, relativeTo: root.parent, duration: 0.45, timingFunction: .easeInOut)
        figure.move(to: Self.figureTransform(on: target), relativeTo: lift, duration: 0.45, timingFunction: .easeInOut)
        let up = FromToByAnimation(from: Transform(), to: Transform(translation: [0, 0.55, 0]), duration: 0.2, timing: .easeOut, bindTarget: .transform)
        let down = FromToByAnimation(from: Transform(translation: [0, 0.55, 0]), to: Transform(), duration: 0.25, timing: .easeIn, bindTarget: .transform)
        if let hopUp = try? AnimationResource.generate(with: up), let hopDown = try? AnimationResource.generate(with: down),
           let hop = try? AnimationResource.sequence(with: [hopUp, hopDown]) {
            lift.playAnimation(hop)
        }
    }

    private func place(on tile: Hex) {
        root.position = BoardWorld.top(of: tile)
        figure.transform = Self.figureTransform(on: tile)
    }

    /// The cut-out faces the camera and is pulled toward it so its lower edge clears the tile; its size and
    /// anchor (the render's base sits 63% down the image) match how the mockup lays the render over a tile.
    private static func figureTransform(on tile: Hex) -> Transform {
        let base = BoardWorld.top(of: tile)
        let eye = SIMD3<Float>(BoardCamera.eye)
        let toEye = simd_normalize(eye - base)
        let pull: Float = 1.6
        let anchor = base + toEye * pull
        let shrink = simd_length(eye - anchor) / simd_length(eye - base)
        let width = 512 * 1.15 / 178.2 * shrink
        let up = SIMD3<Float>(BoardCamera.up)
        let center = anchor + up * (0.6259 - 0.5) * width
        return Transform(scale: [width, width, 1], rotation: BoardCamera.facing, translation: center - base)
    }

    private static func decal(_ material: UnlitMaterial, size: Float) -> ModelEntity {
        let entity = ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [material])
        entity.components.set(DynamicLightShadowComponent(castsShadow: false))
        return entity
    }
}
