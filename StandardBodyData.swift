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

    // スムーズ法線再計算（全ポリゴンの面法線を頂点に加算平均）
    private static func recalculateNormals(mesh: BodyMesh) {
        var normals = [SIMD3<Float>](repeating: .zero, count: mesh.vertices.count)
        for poly in mesh.polygons {
            let v0 = mesh.vertices[poly.v0].position
            let v1 = mesh.vertices[poly.v1].position
            let v2 = mesh.vertices[poly.v2].position
            let fn = simd_cross(v1 - v0, v2 - v0)
            normals[poly.v0] += fn
            normals[poly.v1] += fn
            normals[poly.v2] += fn
        }
        for i in 0..<mesh.vertices.count {
            let len = simd_length(normals[i])
            if len > 0 { mesh.vertices[i].normal = normals[i] / len }
        }
    }

    // ── 胴体（元の26断面をそのまま維持）─────────────────────
    private static func buildTorso(
        m: StandardMeasurement,
        vertices: inout [BodyVertex],
        polygons:  inout [BodyPolygon],
        zones:     inout [DeformationZone]
    ) {
        // 全体1cm刻みスライス定義（rz/rx=0.82で統一してトルソーらしい断面に）
        let slices: [(y: Float, rx: Float, rz: Float, region: BodyRegion, w: Float)] = [
            (157,  9.5,  9.5,  .neutral,   0.05),
            (156,  9.3,  9.3,  .neutral,   0.05),
            (155,  9.0,  9.0,  .neutral,   0.05),
            (154,  8.0,  8.0,  .neck,      0.40),
            (153,  7.2,  7.2,  .neck,      0.50),
            (152,  6.8,  6.8,  .neck,      0.55),
            (151,  6.5,  6.5,  .neck,      0.60),
            (150,  6.3,  6.3,  .neck,      0.65),
            (149,  6.1,  6.1,  .neck,      0.70),
            (148,  5.9,  5.9,  .neck,      0.75),
            (147,  5.7,  5.7,  .neck,      0.80),
            (146,  5.6,  5.6,  .neck,      0.85),
            (145,  5.5,  5.5,  .neck,      0.90),
            (144,  5.5,  5.5,  .neck,      0.90),
            (143,  6.5,  4.5,  .shoulder,  0.60),
            (142,  8.5,  5.9,  .shoulder,  0.65),
            (141, 11.0,  7.7,  .shoulder,  0.70),
            (140, 13.5,  9.4,  .shoulder,  0.75),
            (139, 16.0, 11.2,  .shoulder,  0.80),
            (138, 18.0, 12.6,  .shoulder,  0.85),
            (137, 19.0, 13.3,  .shoulder,  0.90),
            (136, 19.3, 15.8,  .bust,      0.65),
            (135, 19.6, 16.1,  .bust,      0.70),
            (134, 19.9, 16.3,  .bust,      0.75),
            (133, 20.2, 16.6,  .bust,      0.80),
            (132, 20.4, 16.7,  .bust,      0.85),
            (131, 20.6, 16.9,  .bust,      0.90),
            (130, 20.7, 17.0,  .bust,      0.93),
            (129, 20.8, 17.1,  .bust,      0.95),
            (128, 20.7, 17.0,  .bust,      0.97),
            (127, 20.6, 16.9,  .bust,      0.98),
            (126, 20.5, 16.8,  .bust,      1.00),  // バスト最大
            (125, 20.3, 16.6,  .bust,      0.97),
            (124, 20.0, 16.4,  .bust,      0.95),
            (123, 19.5, 16.0,  .bust,      0.90),
            (122, 19.2, 15.7,  .underBust, 0.88),
            (121, 18.8, 15.4,  .underBust, 0.85),
            (120, 18.4, 15.1,  .underBust, 0.83),
            (119, 18.0, 14.8,  .underBust, 0.80),
            (118, 17.6, 14.4,  .underBust, 0.77),
            (117, 17.2, 14.1,  .underBust, 0.74),
            (116, 16.8, 13.8,  .underBust, 0.71),
            (115, 16.5, 13.5,  .underBust, 0.68),
            (114, 16.2, 13.3,  .waist,     0.85),
            (113, 16.0, 13.1,  .waist,     0.90),
            (112, 15.7, 12.9,  .waist,     0.95),
            (111, 15.5, 12.7,  .waist,     1.00),  // ウエスト最細
            (110, 15.5, 12.7,  .waist,     1.00),
            (109, 15.5, 12.7,  .waist,     1.00),
            (108, 15.6, 12.8,  .abdomen,   0.78),
            (107, 15.8, 13.0,  .abdomen,   0.76),
            (106, 16.0, 13.1,  .abdomen,   0.74),
            (105, 16.2, 13.3,  .abdomen,   0.75),
            (104, 16.6, 13.6,  .abdomen,   0.76),
            (103, 17.0, 13.9,  .abdomen,   0.78),
            (102, 17.5, 14.3,  .abdomen,   0.79),
            (101, 18.0, 14.8,  .abdomen,   0.80),
            (100, 18.6, 15.3,  .hip,       0.82),
            ( 99, 19.2, 15.7,  .hip,       0.85),
            ( 98, 19.7, 16.2,  .hip,       0.88),
            ( 97, 20.2, 16.6,  .hip,       0.92),
            ( 96, 20.6, 16.9,  .hip,       0.96),
            ( 95, 21.0, 17.2,  .hip,       1.00),  // ヒップ最大
            ( 94, 20.9, 17.1,  .hip,       0.98),
            ( 93, 20.8, 17.1,  .hip,       0.97),
            ( 92, 20.5, 16.8,  .hip,       0.95),
            ( 91, 20.0, 16.4,  .hip,       0.92),
            ( 90, 19.5, 16.0,  .hip,       0.88),
            ( 89, 19.0, 15.6,  .leg,       0.70),
            ( 88, 18.5, 15.2,  .leg,       0.65),
            ( 87, 18.0, 14.8,  .leg,       0.60),
            ( 86, 17.5, 14.3,  .leg,       0.55),
            ( 85, 17.0, 13.9,  .leg,       0.50),
            ( 84, 16.5, 13.5,  .leg,       0.48),
            ( 83, 16.0, 13.1,  .leg,       0.45),
            ( 82, 15.5, 12.7,  .leg,       0.42),
            ( 81, 15.1, 12.4,  .leg,       0.40),
            ( 80, 14.8, 12.1,  .leg,       0.38),
            ( 79, 14.5, 11.9,  .leg,       0.36),
            ( 78, 14.3, 11.7,  .leg,       0.34),
            ( 77, 14.1, 11.6,  .leg,       0.32),
            ( 76, 14.0, 11.5,  .leg,       0.30),
        ]

        let ringSegments = 48
        let totalRings   = slices.count
        let baseIndex    = 0

        // 楕円の等弧長サンプリング用テーブルを生成
        // rx,rz の楕円を n 分割する角度配列を返す
        func ellipseArcAngles(rx: Float, rz: Float, n: Int) -> [Float] {
            let steps = n * 20  // 細かく積分
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

        for (si, slice) in slices.enumerated() {
            let yM   = (slice.y - 111.0) / 100.0
            let rxM  = slice.rx / 100.0
            let rzM  = slice.rz / 100.0
            let uRow = Float(si) / Float(totalRings - 1)

            // 乳房の形状パラメータ（スライスのrz値で断面形状を制御するため個別膨らみ処理は無効）
            let isBustSlice = false  // 個別の乳房膨らみ処理を無効化（線が入るため）
            let breastBulge: Float = 0
            let bustCenterX: Float = rxM * 0.20

            let arcAngles = ellipseArcAngles(rx: rxM, rz: rzM, n: ringSegments)
            for vi in 0..<ringSegments {
                let angle = arcAngles[vi]
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
        // 腕の外側半分のみ接続（X+側=右腕外側、X-側=左腕外側）
        //
        // 胴体リングの頂点X座標（vi=0がX+端=+19cm）:
        //   右外側(X+): vi=0〜6, vi=19〜23  → X > 0
        //   左外側(X-): vi=7〜17            → X < 0
        //
        // 右腕(side>0): vi=0〜6 と vi=19〜23 を接続
        // 左腕(side<0): vi=7〜17 を接続

        // bridgeIndices: seg数に対応して動的に計算
        // vi=0がX+端（cos(0)=1）、外側半分(side側)を接続
        // 右腕(side>0): X>0側 = vi=0..seg/4 と vi=3*seg/4..seg-1
        // 左腕(side<0): X<0側 = vi=seg/4..3*seg/4
        let quarterSeg = seg / 4
        let bridgeIndices: [Int]
        if side > 0 {
            bridgeIndices = Array((3 * quarterSeg)..<seg) + Array(0..<(quarterSeg + 1))
        } else {
            bridgeIndices = Array(quarterSeg..<(3 * quarterSeg + 1))
        }

        for i in 0..<(bridgeIndices.count - 1) {
            let vi   = bridgeIndices[i]
            let next = bridgeIndices[i + 1]
            let t0 = shoulderRingBase + vi
            let t1 = shoulderRingBase + next
            let a0 = base + vi
            let a1 = base + next
            polygons.append(BodyPolygon(v0: t0, v1: a0, v2: a1))
            polygons.append(BodyPolygon(v0: t0, v1: a1, v2: t1))
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
        legRingBase: Int,
        ringSegments: Int,
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

        let seg  = ringSegments  // 胴体と同じセグメント数で統一
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

        // ── 胴体底面(y=76) → 脚付け根のブリッジ接続 ──────────
        // 胴体底面リング(ringSegments=24, 中心X=0, rx=14cm)の
        // 外側半分(side側)を脚付け根リングにつなぐ
        //
        // bridgeIndices: ringSegments数に対応して動的に計算
        // 右脚(side>0): X>0側 = vi=0..seg/4 と vi=3*seg/4..seg-1
        // 左脚(side<0): X<0側 = vi=seg/4..3*seg/4
        let legQuarter = ringSegments / 4
        let legBridgeIndices: [Int]
        if side > 0 {
            legBridgeIndices = Array((3 * legQuarter)..<ringSegments) + Array(0..<(legQuarter + 1))
        } else {
            legBridgeIndices = Array(legQuarter..<(3 * legQuarter + 1))
        }
        for i in 0..<(legBridgeIndices.count - 1) {
            let vi   = legBridgeIndices[i]
            let next = legBridgeIndices[i + 1]
            let t0 = legRingBase + vi
            let t1 = legRingBase + next
            let a0 = base + vi
            let a1 = base + next
            polygons.append(BodyPolygon(v0: t0, v1: a0, v2: a1))
            polygons.append(BodyPolygon(v0: t0, v1: a1, v2: t1))
        }
    }
}
