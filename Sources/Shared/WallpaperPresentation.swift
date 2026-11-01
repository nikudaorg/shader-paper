import Foundation

/// Values passed unchanged to Metal at fragment buffer(2). The source is
/// WallpaperAgent's presentationMode, never clock speed or renderer activity.
enum WallpaperPresentation: UInt32, Codable {
    case unknown = 0, desktop = 1, locked = 2, idle = 3, screenSaver = 4, preview = 5
    init(mode: String) {
        switch mode {
        case "active", "default", "desktop": self = .desktop
        case "locked": self = .locked
        case "idle": self = .idle
        case "screenSaver": self = .screenSaver
        default: self = .unknown
        }
    }
    var usesLockAppearance: Bool { self == .locked || self == .screenSaver || self == .preview }
    var role: String { usesLockAppearance ? "locked" : "desktop" }
}

struct PatternSettings: Codable, Equatable {
    var seed: UInt32 = 3_845_275_645
    var scale: Float = 19
    var speed: Float = 0.2
    var density: Float = 0.26
    var mode: String = "restless"
    var hue: Float = 277.47655
    var colorDrift = true
    var running = true
    var validated: Self {
        var p = self
        p.scale = p.scale.isFinite ? min(28, max(6, p.scale)) : 19
        p.speed = p.speed.isFinite ? min(1.5, max(0.1, p.speed)) : 0.2
        p.density = p.density.isFinite ? min(0.85, max(0.15, p.density)) : 0.26
        p.hue = p.hue.isFinite ? (p.hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) : 277
        if !["organic", "eddies", "restless"].contains(p.mode) { p.mode = "organic" }
        return p
    }
}

/// Rectangles use top-left coordinates in the user's 1440x932 logical display.
/// Their normalized placement survives Retina backing and adaptive rendering.
struct LegibilitySettings: Codable, Equatable {
    var enabled = true
    var radius: Float = 6
    var feather: Float = 36
    var clockX: Float = 720, clockY: Float = 155
    var clockWidth: Float = 560, clockHeight: Float = 230
    var loginX: Float = 720, loginY: Float = 770
    var loginWidth: Float = 500, loginHeight: Float = 250
}

struct WallpaperConfiguration: Codable, Equatable {
    var version = 1
    var desktopShader = "Calm Sky"
    var lockShader = "Patterns"
    var desktopAnimated = false
    var lockAnimated = true
    var pattern = PatternSettings()
    var legibility = LegibilitySettings()
    static let defaults = WallpaperConfiguration()

    static func decode(_ data: Data?) -> Self {
        guard let data else { return .defaults }
        if let result = try? JSONDecoder().decode(Self.self, from: data), result.version == 1 { return result }
        // Preserve selections made by upstream's plain shader-name format.
        if let name = String(data: data, encoding: .utf8), !name.isEmpty, !name.hasPrefix("{") {
            var legacy = Self.defaults; legacy.desktopShader = name; legacy.lockShader = name
            legacy.legibility.enabled = false
            return legacy
        }
        return .defaults
    }
    func encoded() throws -> Data { try JSONEncoder().encode(self) }
    func shader(for mode: WallpaperPresentation) -> String { mode.usesLockAppearance ? lockShader : desktopShader }
    func animates(in mode: WallpaperPresentation) -> Bool {
        (mode.usesLockAppearance ? lockAnimated : desktopAnimated) && (shader(for: mode) != "Patterns" || pattern.running)
    }
}
