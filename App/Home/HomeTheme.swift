import SwiftUI

/// Which version of downtown the home screen shows, from the device's local time.
enum TimeOfDay: String, CaseIterable {
    case morning, evening, night

    /// Morning 06:00–16:59, evening 17:00–19:59, night 20:00–05:59.
    init(date: Date, calendar: Calendar = .current) {
        #if DEBUG
        // Launch with `-timeOfDay night` (or morning, evening) to check one version at any hour.
        if let forced = UserDefaults.standard.string(forKey: "timeOfDay").flatMap(TimeOfDay.init(rawValue:)) {
            self = forced
            return
        }
        #endif
        switch calendar.component(.hour, from: date) {
        case 6..<17: self = .morning
        case 17..<20: self = .evening
        default: self = .night
        }
    }
}

/// Colours for the home screen controls. Evening and night follow the design's Downtown Sunset and
/// Night Patrol skins; morning uses the light Harbor Morning skin.
struct HomeSkin {
    var text: Color
    var sub: Color
    var panel: Color
    var panelBorder: Color
    var counter: Color
    /// Ring around the round side buttons.
    var rim: Color
    var tileCenter: Color
    var tileEdge: Color
    var label: Color
    var labelText: Color
    var plate: Color
    var plateText: Color
    var thiefLabel: Color
    var policeLabel: Color
    var subtitle: Color
    var playTop: Color
    var playBottom: Color
    var playRim: Color
    var playEdge: Color
    var playText: Color
    var playTextShadow: Color
    var playGlow: Color
    var pedestal: Color
    var thiefRing: Color
    var policeRing: Color
    var pedestalGlow: Double
}

extension HomeSkin {
    init(_ time: TimeOfDay) {
        switch time {
        case .morning: self = .morning
        case .evening: self = .evening
        case .night: self = .night
        }
    }

    static let morning = HomeSkin(
        text: Color(hex: 0x1B2B4A), sub: Color(hex: 0x8A5A12),
        panel: Color(hex: 0xFFF8EC, opacity: 0.85), panelBorder: Color(hex: 0xE7D7BB), counter: Color(hex: 0xF3E8D3), rim: Color(hex: 0xF2C14E),
        tileCenter: .white, tileEdge: Color(hex: 0xF1E3C8),
        label: Color(hex: 0xFFF8EC, opacity: 0.95), labelText: Color(hex: 0x1B2B4A),
        plate: Color(hex: 0xFFF8EC, opacity: 0.85), plateText: Color(hex: 0x1B2B4A),
        thiefLabel: Color(hex: 0x8A5A12), policeLabel: Color(hex: 0x1F4FA0), subtitle: Color(hex: 0x13294B),
        playTop: Color(hex: 0x1C6FA3), playBottom: Color(hex: 0x0B3A5C), playRim: Color(hex: 0xF2C14E), playEdge: Color(hex: 0x072640),
        playText: .white, playTextShadow: .black.opacity(0.3), playGlow: .clear,
        pedestal: Color(hex: 0xFFF8EC, opacity: 0.9), thiefRing: Color(hex: 0xE0A33A), policeRing: Color(hex: 0x3A78D6), pedestalGlow: 0.5
    )

    static let evening = HomeSkin(
        text: .white, sub: Color(hex: 0xFFE3B0),
        panel: Color(red: 28 / 255, green: 16 / 255, blue: 48 / 255, opacity: 0.55), panelBorder: Color(red: 1, green: 214 / 255, blue: 150 / 255, opacity: 0.55),
        counter: Color(red: 16 / 255, green: 8 / 255, blue: 30 / 255, opacity: 0.6), rim: Color(hex: 0xFFE7B3),
        tileCenter: Color(hex: 0x5A4284), tileEdge: Color(hex: 0x1C1030),
        label: Color(red: 20 / 255, green: 10 / 255, blue: 36 / 255, opacity: 0.72), labelText: .white,
        plate: Color(red: 20 / 255, green: 12 / 255, blue: 40 / 255, opacity: 0.72), plateText: .white,
        thiefLabel: Color(hex: 0xFFC977), policeLabel: Color(hex: 0x9CC6FF), subtitle: Color(hex: 0xFFE3B0),
        playTop: Color(hex: 0xEE6A2A), playBottom: Color(hex: 0xC23A16), playRim: Color(hex: 0xFFE7B3), playEdge: Color(hex: 0x7E2410),
        playText: .white, playTextShadow: .black.opacity(0.28), playGlow: .clear,
        pedestal: Color(hex: 0x140D22, opacity: 0.7), thiefRing: Color(hex: 0xFFB547), policeRing: Color(hex: 0x5AA2FF), pedestalGlow: 0.55
    )

    static let night = HomeSkin(
        text: .white, sub: Color(hex: 0x9FF0FF),
        panel: Color(red: 8 / 255, green: 12 / 255, blue: 36 / 255, opacity: 0.7), panelBorder: Color(red: 110 / 255, green: 231 / 255, blue: 1, opacity: 0.6),
        counter: Color(red: 2 / 255, green: 4 / 255, blue: 16 / 255, opacity: 0.7), rim: Color(hex: 0x9FF0FF),
        tileCenter: Color(hex: 0x24387A), tileEdge: Color(hex: 0x070B24),
        label: Color(red: 4 / 255, green: 6 / 255, blue: 20 / 255, opacity: 0.82), labelText: .white,
        plate: Color(red: 6 / 255, green: 10 / 255, blue: 30 / 255, opacity: 0.8), plateText: .white,
        thiefLabel: Color(hex: 0xFFC977), policeLabel: Color(hex: 0x9CC6FF), subtitle: Color(hex: 0x9FF0FF),
        playTop: Color(hex: 0xFFE15C), playBottom: Color(hex: 0xF2B705), playRim: Color(hex: 0xFFF6C2), playEdge: Color(hex: 0x8A6200),
        playText: Color(hex: 0x17123A), playTextShadow: .white.opacity(0.4), playGlow: Color(red: 1, green: 210 / 255, blue: 63 / 255, opacity: 0.55),
        pedestal: Color(hex: 0x05071A, opacity: 0.8), thiefRing: Color(hex: 0xFFB547), policeRing: Color(hex: 0x5AA2FF), pedestalGlow: 0.6
    )
}

/// Colours for the downtown scenery behind the home screen. One skyline, lit three ways.
struct DowntownPalette {
    var skyTop: Color
    var skyMid: Color
    var skyHorizon: Color
    var far: Color
    var farWindows: Double
    var mid: Color
    var trunk: Color
    var canopy: Color
    var window: Color
    /// Second window colour, mixed in at night.
    var windowAlt: Color
    var track: Color
    var train: Color
    var trainWindows: Color
    var trainStripe: Color
    var floorTop: Color
    var floorBottom: Color
    var floorLine: Color
    /// Darkening at the top of the screen so the status bar and top controls read clearly.
    var topShade: Color
}

extension DowntownPalette {
    init(_ time: TimeOfDay) {
        switch time {
        case .morning:
            self.init(
                skyTop: Color(hex: 0x57B0EA), skyMid: Color(hex: 0x9AD6F6), skyHorizon: Color(hex: 0xFFF0D2),
                far: Color(hex: 0xA9C3E3), farWindows: 0.6, mid: Color(hex: 0x6F8CC0), trunk: Color(hex: 0x7E5A3C), canopy: Color(hex: 0x4FA86A),
                window: Color(hex: 0xF2FAFF), windowAlt: Color(hex: 0xF2FAFF),
                track: Color(hex: 0x44597F), train: .white, trainWindows: Color(hex: 0x57B0EA, opacity: 0.8), trainStripe: Color(hex: 0xE8642A),
                floorTop: Color(hex: 0xE3D5BF), floorBottom: Color(hex: 0xA68C6E), floorLine: .black.opacity(0.08),
                topShade: Color(hex: 0x0B2A44, opacity: 0.3)
            )
        case .evening:
            self.init(
                skyTop: Color(hex: 0x2C2A6B), skyMid: Color(hex: 0xC8597A), skyHorizon: Color(hex: 0xFFB36B),
                far: Color(hex: 0x7A4F8F), farWindows: 0.55, mid: Color(hex: 0x3E2C5E), trunk: Color(hex: 0x3E2C5E), canopy: Color(hex: 0x2F5E5A),
                window: Color(hex: 0xFFD27A), windowAlt: Color(hex: 0xFFD27A),
                track: Color(hex: 0x2A1F40), train: Color(hex: 0xF2F2F7), trainWindows: Color(hex: 0x2C2A6B, opacity: 0.8), trainStripe: Color(hex: 0xE8642A),
                floorTop: Color(hex: 0x3A2850), floorBottom: Color(hex: 0x140D22), floorLine: .white.opacity(0.07),
                topShade: .black.opacity(0.45)
            )
        case .night:
            self.init(
                skyTop: Color(hex: 0x070B24), skyMid: Color(hex: 0x10173F), skyHorizon: Color(hex: 0x1F2A6B),
                far: Color(hex: 0x0F1638), farWindows: 0.8, mid: Color(hex: 0x151F4A), trunk: Color(hex: 0x151F4A), canopy: Color(hex: 0x0F2C3C),
                window: Color(hex: 0xFFD27A), windowAlt: Color(hex: 0x6EE7FF),
                track: Color(hex: 0x0B1030), train: Color(hex: 0xDDE3FF), trainWindows: Color(hex: 0xFFE08A, opacity: 0.95), trainStripe: Color(hex: 0xFF5FA2),
                floorTop: Color(hex: 0x121A44), floorBottom: Color(hex: 0x05071A), floorLine: .white.opacity(0.06),
                topShade: .black.opacity(0.25)
            )
        }
    }

}
