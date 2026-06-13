//
//  MorphingEngine.swift
//  SewingCAD
//
//  Phase 3 強化版: MeasurementProfile の全34項目を体型変形に反映
//
//  fieldID マッピング（MeasurementDetailView.allMeasurementFields と一致）:
//   0=ハイバスト     1=バスト          2=アンダーバスト  3=ウエスト
//   4=ミドルヒップ   5=ヒップ          6=腕つけ根回り    7=上腕回り
//   8=肘回り         9=手首回り        10=手のひら回り   11=頭回り
//   12=首つけ根回り  13=大腿回り       14=下腿回り
//   15=背肩幅        16=背幅           17=胸幅           18=バストポイント間隔
//   19=身長          20=総丈           21=背丈            22=後ろ丈
//   23=乳下り        24=前丈           25=袖丈            26=ウエスト高
//   27=ヒップ高      28=腰丈           29=股上丈          30=股下丈
//   31=膝丈          32=股上前後長     33=体重
//

import Foundation
import simd
import CoreData

// MARK: - モーフィングエンジン

class MorphingEngine: ObservableObject {

    @Published var appliedName: String = "標準体型"

    // MARK: メイン変形メソッド

    func morph(base: BodyMesh, measurement: MeasurementProfile) -> BodyMesh {
        let std    = StandardMeasurement()
        let result = base.copy()

        func v(_ id: Int) -> Float {
            let raw = Float(measurement.value(for: id))
            return raw > 0 ? raw : defaultValue(id, std: std)
        }

        let height      = v(19)
        let bust        = v(1)
        let highBust    = v(0)
        let underBust   = v(2)
        let waist       = v(3)
        let midHip      = v(4)
        let hip         = v(5)
        let upperArm    = v(7)
        let wristCirc   = v(9)
        let neckCirc    = v(12)
        let thigh       = v(13)
        let calf        = v(14)
        let shoulderW   = v(15)
        let backLength  = v(21)
        let sleeveLen   = v(25)
        let waistHeight = v(26)
        let inseam      = v(30)

        applyMorph(
            to: result, std: std,
            height: height, bust: bust, highBust: highBust,
            underBust: underBust, waist: waist, midHip: midHip,
            hip: hip, upperArm: upperArm, wristCirc: wristCirc,
            neckCirc: neckCirc, thigh: thigh, calf: calf,
            shoulderW: shoulderW, backLength: backLength,
            sleeveLen: sleeveLen, waistHeight: waistHeight, inseam: inseam
        )

        recalculateNormals(mesh: result)
        appliedName = measurement.name ?? "不明"
        return result
    }

    /// StandardMeasurementを直接受け取るスレッドセーフ版
    func morph(base: BodyMesh, stdM: StandardMeasurement) -> BodyMesh {
        let std    = StandardMeasurement()
        let result = base.copy()

        func use(_ val: Float, _ def: Float) -> Float { val > 0 ? val : def }

        applyMorph(
            to: result, std: std,
            height:      use(stdM.height,      std.height),
            bust:        use(stdM.bust,        std.bust),
            highBust:    use(stdM.bust * 0.90, std.bust * 0.90),
            underBust:   use(stdM.underBust,   std.underBust),
            waist:       use(stdM.waist,       std.waist),
            midHip:      use(stdM.hip * 0.88,  std.hip * 0.88),
            hip:         use(stdM.hip,         std.hip),
            upperArm:    use(stdM.upperArm,    std.upperArm),
            wristCirc:   use(stdM.wrist,       std.wrist),
            neckCirc:    use(stdM.neck,        std.neck),
            thigh:       use(stdM.thigh,       std.thigh),
            calf:        use(stdM.calf,        std.calf),
            shoulderW:   use(stdM.shoulder,    std.shoulder),
            backLength:  use(stdM.backLength,  std.backLength),
            sleeveLen:   use(stdM.sleeveLen,   std.sleeveLen),
            waistHeight: use(stdM.waistHeight, std.waistHeight),
            inseam:      use(stdM.inseam,      std.inseam)
        )

        recalculateNormals(mesh: result)
        appliedName = "カスタム"
        return result
    }

    /// 共通変形ロジック（CoreData非依存）
    private func applyMorph(
        to result: BodyMesh,
        std: StandardMeasurement,
        height: Float, bust: Float, highBust: Float,
        underBust: Float, waist: Float, midHip: Float,
        hip: Float, upperArm: Float, wristCirc: Float,
        neckCirc: Float, thigh: Float, calf: Float,
        shoulderW: Float, backLength: Float,
        sleeveLen: Float, waistHeight: Float, inseam: Float
    ) {
        // ── 比率・差分 ────────────────────────────────────
        let heightRatio    = clamp(height      / std.height,      0.5, 1.8)
        let bustDiff       = bust        - std.bust
        let underBustDiff  = underBust   - std.underBust
        let waistDiff      = waist       - std.waist
        let midHipDiff     = midHip      - (std.hip * 0.88)
        let hipDiff        = hip         - std.hip
        let neckDiff       = neckCirc    - std.neck
        let shoulderRatio  = clamp(shoulderW   / std.shoulder,    0.6, 1.5)
        let upperArmDiff   = upperArm    - std.upperArm
        let wristDiff      = wristCirc   - std.wrist
        let thighDiff      = thigh       - std.thigh
        let calfDiff       = calf        - std.calf
        // Y方向はすべて heightRatio で統一（wDeltaは使わない）
        let backLenRatio   = clamp(backLength  / std.backLength,  0.5, 1.8)
        let sleeveLenRatio = clamp(sleeveLen   / std.sleeveLen,   0.5, 1.8)
        let inseamRatio    = clamp(inseam      / std.inseam,      0.5, 1.8)

        // 半径差分（周長差 → 半径差: cm → m）
        func rdiff(_ diff: Float) -> Float { diff / (2 * Float.pi) / 100.0 }

        // 肩付け根のY境界
        let shoulderTopY: Float = (141.0 - 111.0) / 100.0  // 0.30m

        for i in result.vertices.indices {
            var vtx = result.vertices[i]
            let w  = vtx.influenceWeight
            let yM = vtx.position.y

            switch vtx.region {

            case .neck:
                // XZ：首周りスケール
                vtx.position.x += rdiff(neckDiff) * w * 0.5
                vtx.position.z += rdiff(neckDiff) * w * 0.4
                // Y：背丈比率
                vtx.position.y = yM * backLenRatio

            case .shoulder:
                // Z：バスト差分で微調整
                vtx.position.z += rdiff(bustDiff) * w * 0.3

                if yM >= shoulderTopY * 0.5 {
                    // ── 胴体肩エリア：肩幅比率でXをスケール ──
                    vtx.position.x *= shoulderRatio
                    vtx.position.y = yM * backLenRatio
                } else {
                    // ── 腕エリア：肩幅シフト＋腕太さ変化を分離 ──
                    // 標準の肩幅端X
                    let stdShoulderX = std.shoulder / 2.0 / 100.0
                    // 新しい肩幅端X
                    let newShoulderX = shoulderW / 2.0 / 100.0
                    // 腕中心軸からのオフセット（腕の太さ分）
                    let armOffset = vtx.position.x - (sign(vtx.position.x) * stdShoulderX)
                    // 新しいX = 新しい肩幅端 + 腕太さ変化
                    let armThicknessChange = rdiff(upperArmDiff) * w * 0.5
                    vtx.position.x = sign(vtx.position.x) * newShoulderX + armOffset + armThicknessChange * sign(vtx.position.x)
                    vtx.position.z += rdiff(upperArmDiff) * w * 0.4
                    // Y：袖丈比率
                    let relY = yM - shoulderTopY
                    vtx.position.y = shoulderTopY * backLenRatio + relY * sleeveLenRatio
                    // 手首
                    let wristBlend = max(0, 1.0 - w * 2.5)
                    vtx.position.x += rdiff(wristDiff) * wristBlend * sign(vtx.position.x)
                }

            case .bust:
                vtx.position.x += rdiff(bustDiff) * w * sign(vtx.position.x)
                vtx.position.z += rdiff(bustDiff) * w * 0.7
                vtx.position.y = yM * backLenRatio

            case .underBust:
                vtx.position.x += rdiff(underBustDiff) * w * sign(vtx.position.x)
                vtx.position.z += rdiff(underBustDiff) * w * 0.6
                vtx.position.y = yM * backLenRatio

            case .waist:
                vtx.position.x += rdiff(waistDiff) * w * sign(vtx.position.x)
                vtx.position.z += rdiff(waistDiff) * w * 0.7
                // ウエストはbackLenRatioとinseamRatioの中間
                let t = clamp(-yM / 0.15, 0, 1)  // ウエスト付近で滑らかにブレンド
                vtx.position.y = yM * (backLenRatio * (1-t) + inseamRatio * t)

            case .abdomen:
                vtx.position.x += rdiff(midHipDiff) * w * 0.6 * sign(vtx.position.x)
                vtx.position.z += rdiff(midHipDiff) * w * 0.7
                vtx.position.y = yM * inseamRatio

            case .hip:
                vtx.position.x += rdiff(hipDiff) * w * sign(vtx.position.x)
                vtx.position.z += rdiff(hipDiff) * w * 0.75
                vtx.position.y = yM * inseamRatio

            case .leg:
                if yM > -0.15 {
                    // 大腿
                    vtx.position.x += rdiff(thighDiff) * w * 0.7 * sign(vtx.position.x)
                    vtx.position.z += rdiff(thighDiff) * w * 0.5
                } else {
                    // 下腿〜足首
                    vtx.position.x += rdiff(calfDiff) * w * 0.6 * sign(vtx.position.x)
                    vtx.position.z += rdiff(calfDiff) * w * 0.4
                }
                vtx.position.y = yM * inseamRatio

            case .neutral:
                vtx.position.y = yM * heightRatio
            }

            result.vertices[i] = vtx
        }
    }

    func morphToStandard(base: BodyMesh) -> BodyMesh {
        appliedName = "標準体型"
        return base.copy()
    }

    // MARK: ノーマル再計算

    private func recalculateNormals(mesh: BodyMesh) {
        var normals = [SIMD3<Float>](repeating: .zero, count: mesh.vertices.count)
        for poly in mesh.polygons {
            let v0 = mesh.vertices[poly.v0].position
            let v1 = mesh.vertices[poly.v1].position
            let v2 = mesh.vertices[poly.v2].position
            let fn = cross(v1 - v0, v2 - v0)
            normals[poly.v0] += fn
            normals[poly.v1] += fn
            normals[poly.v2] += fn
        }
        for i in mesh.vertices.indices {
            let len = simd.length(normals[i])
            if len > 0 { mesh.vertices[i].normal = normals[i] / len }
        }
    }

    // MARK: デフォルト値（標準体型）

    private func defaultValue(_ id: Int, std: StandardMeasurement) -> Float {
        switch id {
        case  0: return std.bust * 0.90
        case  1: return std.bust
        case  2: return std.underBust
        case  3: return std.waist
        case  4: return std.hip * 0.88
        case  5: return std.hip
        case  6: return std.bust * 0.48
        case  7: return std.upperArm
        case  8: return std.upperArm * 0.82
        case  9: return std.wrist
        case 10: return std.wrist * 1.20
        case 11: return 55.0
        case 12: return std.neck
        case 13: return std.thigh
        case 14: return std.calf
        case 15: return std.shoulder
        case 16: return std.shoulder * 0.86
        case 17: return std.shoulder * 0.80
        case 18: return 18.0
        case 19: return std.height
        case 20: return std.height - 8.0
        case 21: return std.backLength
        case 22: return std.backLength + 1.5
        case 23: return std.backLength * 0.62
        case 24: return std.backLength + 2.5
        case 25: return std.sleeveLen
        case 26: return std.waistHeight
        case 27: return std.hipHeight
        case 28: return std.waistHeight - std.hipHeight
        case 29: return std.waistHeight - std.inseam
        case 30: return std.inseam
        case 31: return std.waistHeight - std.height * 0.27
        case 32: return 62.0
        case 33: return 52.0
        default: return 0
        }
    }

    // MARK: ユーティリティ

    private func sign(_ v: Float) -> Float { v >= 0 ? 1 : -1 }
    private func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        Swift.max(lo, Swift.min(hi, v))
    }
}

// MARK: - パターン位置合わせ

struct PatternPlacement: Identifiable {
    let id = UUID()
    var patternID: UUID
    var bodyFace: BodyFace
    var anchorPoint: SIMD3<Float>
    var isSymmetric: Bool
    var scale: Float = 1.0
}

class PatternPlacementEngine: ObservableObject {
    @Published var placements: [PatternPlacement] = []

    func updatePlacements(morphedMesh: BodyMesh, original: BodyMesh) {
        guard morphedMesh.vertices.count == original.vertices.count else { return }
        let bustScale = safeScale(morphed: morphedMesh, original: original, region: .bust)
        let hipScale  = safeScale(morphed: morphedMesh, original: original, region: .hip)
        placements = placements.map { p in
            var up = p
            switch p.bodyFace {
            case .front, .back, .sleeve: up.scale = bustScale
            case .skirt:                 up.scale = hipScale
            }
            return up
        }
    }

    func autoPlace(patternID: UUID, face: BodyFace, isSymmetric: Bool = false) {
        let anchor: SIMD3<Float>
        switch face {
        case .front:  anchor = SIMD3( 0,     0.26,  0.13)
        case .back:   anchor = SIMD3( 0,     0.26, -0.13)
        case .sleeve: anchor = SIMD3( 0.19,  0.40,  0)
        case .skirt:  anchor = SIMD3( 0,    -0.04,  0)
        }
        placements.append(PatternPlacement(
            patternID: patternID, bodyFace: face,
            anchorPoint: anchor, isSymmetric: isSymmetric
        ))
    }

    private func safeScale(morphed: BodyMesh, original: BodyMesh, region: BodyRegion) -> Float {
        let orig = averageRadius(mesh: original, region: region)
        let morp = averageRadius(mesh: morphed,  region: region)
        return orig > 0 ? morp / orig : 1.0
    }

    private func averageRadius(mesh: BodyMesh, region: BodyRegion) -> Float {
        let verts = mesh.vertices.filter { $0.region == region }
        guard !verts.isEmpty else { return 0 }
        return verts.reduce(Float(0)) {
            $0 + sqrt($1.position.x * $1.position.x + $1.position.z * $1.position.z)
        } / Float(verts.count)
    }
}
