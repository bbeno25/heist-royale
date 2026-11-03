import CoreText
import SwiftUI

extension Color {
    /// A colour from a 0xRRGGBB value, as written in the design files.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Brand colours shared by the logo, splash and home screen.
enum Brand {
    static let thief = Color(hex: 0xFF7A2F)
    static let police = Color(hex: 0x2F8CFF)
    static let ink = Color(hex: 0x05030C)
    static let cream = Color(hex: 0xFFF4E0)
    static let gold = Color(hex: 0xFFC83D)
}

/// The bundled Google Fonts, registered through `UIAppFonts` in Info.plist.
/// Fredoka, Nunito Sans and Baloo 2 are variable fonts, so the weight is set on their 'wght' axis
/// (100–900, like CSS) rather than picked from named styles.
enum BrandFont {
    /// Logo lettering, read as glyph outlines by `WordmarkWord`.
    static let bungee = "Bungee-Regular"

    /// Home screen text.
    static func nunito(_ size: CGFloat, _ weight: CGFloat) -> Font {
        variable("Nunito Sans", size: size, weight: weight)
    }

    /// Splash screen text.
    static func fredoka(_ size: CGFloat, _ weight: CGFloat) -> Font {
        variable("Fredoka", size: size, weight: weight)
    }

    /// The big PLAY label.
    static func baloo(_ size: CGFloat, _ weight: CGFloat) -> Font {
        variable("Baloo 2", size: size, weight: weight)
    }

    private static func variable(_ family: String, size: CGFloat, weight: CGFloat) -> Font {
        let weightAxis = 0x7767_6874  // 'wght'
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontVariationAttribute: [weightAxis: weight],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}
