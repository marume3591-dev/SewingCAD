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
        // 元の26断面スライス定義（肩スライスは固定値に戻す）
        let slices: [(y: Float, rx: Float, rz: Float, region: BodyRegion, w: Float)] = [
            (157,  9.5,  9.5,  .neutral,   0.05),
            (154,  9.0,  9.0,  .neutral,   0.05),
            (150,  6.5,  6.0,  .neck,      0.6),
            (147,  5.8,  5.5,  .neck,      0.8),
            (144,  5.5,  5.2,  .neck,      0.9),
            (141, 14.0,  7.5,  .shoulder,  0.8),   // 腕の付け根高さ
            (138, 19.0,  8.5,  .shoulder,  0.9),   // 腕の開始高さ（rx=19cm）
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

            // 乳房の形状パラメータ
            // バスト断面（y=135〜123cm）の前面（Z+）に膨らみを追加
            let isBustSlice = slice.region == .bust
            // 乳房の中心は左右に分かれる（X=±バスト幅の30%）
            let bustCenterX: Float = rxM * 0.30
            // 膨らみ量：バスト半径の20%程度
            let breastBulge: Float = isBustSlice ? rzM * 0.25 * slice.w : 0

            for vi in 0..<ringSegments {
                let angle = 2 * Float.pi * Float(vi) / Float(ringSegments)
                let cosA  = cos(angle)
                let sinA  = sin(angle)   // Z方向（正=前面）

                var px = cosA * rxM
                var pz = sinA * rzM

                // 前面（sinA > 0）の胸部スライスに乳房の膨らみを追加
                if isBustSlice && sinA > 0 {
                    // 左右の乳房中心からの距離に基づいてガウス型の膨らみ
                    let frontFactor = sinA  // 前面ほど強く（0〜1）
                    // 左乳房（X < 0）と右乳房（X > 0）
                    let distFromLeftCenter  = px + bustCenterX
                    let distFromRightCenter = px - bustCenterX
                    let sigma: Float = rxM * 0.40  // 乳房の広がり
                    let leftGauss  = exp(-(distFromLeftCenter  * distFromLeftCenter)  / (2 * sigma * sigma))
                    let rightGauss = exp(-(distFromRightCenter * distFromRightCenter) / (2 * sigma * sigma))
                    let breastFactor = max(leftGauss, rightGauss)
                    pz += breastBulge * frontFactor * breastFactor
                }

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
        shoulderRingBase: Int,
        ringSegments: Int,
        vertices: inout [BodyVertex],
        polygons:  inout [BodyPolygon]
    ) {
        let uArmR:  Float = m.upperArm / (2 * Float.pi) / 100.0
        let elbowR: Float = uArmR * 0.78
        let wristR: Float = m.wrist / (2 * Float.pi) / 100.0
        let armLen: Float = m.sleeveLen / 100.0

        // 腕の方向：斜め外下
        let armDirX: Float = side * 0.35
        let armDirY: Float = -1.0
        let armLen3D = sqrt(armDirX * armDirX + armDirY * armDirY)
        let armDX = armDirX / armLen3D * armLen
        let armDY = armDirY / armLen3D * armLen

        let startY: Float = (138.0 - 111.0) / 100.0
        let startX: Float = side * 19.0 / 100.0

        // 腕スライス（t=0.0を除く：付け根は胴体頂点を流用）
        typealias Sl = (t: Float, rx: Float, rz: Float, w: Float)
        let slices: [Sl] = [
            (0.12, uArmR * 1.08, uArmR * 1.00, 0.7),
            (0.25, uArmR,        uArmR * 0.95,  0.6),
            (0.38, uArmR * 0.94, uArmR * 0.90,  0.5),
            (0.50, elbowR * 1.10,elbowR * 0.95, 0.4),
            (0.63, elbowR,       elbowR * 0.88, 0.4),
            (0.76, wristR * 1.28,wristR * 1.15, 0.35),
            (0.88, wristR * 1.08,wristR * 1.02, 0.3),
            (1.00, wristR,       wristR * 0.88, 0.25),
        ]

        // 腕リングは胴体と同じ24頂点を使う
        let seg  = ringSegments  // 24
        let base = vertices.count

        // 腕スライス頂点を生成（付け根はなし、t=0.12から）
        for (_, sl) in slices.enumerated() {
            let t  = sl.t
            let cx = startX + armDX * t
            let cy = startY + armDY * t
            let cz: Float = 0.010 * (1 - t)

            for vi in 0..<seg {
                let angle = 2 * Float.pi * Float(vi) / Float(seg)
                vertices.append(BodyVertex(
                    position: SIMD3(cx + cos(angle) * sl.rx, cy, cz + sin(angle) * sl.rz),
                    normal:   SIMD3(cos(angle), 0, sin(angle)),
                    region:   .shoulder, influenceWeight: sl.w,
                    uv: SIMD2(Float(vi) / Float(seg), sl.t)
                ))
            }
        }

        // 胴体y=138断面（shoulderRingBase）→ 腕最初のスライス（base）
        // 胴体24頂点と腕24頂点を1対1でつなぐ
        for vi in 0..<seg {
            let next = (vi + 1) % seg
            let t0 = shoulderRingBase + vi
            let t1 = shoulderRingBase + next
            let a0 = base + vi
            let a1 = base + next
            // 右腕(side>0): 反時計回り, 左腕(side<0): 時計回り
            if side > 0 {
                polygons.append(BodyPolygon(v0: t0, v1: a0, v2: a1))
                polygons.append(BodyPolygon(v0: t0, v1: a1, v2: t1))
            } else {
                polygons.append(BodyPolygon(v0: t0, v1: a1, v2: a0))
                polygons.append(BodyPolygon(v0: t0, v1: t1, v2: a1))
            }
        }

        // 腕スライス間ポリゴン
        for si in 0..<(slices.count - 1) {
            for vi in 0..<seg {
                let next = (vi + 1) % seg
                let b0 = base + si * seg
                let b1 = base + (si + 1) * seg
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+vi,   v2: b1+next))
                polygons.append(BodyPolygon(v0: b0+vi,   v1: b1+next, v2: b0+next))
            }
        }

        // 手首キャップ
        let capIdx   = vertices.count
        let lastBase = base + (slices.count - 1) * seg
        vertices.append(BodyVertex(
            position: SIMD3(startX + armDX, startY + armDY, 0),
            normal: simd_normalize(SIMD3<Float>(armDX, armDY, 0)),
            region: .shoulder, influenceWeight: 0.2,
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
