//
//  PatternMeshBuilder.swift
//  SewingCAD
//
//  Step 2 & 3: パターンの三角分割 + ボディ曲面への投影（方法B）
//
//  座標系:
//    BodyMesh  … ウエスト=Y0原点、メートル単位
//    Pattern2D … px単位（1cm = 37.8px）
//

import Foundation
import SceneKit
import simd

// MARK: - 2D三角形

private struct Triangle2D {
    var a: CGPoint
    var b: CGPoint
    var c: CGPoint
}

// MARK: - PatternMeshBuilder

struct PatternMeshBuilder {

    // px → メートル変換係数
    private static let pxToM: CGFloat = 1.0 / 37.8 / 100.0

    // ボディ表面からの浮かせ量（布の厚み相当）
    private static let surfaceOffset: Float = 0.004   // 4mm

    // ── メインエントリ ──────────────────────────────────────────
    /// パターンデータ＋ボディメッシュ＋パーツタイプ → SCNNode（曲面貼り付き）
    static func build(
        patternData: PatternData,
        bodyMesh: BodyMesh,
        partType: PatternPartType,
        stdM: StandardMeasurement,
        waistOffsetY: CGFloat,
        image: NSImage?
    ) -> [SCNNode] {

        // 1. パターンのバウンディングボックスと輪郭点群を取得
        let bbox = boundingBox(of: patternData)
        guard bbox.width > 1, bbox.height > 1 else { return [] }

        // 2. グリッド分割で2D三角形メッシュを生成
        let gridDiv = 16   // 16分割で滑らかな曲面フィット
        let triangles2D = gridTriangulate(bbox: bbox, divisions: gridDiv)

        // 3. パーツタイプ別に配置パラメータを決定
        let placement = PlacementParams(
            for: partType, bodyMesh: bodyMesh, stdM: stdM, bbox: bbox
        )

        // 4. 各三角形の頂点をボディ曲面座標に投影
        let mat = makeMaterial(image: image)

        // 右側（または単体）ノード
        let rightNode = buildProjectedNode(
            triangles: triangles2D,
            bbox: bbox,
            placement: placement,
            bodyMesh: bodyMesh,
            mirror: false,
            material: mat,
            waistOffsetY: Float(waistOffsetY)
        )
        rightNode.name = "pattern_\(partType.rawValue)_R"

        switch partType {
        case .bodiceFront, .bodiceBack, .skirtFront, .skirtBack, .pants:
            // 左右ミラー表示
            let leftNode = buildProjectedNode(
                triangles: triangles2D,
                bbox: bbox,
                placement: placement,
                bodyMesh: bodyMesh,
                mirror: true,
                material: mat,
                waistOffsetY: Float(waistOffsetY)
            )
            leftNode.name = "pattern_\(partType.rawValue)_L"
            return [rightNode, leftNode]

        case .sleeveFront, .cuff:
            // 左右の腕
            let leftArmPlacement = PlacementParams(
                for: partType, bodyMesh: bodyMesh, stdM: stdM, bbox: bbox, armSide: -1
            )
            let leftArmNode = buildProjectedNode(
                triangles: triangles2D,
                bbox: bbox,
                placement: leftArmPlacement,
                bodyMesh: bodyMesh,
                mirror: false,
                material: mat,
                waistOffsetY: Float(waistOffsetY)
            )
            leftArmNode.name = "pattern_\(partType.rawValue)_L"
            return [rightNode, leftArmNode]

        default:
            return [rightNode]
        }
    }

    // ── グリッド三角分割 ────────────────────────────────────────
    /// bbox を gridDiv×gridDiv のグリッドに分割して三角形リストを返す
    private static func gridTriangulate(bbox: CGRect, divisions: Int) -> [Triangle2D] {
        var tris: [Triangle2D] = []
        let dw = bbox.width  / CGFloat(divisions)
        let dh = bbox.height / CGFloat(divisions)

        for row in 0..<divisions {
            for col in 0..<divisions {
                let x0 = bbox.minX + CGFloat(col) * dw
                let y0 = bbox.minY + CGFloat(row) * dh
                let x1 = x0 + dw
                let y1 = y0 + dh

                // 各セルを2三角形に分割
                tris.append(Triangle2D(
                    a: CGPoint(x: x0, y: y0),
                    b: CGPoint(x: x1, y: y0),
                    c: CGPoint(x: x1, y: y1)
                ))
                tris.append(Triangle2D(
                    a: CGPoint(x: x0, y: y0),
                    b: CGPoint(x: x1, y: y1),
                    c: CGPoint(x: x0, y: y1)
                ))
            }
        }
        return tris
    }

    // ── 投影済みSCNNodeを生成 ─────────────────────────────────
    private static func buildProjectedNode(
        triangles: [Triangle2D],
        bbox: CGRect,
        placement: PlacementParams,
        bodyMesh: BodyMesh,
        mirror: Bool,
        material: SCNMaterial,
        waistOffsetY: Float
    ) -> SCNNode {

        var positions: [SCNVector3] = []
        var normals:   [SCNVector3] = []
        var uvs:       [CGPoint]    = []
        var indices:   [Int32]      = []
        var idx: Int32 = 0

        for tri in triangles {
            let pts = [tri.a, tri.b, tri.c]
            var projected: [SCNVector3] = []
            var projNormals: [SCNVector3] = []

            for pt in pts {
                let (pos3D, nrm) = projectPoint(
                    pt2D: pt,
                    bbox: bbox,
                    placement: placement,
                    bodyMesh: bodyMesh,
                    mirror: mirror,
                    waistOffsetY: waistOffsetY
                )
                projected.append(pos3D)
                projNormals.append(nrm)
            }

            // UV座標（テクスチャマッピング用）
            let uvList = pts.map { pt -> CGPoint in
                CGPoint(
                    x: (pt.x - bbox.minX) / bbox.width,
                    y: 1.0 - (pt.y - bbox.minY) / bbox.height
                )
            }

            positions.append(contentsOf: projected)
            normals.append(contentsOf: projNormals)
            uvs.append(contentsOf: uvList)

            // ミラー時は三角形の巻き順を逆にして裏面を防ぐ
            if mirror {
                indices.append(contentsOf: [idx+2, idx+1, idx])
            } else {
                indices.append(contentsOf: [idx, idx+1, idx+2])
            }
            idx += 3
        }

        let posSource = SCNGeometrySource(vertices: positions)
        let nrmSource = SCNGeometrySource(normals: normals)
        let uvSource  = SCNGeometrySource(textureCoordinates: uvs)
        let element   = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        let geo = SCNGeometry(sources: [posSource, nrmSource, uvSource], elements: [element])
        geo.materials = [material]

        return SCNNode(geometry: geo)
    }

    // ── 1点の2D→3D曲面投影 ────────────────────────────────────
    /// パターンの1点(pt2D)をボディ曲面に投影した3D座標と法線を返す
    private static func projectPoint(
        pt2D: CGPoint,
        bbox: CGRect,
        placement: PlacementParams,
        bodyMesh: BodyMesh,
        mirror: Bool,
        waistOffsetY: Float
    ) -> (SCNVector3, SCNVector3) {

        // パターン2D内での正規化座標（0〜1）
        let u = Float((pt2D.x - bbox.minX) / bbox.width)   // 横位置 0=左端 1=右端
        let v = Float((pt2D.y - bbox.minY) / bbox.height)  // 縦位置 0=上端 1=下端

        // ── Y座標の計算（高さ）──
        // v=0→topY（上端）、v=1→bottomY（下端）でボディ部位間に収める
        let localY = placement.topY + v * placement.heightM  // BodyMesh座標系
        let worldY = localY + waistOffsetY                   // ワールド座標系

        // ── XZ座標の計算（ボディ断面への投影）──
        // そのY高さでのボディ断面半径をメッシュから取得
        let (radiusX, radiusZ) = getBodyRadius(at: localY, bodyMesh: bodyMesh, face: placement.face)

        // ── 方法②: パターン実寸 ÷ 断面半径 = 巻き付け角度 ──────
        // 弧長 s = r * θ  →  θ = s / r
        let patternWidthM = Float(bbox.width) * Float(1.0 / 37.8 / 100.0)
        let effectiveRadius = (radiusX + radiusZ) * 0.5
        let totalArcAngle = effectiveRadius > 0 ? patternWidthM / effectiveRadius : Float.pi * 0.5

        // mirror時はu方向を反転して左半身を対称配置
        let uMapped: Float = mirror ? (1.0 - u) : u
        let angle = (uMapped - 0.5) * totalArcAngle
        let xSign: Float = mirror ? -1.0 : 1.0

        let x: Float
        let z: Float
        let nx: Float
        let nz: Float

        switch placement.face {
        case .front:
            x  =  sin(angle) * radiusX * xSign
            z  =  cos(angle) * radiusZ + surfaceOffset
            nx =  sin(angle) * xSign
            nz =  cos(angle)

        case .back:
            x  =  sin(angle) * radiusX * xSign
            z  = -cos(angle) * radiusZ - surfaceOffset
            nx =  sin(angle) * xSign
            nz = -cos(angle)

        case .armRight:
            let a = (uMapped - 0.5) * min(totalArcAngle, Float.pi * 0.5)
            x  =  placement.xOffset + cos(a) * radiusX * 0.4 + surfaceOffset
            z  =  sin(a) * radiusZ * 0.4
            nx =  1; nz = 0

        case .armLeft:
            let a = (uMapped - 0.5) * min(totalArcAngle, Float.pi * 0.5)
            x  =  placement.xOffset - cos(a) * radiusX * 0.4 - surfaceOffset
            z  =  sin(a) * radiusZ * 0.4
            nx = -1; nz = 0
        }

        let position = SCNVector3(x, worldY, z)
        let normal   = SCNVector3(nx, 0, nz)
        return (position, normal)
    }

    // ── BodyMeshから指定Y高さの断面半径を取得 ─────────────────
    /// BodyMeshの頂点群から指定Y（ウエスト=0原点）での楕円半径(rx, rz)を返す
    private static func getBodyRadius(
        at localY: Float,
        bodyMesh: BodyMesh,
        face: ProjectionFace
    ) -> (rx: Float, rz: Float) {

        // 対象regionでY値が近い頂点を探す
        let targetRegions: [BodyRegion]
        switch face {
        case .front, .back:
            targetRegions = [.bust, .waist, .hip, .abdomen, .underBust, .shoulder, .neck, .leg]
        case .armRight, .armLeft:
            targetRegions = [.shoulder]
        }

        let candidates = bodyMesh.vertices.filter {
            targetRegions.contains($0.region)
        }

        guard !candidates.isEmpty else { return (0.13, 0.10) }

        // Y値が最も近い頂点群（±3cm = ±0.03m 以内）を抽出
        let tolerance: Float = 0.04
        let nearby = candidates.filter { abs($0.position.y - localY) < tolerance }

        let pool = nearby.isEmpty ? candidates.sorted {
            abs($0.position.y - localY) < abs($1.position.y - localY)
        }.prefix(24) : ArraySlice(nearby)

        // X方向最大値（左右の広がり）
        let maxX = pool.map { abs($0.position.x) }.max() ?? 0.13
        // Z方向最大値（前後の奥行き）
        let maxZ = pool.map { abs($0.position.z) }.max() ?? 0.10

        return (maxX, maxZ)
    }

    // ── マテリアル生成 ─────────────────────────────────────────
    private static func makeMaterial(image: NSImage?) -> SCNMaterial {
        let mat = SCNMaterial()
        if let img = image {
            mat.diffuse.contents = img
        } else {
            mat.diffuse.contents = NSColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 0.9)
        }
        mat.isDoubleSided       = true
        mat.transparencyMode    = .default
        mat.writesToDepthBuffer = true
        mat.blendMode           = .alpha
        return mat
    }

    // ── バウンディングボックス ─────────────────────────────────
    static func boundingBox(of data: PatternData) -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        func expand(_ x: CGFloat, _ y: CGFloat) {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }
        for l in data.lines  { expand(l.x1, l.y1); expand(l.x2, l.y2) }
        for c in data.curves { for n in c.nodes { expand(n.x, n.y) } }
        for a in data.arcs {
            expand(a.cx - a.radius, a.cy - a.radius)
            expand(a.cx + a.radius, a.cy + a.radius)
        }
        guard minX != .infinity else { return .zero }
        let pad: CGFloat = 10
        return CGRect(x: minX-pad, y: minY-pad,
                      width: maxX-minX+pad*2, height: maxY-minY+pad*2)
    }
}

// MARK: - 投影面の種類

private enum ProjectionFace {
    case front      // 前面（Z+方向）
    case back       // 後面（Z-方向）
    case armRight   // 右腕
    case armLeft    // 左腕
}

// MARK: - 配置パラメータ

private struct PlacementParams {
    var face: ProjectionFace
    var topY: Float       // パーツ上端（BodyMesh座標系、ウエスト=0）
    var bottomY: Float    // パーツ下端（BodyMesh座標系）
    var heightM: Float    // topY〜bottomYの距離（= bottomY - topY、負になる）
    var xOffset: Float
    var zOffset: Float

    init(
        for type: PatternPartType,
        bodyMesh: BodyMesh,
        stdM: StandardMeasurement,
        bbox: CGRect,
        armSide: Float = 1
    ) {
        let widthM = Float(bbox.width) * Float(1.0 / 37.8 / 100.0)

        // BodyMesh座標系（ウエスト=Y0原点）での各部位Y
        let waistY:    Float =  0.0
        let shoulderY: Float =  (141.0 - 111.0) / 100.0 * (stdM.height / 158.0)  // ≈ +0.30m
        let hipY:      Float = -(stdM.waistHeight - stdM.hipHeight) / 100.0        // ≈ -0.19m
        let hemY:      Float = hipY - 0.25   // スカート裾：ヒップから25cm下
        let wristY:    Float = shoulderY - stdM.sleeveLen / 100.0  // 手首Y

        switch type {
        case .bodiceFront:
            face    = .front
            topY    = shoulderY
            bottomY = waistY
            xOffset = 0; zOffset = 0

        case .bodiceBack:
            face    = .back
            topY    = shoulderY
            bottomY = waistY
            xOffset = 0; zOffset = 0

        case .sleeveFront:
            face    = armSide > 0 ? .armRight : .armLeft
            topY    = shoulderY
            bottomY = wristY
            xOffset = armSide * (stdM.shoulder / 2.0 / 100.0 + widthM * 0.3)
            zOffset = 0

        case .skirtFront:
            face    = .front
            topY    = waistY
            bottomY = hemY
            xOffset = 0; zOffset = 0

        case .skirtBack:
            face    = .back
            topY    = waistY
            bottomY = hemY
            xOffset = 0; zOffset = 0

        case .pants:
            face    = .front
            topY    = waistY
            bottomY = waistY - stdM.inseam / 100.0
            xOffset = 0; zOffset = 0

        case .collar:
            face    = .front
            topY    = shoulderY + 0.06
            bottomY = shoulderY
            xOffset = 0; zOffset = 0

        case .cuff:
            face    = armSide > 0 ? .armRight : .armLeft
            topY    = wristY + 0.04
            bottomY = wristY - 0.04
            xOffset = armSide * (stdM.shoulder / 2.0 / 100.0 + widthM * 0.3)
            zOffset = 0

        case .waistband:
            face    = .front
            topY    = waistY + 0.03
            bottomY = waistY - 0.03
            xOffset = 0; zOffset = 0

        case .other:
            face    = .front
            topY    = waistY
            bottomY = hemY
            xOffset = stdM.shoulder / 2.0 / 100.0 + 0.05
            zOffset = 0
        }

        // heightM: v=0→topY、v=1→bottomY のマッピング用
        heightM = bottomY - topY  // 負の値（下方向）
    }
}
