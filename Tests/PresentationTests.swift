import Foundation
@main struct PresentationTests {
    static func main() throws {
        enum Mode { case active, locked, suspended(String) }
        struct Box { let presentationMode: Mode? }
        struct Request { let box: Box }
        let request = Request(box: Box(presentationMode: .locked))
        precondition(caseName(findProperty("presentationMode",in:request)) == "locked")
        precondition(caseName(Mode.suspended("display asleep")) == "suspended")
        precondition(caseName(Optional<Mode>.none as Any) == nil)
        precondition(findProperty("activityState",in:request) == nil)
        var config = WallpaperConfiguration.defaults
        precondition(WallpaperPresentation(mode:"active") == .desktop)
        precondition(WallpaperPresentation(mode:"locked") == .locked)
        precondition(WallpaperPresentation(mode:"futureMode") == .unknown)
        precondition(config.shader(for:.desktop) == "Calm Sky" && !config.animates(in:.desktop))
        precondition(config.shader(for:.locked) == "Patterns" && config.animates(in:.locked))
        config.desktopShader = "Patterns"; config.desktopAnimated = true
        precondition(config.animates(in:.desktop))
        config.pattern.running = false; precondition(!config.animates(in:.locked))
        let encoded = try config.encoded()
        precondition(WallpaperConfiguration.decode(encoded) == config)
        let legacy = WallpaperConfiguration.decode(Data("Light".utf8))
        precondition(legacy.desktopShader == "Light" && legacy.lockShader == "Light")
        precondition(!legacy.legibility.enabled)
        let defaults = WallpaperConfiguration.defaults
        precondition(defaults.legibility.clockY < 300 && defaults.legibility.loginY > 600)
        precondition(WallpaperPresentation.locked.rawValue == 2 && WallpaperPresentation.desktop.rawValue == 1)
        print("PASS: explicit modes, independent appearances, configuration roundtrip, legacy migration and 1440x932 regions")
    }
}
