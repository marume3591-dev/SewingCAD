//
//  StandardBodyData.swift
//  SewingCAD
//
//  改善版: 断面スライス数を14→26に増加、滑らかな体型曲線
//

import Foundation
import simd

// MARK: - 標準計測値

struct StandardMeasurement {
    var height:    Float = 158.0
    var bust:      Float =  83.0
    var waist:     Float =  64.0
    var hip:       Float =  91.0
    var shoulder:  Float =  38.0
    var neck:      Float =  35.0
    var underBust: Float =  72.0
}

// MARK: - 標準ボディ生成

enum StandardBodyGenerator {

    static let standard = StandardMeasurement()

    static func generate() -> BodyMesh {
        var vertices: [BodyVertex] = []
        var polygons:  [BodyPolygon] = []

        // ---- 断面スライス（26断面 / 旧14断面から増加）----
        // (地面からの高さcm, X半径cm, Z半径cm, 部位, 影響度)
        let slices: [(y: Float, rx: Float, rz: Float, region: BodyRegion, w: Float)] = [
            // 頭頂
            (157, 9.5,  9.5,  .neutral,   0.05),
            (154, 9.0,  9.0,  .neutral,   0.05),
            // 首
            (150, 6.5,  6.0,  .neck,      0.6),
            (147, 5.8,  5.5,  .neck,      0.8),
            (144, 5.5,  5.2,  .neck,      0.9),
            // 肩〜胸上
            (141, 14.0, 7.5,  .shoulder,  0.8),
            (138, 19.0, 8.5,  .shoulder,  0.9),
            (135, 20.0, 10.0, .bust,      0.7),
            (132, 20.5, 11.5, .bust,      0.8),
            // バスト
            (129, 20.8, 13.0, .bust,      0.95),
            (126, 20.5, 13.5, .bust,      1.0),   // ← バスト最大
            (123, 19.5, 12.5, .bust,      0.9),
            // アンダーバスト
            (120, 18.0, 11.0, .underBust, 0.85),
            (117, 16.8, 10.5, .underBust, 0.7),
            // ウエスト
            (114, 15.8, 10.2, .waist,     0.9),
            (111, 15.5, 10.0, .waist,     1.0),   // ← ウエスト最細
            (108, 15.5, 10.0, .waist,     1.0),
            // 腹部
            (105, 16.5, 11.0, .abdomen,   0.75),
            (102, 17.5, 11.8, .abdomen,   0.7),
            //  ヒップ
            ( 99, 20.0, 12.5, .hip,       0.85),
            ( 96, 22.5, 13.2, .hip,       1.0),   // ← ヒップ最大
            ( 93, 22.0, 12.8, .hip,       0.95),
            ( 90, 21.0, 12.2, .hip,       0.85),
            // 太もも
            ( 86, 17.5, 10.5, .leg,       0.5),
            ( 82, 15.5,  9.5, .leg,       0.4),
            // 股下
            ( 76, 14.0,  8.5, .leg,       0.3),
        ]

        let ringSegments = 24   // 旧16→24に増加（滑らかな断面）
        let totalRings   = slices.count

        // ---- 頂点生成 ----
        for (si, slice) in slices.enumerated() {
            let yM   = (slice.y - 111.0) / 100.0   // ウエスト(111cm)を原点に
            let rxM  = slice.rx / 100.0
            let rzM  = slice.rz / 100.0
            let uRow = Float(si) / Float(totalRings - 1)

            for vi in 0..<ringSegments {
                let angle = 2 * Float.pi * Float(vi) / Float(ringSegments)
                let x  =  cos(angle) * rxM
                let z  =  sin(angle) * rzM
                let nx =  cos(angle)
                let nz =  sin(angle)
                vertices.append(BodyVertex(
                    position: SIMD3(x, yM, z),
                    normal:   SIMD3(nx, 0, nz),
                    region:   slice.region,
                    influenceWeight: slice.w,
                    uv: SIMD2(Float(vi) / Float(ringSegments), uRow)
                ))
            }
        }

        // ---- ポリゴン生成 ----
        for si in 0..<(totalRings - 1) {
            for vi in 0..<ringSegments {
                let next  = (vi + 1) % ringSegments
                let base0 = si * ringSegments
                let base1 = (si + 1) * ringSegments
                polygons.append(BodyPolygon(v0: base0+vi,   v1: base1+vi,   v2: base1+next))
                polygons.append(BodyPolygon(v0: base0+vi,   v1: base1+next, v2: base0+next))
            }
        }

        // ---- 上キャップ ----
        let topIdx = vertices.count
        vertices.append(BodyVertex(
            position: SIMD3(0, (slices.first!.y - 111.0) / 100.0, 0),
            normal: SIMD3(0, 1, 0), region: .neutral, influenceWeight: 0.05,
            uv: SIMD2(0.5, 0.0)
        ))
        for vi in 0..<ringSegments {
            let next = (vi + 1) % ringSegments
            polygons.append(BodyPolygon(v0: topIdx, v1: next, v2: vi))
        }

        // ---- 下キャップ ----
        let botIdx  = vertices.count
        let botBase = (totalRings - 1) * ringSegments
        vertices.append(BodyVertex(
            position: SIMD3(0, (slices.last!.y - 111.0) / 100.0, 0),
            normal: SIMD3(0, -1, 0), region: .leg, influenceWeight: 0.2,
            uv: SIMD2(0.5, 1.0)
        ))
        for vi in 0..<ringSegments {
            let next = (vi + 1) % ringSegments
            polygons.append(BodyPolygon(v0: botIdx, v1: botBase+vi, v2: botBase+next))
        }

        // ---- 変形ゾーン ----
        var deformZones: [DeformationZone] = []
        for (si, slice) in slices.enumerated() {
            let idxs = Array(si * ringSegments ..< (si + 1) * ringSegments)
            switch slice.region {
            case .bust:
                deformZones.append(DeformationZone(region: .bust,     vertexIndices: idxs, standardValue: StandardMeasurement().bust))
            case .waist:
                deformZones.append(DeformationZone(region: .waist,    vertexIndices: idxs, standardValue: StandardMeasurement().waist))
            case .hip:
                deformZones.append(DeformationZone(region: .hip,      vertexIndices: idxs, standardValue: StandardMeasurement().hip))
            case .shoulder:
                deformZones.append(DeformationZone(region: .shoulder, vertexIndices: idxs, standardValue: StandardMeasurement().shoulder * 2))
            default: break
            }
        }

        return BodyMesh(vertices: vertices, polygons: polygons, deformationZones: deformZones)
    }
}
