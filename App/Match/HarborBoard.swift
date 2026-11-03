import HeistCore
import RealityKit
import simd
import SwiftUI

/// The Pirate Harbor board: a live 3D scene (see `BoardWorld`) seen through the match mockups' tilted
/// camera, with the floating tile tag, taps and VoiceOver on top. The same camera maths places the
/// SwiftUI layer, so it lines up with the 3D scene.
struct HarborBoard: View {
    let scene: BoardScene
    let onTap: (Hex) -> Void

    @State private var world: BoardWorld?

    var body: some View {
        GeometryReader { geometry in
            let camera = BoardCamera(width: geometry.size.width)
            ZStack(alignment: .topLeading) {
                RealityView { content in
                    content.camera = .virtual
                    do {
                        let materials = try await BoardMaterials.shared()
                        content.environment = .skybox(materials.environment)
                        let built = BoardWorld(materials: materials)
                        built.update(scene)
                        content.add(built.root)
                        world = built
                    } catch {
                        assertionFailure("Board materials failed to load: \(error)")
                    }
                } update: { _ in
                    world?.update(scene)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear { LiveBoards.shared.count += 1 }
                .onDisappear { LiveBoards.shared.count -= 1 }

                if let tag = scene.tag {
                    TagView(tag: tag, camera: camera)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }

                // VoiceOver: one invisible element per tile over the 3D view. (Synthesised
                // `accessibilityChildren` on this container stops the 3D view from drawing.)
                ForEach(Harbor.tiles, id: \.self) { tile in
                    let frame = camera.frame(of: tile)
                    Color.clear
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityElement()
                        .accessibilityLabel(accessibilityText(for: tile))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onTap(tile) }
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.35), value: scene.tag)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                if let tile = camera.tile(at: point) { onTap(tile) }
            }
        }
    }

    private func accessibilityText(for tile: Hex) -> String {
        var parts = [Harbor.name(tile)]
        if let art = scene.props[tile] { parts.append(art.replacingOccurrences(of: "art-", with: "")) }
        switch scene.overlays[tile] {
        case .valid: parts.append("valid spot")
        case .vision: parts.append("covered by your camera")
        case .scan: parts.append("in scan area")
        case .reach: parts.append("you can move here")
        case .watched: parts.append("marked")
        case .thiefStart: parts.append("thief start")
        case .policeStart: parts.append("police start")
        case nil: break
        }
        for pawn in scene.pawns where pawn.tile == tile {
            parts.append(pawn.ghost ? "\(pawn.role.title) last seen" : pawn.role.title)
        }
        if scene.fog.contains(tile) { parts.append("in fog") }
        return parts.joined(separator: ", ")
    }
}

/// How many 3D boards are in the view tree. A RealityView that starts while another is still there
/// (say, the round's board fading out under the round result) gets no drawables and stays blank, so a
/// new board waits until `count` is 0.
@MainActor
@Observable
final class LiveBoards {
    static let shared = LiveBoards()
    var count = 0
}

/// The mockup's camera: a perspective view looking down on the board at about 50°.
/// Projects world points (x across, y up, z toward the viewer) into a 1083×900 picture, scaled to the view.
/// The 3D scene uses the same eye, direction and field of view.
struct BoardCamera: Equatable {
    /// View points per picture pixel.
    let scale: CGFloat

    private static let picture = CGSize(width: 1083, height: 900)
    static let eye = SIMD3<Double>(0, 23.7239821810004, 21.410694661251533)
    private static let tanHalfFOV = 0.23086819112556312
    private static let forward = simd_normalize(SIMD3<Double>(0, -0.1, 1.42) - eye)
    private static let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
    static let up = simd_cross(right, forward)

    /// Vertical field of view in degrees.
    static let fieldOfView = 2 * atan(tanHalfFOV) * 180 / .pi

    /// Rotation that points an entity's -z along the view and its +y up the screen (for the camera and
    /// for pieces that stand facing it).
    static let facing = simd_quatf(simd_float3x3(columns: (SIMD3<Float>(right), SIMD3<Float>(up), SIMD3<Float>(-forward))))

    init(width: CGFloat) {
        scale = width / Self.picture.width
    }

    /// The tile's centre on the board, in world units.
    static func center(_ tile: Hex) -> SIMD2<Double> {
        SIMD2(1.5 * Double(tile.q), 3.0.squareRoot() * (Double(tile.r) + Double(tile.q) / 2))
    }

    func point(_ world: SIMD3<Double>) -> CGPoint {
        let d = world - Self.eye
        let x = simd_dot(d, Self.right), y = simd_dot(d, Self.up), z = simd_dot(d, Self.forward)
        let w = Self.picture.width, h = Self.picture.height
        return CGPoint(x: (w / 2 + x / z / Self.tanHalfFOV * h / 2) * scale, y: (h / 2 - y / z / Self.tanHalfFOV * h / 2) * scale)
    }

    func point(_ tile: Hex, dx: Double = 0, height: Double = Double(BoardWorld.tileTop), dz: Double = 0) -> CGPoint {
        let c = Self.center(tile)
        return point(SIMD3(c.x + dx, height, c.y + dz))
    }

    /// A flat-topped hexagon around the tile at the given radius, on top of the tiles.
    func hexagon(_ tile: Hex, radius: Double) -> [CGPoint] {
        (0..<6).map { corner in
            let angle = Double(corner) * .pi / 3
            return point(tile, dx: radius * cos(angle), dz: radius * sin(angle))
        }
    }

    func frame(of tile: Hex) -> CGRect {
        let corners = hexagon(tile, radius: 0.86)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// The tile under a point, nearest tile first.
    func tile(at point: CGPoint) -> Hex? {
        Self.nearFirst.first { Path.polygon(hexagon($0, radius: 0.97)).contains(point) }
    }

    /// Tiles from the front of the board to the back.
    static let nearFirst = Harbor.tiles.sorted {
        let a = center($0), b = center($1)
        return a.y == b.y ? a.x < b.x : a.y > b.y
    }
}

extension Path {
    static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// The label floating over the chosen tile, such as "Camera · F4".
private struct TagView: View {
    let tag: TileTag
    let camera: BoardCamera

    var body: some View {
        let px = camera.scale
        let anchor = camera.point(tag.tile, height: 1.15)
        // A point-sized anchor with the label hanging above it, bottom edge on the anchor.
        Color.clear
            .frame(width: 1, height: 1)
            .overlay(alignment: .bottom) {
                Text(tag.text)
                    .font(BrandFont.nunito(30 * px, 900))
                    .foregroundStyle(tag.foreground)
                    .fixedSize()
                    .padding(.horizontal, 16 * px)
                    .padding(.vertical, 6 * px)
                    .background(tag.background, in: RoundedRectangle(cornerRadius: 16 * px))
                    .overlay(RoundedRectangle(cornerRadius: 16 * px).strokeBorder(.white.opacity(0.95), lineWidth: 3 * px))
                    .shadow(color: .black.opacity(0.45), radius: 7 * px, y: 6 * px)
            }
            .position(x: anchor.x, y: anchor.y - 6 * px)
            .allowsHitTesting(false)
    }
}
