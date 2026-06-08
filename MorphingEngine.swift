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

        // 計測値ヘルパー（0の場合は標準値）
        func v(_ id: Int) -> Float {
            let raw = Float(measurement.value(for: id))
            return raw > 0 ? raw : defaultValue(id, std: std)
        }

        // ── 寸法取得 ──────────────────────────────────────
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

        // ── 標準値との差分・比率 ───────────────────────────
        let heightRatio   = height      / std.height
        let bustDiff      = bust        - std.bust
        let waistDiff     = waist       - std.waist
        let hipDiff       = hip         - std.hip
        let midHipDiff    = midHip      - (std.hip * 0.88)
        let highBustDiff  = highBust    - (std.bust * 0.90)
        let underBustDiff = underBust   - std.underBust
        let neckDiff      = neckCirc    - std.neck
        let shoulderRatio = shoulderW   / std.shoulder
        let upperArmDiff  = upperArm    - std.upperArm
        let wristDiff     = wristCirc   - std.wrist
        let thighDiff     = thigh       - std.thigh
        let calfDiff      = calf        - std.calf
        let backLenRatio  = backLength  / std.backLength
        let sleeveLenRatio = sleeveLen  / std.sleeveLen
        let waistHRatio   = waistHeight / std.waistHeight
        let inseamRatio   = inseam      / std.inseam

        // 半径差分（cm → m）
        func rdiff(_ diff: Float) -> Float { diff / (2 * Float.pi) / 100.0 }

        // ── ウエストY原点基準の各ライン高さ（メートル）─────
        let stdWY  = std.waistHeight / 100.0    // 標準ウエスト高 m
        let newWY  = waistHeight     / 100.0
        let wDelta = newWY - stdWY

        for i in result.vertices.indices {
            var vtx = result.vertices[i]
            let w   = vtx.influenceWeight
            // 現在のY（ウエスト=0原点）
            let yM  = vtx.position.y

            switch vtx.region {

            // ── 首 ──────────────────────────────────
            case .neck:
                vtx.position.x += rdiff(neckDiff) * w
                vtx.position.z += rdiff(neckDiff) * w * 0.8
                // ウエスト上方のY：背丈比率でスケール
                if yM > 0 {
                    vtx.position.y = yM * backLenRatio + wDelta * 0.5 * w
                }

            // ── 肩 ──────────────────────────────────
            case .shoulder:
                // X方向：肩幅比率
                vtx.position.x *= shoulderRatio
                // Z方向：バスト差分で微調整
                vtx.position.z += rdiff(bustDiff) * w * 0.5
                // 腕部分の肩（Y < 0 は腕メッシュ）：袖丈比率
                if yM < 0 {
                    // 腕: Y を sleeveLenRatio でスケール + 上腕太さ
                    vtx.position.y *= sleeveLenRatio
                    vtx.position.x += rdiff(upperArmDiff) * w * abs(vtx.position.x) * 0.3
                    vtx.position.z += rdiff(upperArmDiff) * w * 0.4
                    // 手首部分（wに依存）
                    let wristBlend = max(0, 1.0 - w * 2.5)  // w が小さいほど手首寄り
                    vtx.position.x += rdiff(wristDiff) * wristBlend
                    vtx.position.z += rdiff(wristDiff) * wristBlend * 0.8
                } else if yM > 0 {
                    vtx.position.y = yM * backLenRatio + wDelta * 0.5 * w
                }

            // ── バスト ───────────────────────────────
            case .bust:
                let disp = rdiff(bustDiff) * w
                vtx.position.x += disp * sign(vtx.position.x)
                vtx.position.z += rdiff(bustDiff) * w * 0.85
                // ハイバスト補正（上部断面）
                let hbDisp = rdiff(highBustDiff) * w * 0.3
                vtx.position.x += hbDisp * sign(vtx.position.x)
                if yM > 0 {
                    vtx.position.y = yM * backLenRatio + wDelta * 0.5 * w
                }

            // ── アンダーバスト ────────────────────────
            case .underBust:
                let disp = rdiff(underBustDiff) * w
                vtx.position.x += disp * sign(vtx.position.x)
                vtx.position.z += rdiff(underBustDiff) * w * 0.7
                if yM > 0 {
                    vtx.position.y = yM * backLenRatio + wDelta * 0.5 * w
                }

            // ── ウエスト ─────────────────────────────
            case .waist:
                let disp = rdiff(waistDiff) * w
                vtx.position.x += disp * sign(vtx.position.x)
                vtx.position.z += rdiff(waistDiff) * w * 0.78
                // ウエスト高による縦方向微調整
                vtx.position.y += wDelta * 0.08 * w

            // ── 腹部 ─────────────────────────────────
            case .abdomen:
                let disp = rdiff(midHipDiff) * w * 0.75
                vtx.position.x += disp * sign(vtx.position.x)
                vtx.position.z += rdiff(midHipDiff) * w * 0.85
                // ウエスト高〜ヒップ高の間でY調整
                let localT = clamp((-yM) / stdWY, 0, 1)
                vtx.position.y += wDelta * localT * 0.4 * w

            // ── ヒップ ───────────────────────────────
            case .hip:
                let disp = rdiff(hipDiff) * w
                vtx.position.x += disp * sign(vtx.position.x)
                vtx.position.z += rdiff(hipDiff) * w * 0.82
                // 股下丈・ウエスト高でヒップのY位置調整
                let hipStdY = -(stdWY - std.hipHeight / 100.0)
                let hipNewY = -(newWY - Float(measurement.value(for: 27) > 0 ? Float(measurement.value(for: 27)) : std.hipHeight) / 100.0)
                if abs(hipStdY) > 0 && abs(yM - hipStdY) < 0.12 {
                    vtx.position.y = yM * (hipNewY / hipStdY) * w + yM * (1.0 - w)
                }

            // ── 脚 ──────────────────────────────────
            case .leg:
                // 地面からの絶対高さ（stdWY 基準で変換）
                let absY = yM + stdWY
                if absY / stdWY > 0.45 {
                    // 大腿域: 太もも差分
                    let disp = rdiff(thighDiff) * w * 0.8
                    vtx.position.x += disp * sign(vtx.position.x)
                    vtx.position.z += rdiff(thighDiff) * w * 0.6
                } else {
                    // 下腿〜足首域: ふくらはぎ差分
                    let disp = rdiff(calfDiff) * w * 0.7
                    vtx.position.x += disp * sign(vtx.position.x)
                    vtx.position.z += rdiff(calfDiff) * w * 0.5
                }
                // Y方向: 股下丈比率でスケール（ウエスト下方）
                if yM < 0 {
                    vtx.position.y = yM * inseamRatio
                }

            // ── 中立（頭部等）───────────────────────
            case .neutral:
                vtx.position.y *= heightRatio
            }

            result.vertices[i] = vtx
        }

        recalculateNormals(mesh: result)
        appliedName = measurement.name ?? "不明"
        return result
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
