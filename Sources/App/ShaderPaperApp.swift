import SwiftUI

@main struct ShaderPaperApp: App {
    init() {
        let args = CommandLine.arguments
        if args.contains("--activate") || args.contains("--restore") || args.contains("--register") {
            do {
                if let index = args.firstIndex(of: "--activate"), args.count > index+1 {
                    try WallpaperSelection.activate(args[index+1]); print("Selected wallpaper.")
                } else if args.contains("--restore") { try WallpaperSelection.restore(); print("Previous wallpaper restored.") }
                else { try WallpaperSelection.register(); print("Native shader extension registered.") }
                exit(0)
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        WindowGroup("Shader Paper · Patterns") { AppearanceView() }
            .defaultSize(width: 860,height: 820)
    }
}

struct AppearanceView: View {
    @State private var configuration = WallpaperSelection.savedConfiguration()
    @State private var message = "Desktop and lock screen use macOS’s explicit presentation mode."
    @State private var error: String?
    private let entries = ShaderLibrary.entries
    private func number(_ label: String, _ value: Binding<Float>, _ range: ClosedRange<Float>) -> some View {
        HStack { Text(label).frame(width: 150,alignment: .leading); Slider(value: value,in: range); Text(value.wrappedValue,format: .number.precision(.fractionLength(1))).monospacedDigit().frame(width: 48) }
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text("Two sides of your Mac.").font(.system(size: 28,weight: .medium))
            Text("A calm desktop. A living pattern when locked.").foregroundStyle(.secondary)
            HStack(alignment: .top,spacing: 18) {
                appearance("Desktop",selection: $configuration.desktopShader,animated: $configuration.desktopAnimated)
                appearance("Lock screen",selection: $configuration.lockShader,animated: $configuration.lockAnimated)
            }
            Form {
                Section("Pattern") {
                    number("Largest cell (%)",$configuration.pattern.scale,6...28)
                    number("Flow speed",$configuration.pattern.speed,0.1...1.5)
                    number("Subdivision",$configuration.pattern.density,0.15...0.85)
                    Picker("Motion field",selection: $configuration.pattern.mode) {
                        Text("Organic flow").tag("organic"); Text("Long eddies").tag("eddies"); Text("Restless flow").tag("restless")
                    }
                    number("Accent hue",$configuration.pattern.hue,0...359)
                    HStack {
                        Toggle("Color drift",isOn: $configuration.pattern.colorDrift)
                        Toggle("Animate pattern",isOn: $configuration.pattern.running)
                        Spacer()
                        Button("New pattern") { configuration.pattern.seed = UInt32.random(in: UInt32.min...UInt32.max) }
                    }
                }
                Section("Lock-screen legibility · 1440 × 932 reference") {
                    Toggle("Soften behind the clock and login",isOn: $configuration.legibility.enabled)
                    number("Blur radius (pt)",$configuration.legibility.radius,0...16)
                    DisclosureGroup("Adjust protected regions") {
                        number("Clock center Y",$configuration.legibility.clockY,50...360)
                        number("Clock width",$configuration.legibility.clockWidth,240...900)
                        number("Clock height",$configuration.legibility.clockHeight,100...400)
                        number("Login center Y",$configuration.legibility.loginY,450...900)
                        number("Login width",$configuration.legibility.loginWidth,250...900)
                        number("Login height",$configuration.legibility.loginHeight,120...420)
                    }
                }
            }.formStyle(.grouped)
            HStack {
                Button("Save settings…") { saveSettings() }
                Button("Load settings…") { loadSettings() }
                Spacer()
                Button("Apply appearances") {
                    do { try WallpaperSelection.activate(configuration); message = "Applied. Lock with Control–Command–Q to see the pattern. You can close this window." }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Text(message).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Wallpaper Settings") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!) }
                Spacer()
                Button("Restore Previous Wallpaper") {
                    do { try WallpaperSelection.restore(); message = "Previous wallpaper restored." }
                    catch { self.error = error.localizedDescription }
                }
            }.font(.caption).buttonStyle(.link)
        }.padding(24).frame(minWidth: 760,minHeight: 760)
        .alert("Couldn’t update wallpaper",isPresented: Binding(get:{error != nil},set:{if !$0 {error = nil}})) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func appearance(_ title: String,selection: Binding<String>,animated: Binding<Bool>) -> some View {
        VStack(alignment: .leading,spacing: 8) {
            if let entry = entries.first(where:{$0.id == selection.wrappedValue}),let image = NSImage(contentsOf:entry.thumbnailURL) {
                Image(nsImage:image).resizable().aspectRatio(1.6,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:8))
            }
            Picker(title,selection: selection) { ForEach(entries) { Text($0.name).tag($0.id) } }
            Toggle("Animate \(title.lowercased())",isOn:animated)
        }.frame(maxWidth:.infinity)
    }
    private func saveSettings() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Patterns-appearance.json"
        guard panel.runModal() == .OK,let url = panel.url else { return }
        do { try configuration.encoded().write(to:url,options:.atomic) } catch { self.error = error.localizedDescription }
    }
    private func loadSettings() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,let url = panel.url else { return }
        do {
            let data = try Data(contentsOf:url)
            guard data.count < 32768 else { throw failure("Choose a small settings JSON file.") }
            // Accept both a full appearance configuration and the browser recipe.
            if let full = try? JSONDecoder().decode(WallpaperConfiguration.self,from:data),full.version == 1 { configuration = full }
            else {
                struct Recipe: Decodable { let app: String; let settings: PatternSettings }
                let recipe = try JSONDecoder().decode(Recipe.self,from:data)
                guard recipe.app == "patterns-in-motion" else { throw failure("Not a Patterns settings file.") }
                configuration.pattern = recipe.settings.validated
            }
            message = "Settings loaded. Apply appearances to publish them."
        } catch { self.error = error.localizedDescription }
    }
}

func failure(_ description: String) -> NSError {
    NSError(domain:"VisualMeditation",code:1,userInfo:[NSLocalizedDescriptionKey:description])
}
