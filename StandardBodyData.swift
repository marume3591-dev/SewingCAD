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
    static func generate(m: StandardMeasurement = StandardMeasurement()) -> BodyMesh {
        var vertices: [BodyVertex]  = []
        var polygons:  [BodyPolygon] = []
        var zones:     [DeformationZone] = []

        buildTorso(m: m, vertices: &vertices, polygons: &polygons, zones: &zones)

        // 胴体y=138cm断面（slices index=6）の頂点開始インデックスを計算
        // slice 0〜5 × 24頂点 = 144頂点目から
        let ringSegments = 24
        let shoulderSliceIndex = 6  // y=138cmはslices配列の7番目(index=6)
        let shoulderRingBase = shoulderSliceIndex * ringSegments

        for side: Float in [-1, 1] {
            buildArm(m: m, side: side,
                     shoulderRingBase: shoulderRingBase,
                     ringSegments: ringSegments,
                     vertices: &vertices, polygons: &polygons)
        }
        for side: Float in [-1, 1] {
            buildLeg(m: m, side: side, vertices: &vertices, polygons: &polygons)
        }

        return BodyMesh(vertices: vertices, polygons: polygons, deformationZones: zones)
    }

    // 引数なし版（既存コードとの互換）
    static func generate() -> BodyMesh {
        generate(m: StandardMeasurement())
    }

    // ── 胴体（元の26断面をそのまま維持）─────────────────────
    private static func buildTorso(
        m: StandardMeasurement,
        vertices: inout [BodyVertex],
        polygons:  inout [BodyPolygon],
        zones:     inout [DeformationZone]
    ) {
        // 元の26断面スライス定義（既存コードと同一）
        let slices: [(y: Float, rx: Float, rz: Float, region: BodyRegion, w: Float)] = [
            (157, 9.5,  9.5,  .neutral,   0.05),
            (154, 9.0,  9.0,  .neutral,   0.05),
            (150, 6.5,  6.0,  .neck,      0.6),
            (147, 5.8,  5.5,  .neck,      0.8),
            (144, 5.5,  5.2,  .neck,      0.9),
            (141, 14.0, 7.5,  .shoulder,  0.8),
            (138, 19.0, 8.5,  .shoulder,  0.9),
            (135, 20.0, 10.0, .bust,      0.7),
            (132, 20.5, 11.5, .bust,      0.8),
            (129, 20.8, 13.0, .bust,      0.95),
            (126, 20.5, 13.5, .bust,      1.0),
            (123, 19.5, 12.5, .bust,      0.9),
            (120, 18.0, 11.0, .underBust, 0.85),
            (117, 16.8, 10.5, .underBust, 0.7),
            (114, 15.8, 10.2, .waist,     0.9),
            (111, 15.5, 10.0, .waist,     1.0),
            (108, 15.5, 10.0, .waist,     1.0),
            (105, 16.5, 11.0, .abdomen,   0.75),
            (102, 17.5, 11.8, .abdomen,   0.7),
            ( 99, 20.0, 12.5, .hip,       0.85),
            ( 96, 22.5, 13.2, .hip,       1.0),
            ( 93, 22.0, 12.8, .hip,       0.95),
            ( 90, 21.0, 12.2, .hip,       0.85),
            ( 86, 17.5, 10.5, .leg,       0.5),
            ( 82, 15.5,  9.5, .leg,       0.4),
            ( 76, 14.0,  8.5, .leg,       0.3),
        ]

        let ringSegments = 24
        let totalRings   = slices.count
        let baseIndex    = 0

        for (si, slice) in slices.enumerated() {
            let yM   = (slice.y - 111.0) / 100.0
            let rxM  = slice.rx / 100.0
            let rzM  = slice.rz / 100.0
            let uRow = Float(si) / Float(totalRings - 1)
            for vi in 0..<ringSegments {
                let angle = 2 * Float.pi * Float(vi) / Float(ringSegments)
                vertices.append(BodyVertex(
                    position: SIMD3(cos(angle) * rxM, yM, sin(angle) * rzM),
                    normal:   SIMD3(cos(angle), 0, sin(angle)),
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

    // ── 腕（片側9断面）+ 胴体肩リングとのブリッジ接続 ────────
    private static func buildArm(
        m: StandardMeasurement,
        side: Float,
        shoulderRingBase: Int,  // 胴体y=138cm断面の頂点開始インデックス
        ringSegments: Int,      // 胴体リングの頂点数(24)
        vertices: inout [BodyVertex],
        polygons:  inout [BodyPolygon]
    ) {
        let shoulderTopY: Float = (138.0 - 111.0) / 100.0
        let shoulderX:    Float = side * m.shoulder / 2.0 / 100.0

        let armLen:   Float = m.sleeveLen / 100.0
        let uArmR:    Float = m.upperArm  / (2 * Float.pi) / 100.0
        let elbowR:   Float = uArmR * 0.78
        let wristR:   Float = m.wrist / (2 * Float.pi) / 100.0
        let shoulderJointR: Float = uArmR * 1.3

        typealias Sl = (t: Float, rx: Float, rz: Float, w: Float)
        let slices: [Sl] = [
            (0.00, shoulderJointR,    shoulderJointR * 0.9,  0.4),
            (0.06, uArmR * 1.08,      uArmR * 1.00,          0.7),
            (0.18, uArmR,             uArmR * 0.95,          0.6),
            (0.33, uArmR * 0.94,      uArmR * 0.90,          0.5),
            (0.50, elbowR * 1.10,     elbowR * 0.95,         0.4),
            (0.63, elbowR,            elbowR * 0.88,         0.4),
            (0.76, wristR * 1.28,     wristR * 1.15,         0.35),
            (0.90, wristR * 1.08,     wristR * 1.02,         0.3),
            (1.00, wristR,            wristR * 0.88,         0.25),
        ]

        // 腕の頂点数は胴体リングと同じ24に統一（ブリッジしやすくする）
        let seg  = ringSegments  // 24
        let base = vertices.count

        for (i, sl) in slices.enumerated() {
            let t       = sl.t
            let slopeX: Float = side * t * (m.shoulder / 100.0) * 0.05
            let xPos    = shoulderX + slopeX
            let yPos    = shoulderTopY - t * armLen
            let zPos: Float = 0.012 * (1 - t)

            let uRow = Float(i) / Float(slices.count - 1)
            for vi in 0..<seg {
                let angle = 2 * Float.pi * Float(vi) / Float(seg)
                vertices.append(BodyVertex(
                    position: SIMD3(xPos + cos(angle) * sl.rx,
                                    yPos,
                                    zPos + sin(angle) * sl.rz),
                    normal:   SIMD3(cos(angle), 0, sin(angle)),
                    region:   .shoulder,
                    influenceWeight: sl.w,
                    uv: SIMD2(Float(vi) / Float(seg), uRow)
                ))
            }
        }

        // 腕スライス間のポリゴン
        for si in 0..<(slices.count - 1) {
            for vi in 0..<seg {
                let next = (vi + 1) % seg
                let b0 = base + si * seg
                let b1 = base + (si + 1) * seg
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+vi,   v2: b1+next))
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+next, v2: b0+next))
            }
        }

        // ── 胴体肩リング → 腕付け根リングのブリッジ接続 ──────
        // 胴体y=138cm断面(24頂点, 中心X=0, rx=19cm)の外側半分を
        // 腕付け根(24頂点, 中心X=±19cm, r=5.6cm)につなぐ
        //
        // 胴体リングの頂点: angle = 2π*vi/24
        //   vi=0  → X=+19cm (右端), Z=0
        //   vi=6  → X=0, Z=+8.5cm (前)
        //   vi=12 → X=-19cm (左端), Z=0
        //   vi=18 → X=0, Z=-8.5cm (後)
        //
        // 右腕(side=+1): 胴体右半分 vi=18〜6 (X+側) を腕につなぐ
        // 左腕(side=-1): 胴体左半分 vi=6〜18 (X-側) を腕につなぐ

        let armRing0 = base  // 腕付け根リング開始

        // 胴体外側半分(13頂点)と腕付け根(24頂点)を最近傍でつなぐ
        // 胴体: vi=0(X+端)を中心にsideに応じて前後12頂点
        // 腕:   vi=0(X+方向)を中心に前後12頂点

        // 胴体リングで腕側（外側）に対応する頂点範囲
        // right arm: torso vi=18..24,0..6 (X+側の外半分)
        // left arm:  torso vi=6..18 (X-側の外半分)
        let halfSeg = seg / 2  // 12

        for vi in 0...halfSeg {
            // 胴体リングの外側頂点インデックス
            let tvi: Int
            if side > 0 {
                // 右腕: vi=0が右端(X+), 前後に6頂点ずつ
                tvi = ((seg - halfSeg/2 + vi) % seg)
            } else {
                // 左腕: vi=12が左端(X-), 前後に6頂点ずつ
                tvi = ((halfSeg/2 + vi) % seg)
            }
            let tnext_vi = vi < halfSeg ? vi + 1 : vi

            let tvi_next: Int
            if side > 0 {
                tvi_next = ((seg - halfSeg/2 + tnext_vi) % seg)
            } else {
                tvi_next = ((halfSeg/2 + tnext_vi) % seg)
            }

            // 腕リングの対応頂点（0が外端、前後に広がる）
            let avi      = (vi * seg / (halfSeg + 1)) % seg
            let avi_next = (tnext_vi * seg / (halfSeg + 1)) % seg

            let t0 = shoulderRingBase + tvi
            let t1 = shoulderRingBase + tvi_next
            let a0 = armRing0 + avi
            let a1 = armRing0 + avi_next

            if vi < halfSeg && a0 != a1 {
                polygons.append(BodyPolygon(v0: t0, v1: a0, v2: a1))
                polygons.append(BodyPolygon(v0: t0, v1: a1, v2: t1))
            } else if vi < halfSeg {
                polygons.append(BodyPolygon(v0: t0, v1: a0, v2: t1))
            }
        }

        // 手首キャップ
        let capIdx   = vertices.count
        let lastBase = base + (slices.count - 1) * seg
        let wristSlopeX: Float = side * (m.shoulder / 100.0) * 0.05
        vertices.append(BodyVertex(
            position: SIMD3(shoulderX + wristSlopeX, shoulderTopY - armLen, 0.0),
            normal: SIMD3(0, -1, 0), region: .shoulder, influenceWeight: 0.2,
            uv: SIMD2(0.5, 1.0)
        ))
        for vi in 0..<seg {
            polygons.append(BodyPolygon(v0: capIdx, v1: lastBase + vi, v2: lastBase + (vi+1) % seg))
        }
    }

    // ── 脚（片側10断面）────────────────────────────────────
    private static func buildLeg(
        m: StandardMeasurement,
        side: Float,
        vertices: inout [BodyVertex],
        polygons:  inout [BodyPolygon]
    ) {
        let thighR  = m.thigh / (2 * Float.pi) / 100.0
        let calfR   = m.calf  / (2 * Float.pi) / 100.0
        let ankleR  = calfR * 0.60
        let hipR    = m.hip   / (2 * Float.pi) / 100.0

        // 胴体の股断面（y=76cm）からスタート
        let crotchY: Float = (76.0  - 111.0) / 100.0  // ≈ -0.35m
        let ankleY:  Float = (3.0   - 111.0) / 100.0  // 床面3cm上 ≈ -1.08m
        let legLen  = crotchY - ankleY

        // 股付根のX位置：胴体底断面rx=14cmの中間点に配置
        // 脚2本が左右に分かれるので中心から7cm = rx/2
        let hipRatio: Float = m.hip / 91.0
        // 胴体底断面のモーフ後rx ≈ 14cm × hipRatio × 0.5
        let hipX: Float = side * 14.0 / 2.0 / 100.0 * hipRatio
        // 脚付け根半径：胴体底断面rx/2に合わせる（隙間なく収まるサイズ）
        let crotchJointR: Float = 14.0 / 2.0 / 100.0 * hipRatio

        typealias Sl = (t: Float, rx: Float, rz: Float, w: Float)
        let slices: [Sl] = [
            (0.00, crotchJointR,       crotchJointR * 0.9, 0.45), // 胴体底面にフィット
            (0.08, thighR * 1.10,      thighR * 1.00,      0.65),
            (0.20, thighR,             thighR * 0.95,      0.60),
            (0.32, thighR * 0.88,      thighR * 0.85,      0.52),
            (0.44, thighR * 0.76,      thighR * 0.72,      0.42),  // 膝上
            (0.52, thighR * 0.72,      thighR * 0.67,      0.38),  // 膝
            (0.62, calfR  * 1.08,      calfR  * 1.00,      0.42),
            (0.74, calfR,              calfR  * 0.92,      0.38),
            (0.88, ankleR * 1.15,      ankleR * 1.05,      0.28),  // くるぶし上
            (1.00, ankleR,             ankleR * 0.88,      0.18),
        ]

        let seg  = 16
        let base = vertices.count

        for (i, sl) in slices.enumerated() {
            let t    = sl.t
            let xPos = hipX + side * t * 0.004  // わずかに外開き
            let yPos = crotchY - t * legLen
            let zPos: Float = t * 0.018          // 少し前傾

            let uRow = Float(i) / Float(slices.count - 1)
            for vi in 0..<seg {
                let angle = 2 * Float.pi * Float(vi) / Float(seg)
                vertices.append(BodyVertex(
                    position: SIMD3(xPos + cos(angle) * sl.rx,
                                    yPos,
                                    zPos + sin(angle) * sl.rz),
                    normal:   SIMD3(cos(angle), 0, sin(angle)),
                    region:   .leg,
                    influenceWeight: sl.w,
                    uv: SIMD2(Float(vi) / Float(seg), uRow)
                ))
            }
        }

        for si in 0..<(slices.count - 1) {
            for vi in 0..<seg {
                let next = (vi + 1) % seg
                let b0 = base + si * seg
                let b1 = base + (si + 1) * seg
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+vi,   v2: b1+next))
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+next, v2: b0+next))
            }
        }

        // 足首キャップ
        let capIdx   = vertices.count
        let lastBase = base + (slices.count - 1) * seg
        vertices.append(BodyVertex(
            position: SIMD3(hipX + side * 0.004, ankleY, 0.018),
            normal: SIMD3(0, -1, 0), region: .leg, influenceWeight: 0.1,
            uv: SIMD2(0.5, 1.0)
        ))
        for vi in 0..<seg {
            polygons.append(BodyPolygon(v0: capIdx, v1: lastBase + vi, v2: lastBase + (vi+1) % seg))
        }
    }
}
