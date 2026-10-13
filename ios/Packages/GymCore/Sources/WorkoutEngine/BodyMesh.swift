import Foundation

/// 3D body figure for the 3D body map (#225), built from the 2D body map art: the front silhouette is inflated into a
/// rounded volume (depth ∝ √distance to the edge, plus a little relief over the muscles), split into a front and a back
/// surface that meet on the contour. The front surface shows the front sheet, the back surface the back sheet, so the
/// 3D figure, its colours and its taps all come from the same polygons as the 2D map. No third-party model.
///
/// Model space: x = design x − 100 (figure's right side at −x), y = 410 − design y (feet at 0, up), z toward the viewer
/// of the front view. Texture coordinates: (0, 0) = top-left of the sheet, as drawn by the 2D map.
public struct BodyMesh: Sendable {
    public struct Surface: Sendable {
        public var positions: [SIMD3<Float>]
        public var normals: [SIMD3<Float>]
        public var uvs: [SIMD2<Float>]
        public var indices: [UInt32]
    }

    public let front: Surface
    public let back: Surface

    /// Design units per grid step of the mesh.
    public static let step = 1.5
    /// Depth scale: z = depth · √d (d = design units from the edge).
    static let depth = 3.8
    /// Extra depth over muscles (design units).
    static let relief = 1.4

    // MARK: Hit testing

    /// Muscle under a point on the mesh (model space), using the 2D map's hit test on the side it lies on.
    public static func muscle(atModel p: SIMD3<Float>, figure: BodyMapLayout.Figure, tolerance: Double = 4) -> Muscle? {
        let (side, x, y) = designPoint(p)
        return BodyMapLayout.muscle(at: x, y, side: side, figure: figure, tolerance: tolerance)
    }

    /// Side and design-space point of a model-space point. The back sheet is drawn as seen from behind, so its x runs
    /// the other way.
    public static func designPoint(_ p: SIMD3<Float>) -> (BodyMapLayout.Side, Double, Double) {
        let y = BodyMapLayout.height - Double(p.y)
        return p.z >= 0 ? (.front, Double(p.x) + BodyMapLayout.width / 2, y) : (.back, BodyMapLayout.width / 2 - Double(p.x), y)
    }

    /// Model-space centre of a muscle on the side it shows best (camera focus for a picked muscle).
    public static func centre(of muscle: Muscle, figure: BodyMapLayout.Figure) -> (side: BodyMapLayout.Side, point: SIMD3<Float>)? {
        guard let f = BodyMapLayout.focus(muscle, figure: figure) else { return nil }
        let cx = f.x + f.size / 2, cy = f.y + f.size / 2
        let x = f.side == .front ? cx - BodyMapLayout.width / 2 : BodyMapLayout.width / 2 - cx
        return (f.side, SIMD3(Float(x), Float(BodyMapLayout.height - cy), f.side == .front ? 10 : -10))
    }

    // MARK: Build

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [BodyMapLayout.Figure: BodyMesh] = [:]

    /// Cached mesh for a figure (first build takes a few tens of ms; call off the main thread).
    public static func of(_ figure: BodyMapLayout.Figure) -> BodyMesh {
        lock.lock(); defer { lock.unlock() }
        if let m = cache[figure] { return m }
        let m = build(figure)
        cache[figure] = m
        return m
    }

    /// Raster resolution (cells per design unit) for the distance fields.
    static let res = 1.5

    public static func build(_ figure: BodyMapLayout.Figure) -> BodyMesh {
        let W = BodyMapLayout.width, H = BodyMapLayout.height
        let grid = Raster(w: Int(W * res), h: Int(H * res))
        let silhouette = grid.sdf(fill: BodyMapLayout.outline(.front, figure: figure))
        let reliefFront = grid.sdf(fill: BodyMapLayout.shapes(.front, figure: figure).map(\.points))
        let reliefBack = grid.sdf(fill: BodyMapLayout.shapes(.back, figure: figure).map(\.points))

        let nx = Int(W / step) + 1, ny = Int(H / step) + 1
        var index = [Int32](repeating: -1, count: nx * ny)
        var inside = [Bool](repeating: false, count: nx * ny)
        struct V { var x, y, d: Double; var edge: SIMD2<Double>? }
        var verts: [V] = []
        for j in 0..<ny {
            for i in 0..<nx {
                var x = Double(i) * step, y = Double(j) * step
                let d = grid.sample(silhouette, x, y)
                if d < -step * 1.01 { continue }
                var edge: SIMD2<Double>?
                if d <= 0 {
                    // Snap onto the contour along the field's gradient, so the outline is smooth, not stair-stepped.
                    let e = 0.5
                    let gx = grid.sample(silhouette, x + e, y) - grid.sample(silhouette, x - e, y)
                    let gy = grid.sample(silhouette, x, y + e) - grid.sample(silhouette, x, y - e)
                    let len = max(1e-6, hypot(gx, gy))
                    x += gx / len * -d
                    y += gy / len * -d
                    edge = SIMD2(-gx / len, -gy / len)
                } else {
                    inside[j * nx + i] = true
                }
                index[j * nx + i] = Int32(verts.count)
                verts.append(V(x: x, y: y, d: max(0, d), edge: edge))
            }
        }

        func surface(front: Bool) -> Surface {
            let rel = front ? reliefFront : reliefBack
            let sign: Double = front ? 1 : -1
            var pos: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = []
            pos.reserveCapacity(verts.count); uv.reserveCapacity(verts.count)
            for v in verts {
                let sx = front ? v.x : W - v.x // sheet x
                var z = 0.0
                if v.d > 0 {
                    let r = grid.sample(rel, sx, v.y) // signed distance into the muscles
                    let bump = max(0, min(1, (r + 1) / 3.5))
                    z = depth * v.d.squareRoot() + relief * bump * bump * (3 - 2 * bump) * min(1, v.d / 3)
                }
                pos.append(SIMD3(Float(v.x - W / 2), Float(H - v.y), Float(sign * z)))
                uv.append(SIMD2(Float(sx / W), Float(v.y / H)))
            }
            var idx: [UInt32] = []
            idx.reserveCapacity(verts.count * 6)
            for j in 0..<(ny - 1) {
                for i in 0..<(nx - 1) {
                    let k = [j * nx + i, j * nx + i + 1, (j + 1) * nx + i, (j + 1) * nx + i + 1]
                    guard k.allSatisfy({ index[$0] >= 0 }), k.contains(where: { inside[$0] }) else { continue }
                    let a = UInt32(index[k[0]]), b = UInt32(index[k[1]]), c = UInt32(index[k[2]]), d = UInt32(index[k[3]])
                    // Counter-clockwise seen from the surface's own side (y is flipped into model space).
                    if front { idx += [a, c, b, b, c, d] } else { idx += [a, b, c, b, d, c] }
                }
            }
            var normals = Self.normals(pos, idx)
            for (k, v) in verts.enumerated() {
                if let e = v.edge { normals[k] = SIMD3(Float(e.x), Float(-e.y), 0) } // seam: outward, in plane
            }
            return Surface(positions: pos, normals: normals, uvs: uv, indices: idx)
        }
        return BodyMesh(front: surface(front: true), back: surface(front: false))
    }

    static func normals(_ pos: [SIMD3<Float>], _ idx: [UInt32]) -> [SIMD3<Float>] {
        var n = [SIMD3<Float>](repeating: .zero, count: pos.count)
        for t in stride(from: 0, to: idx.count, by: 3) {
            let a = Int(idx[t]), b = Int(idx[t + 1]), c = Int(idx[t + 2])
            let f = cross(pos[b] - pos[a], pos[c] - pos[a])
            n[a] += f; n[b] += f; n[c] += f
        }
        return n.map { v in
            let l = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
            return l > 0 ? v / l : SIMD3(0, 0, 1)
        }
    }

    private static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
}

/// Signed distance fields over the design space (positive inside), from smoothed polygons.
private struct Raster {
    let w, h: Int
    var scale: Double { BodyMesh.res }

    func sample(_ f: [Float], _ x: Double, _ y: Double) -> Double {
        let i = min(w - 1, max(0, Int((x * scale).rounded()))), j = min(h - 1, max(0, Int((y * scale).rounded())))
        return Double(f[j * w + i])
    }

    /// Union of the polygons (each Catmull-Rom smoothed like the 2D map), as a signed distance in design units.
    func sdf(fill polygons: [[BodyMapLayout.Point]]) -> [Float] {
        var mask = [Bool](repeating: false, count: w * h)
        for poly in polygons {
            let pts = Self.smoothed(poly).map { (x: $0.x * scale, y: $0.y * scale) }
            guard pts.count > 2 else { continue }
            for j in 0..<h {
                let y = Double(j) + 0.5
                var xs: [Double] = []
                var k = pts.count - 1
                for i in pts.indices {
                    let p = pts[i], q = pts[k]
                    if (p.y > y) != (q.y > y) { xs.append(p.x + (y - p.y) * (q.x - p.x) / (q.y - p.y)) }
                    k = i
                }
                xs.sort()
                for s in stride(from: 0, to: xs.count - 1, by: 2) {
                    let a = max(0, Int((xs[s] - 0.5).rounded(.up))), b = min(w - 1, Int((xs[s + 1] - 0.5).rounded(.down)))
                    if a <= b { for i in a...b { mask[j * w + i] = true } }
                }
            }
        }
        let din = edt(mask, target: false), dout = edt(mask, target: true)
        var out = [Float](repeating: 0, count: w * h)
        for i in out.indices { out[i] = Float((mask[i] ? din[i] : -dout[i]) / scale) }
        return out
    }

    /// Catmull-Rom spline through the closed polygon, 6 samples per edge.
    static func smoothed(_ pts: [BodyMapLayout.Point]) -> [BodyMapLayout.Point] {
        let n = pts.count
        guard n > 2 else { return pts }
        var out: [BodyMapLayout.Point] = []
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            for s in 0..<6 {
                let t = Double(s) / 6, t2 = t * t, t3 = t2 * t
                func f(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
                }
                out.append(BodyMapLayout.Point(x: f(p0.x, p1.x, p2.x, p3.x), y: f(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        return out
    }

    /// Euclidean distance (in cells) to the nearest cell whose mask equals `target` (Felzenszwalb–Huttenlocher).
    func edt(_ mask: [Bool], target: Bool) -> [Double] {
        let inf = 1e12
        var g = mask.map { $0 == target ? 0.0 : inf }
        var col = [Double](repeating: 0, count: h)
        for x in 0..<w {
            for y in 0..<h { col[y] = g[y * w + x] }
            let r = Self.edt1(col)
            for y in 0..<h { g[y * w + x] = r[y] }
        }
        var row = [Double](repeating: 0, count: w)
        for y in 0..<h {
            for x in 0..<w { row[x] = g[y * w + x] }
            let r = Self.edt1(row)
            for x in 0..<w { g[y * w + x] = r[x].squareRoot() }
        }
        return g
    }

    static func edt1(_ f: [Double]) -> [Double] {
        let n = f.count
        var d = [Double](repeating: 0, count: n), v = [Int](repeating: 0, count: n), z = [Double](repeating: 0, count: n + 1)
        var k = 0
        z[0] = -.infinity; z[1] = .infinity
        if n > 1 {
            for q in 1..<n {
                var s = ((f[q] + Double(q * q)) - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
                while s <= z[k] {
                    k -= 1
                    s = ((f[q] + Double(q * q)) - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
                }
                k += 1
                v[k] = q; z[k] = s; z[k + 1] = .infinity
            }
        }
        k = 0
        for q in 0..<n {
            while z[k + 1] < Double(q) { k += 1 }
            d[q] = Double((q - v[k]) * (q - v[k])) + f[v[k]]
        }
        return d
    }
}
