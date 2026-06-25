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

            // 前後非対称：前面(sinA>0)と後面(sinA<0)でrzを変える
            // 人体は胸が前に出て背中はフラット、ヒップは後方に張り出す
            // yMはウエスト=0、バスト≈+0.15、ヒップ≈-0.16
            let tBody = max(-1.0, min(1.0, yM / 0.16))  // -1(ヒップ)〜+1(バスト)
            // 前面のrz倍率：バストで1.25倍、ウエストで1.0倍、ヒップで0.95倍
            let rzFrontMult: Float = tBody > 0
                ? 1.0 + tBody * 0.45   // バスト方向：前に膨らむ
                : 1.0 + tBody * 0.05   // ヒップ方向：前はほぼ変わらず
            // 後面のrz倍率：バストで0.80倍（背中フラット）、ヒップで1.10倍（お尻）
            let rzBackMult: Float = tBody > 0
                ? 1.0 - tBody * 0.28   // バスト方向：背中は引っ込む
                : 1.0 - tBody * 0.10   // ヒップ方向：後ろに張り出す

            let arcAngles = ellipseArcAngles(rx: rxM, rz: rzM, n: ringSegments)
            for vi in 0..<ringSegments {
                let angle = arcAngles[vi]
                let cosA  = cos(angle)
                let sinA  = sin(angle)   // Z方向（正=前面）

                var px = cosA * rxM
                // 基本の楕円 + 断面全体の前後シフト + 前面のみの追加膨らみ
                // 前面(sinA>0)と後面(sinA<0)で異なるrzを使用
                let rzEff = sinA > 0 ? rzM * rzFrontMult : rzM * rzBackMult
                var pz = sinA * rzEff

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
        let armDirX: Float = side * 0.22  // より下向きに
        let armDirY: Float = -1.0
        let armLen3D = sqrt(armDirX * armDirX + armDirY * armDirY)
        let armDX = armDirX / armLen3D * armLen
        let armDY = armDirY / armLen3D * armLen

        let startY: Float = (138.0 - 111.0) / 100.0
        let startX: Float = side * 13.8 / 100.0  // y=138のrxに合わせる

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
        let hipX: Float = side * 8.6 / 2.0 / 100.0 * hipRatio  // y=76のrx/2
        // 脚付け根半径：胴体底断面rx/2に合わせる
        let crotchJointR: Float = 8.6 / 2.0 / 100.0 * hipRatio

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
