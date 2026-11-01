import AppKit
import ExtensionFoundation
import os

private let logger = Logger(subsystem: ShaderLibrary.provider, category: "wallpaper")
func extensionLog(_ message: String) { logger.notice("\(message, privacy: .public)") }
func traceLog(_ message: String) { logger.debug("\(message, privacy: .public)") }

@main final class MeditationExtension: NSObject, AppExtension {
    override required init() {
        super.init()
        guard dlopen("/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit", RTLD_LAZY) != nil else {
            extensionLog("WallpaperExtensionKit is unavailable"); return
        }
        extensionLog("Started native shader extension; \(ShaderLibrary.entries.count) shaders")
        DispatchQueue.main.async { Engine.shared.observeEnvironment() }
    }
    var configuration: some AppExtensionConfiguration { MeditationExtensionConfig() }
}

/// Called only on the main queue, including XPC operations and render timers.
final class Engine {
    static let shared = Engine()
    struct Surface {
        var context: CAContext
        var root: CALayer
        var renderer: ShaderRenderer
        var preview: Bool
        var generation: UUID
        var valid: Bool
        var configuration: WallpaperConfiguration
        var presentation: WallpaperPresentation
        var activity: String
    }
    var surfaces: [UUID: Surface] = [:]
    private var clocks: [String: MotionClock] = [:]
    private var pendingUpdates: [UUID: (mode: String?, activity: String?)] = [:]
    private var sleeping = false
    private var lastCheckpoint = CACurrentMediaTime()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func clock(for shader: String, role: String = "locked") -> MotionClock {
        let key = "\(role).\(shader)"
        if let clock = clocks[key] { return clock }
        let saved = UserDefaults.standard.object(forKey: "time.\(key)") == nil
            ? UserDefaults.standard.double(forKey: "time.\(shader)") : UserDefaults.standard.double(forKey: "time.\(key)")
        let clock = MotionClock(saved: saved)
        clocks[key] = clock
        return clock
    }
    func checkpoint() {
        for (id, clock) in clocks { UserDefaults.standard.set(clock.value, forKey: "time.\(id)") }
        lastCheckpoint = CACurrentMediaTime()
    }
    func observeEnvironment() {
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.sleeping = asleep; self?.applyPolicy()
            }
            observers.append((workspace, token))
        }
        let token = workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.applyPolicy() }
        observers.append((workspace, token))
        let system = NotificationCenter.default
        for name in [Notification.Name.NSSystemTimeZoneDidChange, Notification.Name.NSSystemClockDidChange] {
            let token = system.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                for surface in self.surfaces.values {
                    surface.renderer.refreshDaylight()
                }
            }
            observers.append((system, token))
        }
    }
    func update(id: UUID, mode: String?, activity: String?) {
        guard var surface = surfaces[id] else {
            let previous = pendingUpdates[id]
            pendingUpdates[id] = (mode ?? previous?.mode, activity ?? previous?.activity)
            if pendingUpdates.count > 64, let stale = pendingUpdates.keys.first(where: { $0 != id }) { pendingUpdates.removeValue(forKey: stale) }
            return
        }
        guard !surface.preview else { return }
        if let mode { surface.presentation = WallpaperPresentation(mode: mode) }
        if let activity { surface.activity = activity }
        surfaces[id] = surface
        extensionLog("Surface \(id): presentation=\(surface.presentation), activity=\(surface.activity)")
        applyPolicy()
    }
    func applyPolicy() {
        var movingClocks = Set<String>()
        for surface in surfaces.values where !surface.preview && surface.valid {
            let mode = surface.presentation, config = surface.configuration
            let entry = ShaderLibrary.entry(config.shader(for: mode)) ?? ShaderLibrary.entry(ShaderLibrary.defaultShader)!
            let key = "\(mode.role).\(entry.id)", clock = self.clock(for: entry.id, role: mode.role)
            let active = !sleeping && surface.activity == "active"
            do { try surface.renderer.setAppearance(entry: entry, clock: clock, presentation: mode, configuration: config, redraw: active) }
            catch { extensionLog("Appearance change failed: \(error.localizedDescription)"); surface.renderer.stop(); continue }
            if active && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && mode != .unknown && mode != .idle && config.animates(in: mode) {
                movingClocks.insert(key)
            }
        }
        for (key,clock) in clocks { clock.setMoving(movingClocks.contains(key), immediately: !movingClocks.contains(key)) }
        for surface in surfaces.values where !surface.preview && surface.valid {
            let active = !sleeping && surface.activity == "active"
            surface.renderer.setDaylightUpdatesEnabled(active)
            if !active || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                surface.renderer.stop()
                if active { surface.renderer.restoreNativeFrame() }
            } else if !surface.renderer.clock.settled { surface.renderer.start() }
            else { surface.renderer.stop(); surface.renderer.restoreNativeFrame() }
        }
        if movingClocks.isEmpty { checkpoint() }
    }
    func acquire(id: UUID, configuration data: Data?, size: CGSize, scale: CGFloat, display: UInt32?, preview: Bool, mode: String? = nil, activity: String? = nil) throws -> AnyObject {
        let configuration = WallpaperConfiguration.decode(data)
        let pending = pendingUpdates.removeValue(forKey: id)
        let reportedMode = mode ?? pending?.mode
        let effectiveActivity = activity ?? pending?.activity ?? surfaces[id]?.activity ?? "active"
        let presentation = preview ? WallpaperPresentation.preview : (reportedMode.map(WallpaperPresentation.init(mode:)) ?? surfaces[id]?.presentation ?? .desktop)
        let entry = ShaderLibrary.entry(configuration.shader(for: presentation)) ?? ShaderLibrary.entry(ShaderLibrary.defaultShader)
        guard let entry else { throw failure("No bundled shaders") }
        if var existing = surfaces[id], existing.configuration == configuration, existing.preview == preview,
           existing.root.bounds.size == size, existing.root.contentsScale == scale {
            existing.generation = UUID(); existing.valid = true; existing.presentation = presentation
            existing.activity = effectiveActivity; surfaces[id] = existing
            if !preview { applyPolicy() }
            guard let result = createRemoteContextXPC(contextId: existing.context.contextId) else { throw failure("Could not return wallpaper surface") }
            return result
        }
        let existing = surfaces[id]
        existing?.renderer.stop()
        existing?.renderer.setDaylightUpdatesEnabled(false)
        let context: CAContext
        if let old = existing { context = old.context }
        else {
            let options: [String: Any] = display.map { ["displayId": $0] } ?? [:]
            guard let remote = CAContext.remoteContext(withOptions: options) as? CAContext, remote.contextId != 0 else { throw failure("Could not create wallpaper surface") }
            context = remote
        }
        let root = existing?.root ?? CALayer()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit(); CATransaction.flush() }
        root.frame = CGRect(origin: .zero, size: size); root.contentsScale = scale
        root.isOpaque = true
        if existing == nil { context.layer = root }
        let clock = preview ? MotionClock(saved: self.clock(for: entry.id, role: presentation.role).value) : self.clock(for: entry.id, role: presentation.role)
        let renderer = try ShaderRenderer(entry: entry, clock: clock, root: root, scale: scale)
        try renderer.setAppearance(entry: entry, clock: clock, presentation: presentation, configuration: configuration)
        existing?.renderer.layer.removeFromSuperlayer()
        renderer.onSettled = { [weak self, weak renderer] in
            self?.checkpoint()
            if let renderer { extensionLog("Settled \(entry.id) at \(renderer.clock.value); timer stopped after \(renderer.frameCount) frames") }
        }
        renderer.onFrame = { [weak self] in
            guard let self, CACurrentMediaTime() - self.lastCheckpoint > 30 else { return }
            self.checkpoint()
        }
        renderer.onError = { error in extensionLog("Rendering \(entry.id) failed: \(error.localizedDescription)") }
        surfaces[id] = Surface(context: context, root: root, renderer: renderer, preview: preview, generation: UUID(), valid: true, configuration: configuration, presentation: presentation, activity: effectiveActivity)
        if preview { clock.setMoving(false, immediately: true) }
        else { applyPolicy() }
        guard let result = createRemoteContextXPC(contextId: context.contextId) else { throw failure("Could not return wallpaper surface") }
        extensionLog("Acquired \(entry.id), surface=\(id), preview=\(preview), context=\(context.contextId)")
        return result
    }
    func invalidate(_ id: UUID) {
        pendingUpdates.removeValue(forKey: id)
        guard let surface = surfaces[id] else { return }
        surfaces[id]?.valid = false
        surface.renderer.stop()
        surface.renderer.setDaylightUpdatesEnabled(false)
        if !surfaces.values.contains(where: { !$0.preview && $0.renderer.isRendering && $0.renderer.clock === surface.renderer.clock }) {
            surface.renderer.clock.setMoving(false, immediately: true)
        }
        checkpoint()
        let generation = surface.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, let stale = self.surfaces[id], stale.generation == generation else { return }
            stale.context.perform(NSSelectorFromString("invalidate"))
            self.surfaces.removeValue(forKey: id)
            if !self.surfaces.values.contains(where: { !$0.preview && $0.renderer.isRendering }) {
                self.clocks.values.forEach { $0.setMoving(false, immediately: true) }
                self.checkpoint()
            }
            extensionLog("Released surface \(id)")
        }
    }
    func snapshot(_ id: UUID?) -> AnyObject? {
        guard let renderer = id.flatMap({ surfaces[$0]?.renderer }) ?? surfaces.values.first?.renderer,
              let pixel = renderer.lastFrame, let surface = CVPixelBufferGetIOSurface(pixel)?.takeUnretainedValue() else { return nil }
        return createSnapshotXPC(surface: surface)
    }
}
