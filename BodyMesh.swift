//
//  BodyMesh.swift
//  SewingCAD
//
//  Phase 1 & 2: 標準メッシュの設計 + 変形ポイントの定義
//

import Foundation
import SceneKit

// MARK: - 体の部位

enum BodyRegion: String, CaseIterable {
    case neck       = "neck"
    case shoulder   = "shoulder"
    case bust       = "bust"
    case underBust  = "underBust"
    case waist      = "waist"
    case abdomen    = "abdomen"
    case hip        = "hip"
    case leg        = "leg"
    case neutral    = "neutral"

    /// 変形方向ベクトル（X:横, Y:縦, Z:前後）
    var deformAxis: SIMD3<Float> {
        switch self {
        case .bust:      return SIMD3(1, 0, 0.5)   // 外側＋前方に膨らむ
        case .waist:     return SIMD3(-1, 0, -0.3)  // 内側に絞られる
        case .hip:       return SIMD3(1, 0, 0.3)    // 外側＋やや後方に広がる
        case .shoulder:  return SIMD3(1, 0.2, 0)
        case .underBust: return SIMD3(0.5, 0, 0.2)
        case .abdomen:   return SIMD3(0.5, 0, 0.5)
        case .neck:      return SIMD3(0.3, 0.1, 0)
        case .leg:       return SIMD3(0.5, -1, 0)
        case .neutral:   return SIMD3(0, 0, 0)
        }
    }
}

// MARK: - 体の面（パターン配置用）

enum BodyFace: String, CaseIterable {
    case front  = "前身頃"
    case back   = "後身頃"
    case sleeve = "袖"
    case skirt  = "スカート"
}

// MARK: - 頂点

struct BodyVertex {
    let id: UUID
    var position: SIMD3<Float>      // メートル単位（1.0 = 100cm）
    var normal: SIMD3<Float>
    var region: BodyRegion
    /// この頂点がどれだけ変形の影響を受けるか（0.0〜1.0）
    var influenceWeight: Float
    /// UV座標（テクスチャ・パターン投影用）
    var uv: SIMD2<Float>

    init(position: SIMD3<Float>,
         normal: SIMD3<Float> = SIMD3(0, 0, 1),
         region: BodyRegion,
         influenceWeight: Float = 1.0,
         uv: SIMD2<Float> = SIMD2(0, 0)) {
        self.id = UUID()
        self.position = position
        self.normal = normal
        self.region = region
        self.influenceWeight = influenceWeight
        self.uv = uv
    }
}

// MARK: - ポリゴン（三角形）

struct BodyPolygon {
    var v0: Int
    var v1: Int
    var v2: Int
}

// MARK: - 変形ゾーン

struct DeformationZone {
    var region: BodyRegion
    /// このゾーンに属する頂点インデックス
    var vertexIndices: [Int]
    /// 標準値（cm）
    var standardValue: Float

    /// 差分に応じた変位量を計算
    /// - Parameter diff: 実測値 - 標準値 (cm)
    func displacement(for diff: Float) -> SIMD3<Float> {
        // 周囲の差分をラジアル変位に変換
        // 周囲 = 2πr → r = 周囲 / 2π
        let radiusDiff = diff / (2 * Float.pi)   // cm単位
        let radiusDiffM = radiusDiff / 100.0      // メートル単位
        return region.deformAxis * radiusDiffM
    }
}

// MARK: - ボディメッシュ

class BodyMesh: ObservableObject {
    @Published var vertices: [BodyVertex]
    var polygons: [BodyPolygon]
    var deformationZones: [DeformationZone]

    init(vertices: [BodyVertex],
         polygons: [BodyPolygon],
         deformationZones: [DeformationZone] = []) {
        self.vertices = vertices
        self.polygons = polygons
        self.deformationZones = deformationZones
    }

    // MARK: SceneKit ジオメトリ生成

    func buildGeometry() -> SCNGeometry {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvCoords: [CGPoint] = []
        var indices: [Int32] = []

        for v in vertices {
            positions.append(SCNVector3(v.position.x, v.position.y, v.position.z))
            normals.append(SCNVector3(v.normal.x, v.normal.y, v.normal.z))
            uvCoords.append(CGPoint(x: CGFloat(v.uv.x), y: CGFloat(v.uv.y)))
        }

        for poly in polygons {
            indices.append(Int32(poly.v0))
            indices.append(Int32(poly.v1))
            indices.append(Int32(poly.v2))
        }

        let positionSource = SCNGeometrySource(vertices: positions)
        let normalSource   = SCNGeometrySource(normals: normals)
        let uvSource = SCNGeometrySource(
            textureCoordinates: uvCoords
        )
        let element = SCNGeometryElement(
            indices: indices,
            primitiveType: .triangles
        )

        let geometry = SCNGeometry(
            sources: [positionSource, normalSource, uvSource],
            elements: [element]
        )

        // マテリアル設定
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(
            red: 0.95, green: 0.88, blue: 0.80, alpha: 1.0
        )
        material.specular.contents = NSColor.white
        material.shininess = 0.3
        material.isDoubleSided = true
        geometry.materials = [material]

        return geometry
    }

    // MARK: ワイヤーフレーム用ジオメトリ

    func buildWireframeGeometry() -> SCNGeometry {
        var positions: [SCNVector3] = []
        var indices: [Int32] = []
        var idx: Int32 = 0

        for poly in polygons {
            let v0 = vertices[poly.v0].position
            let v1 = vertices[poly.v1].position
            let v2 = vertices[poly.v2].position

            positions.append(contentsOf: [
                SCNVector3(v0.x, v0.y, v0.z),
                SCNVector3(v1.x, v1.y, v1.z),
                SCNVector3(v1.x, v1.y, v1.z),
                SCNVector3(v2.x, v2.y, v2.z),
                SCNVector3(v2.x, v2.y, v2.z),
                SCNVector3(v0.x, v0.y, v0.z),
            ])
            indices.append(contentsOf: [idx, idx+1, idx+2, idx+3, idx+4, idx+5])
            idx += 6
        }

        let positionSource = SCNGeometrySource(vertices: positions)
        let element = SCNGeometryElement(
            indices: indices,
            primitiveType: .line
        )
        let geo = SCNGeometry(sources: [positionSource], elements: [element])
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(white: 0.4, alpha: 0.5)
        geo.materials = [mat]
        return geo
    }

    // MARK: ディープコピー

    func copy() -> BodyMesh {
        BodyMesh(
            vertices: vertices,
            polygons: polygons,
            deformationZones: deformationZones
        )
    }
}
