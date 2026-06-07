//
//  MorphingEngine.swift
//  SewingCAD
//
//  Phase 3: モーフィング実装
//  CoreData の MeasurementProfile エンティティと連動して
//  標準メッシュを個人体型に変形する
//

import Foundation
import simd
import CoreData

// MARK: - モーフィングエンジン

class MorphingEngine: ObservableObject {

    @Published var appliedName: String = "標準体型"

    // MARK: メイン変形メソッド

    func morph(base: BodyMesh, measurement: MeasurementProfile) -> BodyMesh {
        let std = StandardMeasurement()
        let result = base.copy()

        // fieldID対応: 19=身長, 1=バスト, 3=ウエスト, 5=ヒップ
        let heightRatio = measurement.value(for: 19) > 0
            ? Float(measurement.value(for: 19)) / std.height : 1.0
        let bustDiff  = measurement.value(for: 1) > 0
            ? Float(measurement.value(for: 1))  - std.bust  : 0
        let waistDiff = measurement.value(for: 3) > 0
            ? Float(measurement.value(for: 3))  - std.waist : 0
        let hipDiff   = measurement.value(for: 5) > 0
            ? Float(measurement.value(for: 5))  - std.hip   : 0

        for i in result.vertices.indices {
            var v = result.vertices[i]
            let w = v.influenceWeight

            v.position.y *= heightRatio

            switch v.region {
            case .bust, .underBust:
                let zone = DeformationZone(region: .bust, vertexIndices: [], standardValue: std.bust)
                v.position += zone.displacement(for: bustDiff) * w

            case .waist:
                let zone = DeformationZone(region: .waist, vertexIndices: [], standardValue: std.waist)
                v.position += zone.displacement(for: waistDiff) * w

            case .hip, .abdomen:
                let zone = DeformationZone(region: .hip, vertexIndices: [], standardValue: std.hip)
                v.position += zone.displacement(for: hipDiff) * w

            case .leg:
                v.position.y *= (heightRatio - 1.0) * 0.5 + 1.0

            default:
                break
            }

            result.vertices[i] = v
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
            let faceNormal = cross(v1 - v0, v2 - v0)
            normals[poly.v0] += faceNormal
            normals[poly.v1] += faceNormal
            normals[poly.v2] += faceNormal
        }
        for i in mesh.vertices.indices {
            let len = length(normals[i])
            if len > 0 { mesh.vertices[i].normal = normals[i] / len }
        }
    }
}

// MARK: - パターン位置合わせ（Phase 4）

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
            var updated = p
            switch p.bodyFace {
            case .front, .back, .sleeve: updated.scale = bustScale
            case .skirt:                 updated.scale = hipScale
            }
            return updated
        }
    }

    func autoPlace(patternID: UUID, face: BodyFace, isSymmetric: Bool = false) {
        let anchor: SIMD3<Float>
        switch face {
        case .front:  anchor = SIMD3(0,  0.26,  0.13)
        case .back:   anchor = SIMD3(0,  0.26, -0.13)
        case .sleeve: anchor = SIMD3(0.19, 0.40, 0)
        case .skirt:  anchor = SIMD3(0, -0.04,  0)
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
