import RealityKit
import simd
import UIKit

/// The board's 3D pieces, built from simple shapes in the style of the design's renders. Each model
/// stands on the origin (the top of its tile), roughly a tile wide, front facing the camera (+z).
@MainActor
enum BoardProp {
    static func make(_ art: String, _ materials: BoardMaterials) -> Entity {
        let entity = build(art, materials)
        // The renders show the pieces big on their tiles.
        entity.scale = SIMD3(repeating: scale[art] ?? 1.3)
        return entity
    }

    private static let scale: [String: Float] = [
        "art-barrel": 1.6, "art-net": 1.5, "art-cave": 1.35, "art-chest": 1.75, "art-chestopen": 1.75, "art-reinforced": 1.75,
        "art-exit": 1.4, "art-mystery": 1.7, "art-camera": 1.5, "art-dummycam": 1.5,
    ]

    private static func build(_ art: String, _ materials: BoardMaterials) -> Entity {
        switch art {
        case "art-barrel": barrels(materials)
        case "art-net": net(materials)
        case "art-cave": cave(materials)
        case "art-chest": chest(.closed, materials)
        case "art-chestopen": chest(.open, materials)
        case "art-reinforced": chest(.reinforced, materials)
        case "art-exit": boat(materials)
        case "art-mystery": mysteryBox()
        case "art-camera": camera(body: 0x8D95A8)
        case "art-dummycam": camera(body: 0xC9A36A)
        case "art-detector": detector()
        case "art-sapling": sapling()
        case "art-lookout": lookout()
        case "art-smokebomb": smokeCache()
        default: Entity()
        }
    }

    // MARK: Terrain

    /// Three barrels standing together (the harbour's rocks).
    static func barrels(_ materials: BoardMaterials) -> Entity {
        let group = Entity()
        for (x, z) in [(Float(-0.19), Float(0.12)), (0.19, 0.12), (0, -0.19)] {
            let barrel = Entity()
            barrel.addChild(model(.generateCylinder(height: 0.42, radius: 0.18), materials.staves, at: [0, 0.21, 0]))
            for y in [Float(0.09), 0.33] {
                barrel.addChild(model(.generateCylinder(height: 0.035, radius: 0.186), color(0x8C6440, roughness: 0.6), at: [0, y, 0]))
            }
            barrel.addChild(model(.generateCylinder(height: 0.01, radius: 0.165), color(0xEDCB95, roughness: 0.8), at: [0, 0.425, 0]))
            barrel.position = [x, 0, z]
            group.addChild(barrel)
        }
        return group
    }

    /// A dome of fishing net with floats (the harbour's bushes).
    static func net(_ materials: BoardMaterials) -> Entity {
        let group = Entity()
        let dome = model(.generateSphere(radius: 0.42), materials.net, at: [0, 0, 0])
        dome.scale = [1, 0.78, 1]
        group.addChild(dome)
        let float = color(0xF6B43A, roughness: 0.4)
        for index in 0..<7 {
            let around = Float(index) / 7 * 2 * .pi + 0.3
            let lift: Float = index % 2 == 0 ? 0.55 : 0.95
            let p = SIMD3(cos(around) * cos(lift) * 0.42, sin(lift) * 0.42 * 0.78, sin(around) * cos(lift) * 0.42)
            group.addChild(model(.generateSphere(radius: 0.05), float, at: p))
        }
        return group
    }

    /// A pale sea-cave rock with a dark opening toward the viewer (the tunnel ends).
    static func cave(_ materials: BoardMaterials) -> Entity {
        let group = Entity()
        let rock = model(.generateSphere(radius: 0.6), materials.rock, at: [0, 0.04, -0.04])
        rock.scale = [1.05, 0.75, 0.88]
        group.addChild(rock)
        let mouth = model(.generateCylinder(height: 0.06, radius: 0.24), color(0x2F2925, roughness: 1), at: [0, 0.06, 0.46])
        mouth.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        mouth.scale = [1, 1, 1.25]
        group.addChild(mouth)
        return group
    }

    /// A boat waiting in a water cut-out (an exit, as the thief sees it).
    static func boat(_ materials: BoardMaterials) -> Entity {
        let group = Entity()
        let water = model(.generatePlane(width: 1.55, depth: 1.55), materials.exitWater, at: [0, -0.13, 0])
        group.addChild(water)

        let hull = Entity()
        hull.addChild(model(.generateBox(width: 0.62, height: 0.13, depth: 0.24, cornerRadius: 0.06), color(0xD9463B, roughness: 0.5), at: [0, -0.06, 0]))
        hull.addChild(model(.generateBox(width: 0.6, height: 0.05, depth: 0.25, cornerRadius: 0.02), color(0xF7F3EA, roughness: 0.5), at: [0, 0.02, 0]))
        hull.addChild(model(.generateCylinder(height: 0.55, radius: 0.014), color(0x8A5E34), at: [0.02, 0.3, 0]))
        let sail = ModelEntity(mesh: BoardMesh.triangle([0.04, 0.12], [0.04, 0.56], [0.27, 0.14]), materials: [doubleSided(0xFFFFFF)])
        hull.addChild(sail)
        hull.orientation = simd_quatf(angle: -0.5, axis: [0, 1, 0])
        group.addChild(hull)

        // Rocks gently on the water.
        let rest = hull.transform
        var tilted = rest
        tilted.rotation = simd_quatf(angle: 0.07, axis: [1, 0, 0]) * rest.rotation
        tilted.translation.y += 0.02
        let bob = FromToByAnimation(from: rest, to: tilted, duration: 1.8, timing: .easeInOut, bindTarget: .transform, repeatMode: .autoReverse)
        if let animation = try? AnimationResource.generate(with: bob) { hull.playAnimation(animation) }
        return group
    }

    // MARK: Chests and boxes

    enum ChestLook { case closed, open, reinforced }

    static func chest(_ look: ChestLook, _ materials: BoardMaterials) -> Entity {
        let group = Entity()
        let wood = materials.chestWood
        // Painted trim, as in the renders: bright gold, or steel on a reinforced chest.
        let trim = look == .reinforced ? color(0xC9CED8, roughness: 0.35, metallic: 0.3) : color(0xFFCE45, roughness: 0.4, metallic: 0.15)
        group.addChild(model(.generateBox(width: 0.5, height: 0.27, depth: 0.34, cornerRadius: 0.03), wood, at: [0, 0.135, 0]))
        // Gold edges: corner posts, the base rim and the top rim, plus two straps.
        for x in [Float(-0.24), 0.24] {
            for z in [Float(-0.16), 0.16] {
                group.addChild(model(.generateBox(width: 0.045, height: 0.28, depth: 0.045, cornerRadius: 0.01), trim, at: [x, 0.14, z]))
            }
        }
        for y in [Float(0.02), 0.255] {
            group.addChild(model(.generateBox(width: 0.53, height: 0.04, depth: 0.37, cornerRadius: 0.01), trim, at: [0, y, 0]))
        }
        for x in [Float(-0.13), 0.13] {
            group.addChild(model(.generateBox(width: 0.04, height: 0.27, depth: 0.355, cornerRadius: 0.01), trim, at: [x, 0.135, 0]))
        }

        // The rounded lid hinges at the back.
        let hinge = Entity()
        hinge.position = [0, 0.27, -0.17]
        let lid = model(.generateCylinder(height: 0.5, radius: 0.17), wood, at: [0, 0, 0.17])
        lid.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        lid.scale = [0.8, 1, 1]
        hinge.addChild(lid)
        for x in [Float(-0.24), -0.13, 0.13, 0.24] {
            let band = model(.generateCylinder(height: x.magnitude > 0.2 ? 0.035 : 0.04, radius: 0.178), trim, at: [x, 0, 0.17])
            band.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            band.scale = [0.8, 1, 1]
            hinge.addChild(band)
        }
        group.addChild(hinge)

        switch look {
        case .closed:
            group.addChild(model(.generateBox(width: 0.09, height: 0.1, depth: 0.03, cornerRadius: 0.01), trim, at: [0, 0.22, 0.17]))
        case .reinforced:
            let lock = Entity()
            lock.addChild(model(.generateBox(width: 0.11, height: 0.1, depth: 0.04, cornerRadius: 0.015), trim, at: [0, 0, 0]))
            for x in [Float(-0.035), 0.035] {
                lock.addChild(model(.generateCylinder(height: 0.07, radius: 0.012), trim, at: [x, 0.075, 0]))
            }
            lock.addChild(model(.generateBox(width: 0.094, height: 0.024, depth: 0.024, cornerRadius: 0.01), trim, at: [0, 0.108, 0]))
            lock.position = [0, 0.17, 0.2]
            group.addChild(lock)
        case .open:
            hinge.orientation = simd_quatf(angle: -1.9, axis: [1, 0, 0])
            let gold = color(0xF6C445, roughness: 0.3, metallic: 0.7)
            for (index, p) in [SIMD3<Float>(-0.12, 0.28, 0.02), [0.06, 0.29, -0.04], [0.14, 0.28, 0.06], [-0.02, 0.3, 0.07], [0.0, 0.31, -0.02]].enumerated() {
                let coin = model(.generateCylinder(height: 0.016, radius: 0.05), gold, at: p)
                coin.orientation = simd_quatf(angle: Float(index) * 0.3, axis: [1, 0, 0.4])
                group.addChild(coin)
            }
            group.addChild(model(.generateSphere(radius: 0.045), color(0x6EE7FF, roughness: 0.1, metallic: 0.3), at: [-0.08, 0.33, -0.05]))
            group.addChild(model(.generateBox(width: 0.07, height: 0.07, depth: 0.07, cornerRadius: 0.01), color(0x5AA2FF, roughness: 0.1, metallic: 0.3), at: [0.1, 0.33, 0.0]))
        }
        return group
    }

    /// A purple gift box with a gold ribbon, turning slowly (a mystery box).
    static func mysteryBox() -> Entity {
        let group = Entity()
        let box = Entity()
        let ribbon = color(0xF7D26A, roughness: 0.35, metallic: 0.4)
        box.addChild(model(.generateBox(width: 0.34, height: 0.32, depth: 0.34, cornerRadius: 0.03), color(0xA27CF0, roughness: 0.5), at: [0, 0.16, 0]))
        box.addChild(model(.generateBox(width: 0.07, height: 0.33, depth: 0.35), ribbon, at: [0, 0.16, 0]))
        box.addChild(model(.generateBox(width: 0.35, height: 0.33, depth: 0.07), ribbon, at: [0, 0.16, 0]))
        for x in [Float(-0.05), 0.05] {
            let bow = model(.generateSphere(radius: 0.055), ribbon, at: [x, 0.35, 0])
            bow.scale = [1.2, 0.7, 0.8]
            box.addChild(bow)
        }
        group.addChild(box)
        let spin = FromToByAnimation(from: Transform(), to: Transform(rotation: simd_quatf(angle: .pi, axis: [0, 1, 0])), duration: 3, timing: .linear, bindTarget: .transform, repeatMode: .cumulative)
        if let animation = try? AnimationResource.generate(with: spin) { box.playAnimation(animation) }
        return group
    }

    // MARK: Prep pieces

    /// A security camera on a pole (grey), or the dummy (tan).
    static func camera(body: UInt32) -> Entity {
        let group = Entity()
        let metal = color(0x6E7487, roughness: 0.35, metallic: 0.6)
        group.addChild(model(.generateCylinder(height: 0.03, radius: 0.12), metal, at: [0, 0.015, 0]))
        group.addChild(model(.generateCylinder(height: 0.48, radius: 0.022), metal, at: [0, 0.25, 0]))
        let head = Entity()
        head.addChild(model(.generateBox(width: 0.26, height: 0.11, depth: 0.13, cornerRadius: 0.02), color(body, roughness: 0.4, metallic: 0.3), at: [0, 0, 0]))
        let lens = model(.generateCylinder(height: 0.03, radius: 0.035), color(0x1C2030, roughness: 0.1), at: [0.14, 0, 0])
        lens.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        head.addChild(lens)
        head.position = [0.04, 0.53, 0]
        head.orientation = simd_quatf(angle: -0.6, axis: [0, 1, 0]) * simd_quatf(angle: -0.35, axis: [0, 0, 1])
        group.addChild(head)
        return group
    }

    static func detector() -> Entity {
        let group = Entity()
        group.addChild(model(.generateCylinder(height: 0.05, radius: 0.17), color(0x9AA0AE, roughness: 0.3, metallic: 0.6), at: [0, 0.025, 0]))
        group.addChild(model(.generateCylinder(height: 0.02, radius: 0.13), glowing(0xFF5F7E), at: [0, 0.055, 0]))
        let dome = model(.generateSphere(radius: 0.09), color(0x2B2F3A, roughness: 0.15), at: [0, 0.06, 0])
        dome.scale = [1, 0.6, 1]
        group.addChild(dome)
        return group
    }

    /// A young bush the thief planted.
    static func sapling() -> Entity {
        let group = Entity()
        let leaf = color(0x52B35A, roughness: 0.8)
        for (p, r) in [(SIMD3<Float>(-0.12, 0.16, 0.04), Float(0.18)), ([0.12, 0.15, 0.03], 0.17), ([0, 0.24, -0.06], 0.2)] {
            group.addChild(model(.generateSphere(radius: r), leaf, at: p))
        }
        return group
    }

    /// A brass spyglass on a tripod.
    static func lookout() -> Entity {
        let group = Entity()
        let wood = color(0x8A5E34)
        for index in 0..<3 {
            let angle = Float(index) * 2 * .pi / 3
            let leg = model(.generateCylinder(height: 0.46, radius: 0.016), wood, at: [cos(angle) * 0.08, 0.21, sin(angle) * 0.08])
            leg.orientation = simd_quatf(angle: 0.3, axis: [sin(angle), 0, -cos(angle)])
            group.addChild(leg)
        }
        let glass = model(.generateCylinder(height: 0.36, radius: 0.04), color(0xE2B34C, roughness: 0.3, metallic: 0.8), at: [0, 0.46, 0])
        glass.orientation = simd_quatf(angle: -0.25, axis: [1, 0, 0]) * simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        group.addChild(glass)
        return group
    }

    /// A hidden smoke canister in a puff of smoke.
    static func smokeCache() -> Entity {
        let group = Entity()
        group.addChild(model(.generateCylinder(height: 0.16, radius: 0.06), color(0x6A45C2, roughness: 0.4), at: [0.1, 0.08, 0.08]))
        let puff = color(0xD8DCE4, roughness: 0.9)
        for (p, r) in [(SIMD3<Float>(-0.08, 0.16, 0), Float(0.15)), ([0.06, 0.24, -0.05], 0.13), ([-0.02, 0.3, 0.04], 0.1)] {
            group.addChild(model(.generateSphere(radius: r), puff, at: p))
        }
        return group
    }

    // MARK: Materials

    static func model(_ mesh: MeshResource, _ material: some Material, at position: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position
        return entity
    }

    static func color(_ hex: UInt32, roughness: Float = 0.7, metallic: Float = 0) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(hex: hex))
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        return material
    }

    static func textured(_ texture: TextureResource, roughness: Float, transparent: Bool = false) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.roughness = .init(floatLiteral: roughness)
        if transparent { material.blending = .transparent(opacity: .init(floatLiteral: 1)) }
        return material
    }

    static func glowing(_ hex: UInt32) -> UnlitMaterial {
        UnlitMaterial(color: UIColor(hex: hex))
    }

    static func doubleSided(_ hex: UInt32) -> PhysicallyBasedMaterial {
        var material = color(hex, roughness: 0.8)
        material.faceCulling = .none
        return material
    }

}
