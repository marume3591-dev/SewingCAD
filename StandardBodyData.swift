//
//  StandardBodyData.swift
//  SewingCAD
//
//  既存の26断面胴体に加え、腕（左右各9断面）・脚（左右各10断面）を追加。
//  座標系: ウエスト(111cm地点)をY=0原点、メートル単位（1.0=100cm）
//

import Foundation
import simd

// MARK: - 標準計測値

struct StandardMeasurement {
    var height:      Float = 158.0
    var bust:        Float =  83.0
    var waist:       Float =  64.0
    var hip:         Float =  91.0
    var shoulder:    Float =  38.0
    var neck:        Float =  35.0
    var underBust:   Float =  72.0
    // 追加寸法（腕・脚・縦寸法）
    var backLength:  Float =  38.8
    var sleeveLen:   Float =  54.0
    var upperArm:    Float =  27.0
    var wrist:       Float =  15.5
    var thigh:       Float =  52.0
    var calf:        Float =  34.0
    var inseam:      Float =  74.0
    var waistHeight: Float =  98.0
    var hipHeight:   Float =  85.0
}

// MARK: - 標準ボディ生成

enum StandardBodyGenerator {

    static let standard = StandardMeasurement()

    // ── メインエントリ ──────────────────────────────────────
    // 楕円の等弧長サンプリング（全メソッドから共有）
    static func ellipseArcAngles(rx: Float, rz: Float, n: Int) -> [Float] {
        let steps = n * 20
        var arcLen: [Float] = [0]
        var prevX = rx, prevZ: Float = 0
        for i in 1...steps {
            let a = 2 * Float.pi * Float(i) / Float(steps)
            let x = cos(a) * rx, z = sin(a) * rz
            let d = sqrt((x-prevX)*(x-prevX) + (z-prevZ)*(z-prevZ))
            arcLen.append(arcLen.last! + d)
            prevX = x; prevZ = z
        }
        let total = arcLen.last!
        var angles: [Float] = []
        var j = 0
        for k in 0..<n {
            let target = total * Float(k) / Float(n)
            while j < steps - 1 && arcLen[j+1] < target { j += 1 }
            let t = arcLen[j+1] > arcLen[j]
                ? (target - arcLen[j]) / (arcLen[j+1] - arcLen[j]) : 0
            let a = 2 * Float.pi * (Float(j) + t) / Float(steps)
            angles.append(a)
        }
        return angles
    }

    static func generate(m: StandardMeasurement = StandardMeasurement()) -> BodyMesh {
        var vertices: [BodyVertex]  = []
        var polygons:  [BodyPolygon] = []
        var zones:     [DeformationZone] = []

        buildTorso(m: m, vertices: &vertices, polygons: &polygons, zones: &zones)

        // 胴体・腕・脚すべて48セグメントに統一
        let ringSegments = 48
        let shoulderSliceIndex = 19 // y=138cm: index=19
        let shoulderRingBase = shoulderSliceIndex * ringSegments

        for side: Float in [-1, 1] {
            buildArm(m: m, side: side,
                     shoulderRingBase: shoulderRingBase,
                     ringSegments: ringSegments,
                     vertices: &vertices, polygons: &polygons)
        }
        let legRingSegments = 48
        let legSliceIndex   = 81  // y=76cm: index=81
        let legRingBase     = legSliceIndex * legRingSegments

        for side: Float in [-1, 1] {
            buildLeg(m: m, side: side,
                     legRingBase: legRingBase,
                     ringSegments: legRingSegments,
                     vertices: &vertices, polygons: &polygons)
        }

        // 生成直後にスムーズ法線を再計算（シェーディングの角張りを防ぐ）
        let mesh = BodyMesh(vertices: vertices, polygons: polygons, deformationZones: zones)
        recalculateNormals(mesh: mesh)
        return mesh
    }

    // 引数なし版（既存コードとの互換）
    static func generate() -> BodyMesh {
        generate(m: StandardMeasurement())
    }

    // スムーズ法線再計算（位置が近い頂点の法線をマージして接続部を滑らかに）
    private static func recalculateNormals(mesh: BodyMesh) {
        let count = mesh.vertices.count
        var normals = [SIMD3<Float>](repeating: .zero, count: count)

        // 各ポリゴンの面法線を頂点に加算
        for poly in mesh.polygons {
            let v0 = mesh.vertices[poly.v0].position
            let v1 = mesh.vertices[poly.v1].position
            let v2 = mesh.vertices[poly.v2].position
            let fn = simd_cross(v1 - v0, v2 - v0)
            normals[poly.v0] += fn
            normals[poly.v1] += fn
            normals[poly.v2] += fn
        }

        // グリッドベースで近接頂点の法線をマージ（O(n)近似）
        let threshold: Float = 0.003
        let gridSize: Float = threshold
        var grid: [SIMD3<Int32>: [Int]] = [:]
        for i in 0..<count {
            let p = mesh.vertices[i].position
            let key = SIMD3<Int32>(Int32(floor(p.x/gridSize)), Int32(floor(p.y/gridSize)), Int32(floor(p.z/gridSize)))
            grid[key, default: []].append(i)
        }

        var merged = normals
        for (key, indices) in grid {
            // 隣接セルも含めてマージ
            var group: [Int] = indices
            for dx: Int32 in -1...1 {
                for dy: Int32 in -1...1 {
                    for dz: Int32 in -1...1 {
                        if dx == 0 && dy == 0 && dz == 0 { continue }
                        let nk = SIMD3<Int32>(key.x+dx, key.y+dy, key.z+dz)
                        if let neighbors = grid[nk] {
                            let pi = mesh.vertices[indices[0]].position
                            for j in neighbors {
                                let pj = mesh.vertices[j].position
                                if simd_length(pi - pj) < threshold {
                                    group.append(j)
                                }
                            }
                        }
                    }
                }
            }
            if group.count > 1 {
                let combined = group.reduce(SIMD3<Float>.zero) { $0 + normals[$1] }
                for i in group { merged[i] = combined }
            }
        }

        for i in 0..<count {
            let len = simd_length(merged[i])
            if len > 0 { mesh.vertices[i].normal = merged[i] / len }
        }
    }

    // ── 胴体（元の26断面をそのまま維持）─────────────────────
    private static func buildTorso(
        m: StandardMeasurement,
        vertices: inout [BodyVertex],
        polygons:  inout [BodyPolygon],
        zones:     inout [DeformationZone]
    ) {
        // 全体1cm刻みスライス定義（標準9号実寸ベース, rz/rx=0.82）
        let slices: [(y: Float, rx: Float, rz: Float, region: BodyRegion, w: Float)] = [
            (157,  6.5,  6.5,  .neutral,   0.05),
            (156,  6.3,  6.3,  .neutral,   0.05),
            (155,  6.0,  6.0,  .neutral,   0.05),
            (154,  5.2,  5.2,  .neck,      0.40),
            (153,  4.8,  4.8,  .neck,      0.50),
            (152,  4.5,  4.5,  .neck,      0.60),
            (151,  4.3,  4.3,  .neck,      0.70),
            (150,  4.1,  4.1,  .neck,      0.75),
            (149,  4.0,  4.0,  .neck,      0.80),
            (148,  3.9,  3.9,  .neck,      0.85),
            (147,  3.8,  3.8,  .neck,      0.90),
            (146,  3.8,  3.8,  .neck,      0.90),
            (145,  3.8,  3.8,  .neck,      0.90),
            (144,  3.8,  3.8,  .neck,      0.90),
            (143,  5.0,  4.3,  .shoulder,  0.60),
            (142,  7.0,  6.0,  .shoulder,  0.65),
            (141,  9.5,  8.1,  .shoulder,  0.70),
            (140, 11.5,  9.8,  .shoulder,  0.75),
            (139, 13.0, 11.1,  .shoulder,  0.80),
            (138, 13.8, 11.7,  .shoulder,  0.85),
            (137, 13.8, 11.7,  .shoulder,  0.90),
            (136, 13.5, 11.1,  .bust,      0.65),
            (135, 13.5, 11.1,  .bust,      0.70),
            (134, 13.4, 11.0,  .bust,      0.75),
            (133, 13.4, 11.0,  .bust,      0.80),
            (132, 13.3, 10.9,  .bust,      0.85),
            (131, 13.3, 10.9,  .bust,      0.90),
            (130, 13.3, 10.9,  .bust,      0.93),
            (129, 13.2, 10.8,  .bust,      0.95),
            (128, 13.2, 10.8,  .bust,      0.97),
            (127, 13.2, 10.8,  .bust,      0.98),
            (126, 13.2, 10.8,  .bust,      1.00),  // バスト最大
            (125, 13.1, 10.7,  .bust,      0.97),
            (124, 12.9, 10.6,  .bust,      0.95),
            (123, 12.6, 10.3,  .bust,      0.90),
            (122, 12.3, 10.1,  .underBust, 0.88),
            (121, 12.0,  9.8,  .underBust, 0.85),
            (120, 11.7,  9.6,  .underBust, 0.83),
            (119, 11.4,  9.3,  .underBust, 0.80),
            (118, 11.1,  9.1,  .underBust, 0.77),
            (117, 10.8,  8.9,  .underBust, 0.74),
            (116, 10.5,  8.6,  .underBust, 0.71),
            (115, 10.4,  8.5,  .underBust, 0.68),
            (114, 10.3,  8.4,  .waist,     0.85),
            (113, 10.2,  8.4,  .waist,     0.90),
            (112, 10.2,  8.4,  .waist,     0.95),
            (111, 10.2,  8.4,  .waist,     1.00),  // ウエスト最細
            (110, 10.2,  8.4,  .waist,     1.00),
            (109, 10.2,  8.4,  .waist,     1.00),
            (108, 10.3,  8.4,  .abdomen,   0.78),
            (107, 10.5,  8.6,  .abdomen,   0.76),
            (106, 10.8,  8.9,  .abdomen,   0.74),
            (105, 11.2,  9.2,  .abdomen,   0.75),
            (104, 11.6,  9.5,  .abdomen,   0.76),
            (103, 12.2, 10.0,  .abdomen,   0.78),
            (102, 12.7, 10.4,  .abdomen,   0.79),
            (101, 13.2, 10.8,  .abdomen,   0.80),
            (100, 13.7, 11.2,  .hip,       0.82),
            ( 99, 14.0, 11.5,  .hip,       0.85),
            ( 98, 14.2, 11.6,  .hip,       0.88),
            ( 97, 14.4, 11.8,  .hip,       0.92),
            ( 96, 14.5, 11.9,  .hip,       0.96),
            ( 95, 14.5, 11.9,  .hip,       1.00),  // ヒップ最大
            ( 94, 14.4, 11.8,  .hip,       0.98),
            ( 93, 14.3, 11.7,  .hip,       0.97),
            ( 92, 14.0, 11.5,  .hip,       0.95),
            ( 91, 13.7, 11.2,  .hip,       0.92),
            ( 90, 13.3, 10.9,  .hip,       0.88),
            ( 89, 12.8, 10.5,  .leg,       0.70),
            ( 88, 12.3, 10.1,  .leg,       0.65),
            ( 87, 11.8,  9.7,  .leg,       0.60),
            ( 86, 11.3,  9.3,  .leg,       0.55),
            ( 85, 10.8,  8.9,  .leg,       0.50),
            ( 84, 10.4,  8.5,  .leg,       0.48),
            ( 83, 10.0,  8.2,  .leg,       0.45),
            ( 82,  9.7,  8.0,  .leg,       0.42),
            ( 81,  9.4,  7.7,  .leg,       0.40),
            ( 80,  9.2,  7.5,  .leg,       0.38),
            ( 79,  9.0,  7.4,  .leg,       0.36),
            ( 78,  8.8,  7.2,  .leg,       0.34),
            ( 77,  8.7,  7.1,  .leg,       0.32),
            ( 76,  8.6,  7.1,  .leg,       0.30),
        ]

        let ringSegments = 48
        let totalRings   = slices.count
        let baseIndex    = 0

        // ellipseArcAnglesはstaticメソッドとして外部定義

        for (si, slice) in slices.enumerated() {
            let yM   = (slice.y - 111.0) / 100.0
            let rxM  = slice.rx / 100.0
            let rzM  = slice.rz / 100.0
            let uRow = Float(si) / Float(totalRings - 1)

            let arcAngles = StandardBodyGenerator.ellipseArcAngles(rx: rxM, rz: rzM, n: ringSegments)
            for vi in 0..<ringSegments {
                let angle = arcAngles[vi]
                let cosA  = cos(angle)
                let sinA  = sin(angle)
                let px    = cosA * rxM
                let pz    = sinA * rzM

                vertices.append(BodyVertex(
                    position: SIMD3(px, yM, pz),
                    normal:   SIMD3(cosA, 0, sinA),
                    region:   slice.region,
                    influenceWeight: slice.w,
                    uv: SIMD2(Float(vi) / Float(ringSegments), uRow)
                ))
            }
        }

        for si in 0..<(totalRings - 1) {
            for vi in 0..<ringSegments {
                let next  = (vi + 1) % ringSegments
                let b0 = baseIndex + si * ringSegments
                let b1 = baseIndex + (si + 1) * ringSegments
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+vi,   v2: b1+next))
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+next, v2: b0+next))
            }
        }

        // 上キャップ（頭頂）
        let topIdx = vertices.count
        vertices.append(BodyVertex(
            position: SIMD3(0, (slices.first!.y - 111.0) / 100.0, 0),
            normal: SIMD3(0, 1, 0), region: .neutral, influenceWeight: 0.05, uv: SIMD2(0.5, 0)
        ))
        for vi in 0..<ringSegments {
            let next = (vi + 1) % ringSegments
            polygons.append(BodyPolygon(v0: topIdx, v1: baseIndex + next, v2: baseIndex + vi))
        }

        // 下キャップ（股）
        let botIdx  = vertices.count
        let botBase = baseIndex + (totalRings - 1) * ringSegments
        vertices.append(BodyVertex(
            position: SIMD3(0, (slices.last!.y - 111.0) / 100.0, 0),
            normal: SIMD3(0, -1, 0), region: .leg, influenceWeight: 0.2, uv: SIMD2(0.5, 1)
        ))
        for vi in 0..<ringSegments {
            let next = (vi + 1) % ringSegments
            polygons.append(BodyPolygon(v0: botIdx, v1: botBase+vi, v2: botBase+next))
        }

        // 変形ゾーン
        for (si, slice) in slices.enumerated() {
            let idxs = Array((baseIndex + si * ringSegments) ..< (baseIndex + si * ringSegments + ringSegments))
            switch slice.region {
            case .bust:
                zones.append(DeformationZone(region: .bust,     vertexIndices: idxs, standardValue: m.bust))
            case .waist:
                zones.append(DeformationZone(region: .waist,    vertexIndices: idxs, standardValue: m.waist))
            case .hip:
                zones.append(DeformationZone(region: .hip,      vertexIndices: idxs, standardValue: m.hip))
            case .shoulder:
                zones.append(DeformationZone(region: .shoulder, vertexIndices: idxs, standardValue: m.shoulder * 2))
            default: break
            }
        }
    }

    // ── 腕（片側）────────────────────────────────────────
    // 胴体y=138断面（ringSegments=24）の外側半分（12頂点）を
    // 腕の付け根として直接使い、そこから腕を生やす
    private static func buildArm(
        m: StandardMeasurement,
        side: Float,
        shoulderRingBase: Int,  // 胴体y=138断面の頂点開始インデックス
        ringSegments: Int,
        vertices: inout [BodyVertex],
        polygons:  inout [BodyPolygon]
    ) {
        let uArmR:  Float = m.upperArm / (2 * Float.pi) / 100.0
        let elbowR: Float = uArmR * 0.78
        let wristR: Float = m.wrist / (2 * Float.pi) / 100.0
        let armLen: Float = m.sleeveLen / 100.0

        let armDirX: Float = side * 0.22
        let armDirY: Float = -1.0
        let armLen3D = sqrt(armDirX * armDirX + armDirY * armDirY)
        let armDX = armDirX / armLen3D * armLen
        let armDY = armDirY / armLen3D * armLen

        // 腕の付け根：胴体y=138断面の外側端
        let startY: Float = (138.0 - 111.0) / 100.0
        let startX: Float = side * 13.8 / 100.0

        let seg = ringSegments

        // 腕スライス（t=0は胴体頂点を流用するので省略）
        typealias Sl = (t: Float, rx: Float, rz: Float, w: Float)
        let slices: [Sl] = [
            (0.10, uArmR * 1.15, uArmR * 1.05, 0.8),
            (0.22, uArmR * 1.05, uArmR * 0.95, 0.65),
            (0.35, uArmR,        uArmR * 0.90,  0.55),
            (0.48, elbowR * 1.12,elbowR * 0.95, 0.42),
            (0.60, elbowR,       elbowR * 0.88, 0.40),
            (0.72, wristR * 1.30,wristR * 1.15, 0.35),
            (0.85, wristR * 1.10,wristR * 1.02, 0.28),
            (1.00, wristR,       wristR * 0.88, 0.22),
        ]

        // 腕スライス頂点生成（t>0のみ）
        let armBase = vertices.count
        for sl in slices {
            let cx = startX + armDX * sl.t
            let cy = startY + armDY * sl.t
            let cz: Float = 0.008 * (1 - sl.t)
            let angles = StandardBodyGenerator.ellipseArcAngles(rx: sl.rx, rz: sl.rz, n: seg)
            for vi in 0..<seg {
                let a = angles[vi]
                vertices.append(BodyVertex(
                    position: SIMD3(cx + cos(a)*sl.rx, cy, cz + sin(a)*sl.rz),
                    normal:   SIMD3(cos(a), 0, sin(a)),
                    region: .shoulder, influenceWeight: sl.w,
                    uv: SIMD2(Float(vi)/Float(seg), sl.t)
                ))
            }
        }

        // 胴体y=138リング(shoulderRingBase) → 腕最初スライス(armBase)
        // 胴体リングと腕リングを全周でつなぐ（等弧長で頂点順序が一致）
        // ただし腕のrxは胴体rxより小さいので、対応するvi番号でX座標が異なる
        // → 外側のvi番号帯（side側）だけをつなぐ
        let q = seg / 4
        // 右腕: vi=3q〜seg-1 + 0〜q, 左腕: vi=q〜3q
        let bridgeRange: [Int] = side > 0
            ? (Array((3*q)..<seg) + Array(0...q))
            : Array(q...(3*q))

        for i in 0..<(bridgeRange.count - 1) {
            let vi = bridgeRange[i]; let vn = bridgeRange[i+1]
            let t0 = shoulderRingBase + vi; let t1 = shoulderRingBase + vn
            let a0 = armBase + vi;          let a1 = armBase + vn
            polygons.append(BodyPolygon(v0: t0, v1: a0, v2: a1))
            polygons.append(BodyPolygon(v0: t0, v1: a1, v2: t1))
        }

        // 腕スライス間ポリゴン
        for si in 0..<(slices.count - 1) {
            for vi in 0..<seg {
                let next = (vi+1) % seg
                let b0 = armBase + si*seg; let b1 = armBase + (si+1)*seg
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+vi,   v2: b1+next))
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+next, v2: b0+next))
            }
        }

        // 手首キャップ
        let wristCap = vertices.count
        let lastBase = armBase + (slices.count-1)*seg
        vertices.append(BodyVertex(
            position: SIMD3(startX+armDX, startY+armDY, 0),
            normal: simd_normalize(SIMD3<Float>(armDX, armDY, 0)),
            region: .shoulder, influenceWeight: 0.2,
            uv: SIMD2(0.5, 1.0)
        ))
        for vi in 0..<seg {
            polygons.append(BodyPolygon(v0: wristCap, v1: lastBase+vi, v2: lastBase+(vi+1)%seg))
        }

        // 肩キャップ（内側の穴を閉じる）
        let shoulderCap = vertices.count
        vertices.append(BodyVertex(
            position: SIMD3(startX, startY, 0.008),
            normal: simd_normalize(SIMD3<Float>(-armDX, -armDY, 0)),
            region: .shoulder, influenceWeight: 0.85,
            uv: SIMD2(0.5, 0.0)
        ))
        let innerRange: [Int] = side > 0
            ? Array((q+1)..<(3*q))
            : (Array((3*q+1)..<seg) + Array(0..<q))
        for i in 0..<(innerRange.count - 1) {
            let vi = innerRange[i]; let vn = innerRange[i+1]
            let a0 = armBase + vi; let a1 = armBase + vn
            polygons.append(BodyPolygon(v0: shoulderCap, v1: a0, v2: a1))
        }
    }

    private static func buildLeg(
        m: StandardMeasurement,
        side: Float,
        legRingBase: Int,       // 胴体y=76断面の頂点開始インデックス
        ringSegments: Int,
        vertices: inout [BodyVertex],
        polygons:  inout [BodyPolygon]
    ) {
        let hipRatio: Float = m.hip / 91.0
        // y=76のrx=8.6cm、脚は左右に分かれるのでhipX=±rx/2
        let legRx: Float  = 8.6 / 100.0 * hipRatio
        let hipX: Float   = side * legRx * 0.50
        let crotchY: Float = (76.0 - 111.0) / 100.0
        let ankleY: Float  = crotchY - m.inseam / 100.0

        let thighR: Float = m.thigh / (2 * Float.pi) / 100.0 * hipRatio
        let calfR:  Float = m.calf  / (2 * Float.pi) / 100.0
        let ankleR: Float = calfR * 0.72
        let legR0:  Float = legRx * 0.50  // 付け根半径

        let seg = ringSegments

        // 脚スライス（t=0は胴体y=76頂点を流用）
        typealias Sl = (t: Float, rx: Float, rz: Float, w: Float)
        let legLen = abs(ankleY - crotchY)
        let slices: [Sl] = [
            (0.00, legR0,          legR0,          0.45),  // 付け根（胴体と接続）
            (0.10, thighR * 1.05,  thighR * 0.98,  0.60),
            (0.22, thighR,         thighR * 0.95,   0.58),
            (0.35, thighR * 0.92,  thighR * 0.88,   0.52),
            (0.48, calfR  * 1.10,  calfR  * 0.95,   0.42),
            (0.60, calfR,          calfR  * 0.90,   0.38),
            (0.75, calfR  * 0.88,  calfR  * 0.85,   0.30),
            (0.88, ankleR * 1.08,  ankleR * 0.95,   0.22),
            (1.00, ankleR,         ankleR * 0.88,   0.18),
        ]

        let legBase = vertices.count

        // 脚スライス頂点生成
        for sl in slices {
            let xPos = hipX + side * sl.t * 0.003
            let yPos = crotchY - sl.t * legLen
            let zPos: Float = -0.004 + sl.t * 0.015
            let angles = StandardBodyGenerator.ellipseArcAngles(rx: sl.rx, rz: sl.rz, n: seg)
            for vi in 0..<seg {
                let a = angles[vi]
                vertices.append(BodyVertex(
                    position: SIMD3(xPos + cos(a)*sl.rx, yPos, zPos + sin(a)*sl.rz),
                    normal:   SIMD3(cos(a), 0, sin(a)),
                    region: .leg, influenceWeight: sl.w,
                    uv: SIMD2(Float(vi)/Float(seg), sl.t)
                ))
            }
        }

        // 胴体y=76リング(legRingBase) → 脚t=0スライス(legBase): 外側半分をbridge
        let q = seg / 4
        let bridgeRange: [Int] = side > 0
            ? (Array((3*q)..<seg) + Array(0...q))
            : Array(q...(3*q))

        for i in 0..<(bridgeRange.count - 1) {
            let vi = bridgeRange[i]; let vn = bridgeRange[i+1]
            let t0 = legRingBase + vi; let t1 = legRingBase + vn
            let a0 = legBase + vi;     let a1 = legBase + vn
            polygons.append(BodyPolygon(v0: t0, v1: a0, v2: a1))
            polygons.append(BodyPolygon(v0: t0, v1: a1, v2: t1))
        }

        // 脚スライス間ポリゴン
        for si in 0..<(slices.count - 1) {
            for vi in 0..<seg {
                let next = (vi+1) % seg
                let b0 = legBase + si*seg; let b1 = legBase + (si+1)*seg
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+vi,   v2: b1+next))
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+next, v2: b0+next))
            }
        }

        // 足首キャップ
        let ankleCap = vertices.count
        let lastBase = legBase + (slices.count-1)*seg
        vertices.append(BodyVertex(
            position: SIMD3(hipX + side*0.003, ankleY, 0.011),
            normal: SIMD3(0, -1, 0), region: .leg, influenceWeight: 0.1,
            uv: SIMD2(0.5, 1.0)
        ))
        for vi in 0..<seg {
            polygons.append(BodyPolygon(v0: ankleCap, v1: lastBase+vi, v2: lastBase+(vi+1)%seg))
        }

        // 股部分キャップ（内側の穴を閉じる）
        let groinCap = vertices.count
        vertices.append(BodyVertex(
            position: SIMD3(hipX, crotchY, -0.004),
            normal: SIMD3(0, 1, 0), region: .leg, influenceWeight: 0.45,
            uv: SIMD2(0.5, 0.0)
        ))
        let innerRange: [Int] = side > 0
            ? Array((q+1)..<(3*q))
            : (Array((3*q+1)..<seg) + Array(0..<q))
        for i in 0..<(innerRange.count - 1) {
            let vi = innerRange[i]; let vn = innerRange[i+1]
            polygons.append(BodyPolygon(v0: groinCap, v1: legBase+vi, v2: legBase+vn))
        }
    }
}
