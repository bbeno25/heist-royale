import SwiftUI

/// Fits a fixed design canvas (the mockups are 393×852 pt) onto the screen, so positions and sizes
/// can be copied from the designs and still work on smaller and larger iPhones.
/// Sizes are multiplied out instead of using `scaleEffect`, which keeps text and vectors sharp.
struct Stage {
    /// Design points to screen points.
    let scale: CGFloat
    /// Where the design canvas's top-left corner sits on screen.
    let origin: CGPoint
    let designSize: CGSize

    init(designSize: CGSize, screen: CGSize) {
        self.designSize = designSize
        scale = min(screen.width / designSize.width, screen.height / designSize.height)
        origin = CGPoint(
            x: (screen.width - designSize.width * scale) / 2,
            y: (screen.height - designSize.height * scale) / 2
        )
    }

    /// The stage's size on screen.
    var size: CGSize {
        CGSize(width: designSize.width * scale, height: designSize.height * scale)
    }

    /// Placement for full-bleed scenery: as wide as the screen, with the design's horizon line
    /// (`anchorY`) kept level with the stage, so the floor stays under the characters.
    func backdrop(screen: CGSize, anchorY: CGFloat) -> Stage {
        let wide = screen.width / designSize.width
        let y = origin.y + anchorY * (scale - wide)
        return Stage(designSize: designSize, scale: wide, origin: CGPoint(x: 0, y: y))
    }

    private init(designSize: CGSize, scale: CGFloat, origin: CGPoint) {
        self.designSize = designSize
        self.scale = scale
        self.origin = origin
    }

    /// Moves a canvas context into design coordinates.
    func apply(to context: inout GraphicsContext) {
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
    }
}

extension EnvironmentValues {
    /// Design points to screen points for views laid out on a `Stage`.
    @Entry var stageScale: CGFloat = 1
}

extension View {
    /// Places a view on the stage at a design-space frame (top-left corner and size).
    func stageFrame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        frame(width: width * scale, height: height * scale)
            .offset(x: x * scale, y: y * scale)
    }
}
