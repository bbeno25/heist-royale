import HeistCore
import RealityKit
import UIKit
import simd

/// Meshes the board needs that RealityKit has no generator for, built from triangles.
@MainActor
enum BoardMesh {
    /// A flat-topped hexagon's corners around a centre in the x–z plane.
    static func hexagon(center: SIMD2<Float> = .zero, radius: Float, rotation: Float = 0) -> [SIMD2<Float>] {
        (0..<6).map { corner in
            let angle = Float(corner) * .pi / 3 + rotation
            return center + radius * SIMD2(cos(angle), sin(angle))
        }
    }

    /// Vertical prisms over convex outlines in the x–z plane: a top cap (material 0) with planar texture
    /// coordinates and the sides (material 1). Several outlines go into one mesh.
    static func prisms(_ outlines: [[SIMD2<Float>]], bottom: Float, top: Float, textureSize: Float = 2, textureAngle: Float = 0) -> MeshResource {
        var builder = TriangleBuilder()
        let (s, c) = (sin(textureAngle), cos(textureAngle))
        for outline in outlines {
            let center = outline.reduce(SIMD2<Float>.zero, +) / Float(outline.count)
            func uv(_ p: SIMD2<Float>) -> SIMD2<Float> {
                let d = p - center
                return SIMD2(c * d.x - s * d.y, s * d.x + c * d.y) / textureSize + 0.5
            }
            for index in outline.indices {
                let a = outline[index], b = outline[(index + 1) % outline.count]
                builder.triangle(
                    (SIMD3(center.x, top, center.y), uv(center)),
                    (SIMD3(a.x, top, a.y), uv(a)),
                    (SIMD3(b.x, top, b.y), uv(b)),
                    normal: SIMD3(0, 1, 0), material: 0
                )
                let edge = b - a
                let outward = simd_normalize(SIMD3(edge.y, 0, -edge.x)) * (simd_dot(SIMD2(edge.y, -edge.x), a - center) < 0 ? -1 : 1)
                let length = simd_length(edge)
                builder.quad(
                    (SIMD3(a.x, top, a.y), SIMD2(0, 0)), (SIMD3(b.x, top, b.y), SIMD2(length, 0)),
                    (SIMD3(b.x, bottom, b.y), SIMD2(length, top - bottom)), (SIMD3(a.x, bottom, a.y), SIMD2(0, top - bottom)),
                    normal: outward, material: 1
                )
            }
        }
        return builder.mesh(named: "prisms")
    }

    /// A flat triangle in the x–y plane (the boat's sail), visible from both sides via its material.
    static func triangle(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> MeshResource {
        var builder = TriangleBuilder()
        builder.triangle((SIMD3(a.x, a.y, 0), .zero), (SIMD3(b.x, b.y, 0), SIMD2(1, 0)), (SIMD3(c.x, c.y, 0), SIMD2(0, 1)), normal: SIMD3(0, 0, 1), material: 0)
        return builder.mesh(named: "triangle")
    }
}

/// Collects triangles with normals, texture coordinates and per-face materials.
@MainActor
private struct TriangleBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var uvs: [SIMD2<Float>] = []
    private var indices: [UInt32] = []
    private var faceMaterials: [UInt32] = []

    /// Adds a triangle, flipping its winding if needed so it faces along `normal`.
    mutating func triangle(_ a: (SIMD3<Float>, SIMD2<Float>), _ b: (SIMD3<Float>, SIMD2<Float>), _ c: (SIMD3<Float>, SIMD2<Float>), normal: SIMD3<Float>, material: UInt32) {
        let facing = simd_dot(simd_cross(b.0 - a.0, c.0 - a.0), normal) >= 0
        let ordered = facing ? [a, b, c] : [a, c, b]
        for vertex in ordered {
            indices.append(UInt32(positions.count))
            positions.append(vertex.0)
            normals.append(normal)
            uvs.append(SIMD2(vertex.1.x, 1 - vertex.1.y))
        }
        faceMaterials.append(material)
    }

    mutating func quad(_ a: (SIMD3<Float>, SIMD2<Float>), _ b: (SIMD3<Float>, SIMD2<Float>), _ c: (SIMD3<Float>, SIMD2<Float>), _ d: (SIMD3<Float>, SIMD2<Float>), normal: SIMD3<Float>, material: UInt32) {
        triangle(a, b, c, normal: normal, material: material)
        triangle(a, c, d, normal: normal, material: material)
    }

    func mesh(named name: String) -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(faceMaterials)
        // The inputs are built here, so a failure is a programming error.
        return try! MeshResource.generate(from: [descriptor])
    }
}

/// Texture pictures painted with Core Graphics: wood, barrel staves, the net, rock, the sea and tile
/// highlights. `BoardMaterials` turns them into RealityKit textures.
@MainActor
enum BoardTexture {
    static func make(_ size: Int, _ draw: (CGContext, CGFloat) -> Void) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            draw(context.cgContext, CGFloat(size))
        }
        return image.cgImage!
    }

    /// Planks with grain, seams and the odd end joint, like the tiles in the renders.
    static func planks(light: UIColor, dark: UIColor, seam: UIColor, count: Int = 7, seed: Int = 1) -> CGImage {
        make(256) { context, size in
            var random = SeededRandom(seed: UInt64(seed))
            let width = size / CGFloat(count)
            for plank in 0..<count {
                let mix = CGFloat.random(in: 0...1, using: &random)
                context.setFillColor(blend(light, dark, mix * 0.6).cgColor)
                let x = CGFloat(plank) * width
                context.fill(CGRect(x: x, y: 0, width: width, height: size))
                context.setStrokeColor(dark.withAlphaComponent(0.25).cgColor)
                context.setLineWidth(1)
                for _ in 0..<5 {
                    let gx = x + CGFloat.random(in: 3...(width - 3), using: &random)
                    context.move(to: CGPoint(x: gx, y: 0))
                    context.addCurve(to: CGPoint(x: gx + CGFloat.random(in: -3...3, using: &random), y: size),
                                     control1: CGPoint(x: gx + 3, y: size * 0.3), control2: CGPoint(x: gx - 3, y: size * 0.7))
                }
                context.strokePath()
                let joint = CGFloat.random(in: 0.15...0.85, using: &random) * size
                context.setFillColor(seam.withAlphaComponent(0.7).cgColor)
                context.fill(CGRect(x: x, y: joint, width: width, height: 2))
                context.setFillColor(seam.cgColor)
                context.fill(CGRect(x: x, y: 0, width: 2, height: size))
                context.setFillColor(seam.withAlphaComponent(0.5).cgColor)
                context.fill(CGRect(x: x + width / 2 - 1, y: joint - 8, width: 2, height: 2))
                context.fill(CGRect(x: x + width / 2 - 1, y: joint + 8, width: 2, height: 2))
            }
        }
    }

    /// Vertical barrel staves.
    static let staves = make(128) { context, size in
        let colors = [UIColor(hex: 0xDDB077), UIColor(hex: 0xD1A066), UIColor(hex: 0xE4BA82), UIColor(hex: 0xC99858)]
        let width = size / 12
        for stave in 0..<12 {
            context.setFillColor(colors[stave % colors.count].cgColor)
            context.fill(CGRect(x: CGFloat(stave) * width, y: 0, width: width, height: size))
            context.setFillColor(UIColor(hex: 0x8A5E34, alpha: 0.6).cgColor)
            context.fill(CGRect(x: CGFloat(stave) * width, y: 0, width: 1.5, height: size))
        }
    }

    /// Teal fishing net with a light mesh.
    static let net = make(256) { context, size in
        context.setFillColor(UIColor(hex: 0x2B8C80).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setStrokeColor(UIColor(hex: 0xD4F5EE, alpha: 0.85).cgColor)
        context.setLineWidth(3)
        let step = size / 16
        for line in 0...32 {
            let offset = CGFloat(line) * step - size
            context.move(to: CGPoint(x: offset, y: 0))
            context.addLine(to: CGPoint(x: offset + size, y: size))
            context.move(to: CGPoint(x: offset + size, y: 0))
            context.addLine(to: CGPoint(x: offset, y: size))
        }
        context.strokePath()
    }

    /// Pale rock with moss.
    static let rock = make(128) { context, size in
        var random = SeededRandom(seed: 7)
        context.setFillColor(UIColor(hex: 0xD8D6CC).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        for _ in 0..<26 {
            let r = CGFloat.random(in: 4...16, using: &random)
            let p = CGPoint(x: CGFloat.random(in: 0...size, using: &random), y: CGFloat.random(in: 0...size, using: &random))
            let moss = Bool.random(using: &random)
            context.setFillColor((moss ? UIColor(hex: 0xA9C48E, alpha: 0.7) : UIColor(hex: 0xC2BEB2, alpha: 0.7)).cgColor)
            context.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }

    /// The sea under and around the dock: bright turquoise near the dock, deeper further out,
    /// with a band of foam along the dock's edge. Covers 60×60 world units.
    static func sea(dockRadius: Float) -> CGImage {
        make(1024) { context, size in
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(hex: 0x2AB2C8).cgColor, UIColor(hex: 0x1B97B5).cgColor, UIColor(hex: 0x10708F).cgColor, UIColor(hex: 0x0A4E6E).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.3, 0.55, 1])!
            let center = CGPoint(x: size / 2, y: size / 2)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size * 0.62, options: [.drawsAfterEndLocation])

            let unit = size / 60
            var random = SeededRandom(seed: 3)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.1).cgColor)
            context.setLineWidth(2)
            for _ in 0..<160 {
                let p = CGPoint(x: CGFloat.random(in: 0...size, using: &random), y: CGFloat.random(in: 0...size, using: &random))
                let w = CGFloat.random(in: 8...26, using: &random)
                context.move(to: p)
                context.addQuadCurve(to: CGPoint(x: p.x + w, y: p.y), control: CGPoint(x: p.x + w / 2, y: p.y - 4))
            }
            context.strokePath()

            // Foam hugging the dock: a soft white band just outside the deck's outline.
            let corners = (0..<6).map { corner -> CGPoint in
                let angle = CGFloat(corner) * .pi / 3 + .pi / 6
                return CGPoint(x: center.x + cos(angle) * CGFloat(dockRadius) * unit, y: center.y + sin(angle) * CGFloat(dockRadius) * unit)
            }
            context.setShadow(offset: .zero, blur: unit * 0.7, color: UIColor.white.cgColor)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.75).cgColor)
            context.setLineWidth(unit * 0.35)
            context.addLines(between: corners + [corners[0]])
            context.strokePath()
        }
    }

    /// The sky around the board as an equirectangular picture; it lights the scene softly from all
    /// sides (bright above, warm at the horizon, dark below), so the sun's shadows still read.
    static func sky() -> CGImage {
        make(512) { context, size in
            let colors = [UIColor(hex: 0x7299B6).cgColor, UIColor(hex: 0xBFB298).cgColor, UIColor(hex: 0x4E5E68).cgColor, UIColor(hex: 0x1A242C).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.48, 0.55, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
        }
    }

    /// A tile highlight: fill and an outline, optionally dashed, drawn on a square that spans 1.7 world units.
    static func highlight(fill: UIColor, stroke: UIColor, lineWidth: CGFloat, dash: [CGFloat], glow: Bool = false) -> CGImage {
        make(256) { context, size in
            let unit = size / 1.7
            let center = CGPoint(x: size / 2, y: size / 2)
            let path = CGMutablePath()
            path.addLines(between: (0..<6).map { corner in
                let angle = CGFloat(corner) * .pi / 3
                return CGPoint(x: center.x + cos(angle) * 0.82 * unit, y: center.y + sin(angle) * 0.82 * unit)
            })
            path.closeSubpath()
            if glow {
                context.setShadow(offset: .zero, blur: 14, color: stroke.cgColor)
                context.setStrokeColor(stroke.cgColor)
                context.setLineWidth(10)
                context.addPath(path)
                context.strokePath()
                context.setShadow(offset: .zero, blur: 0, color: nil)
            }
            context.setFillColor(fill.cgColor)
            context.addPath(path)
            context.fillPath()
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineJoin(.round)
            context.setLineDash(phase: 0, lengths: dash)
            context.addPath(path)
            context.strokePath()
        }
    }

    /// The ring under a meeple, solid or dashed for a last-seen ghost.
    static func ring(_ color: UIColor, dashed: Bool) -> CGImage {
        make(256) { context, size in
            let inset = size * 0.08
            let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
            if !dashed {
                context.setFillColor(color.withAlphaComponent(0.25).cgColor)
                context.fillEllipse(in: rect)
            }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(size * 0.045)
            if dashed { context.setLineDash(phase: 0, lengths: [size * 0.07, size * 0.05]) }
            context.strokeEllipse(in: rect)
        }
    }

    /// A soft round shadow for pieces that are pictures rather than models.
    static let blobShadow = make(128) { context, size in
        let colors = [UIColor.black.withAlphaComponent(0.5).cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        let center = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size / 2, options: [])
    }

    private static func blend(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var (ar, ag, ab, aa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (br, bg, bb, ba): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
    }
}

extension UIColor {
    /// A colour from a 0xRRGGBB value, as written in the design files.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
