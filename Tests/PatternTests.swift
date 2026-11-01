import Foundation
@main struct PatternTests {
    static func main() {
        var settings = PatternSettings(); settings.density = 0.48
        let a = PatternSimulation(columns: 7,rows: 5,settings: settings)
        let b = PatternSimulation(columns: 7,rows: 5,settings: settings)
        precondition(MemoryLayout<PatternSimulation.Tile>.stride == 32)
        let width = 7*36, height = 5*36
        var previous: [Int]?
        for frame in 0..<40 {
            let t = Double(frame)*0.05; a.advance(to:t); b.advance(to:t)
            let (tiles,map) = a.tileData(), (other,otherMap) = b.tileData()
            precondition(map == otherMap && tiles.count == other.count)
            precondition(map.count == width*height)
            precondition(abs(a.leaves.reduce(Float(0),{$0+$1.size*$1.size})-35)<0.001)
            let depths = map.map { a.leaves[Int($0)].depth }
            for y in 0..<height { for x in 0..<width {
                let i = y*width+x, n = a.leaves[Int(map[i])]
                let scale = Int((1/n.size).rounded())
                precondition([1,2,3,4,6,9].contains(scale))
                if let previous { precondition(abs(n.depth-previous[i])<=1) }
                for j in [x+1<width ? i+1 : i,y+1<height ? i+width : i] {
                    let m = a.leaves[Int(map[j])]
                    precondition(abs(n.depth-m.depth)<=1 && max(n.size,m.size)<=3*min(n.size,m.size)+0.0001)
                }
            } }
            previous = depths
        }
        precondition(a.time>0 && a.generation>0)
        let time = a.time; a.advance(to:1.95);precondition(a.time==time)
        print("PASS: native flow, deterministic mixed scales, coverage, balanced neighbors, one-step evolution and GPU layout")
    }
}
