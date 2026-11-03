import RealityKit
import UIKit

/// Every material the 3D board uses, with its textures loaded once (RealityKit loads textures
/// asynchronously) before the board is built.
@MainActor
final class BoardMaterials {
    let tileTops: [PhysicallyBasedMaterial]
    let tileSide: PhysicallyBasedMaterial
    let deckTop: PhysicallyBasedMaterial
    let deckSide: PhysicallyBasedMaterial
    let sea: PhysicallyBasedMaterial
    let staves: PhysicallyBasedMaterial
    let net: PhysicallyBasedMaterial
    let rock: PhysicallyBasedMaterial
    let chestWood: PhysicallyBasedMaterial
    let exitWater: PhysicallyBasedMaterial
    let highlights: [TileOverlay: UnlitMaterial]
    let blobShadow: UnlitMaterial
    let glowHalo: TextureResource
    let glowFill: TextureResource
    let glowOutline: TextureResource
    let environment: EnvironmentResource
    private let rings: [String: UnlitMaterial]
    private let tokens: [Role: UnlitMaterial]

    static let dockRadius: Float = 8.3

    private static var loading: Task<BoardMaterials, Error>?

    /// The materials, loaded once and shared by every board (each round's, and the replay's).
    static func shared() async throws -> BoardMaterials {
        if let loading { return try await loading.value }
        let task = Task { try await BoardMaterials() }
        loading = task
        return try await task.value
    }

    init() async throws {
        func texture(_ image: CGImage) async throws -> TextureResource {
            try await TextureResource(image: image, options: .init(semantic: .color))
        }
        func lit(_ image: CGImage, roughness: Float, transparent: Bool = false) async throws -> PhysicallyBasedMaterial {
            BoardProp.textured(try await texture(image), roughness: roughness, transparent: transparent)
        }
        func flat(_ image: CGImage) async throws -> UnlitMaterial {
            Self.decal(try await texture(image))
        }

        var tops: [PhysicallyBasedMaterial] = []
        for seed in 1...3 {
            tops.append(try await lit(BoardTexture.planks(light: UIColor(hex: 0xC48A50), dark: UIColor(hex: 0x95602F), seam: UIColor(hex: 0x5A3519), count: 7, seed: seed), roughness: 0.75))
        }
        tileTops = tops
        tileSide = BoardProp.color(0x8A5A30, roughness: 0.8)
        deckTop = try await lit(BoardTexture.planks(light: UIColor(hex: 0x9C6838), dark: UIColor(hex: 0x74471F), seam: UIColor(hex: 0x472A14), count: 9, seed: 5), roughness: 0.8)
        deckSide = BoardProp.color(0x7A4E2A, roughness: 0.85)
        sea = try await lit(BoardTexture.sea(dockRadius: Self.dockRadius), roughness: 0.85)
        staves = try await lit(BoardTexture.staves, roughness: 0.75)
        net = try await lit(BoardTexture.net, roughness: 0.85)
        rock = try await lit(BoardTexture.rock, roughness: 0.95)
        chestWood = try await lit(BoardTexture.planks(light: UIColor(hex: 0xD99A55), dark: UIColor(hex: 0xA8642B), seam: UIColor(hex: 0x6B3A16), count: 5, seed: 11), roughness: 0.65)
        exitWater = try await lit(BoardTexture.highlight(fill: UIColor(hex: 0x52D8E6), stroke: UIColor(white: 1, alpha: 0.8), lineWidth: 7, dash: []), roughness: 0.2, transparent: true)

        // Highlight looks from the board mockup, drawn bolder so they read on the wood at board scale.
        highlights = [
            .valid: try await flat(BoardTexture.highlight(fill: UIColor(white: 1, alpha: 0.16), stroke: UIColor(white: 1, alpha: 0.9), lineWidth: 9, dash: [18, 13])),
            .vision: try await flat(BoardTexture.highlight(fill: UIColor(hex: 0x5AA2FF, alpha: 0.5), stroke: UIColor(hex: 0xBFE0FF), lineWidth: 10, dash: [])),
            .scan: try await flat(BoardTexture.highlight(fill: UIColor(hex: 0x6EE7FF, alpha: 0.48), stroke: UIColor(hex: 0x9FF0FF), lineWidth: 10, dash: [22, 14])),
            .reach: try await flat(BoardTexture.highlight(fill: UIColor(hex: 0xFFC94D, alpha: 0.55), stroke: UIColor(hex: 0xFFE07A), lineWidth: 12, dash: [])),
            .watched: try await flat(BoardTexture.highlight(fill: UIColor(hex: 0xFF5F7E, alpha: 0.45), stroke: UIColor(hex: 0xFF9FB2), lineWidth: 10, dash: [20, 13])),
            .thiefStart: try await flat(BoardTexture.highlight(fill: .clear, stroke: UIColor(hex: 0xFFB547), lineWidth: 12, dash: [24, 15])),
            .policeStart: try await flat(BoardTexture.highlight(fill: .clear, stroke: UIColor(hex: 0x5AA2FF), lineWidth: 12, dash: [24, 15])),
        ]
        glowHalo = try await texture(BoardTexture.highlight(fill: .clear, stroke: .white, lineWidth: 18, dash: [], glow: true))
        glowFill = try await texture(BoardTexture.highlight(fill: UIColor(white: 1, alpha: 0.35), stroke: .clear, lineWidth: 0, dash: []))
        glowOutline = try await texture(BoardTexture.highlight(fill: .clear, stroke: .white, lineWidth: 10, dash: []))
        blobShadow = try await flat(BoardTexture.blobShadow)
        environment = try await EnvironmentResource(equirectangular: BoardTexture.sky(), withName: "board-sky")

        var rings: [String: UnlitMaterial] = [:]
        var tokens: [Role: UnlitMaterial] = [:]
        for role in [Role.thief, .police] {
            for ghost in [false, true] {
                rings["\(role)\(ghost)"] = try await flat(BoardTexture.ring(UIColor(role.color), dashed: ghost))
            }
            // The design's render of the meeple, seen from the board camera's angle.
            let image = UIImage(named: role == .thief ? "token-thief" : "token-police")!.cgImage!
            tokens[role] = try await flat(image)
        }
        self.rings = rings
        self.tokens = tokens
    }

    func ring(_ role: Role, ghost: Bool) -> UnlitMaterial { rings["\(role)\(ghost)"]! }

    func token(_ role: Role) -> UnlitMaterial { tokens[role]! }

    /// An unlit, see-through material showing a texture as is.
    static func decal(_ texture: TextureResource, tint: UIColor = .white) -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: tint, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        return material
    }
}
