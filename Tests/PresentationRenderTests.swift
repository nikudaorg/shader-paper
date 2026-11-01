import AppKit
import CoreVideo

@main struct PresentationRenderTests {
    static func bytes(_ pixel: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixel,.readOnly); defer { CVPixelBufferUnlockBaseAddress(pixel,.readOnly) }
        let width = CVPixelBufferGetWidth(pixel),height = CVPixelBufferGetHeight(pixel),stride = CVPixelBufferGetBytesPerRow(pixel)
        let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to:UInt8.self)
        return (0..<height).flatMap { Array(UnsafeBufferPointer(start:base+$0*stride,count:width*4)) }
    }
    static func main() throws {
        _ = NSApplication.shared
        let resources = URL(fileURLWithPath:CommandLine.arguments[1])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = directory.appendingPathComponent("Mode Probe.shader")
        try """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float4 position [[position]]; };
        vertex V vertex_main(uint id [[vertex_id]]) { float2 p=float2(float((id<<1u)&2u),float(id&2u)); return {float4(p*2.0-1.0,0,1)}; }
        fragment half4 fragment_main(V v [[stage_in]],constant float& time [[buffer(0)]],constant uint& mode [[buffer(2)]]) { return half4(float(mode)/5.0,0.25,0.4,1); }
        """.write(to:source,atomically:true,encoding:.utf8)
        let entry = ShaderEntry(id:"Mode Probe",sourceURL:source,thumbnailURL:source)
        let root = CALayer();root.frame = CGRect(x:0,y:0,width:320,height:200)
        let clock = MotionClock(saved:18)
        let renderer = try ShaderRenderer(entry:entry,clock:clock,root:root,scale:1)
        var config = WallpaperConfiguration.defaults; config.legibility.enabled = false
        let before = bytes(renderer.lastFrame!),count = renderer.frameCount
        try renderer.setAppearance(entry:entry,clock:clock,presentation:.locked,configuration:config)
        precondition(bytes(renderer.lastFrame!) != before && renderer.frameCount == count+1)
        precondition(!renderer.isRendering && clock.value == 18,"Mode switch must redraw without animating")
        let locked = bytes(renderer.lastFrame!)
        try renderer.setAppearance(entry:entry,clock:clock,presentation:.desktop,configuration:config)
        precondition(bytes(renderer.lastFrame!) == before && bytes(renderer.lastFrame!) != locked)
        let same = renderer.frameCount
        try renderer.setAppearance(entry:entry,clock:clock,presentation:.desktop,configuration:config)
        precondition(renderer.frameCount == same,"Unchanged presentation must not redraw")

        let entries = ShaderLibrary.entries(in:resources)
        let calm = try ShaderKernel(source:entries.first{$0.id=="Calm Sky"}!.sourceURL)
        let size = CGSize(width:720,height:466)
        let still = bytes(try calm.frame(time:0,size:size))
        let later = bytes(try calm.frame(time:1000,size:size))
        precondition(still==later,"Calm desktop must be an actual still")
        let pattern = try ShaderKernel(source:entries.first{$0.id=="Patterns"}!.sourceURL)
        let sharp = bytes(try pattern.frame(time:0,size:size,presentation:.locked,configuration:config))
        config.legibility.enabled = true
        let blurred = bytes(try pattern.frame(time:0,size:size,presentation:.locked,configuration:config))
        var changes = 0
        for y in 0..<466 { for x in 0..<720 {
            let i = (y*720+x)*4
            let changed = sharp[i] != blurred[i] || sharp[i+1] != blurred[i+1] || sharp[i+2] != blurred[i+2]
            if changed { changes += 1 }
            if x<75 || x>645 { precondition(!changed,"Blur leaked outside protected areas") }
            precondition(blurred[i+3]==255)
        } }
        precondition(changes>100,"Blur region did not soften any motif edges")
        let desktop = bytes(try pattern.frame(time:0,size:size,presentation:.desktop,configuration:config))
        precondition(desktop==sharp,"Login blur must be absent on the desktop")
        print("PASS: explicit uniform changes at frozen time, mandatory redraw, static desktop, localized lock-only blur and opaque output")
    }
}
