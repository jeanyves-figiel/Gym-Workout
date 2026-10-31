import Foundation
import simd

/// The position guide's athletic body (#399 follow-up): a skinned mesh with its skeleton, read from
/// `Resources/ExerciseBody.bin.z` (baked by ios/Tools/illustrations/body.py from CC0 MakeHuman data) and posed on an
/// exercise's key joints the way ios/Tools/illustrations/rig.py does it, so the app shows the same body the catalog
/// was checked with:
///
/// - the pelvis, chest and head frames come from the figure's hip / shoulder / neck / head joints and the spine and
///   neck share the bend between them;
/// - the shoulder girdle follows the arm part way; arms and legs reach the figure's wrists and ankles by two-bone IK
///   (elbow / knee toward the figure's), stretching a little when the figure's limbs are longer;
/// - a hand closes into a fist around whatever it holds (bar, cable handle, dumbbell) and its palm turns to the grip;
/// - linear-blend skinning with the rig's weights, then delta mush (smooth, put the rest detail back) to take the
///   creases out of armpits, shoulders and hips.
///
/// Units and axes are the figure's: x forward, y up, z to the figure's right, floor at y = 0.
public final class BodyRig: Sendable {
    public static let muscleNames = ["", "chest", "front-delts", "side-delts", "rear-delts", "biceps", "triceps",
                                     "brachialis", "forearms", "forearm-extensors", "traps", "upper-back", "lats",
                                     "lower-back", "abs", "lower-abs", "obliques", "serratus", "glutes", "glute-med",
                                     "hip-flexors", "adductors", "quads", "hamstrings", "calves", "soleus", "tibialis"]
    /// Delta-mush passes on the device (the offline check uses 24; 12 keeps a pose under a frame on an A-series chip).
    public static let mushPasses = 12
    /// Stick figure limb lengths (figure.py): the body's limbs stretch by the ratio the figure's exceed them.
    static let figureArm = 42.0 + 38.0, figureLeg = 56.0 + 54.0
    /// Arms keep the body's own length (at most 3 % stretch, #1020): held things sit within its reach (contact.py).
    static let armStretch = 1.03

    // MARK: Rest data

    /// Rest positions.
    public let rest: [SIMD3<Float>]
    /// Fist positions (hand vertices that move when the hand closes), vertex index → position.
    let fist: [(Int, SIMD3<Float>)]
    /// Surface cavity −1 (crease) … 1 (ridge), for the skin shading.
    public let cavity: [Float]
    /// Index into `muscleNames` of the muscle under each vertex (0 = none).
    public let muscle: [UInt8]
    /// Vertices covered by the shorts.
    public let shorts: [Bool]
    /// Fibre phase 0 … 2π across the muscle's pull direction (striation stripes).
    public let phase: [Float]
    public let triangles: [UInt16]
    let boneIndex: [SIMD4<UInt8>]
    let boneWeight: [SIMD4<Float>]

    public let boneNames: [String]
    let parents: [Int]
    let heads: [SIMD3<Double>]
    let tails: [SIMD3<Double>]
    /// Palm normal of each hand in the rest pose, by mesh side.
    let palm: [String: SIMD3<Double>]
    let index: [String: Int]
    /// Bones parent-first.
    let order: [Int]
    /// Hand vertices (primary bone in the hand) by mesh side, and the vertices mostly weighted to the hand.
    let handPrimary: [String: [Bool]]
    let handMostly: [String: [Bool]]
    /// Neighbours of each vertex (CSR) for the mush smoothing.
    let adjStart: [Int32]
    let adjacent: [Int32]
    /// Rest detail the mush puts back: rest − smooth(rest).
    let restDelta: [SIMD3<Float>]

    public var vertexCount: Int { rest.count }

    // MARK: Loading

    /// The body from the bundle; nil when the resource is missing or malformed. Loads once (~1 MB packed).
    public static let shared: BodyRig? = {
        guard let url = Bundle.module.url(forResource: "ExerciseBody.bin", withExtension: "z"),
              let packed = try? Data(contentsOf: url),
              let data = try? (packed as NSData).decompressed(using: .zlib) as Data
        else { return nil }
        return BodyRig(data: data)
    }()

    /// Parses the raw (decompressed) file: see body.py `export_bin` for the layout ("MWB2").
    public init?(data: Data) {
        var p = 0
        func u8() -> Int { defer { p += 1 }; return Int(data[data.startIndex + p]) }
        func u16() -> Int { defer { p += 2 }; return Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: p, as: UInt16.self) }.littleEndian) }
        func i16() -> Int { defer { p += 2 }; return Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: p, as: Int16.self) }.littleEndian) }
        func u32() -> Int { defer { p += 4 }; return Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: p, as: UInt32.self) }.littleEndian) }
        func f32() -> Double {
            defer { p += 4 }
            return Double(Float(bitPattern: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: p, as: UInt32.self) }.littleEndian))
        }
        guard data.count > 20, u8() == 0x4D, u8() == 0x57, u8() == 0x42, u8() == 0x32 else { return nil }
        let nv = u32(), nt = u32(), nb = u32(), nf = u32()
        guard nv > 0, nv <= 65535, nb > 0, nb < 255, data.count >= 20 + nv * 18 + nf * 8 + nt * 6 else { return nil }
        var rest = [SIMD3<Float>](); rest.reserveCapacity(nv)
        var cavity = [Float](), muscle = [UInt8](), shorts = [Bool](), phase = [Float]()
        var bi = [SIMD4<UInt8>](), bw = [SIMD4<Float>]()
        cavity.reserveCapacity(nv); muscle.reserveCapacity(nv); shorts.reserveCapacity(nv); phase.reserveCapacity(nv)
        bi.reserveCapacity(nv); bw.reserveCapacity(nv)
        for _ in 0..<nv {
            rest.append(SIMD3(Float(i16()), Float(i16()), Float(i16())) / 100)
            cavity.append(Float(u8()) / 127.5 - 1)
            let m = u8()
            muscle.append(UInt8(m & 0x7F)); shorts.append(m & 0x80 != 0)
            phase.append(Float(u16()) / 65535 * 2 * .pi)
            let b = SIMD4<UInt8>(UInt8(u8()), UInt8(u8()), UInt8(u8()), UInt8(u8()))
            let w = SIMD4<Float>(Float(u8()), Float(u8()), Float(u8()), Float(u8())) / 255
            let s = w.sum()
            bi.append(b); bw.append(s > 0 ? w / s : SIMD4(1, 0, 0, 0))
        }
        var fist = [(Int, SIMD3<Float>)](); fist.reserveCapacity(nf)
        for _ in 0..<nf {
            let i = u16()
            let v = SIMD3(Float(i16()), Float(i16()), Float(i16())) / 100
            if i < nv { fist.append((i, v)) }
        }
        var tris = [UInt16](); tris.reserveCapacity(nt * 3)
        for _ in 0..<(nt * 3) { tris.append(UInt16(u16())) }
        var names = [String](), parents = [Int](), heads = [SIMD3<Double>](), tails = [SIMD3<Double>]()
        for _ in 0..<nb {
            guard p + 26 <= data.count else { return nil }
            let par = u8()
            parents.append(par == 255 ? -1 : par)
            heads.append(SIMD3(f32(), f32(), f32()))
            tails.append(SIMD3(f32(), f32(), f32()))
            let len = u8()
            guard p + len <= data.count else { return nil }
            names.append(String(decoding: data[(data.startIndex + p)..<(data.startIndex + p + len)], as: UTF8.self))
            p += len
        }
        guard p + 24 <= data.count else { return nil }
        let palmL = SIMD3(f32(), f32(), f32()), palmR = SIMD3(f32(), f32(), f32())
        guard tris.allSatisfy({ Int($0) < nv }), bi.allSatisfy({ Int($0.max()) < nb }),
              parents.allSatisfy({ $0 < nb }) else { return nil }
        self.rest = rest; self.fist = fist; self.cavity = cavity; self.muscle = muscle; self.shorts = shorts
        self.phase = phase; self.triangles = tris; self.boneIndex = bi; self.boneWeight = bw
        self.boneNames = names; self.parents = parents; self.heads = heads; self.tails = tails
        self.palm = ["L": palmL, "R": palmR]
        var index = [String: Int]()
        for (i, n) in names.enumerated() { index[n] = i }
        self.index = index
        guard ["root", "spine01", "neck01", "head", "clavicle.L", "shoulder01.R", "upperarm01.L", "lowerarm01.R",
               "wrist.L", "finger3-1.R", "upperleg01.L", "lowerleg01.R", "foot.L", "toe3-1.R"].allSatisfy({ index[$0] != nil })
        else { return nil }
        // parent-first order
        var order = [Int](), seen = [Bool](repeating: false, count: nb)
        func visit(_ i: Int) {
            if seen[i] { return }
            if parents[i] >= 0 { visit(parents[i]) }
            seen[i] = true; order.append(i)
        }
        for i in 0..<nb { visit(i) }
        self.order = order
        var primary = [String: [Bool]](), mostly = [String: [Bool]]()
        for s in ["L", "R"] {
            var inHand = [Bool](repeating: false, count: nb)
            for (i, n) in names.enumerated() where n.hasSuffix("." + s)
                && (n.hasPrefix("finger") || n.hasPrefix("metacarpal") || n.hasPrefix("wrist")) { inHand[i] = true }
            primary[s] = bi.map { inHand[Int($0.x)] }
            mostly[s] = zip(bi, bw).map { b, w in
                var t: Float = 0
                for k in 0..<4 where inHand[Int(b[k])] { t += w[k] }
                return t > 0.6
            }
        }
        handPrimary = primary; handMostly = mostly
        // vertex adjacency from the triangles (each neighbour once)
        var edges = [UInt64](); edges.reserveCapacity(nt * 6)
        for t in stride(from: 0, to: tris.count, by: 3) {
            let a = UInt64(tris[t]), b = UInt64(tris[t + 1]), c = UInt64(tris[t + 2])
            for (u, v) in [(a, b), (b, a), (b, c), (c, b), (c, a), (a, c)] { edges.append(u << 32 | v) }
        }
        edges.sort()
        var start = [Int32](repeating: 0, count: nv + 1), adj = [Int32](); adj.reserveCapacity(edges.count)
        var last: UInt64 = .max
        for e in edges where e != last {
            last = e
            adj.append(Int32(truncatingIfNeeded: e & 0xFFFF_FFFF))
            start[Int(e >> 32) + 1] += 1
        }
        for i in 0..<nv { start[i + 1] += start[i] }
        adjStart = start; adjacent = adj
        restDelta = Self.delta(rest, start: start, adjacent: adj, passes: Self.mushPasses)
    }

    // MARK: Posing

    /// What a hand holds.
    /// What a hand holds: a bar / handle / cable (axis, end a, end b) or a weight (kind, centre).
    /// rod(axis, a, b, palmsUp), weight(kind, centre, handle axis, palmsUp)
    enum Held { case rod(SIMD3<Double>, SIMD3<Double>, SIMD3<Double>, Bool), weight(String, SIMD3<Double>, SIMD3<Double>?, Bool) }

    /// A posed body: positions and normals per vertex (same order as `rest`), and the centre of each hand by figure
    /// side ("N" / "F") so equipment can sit in it.
    public struct Pose: Sendable {
        public let positions: [SIMD3<Float>]
        public let normals: [SIMD3<Float>]
        public let hands: [String: SIMD3<Double>]
        public let fists: Set<String>
    }

    /// Poses the body on a key position. `mush` = delta-mush passes (0 = plain skinning).
    public func pose(_ key: ExercisePosition.Key, mush: Int = BodyRig.mushPasses) -> Pose {
        var J = [String: SIMD3<Double>]()
        for (n, v) in key.joints where !n.hasPrefix("_") { J[n] = v }
        guard let hip = J["hip"], let shoulder = J["shoulder"], J["neck"] != nil, J["head"] != nil,
              ["N", "F"].allSatisfy({ s in ["shoulder", "elbow", "wrist", "hand", "hip", "knee", "ankle", "toe"]
                  .allSatisfy { J[$0 + s] != nil } })
        else { return Pose(positions: rest, normals: Self.normals(rest, triangles), hands: [:], fists: []) }
        let held: [String: Held?] = ["N": Self.heldObject(J, "N", key.props), "F": Self.heldObject(J, "F", key.props)]
        let grip = Set(["N", "F"].filter { held[$0]! != nil })
        let R0 = restJoints()
        let up = shoulder - hip
        let toe = (J["toeN"]! + J["toeF"]!) / 2 - (J["ankleN"]! + J["ankleF"]!) / 2
        let chir = simd_double3x3(rows: [perp(toe, nrm(up)), up, J["shoulderF"]! - J["shoulderN"]!]).determinant
        // rest: x forward, y up, MakeHuman .L at -z, so (fwd, up, R-L) is right-handed
        let side: [String: String] = chir > 0 ? ["L": "N", "R": "F"] : ["L": "F", "R": "N"]

        func trunk(_ Jx: [String: SIMD3<Double>], _ l: String, _ r: String) -> (simd_double3x3, simd_double3x3, simd_double3x3) {
            let u = nrm(Jx["shoulder"]! - Jx["hip"]!)
            let fwT = (Jx["toe" + l]! + Jx["toe" + r]!) / 2 - (Jx["ankle" + l]! + Jx["ankle" + r]!) / 2
            var out = [simd_double3x3]()
            for lat in [Jx["hip" + r]! - Jx["hip" + l]!, Jx["shoulder" + r]! - Jx["shoulder" + l]!] {
                var f = cross(u, nrm(lat))
                if dot(f, fwT) < 0 { f = -f }
                out.append(basis(u, f))
            }
            let hu = nrm(Jx["head"]! - Jx["neck"]!)
            return (out[0], out[1], basis(hu, out[1].columns.1))
        }
        let (Bp0, Bc0, Bh0) = trunk(R0, "L", "R")
        let (Bp1, Bc1, Bh1) = trunk(J, side["L"]!, side["R"]!)
        let Rp = rot(Bp0, Bp1), Rc = rot(Bc0, Bc1), Rh = rot(Bh0, Bh1)
        let n = boneNames.count
        let fixed: [String: simd_double3x3] = [
            "root": Rp, "spine05": Rp, "spine04": slerp(Rp, Rc, 0.25), "spine03": slerp(Rp, Rc, 0.5),
            "spine02": slerp(Rp, Rc, 0.8), "spine01": Rc, "neck01": slerp(Rc, Rh, 0.35), "neck02": slerp(Rc, Rh, 0.7),
            "neck03": Rh, "head": Rh,
        ]
        let hipRest = (h("upperleg01.L") + h("upperleg01.R")) / 2
        var Rw = [simd_double3x3](repeating: matrix_identity_double3x3, count: n)
        var A = [simd_double3x3](repeating: matrix_identity_double3x3, count: n)
        var T = [SIMD3<Double>](repeating: .zero, count: n)
        var Ph = [SIMD3<Double>](repeating: .zero, count: n)
        var limb = [String: [String: (simd_double3x3, Double)]]()
        let armBones: Set<String> = ["clavicle", "shoulder01", "upperarm01", "upperarm02", "lowerarm01", "lowerarm02", "wrist"]
        let legBones: Set<String> = ["upperleg01", "upperleg02", "lowerleg01", "lowerleg02", "foot"]
        for i in order {
            let name = boneNames[i]
            let p = parents[i]
            Ph[i] = p < 0 ? hip + Rp * (heads[i] - hipRest) : A[p] * heads[i] + T[p]
            let s = name.hasSuffix(".L") ? "L" : name.hasSuffix(".R") ? "R" : ""
            let base = s.isEmpty ? name : String(name.dropLast(2))
            var R = p >= 0 ? Rw[p] : Rp
            var k = 1.0
            if let f = fixed[name] {
                R = f
            } else if armBones.contains(base) {
                if limb[s] == nil {
                    limb[s] = arm(s, side[s]!, J, Rc, Ph[i], held[side[s]!]!,
                                  elev: side[s]! == "N" ? (key.joints["_elev"]?.x ?? 0) : (key.joints["_elev"]?.y ?? 0))
                }
                if let v = limb[s]![base] { R = v.0; k = v.1 }
            } else if legBones.contains(base) {
                if limb["leg" + s] == nil {
                    limb["leg" + s] = leg(s, side[s]!, J, Ph[i])
                }
                if let v = limb["leg" + s]![base] { R = v.0; k = v.1 }
            } else if base.hasPrefix("toe"), let v = limb["leg" + s]?["toe"] {
                R = v.0
            }
            Rw[i] = R
            let d = nrm(tails[i] - heads[i])
            let dd = outer(d, d)
            let Sc = matrix_identity_double3x3 + (k - 1) * dd + (k.squareRoot() - 1) * (matrix_identity_double3x3 - dd)
            A[i] = R * Sc
            T[i] = Ph[i] - A[i] * heads[i]
        }
        // skinning
        var vin = rest
        var fists = Set<String>()
        for s in ["L", "R"] where grip.contains(side[s]!) {
            fists.insert(side[s]!)
            let mask = handPrimary[s]!
            for (i, v) in fist where mask[i] { vin[i] = v }
        }
        let Af = A.map { simd_float3x3(SIMD3<Float>($0.columns.0), SIMD3<Float>($0.columns.1), SIMD3<Float>($0.columns.2)) }
        let Tf = T.map { SIMD3<Float>($0) }
        var out = [SIMD3<Float>](repeating: .zero, count: vin.count)
        var Rv = [simd_float3x3](repeating: simd_float3x3(0), count: mush > 0 ? vin.count : 0)
        for i in 0..<vin.count {
            let b = boneIndex[i], w = boneWeight[i], v = vin[i]
            var o = SIMD3<Float>.zero
            var r = simd_float3x3(0)
            for k in 0..<4 where w[k] > 0 {
                let m = Af[Int(b[k])]
                o += w[k] * (m * v + Tf[Int(b[k])])
                if mush > 0 { r += w[k] * m }
            }
            out[i] = o
            if mush > 0 { Rv[i] = r }
        }
        // delta mush: smooth the skinning creases away, then put the rest-pose detail back
        if mush > 0 {
            let delta = fists.isEmpty && mush == Self.mushPasses ? restDelta
                : Self.delta(vin, start: adjStart, adjacent: adjacent, passes: mush)
            out = Self.smooth(out, start: adjStart, adjacent: adjacent, passes: mush)
            for i in 0..<out.count { out[i] += Rv[i] * delta[i] }
        }
        if key.dy != 0 {
            let dy = Float(key.dy)
            for i in 0..<out.count { out[i].y += dy }
        }
        var hands = [String: SIMD3<Double>]()
        for s in ["L", "R"] {
            var c = SIMD3<Double>.zero, count = 0.0
            for (i, m) in handMostly[s]!.enumerated() where m { c += SIMD3<Double>(out[i]); count += 1 }
            if count > 0 { hands[side[s]!] = c / count }
        }
        return Pose(positions: out, normals: Self.normals(out, triangles), hands: hands, fists: fists)
    }

    /// Per-vertex weight 0 … 1 of the worked muscles, feathered over three passes so the tissue fades into the skin.
    public func work(_ muscles: [Muscle]) -> [Float] {
        let ids = Set(muscles.compactMap { Self.muscleNames.firstIndex(of: $0.rawValue) }.map { UInt8($0) })
        var w = muscle.map { ids.contains($0) ? Float(1) : 0 }
        guard !ids.isEmpty else { return w }
        for _ in 0..<3 {
            var acc = [Float](repeating: 0, count: w.count), cnt = [Float](repeating: 0, count: w.count)
            for t in stride(from: 0, to: triangles.count, by: 3) {
                let a = Int(triangles[t]), b = Int(triangles[t + 1]), c = Int(triangles[t + 2])
                let s = w[a] + w[b] + w[c]
                acc[a] += s; acc[b] += s; acc[c] += s
                cnt[a] += 3; cnt[b] += 3; cnt[c] += 3
            }
            for i in 0..<w.count where cnt[i] > 0 { w[i] = acc[i] / cnt[i] }
        }
        return w
    }

    // MARK: Limbs

    func h(_ name: String) -> SIMD3<Double> { heads[index[name]!] }

    /// The figure's joints in the rest pose.
    func restJoints() -> [String: SIMD3<Double>] {
        var J: [String: SIMD3<Double>] = [
            "hip": (h("upperleg01.L") + h("upperleg01.R")) / 2, "shoulder": (h("upperarm01.L") + h("upperarm01.R")) / 2,
            "neck": h("neck01"), "head": h("head") + (tails[index["head"]!] - h("head")) * 0.35,
        ]
        for s in ["L", "R"] {
            J["shoulder" + s] = h("upperarm01." + s); J["elbow" + s] = h("lowerarm01." + s)
            J["wrist" + s] = h("wrist." + s); J["hand" + s] = h("finger3-1." + s)
            J["hip" + s] = h("upperleg01." + s); J["knee" + s] = h("lowerleg01." + s)
            J["ankle" + s] = h("foot." + s); J["toe" + s] = h("toe3-1." + s)
        }
        return J
    }

    /// Rotations (and stretch) for clavicle … wrist on mesh side `s` / figure side `d`; `clav` = posed clavicle head.
    private func arm(_ s: String, _ d: String, _ J: [String: SIMD3<Double>], _ Rc: simd_double3x3, _ clav: SIMD3<Double>,
                     _ held: Held?, elev: Double = 0) -> [String: (simd_double3x3, Double)] {
        let sh0 = h("upperarm01." + s), el0 = h("lowerarm01." + s), wr0 = h("wrist." + s), hd0 = h("finger3-1." + s)
        let a0 = length(el0 - sh0), b0 = length(wr0 - el0)
        // the figure's arm direction relative to the chest decides how far the girdle follows
        let G = between(nrm(Rc * (el0 - sh0)), nrm(J["elbow" + d]! - J["shoulder" + d]!))
        var Rcl = slerp(Rc, G * Rc, 0.18), Rsh = slerp(Rc, G * Rc, 0.35)
        var S = clav + Rcl * (h("shoulder01." + s) - h("clavicle." + s))
        S += Rsh * (sh0 - h("shoulder01." + s))
        if elev > 0 {           // shrug: the clavicle swings up about its head until the shoulder sits `elev` higher
            let v = S - clav
            let E = between(nrm(v), nrm(v + (Rc * SIMD3(0, 1, 0)) * elev))
            Rcl = E * Rcl; Rsh = E * Rsh
            S = clav + E * v
        }
        // the figure is narrower than the body: carry the shoulder's sideways offset to the elbow and to hands that
        // hang outside the shoulder line (hands that grip or meet in front stay put)
        let lat = nrm(J["shoulder" + d]! - J["shoulder"]!)
        let off = dot(S - J["shoulder" + d]!, lat) * lat
        let wl = length(J["shoulder" + d]! - J["shoulder"]!)
        let kk = min(1, max(0, dot(J["hand" + d]! - J["shoulder"]!, lat) / max(wl, 1e-6)))
        var Wt = J["wrist" + d]! + off * kk + lat * 8 * kk
        let Jel = J["elbow" + d]! + off * (0.5 + 0.5 * kk) + lat * 6 * kk
        // grip: the hollow of the fist (past the knuckles, on the palm side) is what sits on the object. Bars and
        // handles stay where the scene put them and the hand goes to them; a dumbbell was placed in the hand already
        let hd = J["hand" + d]! - J["wrist" + d]!
        let pd = Self.palmDir(J, d, hd, J["wrist" + d]! - J["elbow" + d]!, held, nrm(cross(hd, SIMD3(0, 1, 0))))
        let goff = 0.62 * length(hd0 - wr0) * nrm(hd) + 3.0 * pd
        if case let .rod(_, a, b, _) = held {
            let ab = b - a
            let t = min(1, max(0, dot(Wt + goff - a, ab) / dot(ab, ab)))
            Wt = a + t * ab - goff
        } else if held == nil, J["hand" + d]!.y < 8 {
            Wt.y = max(Wt.y, 4)                              // a flat hand on the floor: wrist a palm's thickness up
        }
        let reach = length(J["wrist" + d]! - J["shoulder" + d]!)
        let k = min(Self.armStretch, max(0.95, Self.figureArm * length(Wt - S) / max(reach, 1e-6) / (a0 + b0)))
        let (E, Wp) = twoBone(S, Wt, a0 * k, b0 * k, Jel + (Jel - (S + Wt) / 2) * 2)
        let ua = E - S, fa = Wp - E
        let bend = length(perp(nrm(fa), nrm(ua)))
        let aUa = bend > 0.2 ? perp(nrm(fa), nrm(ua)) : perp(Rc * SIMD3(1, 0, 0), nrm(ua))
        let ua0 = el0 - sh0, fa0 = wr0 - el0
        let Rua = rot(basis(ua0, perp(nrm(fa0), nrm(ua0))), basis(ua, aUa))
        let aFa0 = -perp(nrm(ua0), nrm(fa0))
        let aFa = bend > 0.2 ? -perp(nrm(ua), nrm(fa)) : Rua * aFa0
        let Rfa = rot(basis(fa0, aFa0), basis(fa, aFa))
        let Rhd = rot(basis(hd0 - wr0, palm[s]!), basis(hd, Self.palmDir(J, d, hd, fa, held, aFa)))
        return ["clavicle": (Rcl, 1), "shoulder01": (Rsh, 1), "upperarm01": (Rua, k), "upperarm02": (Rua, k),
                "lowerarm01": (Rfa, k), "lowerarm02": (Rfa, k), "wrist": (Rhd, 1)]
    }

    /// Rotations (and stretch) for thigh … foot; `Hp` = posed hip joint.
    private func leg(_ s: String, _ d: String, _ J: [String: SIMD3<Double>], _ Hp: SIMD3<Double>) -> [String: (simd_double3x3, Double)] {
        let hp0 = h("upperleg01." + s), kn0 = h("lowerleg01." + s), an0 = h("foot." + s), to0 = h("toe3-1." + s)
        let a0 = length(kn0 - hp0), b0 = length(an0 - kn0)
        let up = nrm(J["shoulder"]! - J["hip"]!)
        var off = Hp - J["hip" + d]!
        off -= dot(off, up) * up
        var At = J["ankle" + d]! + off
        var Toe = J["toe" + d]! + off
        let onToes = At.y >= 8 && Toe.y < 4 && At.y > Toe.y + 6   // push-ups, planks: up on the ball of the foot
        if At.y < 8 {    // the 2D figure's ankle sits on the floor; the body's ankle is above its sole
            At.y += an0.y - 0.5
            Toe.y = max(Toe.y, to0.y)
        } else if onToes {
            Toe.y = to0.y
        }
        let Jkn = J["knee" + d]! + off
        let reach = length(J["ankle" + d]! - J["hip" + d]!)
        let k = min(1.15, max(0.9, Self.figureLeg * length(At - Hp) / max(reach, 1e-6) / (a0 + b0)))
        let (K, Ap) = twoBone(Hp, At, a0 * k, b0 * k, Jkn + (Jkn - (Hp + At) / 2) * 2)
        let th = K - Hp, sn = Ap - K, ft = Toe - Ap
        let th0 = kn0 - hp0, sn0 = an0 - kn0, ft0 = to0 - an0
        let aSn0 = perp(nrm(ft0), nrm(sn0)), aSn = perp(nrm(ft), nrm(sn))
        let kb = length(perp(nrm(sn), nrm(th)))
        let aTh = kb > 0.15 ? -perp(nrm(sn), nrm(th)) : aSn
        let Rth = rot(basis(th0, perp(nrm(ft0), nrm(th0))), basis(th, aTh))
        let Rsn = rot(basis(sn0, aSn0), basis(sn, aSn))
        let up3 = SIMD3<Double>(0, 1, 0)
        let Rft = rot(basis(ft0, Self.dorsum(ft0, sn0)), basis(ft, Self.dorsum(ft, sn)))
        var out: [String: (simd_double3x3, Double)] = ["upperleg01": (Rth, k), "upperleg02": (Rth, k), "lowerleg01": (Rsn, k),
                                                        "lowerleg02": (Rsn, k), "foot": (Rft, 1)]
        if onToes {      // toes bend back to lie flat on the floor
            var fl = perp(ft, up3)
            if length(fl) < 1e-3 { fl = perp(th, up3) }
            out["toe"] = (rot(basis(ft0, up3), basis(nrm(fl), up3)), 1)
        }
        return out
    }

    /// Which way the top of the foot faces (rig.py `dorsum`): back up the shin, so a foot pressing a leg-press sled
    /// or a wall has its sole on the plate whichever way the toes point; world up when the toes point along the shin.
    static func dorsum(_ ft: SIMD3<Double>, _ sn: SIMD3<Double>) -> SIMD3<Double> {
        let up = SIMD3<Double>(0, 1, 0)
        let v = perp(-nrm(sn), nrm(ft))
        let w = min(1, max(0, (length(v) - 0.2) / 0.3))
        let a = w * nrm(v) + (1 - w) * nrm(perp(up, nrm(ft)))
        return length(a) > 1e-3 ? a : up
    }

    // MARK: Hands

    /// What the figure's hand on side `d` holds: a bar / handle / cable through the hand (with its axis), or a
    /// dumbbell / kettlebell / ball at the hand.
    static func heldObject(_ J: [String: SIMD3<Double>], _ d: String, _ props: [ExercisePosition.Prop]) -> Held? {
        let hd = J["hand" + d]!, wr = J["wrist" + d]!
        var best: (Double, Held)?
        for p in props {
            switch p {
            case let .rod(a, b, _, up):
                let ab = b - a
                let L2 = dot(ab, ab)
                guard L2 > 1e-6 else { continue }
                for pt in [hd, (hd + wr) / 2] {
                    let t = min(1, max(0, dot(pt - a, ab) / L2))
                    let dist = length(pt - (a + t * ab))
                    if dist < 9, best.map({ dist < $0.0 }) ?? true { best = (dist, .rod(nrm(ab), a, b, up)) }
                }
            case let .weight(kind, c, r, ax, up):
                let r = r > 0 ? r : 8
                if kind == "ball", r > 12 { continue }        // a stability ball is sat or lain on, not held
                if kind == "roller" || kind == "foam" { continue }    // machine rollers and foam rollers are not held
                // the weight may already sit in the body's (wider) hand, outside the figure's: measure across the
                // shoulder line and allow the sideways offset
                let lat = nrm(J["shoulder" + d]! - J["shoulder"]!)
                let l = dot(c - hd, lat)
                let dist = length((c - hd) - l * lat)
                if dist < r + 6, l > -16, l < 30, best.map({ dist < $0.0 }) ?? true { best = (dist, .weight(kind, c, ax.map(nrm), up)) }
            default: continue
            }
        }
        return best?.1
    }

    /// Dumbbell handle axis for the hand on side `d`: front-back when the arm hangs at the side or reaches out
    /// sideways (neutral grip), across the body otherwise (curls, presses, rows).
    public static func dumbbellAxis(_ J: [String: SIMD3<Double>], _ d: String) -> SIMD3<Double> {
        guard let hd = J["hand" + d], let sh = J["shoulder" + d], let hip = J["hip"], let shoulder = J["shoulder"]
        else { return SIMD3(0, 0, 1) }
        let hanging = hd.y < hip.y + 20 && abs(hd.x - sh.x) < 15
        let lateral = abs(hd.z - shoulder.z) > abs(sh.z - shoulder.z) + 12
        return hanging || lateral ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1)
    }

    /// Palm normal for the hand on figure side `d`: fingers wrap around the held object's axis; the palm continues
    /// the forearm when the load is along it (presses, pulls, hangs), else faces the body. Free hands relax.
    static func palmDir(_ J: [String: SIMD3<Double>], _ d: String, _ hd: SIMD3<Double>, _ fa: SIMD3<Double>,
                        _ held: Held?, _ aFa: SIMD3<Double>) -> SIMD3<Double> {
        let u = nrm(hd)
        let toBody = (J["hip"]! + J["shoulder"]!) / 2 - J["hand" + d]!
        guard let held else {
            let p = J["hand" + d]!.y < 8 ? perp(SIMD3(0, -1, 0), u) : perp(toBody, u)
            return length(p) > 1e-3 ? nrm(p) : aFa
        }
        var axis: SIMD3<Double>
        let palmsUp: Bool
        switch held {
        case let .rod(a, _, _, up): axis = a; palmsUp = up
        case let .weight(_, _, ax, up): axis = ax ?? dumbbellAxis(J, d); palmsUp = up
        }
        axis = perp(axis, u)
        if length(axis) < 0.2 { axis = perp(SIMD3(0, 0, 1), u) }
        let p = nrm(cross(axis, u))
        if palmsUp {                                      // underhand: the palm faces the way the elbow bends
            let sw = J["shoulder" + d]! - J["wrist" + d]!
            var t = perp(sw, nrm(fa))
            if length(t) < 0.25 * length(sw) { t = SIMD3(1, 0, 0) }
            return dot(p, t) >= 0 ? p : -p
        }
        let along = dot(p, nrm(fa))
        if abs(along) > 0.45 { return along > 0 ? p : -p }
        return dot(p, toBody) >= 0 ? p : -p
    }

    // MARK: Mesh helpers

    static func smooth(_ X: [SIMD3<Float>], start: [Int32], adjacent: [Int32], passes: Int) -> [SIMD3<Float>] {
        var X = X
        var Y = X
        for _ in 0..<passes {
            for i in 0..<X.count {
                let a = Int(start[i]), b = Int(start[i + 1])
                guard b > a else { Y[i] = X[i]; continue }
                var s = SIMD3<Float>.zero
                for j in a..<b { s += X[Int(adjacent[j])] }
                Y[i] = 0.5 * X[i] + 0.5 * s / Float(b - a)
            }
            swap(&X, &Y)
        }
        return X
    }

    static func delta(_ X: [SIMD3<Float>], start: [Int32], adjacent: [Int32], passes: Int) -> [SIMD3<Float>] {
        let S = smooth(X, start: start, adjacent: adjacent, passes: passes)
        return zip(X, S).map { $0 - $1 }
    }

    /// Area-weighted vertex normals.
    public static func normals(_ V: [SIMD3<Float>], _ tris: [UInt16]) -> [SIMD3<Float>] {
        var n = [SIMD3<Float>](repeating: .zero, count: V.count)
        for t in stride(from: 0, to: tris.count, by: 3) {
            let a = Int(tris[t]), b = Int(tris[t + 1]), c = Int(tris[t + 2])
            let fn = cross(V[b] - V[a], V[c] - V[a])
            n[a] += fn; n[b] += fn; n[c] += fn
        }
        return n.map { let l = length($0); return l > 1e-9 ? $0 / l : SIMD3(0, 1, 0) }
    }
}

// MARK: - Small rotation algebra (rig.py's helpers)

private func nrm(_ v: SIMD3<Double>) -> SIMD3<Double> {
    let n = length(v)
    return n > 1e-9 ? v / n : v
}

private func perp(_ v: SIMD3<Double>, _ ax: SIMD3<Double>) -> SIMD3<Double> { v - dot(v, ax) * ax }

private func outer(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> simd_double3x3 {
    simd_double3x3(columns: (a * b.x, a * b.y, a * b.z))
}

private func skew(_ a: SIMD3<Double>) -> simd_double3x3 {
    simd_double3x3(columns: (SIMD3(0, a.z, -a.y), SIMD3(-a.z, 0, a.x), SIMD3(a.y, -a.x, 0)))
}

/// Orthonormal frame with `u` as first axis and `a` (made perpendicular) as second.
private func basis(_ u0: SIMD3<Double>, _ a0: SIMD3<Double>) -> simd_double3x3 {
    let u = nrm(u0)
    var a = nrm(perp(a0, u))
    if length(a) < 1e-6 { a = nrm(perp(abs(u.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0), u)) }
    return simd_double3x3(columns: (u, a, cross(u, a)))
}

/// Rotation taking frame B0 to frame B1.
private func rot(_ B0: simd_double3x3, _ B1: simd_double3x3) -> simd_double3x3 { B1 * B0.transpose }

/// Rotation part way from R0 to R1.
private func slerp(_ R0: simd_double3x3, _ R1: simd_double3x3, _ t: Double) -> simd_double3x3 {
    let D = R1 * R0.transpose
    let tr = D.columns.0.x + D.columns.1.y + D.columns.2.z
    let ang = acos(min(1, max(-1, (tr - 1) / 2)))
    if ang < 1e-6 { return R0 }
    var ax = SIMD3(D.columns.1.z - D.columns.2.y, D.columns.2.x - D.columns.0.z, D.columns.0.y - D.columns.1.x)
    if length(ax) < 1e-6 {       // 180 degrees: D + I = 2 a aᵀ, any non-zero column is the axis
        let M = D + matrix_identity_double3x3
        ax = [M.columns.0, M.columns.1, M.columns.2].max { length($0) < length($1) }!
    }
    let K = skew(nrm(ax))
    let a = ang * t
    return (matrix_identity_double3x3 + sin(a) * K + (1 - cos(a)) * (K * K)) * R0
}

/// Shortest rotation taking direction a to direction b.
private func between(_ a0: SIMD3<Double>, _ b0: SIMD3<Double>) -> simd_double3x3 {
    let a = nrm(a0), b = nrm(b0)
    let v = cross(a, b), c = dot(a, b)
    if c < -0.9999 {
        let K = skew(nrm(perp(abs(a.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0), a)))
        return matrix_identity_double3x3 + 2 * (K * K)
    }
    let K = skew(v)
    return matrix_identity_double3x3 + K + (K * K) * (1 / (1 + c))
}

/// Elbow / knee position for a chain S → E → T with lengths a, b, bending toward `pole`; returns (E, end).
private func twoBone(_ S: SIMD3<Double>, _ T: SIMD3<Double>, _ a: Double, _ b: Double, _ pole: SIMD3<Double>)
    -> (SIMD3<Double>, SIMD3<Double>) {
    let d = T - S
    let L = min(length(d), (a + b) * 0.999)
    let u = nrm(d)
    let x = (a * a - b * b + L * L) / (2 * L)
    let hgt = max(a * a - x * x, 0).squareRoot()
    var p = nrm(perp(pole - S, u))
    if length(p) < 1e-6 { p = nrm(perp(SIMD3(1, 0, 0), u)) }
    return (S + u * x + p * hgt, S + u * L)
}
