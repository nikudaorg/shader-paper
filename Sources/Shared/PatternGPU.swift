import Foundation
import Metal

struct PatternUniforms {
    var viewport: SIMD4<Float>
    var lattice: SIMD4<UInt32>
}

final class PatternGPU {
    private let device: MTLDevice
    private var simulation: PatternSimulation?
    private var uploaded: UInt64?
    private(set) var tiles: MTLBuffer?
    private(set) var map: MTLTexture?
    init(device: MTLDevice) { self.device = device }
    func prepare(time: Double, size: CGSize, settings: PatternSettings) throws -> PatternUniforms {
        let p = settings.validated
        let cell = Float(min(size.width,size.height))*p.scale/100
        let columns = max(1,Int(ceil(Float(size.width)/cell))), rows = max(1,Int(ceil(Float(size.height)/cell)))
        if simulation == nil || simulation!.columns != columns || simulation!.rows != rows || simulation!.settings != p {
            simulation = PatternSimulation(columns: columns, rows: rows, settings: p)
            simulation!.synchronizeClock(time); uploaded = nil
        }
        let simulation = simulation!
        simulation.advance(to: time)
        if uploaded != simulation.generation {
            let (data,indices) = simulation.tileData()
            tiles = data.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
            let w = columns*36, h = rows*36
            if map?.width != w || map?.height != h {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Uint, width: w, height: h, mipmapped: false)
                descriptor.usage = .shaderRead; descriptor.storageMode = .shared; map = device.makeTexture(descriptor: descriptor)
            }
            guard tiles != nil, let map else { throw failure("Could not allocate procedural pattern data") }
            indices.withUnsafeBytes { map.replace(region: MTLRegionMake2D(0,0,w,h), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: w*4) }
            uploaded = simulation.generation
        }
        return PatternUniforms(viewport: SIMD4(Float(size.width),Float(size.height),cell,simulation.hue),
            lattice: SIMD4(UInt32(columns*36),UInt32(rows*36),UInt32(simulation.leaves.count),0))
    }
}
