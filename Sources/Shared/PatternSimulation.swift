import Foundation

/// Native port of the browser's persistent density field and mixed 2/3-way
/// hierarchy. Only topology changes; there are no video frames or tile fades.
final class PatternSimulation {
    final class Node {
        let x: Float, y: Float, size: Float, depth: Int, id: UInt32
        var color = 0, foreground = 0, motif = 0, rotation = 0
        var generation: UInt32 = 0, split = false
        var changedAt = -Float.infinity, stepLimit = 2
        var children: [Node] = []
        weak var parent: Node?
        init(x: Float, y: Float, size: Float, depth: Int, id: UInt32) {
            self.x = x; self.y = y; self.size = size; self.depth = depth; self.id = id
        }
    }
    struct Tile {
        var bounds: SIMD4<Float>
        var motif: SIMD4<UInt32>
    }
    let columns: Int, rows: Int
    private(set) var settings: PatternSettings
    private var roots: [Node] = []
    private(set) var leaves: [Node] = []
    private var values: [Float], next: [Float]
    private let width: Int, height: Int
    private let resolution: Float = 5, margin: Float = 4
    private(set) var time: Float = 0
    private var previousTime: Double?
    private var center: Float = 0.5, gain: Float = 1, targetCenter: Float = 0.5, targetGain: Float = 1, contrastAge: Float = 0
    private(set) var generation: UInt64 = 0
    private(set) var hue: Float

    static func hash(_ x: UInt32, _ y: UInt32, _ seed: UInt32) -> Float {
        var n = (x &* 374761393) ^ (y &* 668265263) ^ (seed &* 1274126177)
        n = (n ^ (n >> 13)) &* 1274126177
        return Float(Double(n ^ (n >> 16)) / 4294967296)
    }
    private func hash(_ x: Int, _ y: Int, _ seed: UInt32) -> Float { Self.hash(UInt32(truncatingIfNeeded: x), UInt32(truncatingIfNeeded: y), seed) }
    private func noise(_ x: Float, _ y: Float, _ seed: UInt32) -> Float {
        let ix = Int(floor(x)), iy = Int(floor(y)), fx = x - floor(x), fy = y - floor(y)
        let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
        let a = hash(ix, iy, seed), b = hash(ix + 1, iy, seed), c = hash(ix, iy + 1, seed), d = hash(ix + 1, iy + 1, seed)
        return (a + (b-a)*u)*(1-v) + (c+(d-c)*u)*v
    }
    private func source(_ x: Float, _ y: Float) -> Float {
        let u = x * 0.28 + sin(time * 0.045) * 0.7, v = y * 0.28 + cos(time * 0.039) * 0.7
        let n = 0.8 * noise(u, v, settings.seed &+ 23) + 0.2 * noise(u * 2.1, v * 2.1, settings.seed &+ 71)
        return min(1, max(0, 0.5 + (n - 0.5) * 2.7))
    }
    init(columns: Int, rows: Int, settings: PatternSettings) {
        self.columns = columns; self.rows = rows; self.settings = settings.validated; hue = settings.validated.hue
        width = (columns + 8) * 5 + 1; height = (rows + 8) * 5 + 1
        values = Array(repeating: 0, count: width * height); next = values
        for j in 0..<height { for i in 0..<width { values[j*width+i] = source(Float(i)/resolution-margin, Float(j)/resolution-margin) } }
        measureContrast(); center = targetCenter; gain = targetGain
        for row in 0..<rows { for col in 0..<columns {
            roots.append(makeNode(Float(col), Float(row), 1, 0, UInt32(row * 65536 + col + 1)))
        } }
        updateTree(initialize: true)
    }
    private func makeNode(_ x: Float, _ y: Float, _ size: Float, _ depth: Int, _ id: UInt32) -> Node {
        let n = Node(x: x, y: y, size: size, depth: depth, id: id); assignMotif(n)
        if depth < 2 {
            let count = Self.hash(id, 7, settings.seed) < 0.5 ? 2 : 3
            for row in 0..<count { for col in 0..<count {
                let child = makeNode(x+Float(col)*size/Float(count), y+Float(row)*size/Float(count), size/Float(count), depth+1, id &* 31 &+ UInt32(row*count+col+1))
                child.parent = n; n.children.append(child)
            } }
        }
        return n
    }
    private func assignMotif(_ n: Node) {
        let seed = settings.seed &+ (n.generation &* 7919)
        n.color = min(3, Int(Self.hash(n.id, 2, seed)*4))
        n.foreground = (n.color + 1 + min(2, Int(Self.hash(n.id, 3, seed)*3))) % 4
        n.motif = min(5, Int(Self.hash(n.id, 4, seed)*6)); n.rotation = min(3, Int(Self.hash(n.id, 5, seed)*4))
    }
    private func raw(_ x: Float, _ y: Float) -> Float {
        let px = max(0, min(Float(width)-1.001, (x+margin)*resolution)), py = max(0, min(Float(height)-1.001, (y+margin)*resolution))
        let ix = Int(px), iy = Int(py), u = px-Float(ix), v = py-Float(iy), k = iy*width+ix
        let a = values[k]*(1-u)+values[k+1]*u, b = values[k+width]*(1-u)+values[k+width+1]*u
        return a*(1-v)+b*v
    }
    private func sample(_ x: Float, _ y: Float) -> Float { min(1, max(0, 0.5+(raw(x,y)-center)*gain)) }
    private func measureContrast() {
        var samples: [Float] = []
        for j in 0..<(rows*2) { for i in 0..<(columns*2) { samples.append(raw(Float(i)*0.5+0.25, Float(j)*0.5+0.25)) } }
        samples.sort(); let low = samples[Int(Float(samples.count-1)*0.1)], high = samples[Int(Float(samples.count-1)*0.9)]
        targetCenter = (low+high)*0.5; targetGain = min(16, 0.8/max(0.0001,high-low))
    }
    private func velocity(_ x: Float, _ y: Float, _ t: Float) -> SIMD2<Float> {
        let phase = Self.hash(settings.seed,19,0)*Float.pi*2
        let scale: Float = settings.mode == "eddies" ? 0.72 : (settings.mode == "restless" ? 1.2 : 0.9)
        let a = x*0.54*scale+sin(t*0.12+phase)*1.1, b = y*0.49*scale+cos(t*0.1+phase)*1.3
        let c = x*1.07*scale-y*0.62*scale+t*0.09+phase, d = x*0.38*scale+y*0.91*scale-t*0.07
        return SIMD2(0.8*sin(a)*cos(b)-0.24*cos(c)+0.2*cos(d), -0.88*cos(a)*sin(b)-0.42*cos(c)-0.085*cos(d))
    }
    func advance(to clock: Double) {
        defer { previousTime = clock }
        guard let previousTime, clock > previousTime, settings.running else { return }
        var remaining = Float(min(0.1,clock-previousTime))*settings.speed
        hue = settings.colorDrift ? (hue + Float(min(0.1,clock-previousTime))*0.65).truncatingRemainder(dividingBy: 360) : settings.hue
        while remaining > 0 {
            let dt = min(remaining,1/30); remaining -= dt; time += dt
            let replenish = 1-exp(-dt*0.075)
            for j in 0..<height { for i in 0..<width {
                let x = Float(i)/resolution-margin, y = Float(j)/resolution-margin, v1 = velocity(x,y,time)
                let v2 = velocity(x-v1.x*dt*0.5,y-v1.y*dt*0.5,time-dt*0.5)
                let v = raw(x-v2.x*dt,y-v2.y*dt)
                let recovered = v+(v-0.5)*v*(1-v)*dt*0.18
                next[j*width+i] = min(1,max(0,recovered*(1-replenish)+source(x,y)*replenish))
            } }
            swap(&values,&next); contrastAge += dt
            if contrastAge >= 0.5 { measureContrast(); contrastAge = 0 }
            let response = 1-exp(-dt*1.2)
            center += (targetCenter-center)*response; gain *= exp(log(targetGain/gain)*response)
        }
        updateTree(initialize: false); generation &+= 1
    }
    func synchronizeClock(_ clock: Double) { previousTime = clock }
    private func change(_ n: Node, _ split: Bool) {
        guard n.split != split else { return }; n.split = split; n.changedAt = time
        if split { n.generation &+= 1; assignMotif(n); for child in n.children { child.split = false; child.changedAt = time } }
    }
    private func updateTree(initialize: Bool) {
        func limits(_ n: Node, _ exposed: Int?) -> Int {
            let depth = exposed ?? (n.split ? nil : n.depth)
            var result = initialize ? 2 : (depth.map { $0+1 } ?? 2)
            for c in n.children { result = min(result,limits(c,depth)) }; n.stepLimit = result; return result
        }
        func visit(_ n: Node) {
            guard !n.children.isEmpty else { return }
            let value = sample(n.x+n.size/2,n.y+n.size/2)+(settings.density-0.48)*0.85
            let threshold = 0.23+Float(n.depth)*0.235+(Self.hash(n.id,6,settings.seed)-0.5)*0.045
            let target = value > threshold + (n.split ? -0.025 : 0.025)
            if initialize { change(n,target); if n.split { n.children.forEach(visit) }; return }
            if !n.split { if target && time-n.changedAt >= 0.16 { change(n,true) } }
            else if !target && n.children.allSatisfy({ !$0.split && time-$0.changedAt >= 0.16 }) { change(n,false) }
            else { n.children.forEach(visit) }
        }
        for root in roots { _ = limits(root,nil); visit(root) }
        balance()
    }
    private func collect() -> [Node] {
        var result: [Node] = []
        func visit(_ n: Node) { if n.split { n.children.forEach(visit) } else { result.append(n) } }
        roots.forEach(visit); return result
    }
    private struct Edge { let start: Int, end: Int, node: Node }
    private struct Pair { var a: [Edge] = [], b: [Edge] = [] }
    private func balance() {
        while true {
            leaves = collect(); var vertical: [Int:Pair] = [:], horizontal: [Int:Pair] = [:]
            func insert(_ map: inout [Int:Pair], _ line: Int, _ side: Bool, _ start: Int, _ end: Int, _ n: Node) {
                let e = Edge(start:start,end:end,node:n)
                if side { map[line,default:Pair()].b.append(e) } else { map[line,default:Pair()].a.append(e) }
            }
            for n in leaves {
                let x = Int((n.x*36).rounded()), y = Int((n.y*36).rounded()), size = Int((n.size*36).rounded())
                insert(&vertical,x,false,y,y+size,n); insert(&vertical,x+size,true,y,y+size,n)
                insert(&horizontal,y,false,x,x+size,n); insert(&horizontal,y+size,true,x,x+size,n)
            }
            var refine: [ObjectIdentifier:Node] = [:], deferNodes: [ObjectIdentifier:Node] = [:]
            for map in [vertical,horizontal] { for pair in map.values {
                let a = pair.a.sorted { $0.start < $1.start }, b = pair.b.sorted { $0.start < $1.start }; var i = 0, j = 0
                while i < a.count && j < b.count {
                    let p = a[i], q = b[j]
                    if max(p.start,q.start)<min(p.end,q.end) {
                        let coarse = p.node.size > q.node.size ? p.node : q.node, fine = coarse === p.node ? q.node : p.node
                        if abs(coarse.depth-fine.depth)>1 || coarse.size > 3*fine.size+0.00001 {
                            if coarse.depth+1<=coarse.stepLimit { refine[ObjectIdentifier(coarse)] = coarse }
                            else if let parent = fine.parent { deferNodes[ObjectIdentifier(parent)] = parent }
                        }
                    }
                    if p.end<=q.end { i += 1 } else { j += 1 }
                }
            } }
            if !deferNodes.isEmpty { for n in deferNodes.values { change(n,false) }; continue }
            if refine.isEmpty { return }
            for n in refine.values { change(n,true) }
        }
    }
    func tileData() -> ([Tile], [UInt32]) {
        let w = columns*36, h = rows*36
        var map = [UInt32](repeating: 0,count:w*h), tiles: [Tile] = []; tiles.reserveCapacity(leaves.count)
        for (index,n) in leaves.enumerated() {
            tiles.append(Tile(bounds:SIMD4(n.x,n.y,n.size,0),motif:SIMD4(UInt32(n.color),UInt32(n.foreground),UInt32(n.motif),UInt32(n.rotation))))
            let x = Int((n.x*36).rounded()), y = Int((n.y*36).rounded()), span = Int((n.size*36).rounded())
            for row in y..<min(h,y+span) { for col in x..<min(w,x+span) { map[row*w+col] = UInt32(index) } }
        }
        return (tiles,map)
    }
}
