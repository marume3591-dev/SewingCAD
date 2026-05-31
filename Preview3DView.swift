//
//  Preview3DView.swift
//  SewingCAD
//

import SwiftUI
import SceneKit
import CoreData

// MARK: - パーツの3D配置情報

struct PartPlacement {
    let patternData: PatternData
    let part: PatternPart
}

// MARK: - Preview3DView

struct Preview3DView: View {
    let canvasState: CanvasState
    @ObservedObject var projectManager: ProjectManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Measurement.createdAt, ascending: true)],
        animation: .default)
    private var measurements: FetchedResults<Measurement>

    @State private var selectedMeasurementID: NSManagedObjectID? = nil
    @State private var showPatterns: Bool = true
    @State private var patternOpacity: Double = 1.0

    private var selectedMeasurement: Measurement? {
        guard let id = selectedMeasurementID else { return measurements.first }
        return measurements.first { $0.objectID == id }
    }

    /// 全パーツのPlacementを構築する
    /// プロジェクト未使用の場合はcanvasStateを「前身頃」として1枚表示
    private func buildPlacements() -> [PartPlacement] {
        // ── プロジェクトがある場合 ──
        if let project = projectManager.currentProject, !project.parts.isEmpty {
            return project.parts.compactMap { part -> PartPlacement? in
                let data: PatternData
                if projectManager.activePartID == part.id {
                    // アクティブパーツ = canvasStateの現在の状態をそのまま使う
                    // （まだファイル保存されていなくても表示できる）
                    data = canvasState.toPatternData()
                } else {
                    // 非アクティブパーツ = ファイルから読み込む
                    guard let d = projectManager.loadPatternData(for: part.id) else { return nil }
                    data = d
                }
                // 線も曲線も円弧もない空パーツはスキップ
                guard !data.lines.isEmpty || !data.curves.isEmpty || !data.arcs.isEmpty else { return nil }
                return PartPlacement(patternData: data, part: part)
            }
        }

        // ── プロジェクトなし = canvasStateを前身頃として表示 ──
        let data = canvasState.toPatternData()
        guard !data.lines.isEmpty || !data.curves.isEmpty || !data.arcs.isEmpty else { return [] }
        let fallbackPart = PatternPart(name: "パターン", type: .bodiceFront, fileName: "")
        return [PartPlacement(patternData: data, part: fallbackPart)]
    }

    var body: some View {
        let placements = showPatterns ? buildPlacements() : []

        VStack(spacing: 0) {
            // ツールバー
            HStack(spacing: 12) {
                Text("3D プレビュー")
                    .font(.headline)

                Divider().frame(height: 20)

                if measurements.isEmpty {
                    Text("計測データなし")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Picker("ボディ", selection: Binding(
                        get: { selectedMeasurementID ?? measurements.first?.objectID },
                        set: { selectedMeasurementID = $0 }
                    )) {
                        ForEach(measurements) { m in
                            Text(m.name ?? "").tag(Optional(m.objectID))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .font(.system(size: 12))
                }

                Divider().frame(height: 20)

                Toggle("パターンを表示", isOn: $showPatterns)
                    .font(.system(size: 12))

                Spacer()

                Text("ドラッグ: 回転 / ピンチ: ズーム / 右ドラッグ: 移動")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // ── パターンなし警告 ──
            if showPatterns && placements.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("表示できるパターンがありません")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("キャンバスに線・曲線を描くか、プロジェクトのパーツを選択してください")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.underPageBackgroundColor))
            } else {
                SceneKitView(
                    placements: placements,
                    measurement: selectedMeasurement.map {
                        BodyMeasurements(
                            height: CGFloat($0.height),
                            bust: CGFloat($0.bust),
                            waist: CGFloat($0.waist),
                            hip: CGFloat($0.hip)
                        )
                    } ?? .default,
                    patternOpacity: patternOpacity
                )
            }

            Divider()

            // ステータスバー
            HStack {
                if let m = selectedMeasurement {
                    Text(String(format: "身長: %.0fcm  バスト: %.0fcm  ウエスト: %.0fcm  ヒップ: %.0fcm",
                               m.height, m.bust, m.waist, m.hip))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("計測データがありません。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if placements.isEmpty {
                    Text("パターン: なし")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("表示中: " + placements.map { $0.part.name }.joined(separator: " / "))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

// MARK: - SceneKit NSViewRepresentable

struct SceneKitView: NSViewRepresentable {
    let placements: [PartPlacement]
    let measurement: BodyMeasurements
    let patternOpacity: Double

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        scnView.scene = buildScene()

        let cameraNode = makeCamera()
        scnView.scene?.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        let pov = scnView.pointOfView
        scnView.scene = buildScene()
        if let pov = pov {
            scnView.scene?.rootNode.addChildNode(pov)
            scnView.pointOfView = pov
        }
    }

    private func makeCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 45
        camera.zNear = 0.01
        camera.zFar = 100
        let node = SCNNode()
        node.camera = camera
        node.name = "mainCamera"
        let bodyH = measurement.height * 0.1
        node.position = SCNVector3(0, Float(bodyH * 0.55), Float(bodyH * 2.2))
        node.look(at: SCNVector3(0, Float(bodyH * 0.5), 0))
        return node
    }

    // MARK: - シーン構築

    private func buildScene() -> SCNScene {
        let scene = SCNScene()
        addLights(to: scene)
        addFloor(to: scene)

        let bodyNode = BodyModel.makeNode(from: measurement)
        bodyNode.name = "body"
        scene.rootNode.addChildNode(bodyNode)

        for placement in placements {
            if let node = makePlaneNode(for: placement) {
                scene.rootNode.addChildNode(node)
            }
        }
        return scene
    }

    // MARK: - パーツ平面ノード生成

    private func makePlaneNode(for placement: PartPlacement) -> SCNNode? {
        let data = placement.patternData
        let bbox = boundingBox(of: data)
        guard bbox.width > 1, bbox.height > 1 else { return nil }

        guard let image = renderPatternImage(from: data, bbox: bbox) else { return nil }

        let unitPerPx: CGFloat = 0.1 / 37.8
        let planeW = CGFloat(bbox.width  * unitPerPx)
        let planeH = CGFloat(bbox.height * unitPerPx)

        let plane = SCNPlane(width: planeW, height: planeH)
        plane.firstMaterial?.diffuse.contents = image
        plane.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: plane)
        node.name = "pattern_\(placement.part.type.rawValue)"

        let pose = placementPose(for: placement.part.type,
                                 planeW: Float(planeW), planeH: Float(planeH))
        node.position    = pose.position
        node.eulerAngles = pose.eulerAngles
        return node
    }

    // MARK: - PatternPartTypeごとの配置

    private struct Pose {
        var position: SCNVector3
        var eulerAngles: SCNVector3
    }

    private func placementPose(for type: PatternPartType, planeW: Float, planeH: Float) -> Pose {
        let m = measurement
        let bR        = Float((m.bust  / .pi) * 0.1)
        let wR        = Float((m.waist / .pi) * 0.1)
        let hipR      = Float((m.hip   / .pi) * 0.1)
        let bodyH     = Float(m.height * 0.1)

        let legH      = bodyH * 0.47
        let hipBodyH  = bodyH * 0.12
        let torsoH    = bodyH * 0.28

        let torsoAvgR   = (wR + bR) / 2
        let bustSphR    = bR * 0.36
        let frontZ      = torsoAvgR * 0.65 + bustSphR + 0.005
        let backZ       = -(torsoAvgR * 0.78 + 0.005)
        let torsoMidY   = legH + hipBodyH + torsoH * 0.5
        let shoulderY   = legH + hipBodyH + torsoH
        let shoulderR   = bR * 0.22
        let armH        = bodyH * 0.30
        let armMidY     = shoulderY - armH * 0.5
        let armX        = bR + shoulderR * 1.1

        switch type {
        case .bodiceFront:
            return Pose(position: SCNVector3(0, torsoMidY, frontZ),
                        eulerAngles: SCNVector3(0, 0, 0))
        case .bodiceBack:
            return Pose(position: SCNVector3(0, torsoMidY, backZ),
                        eulerAngles: SCNVector3(0, Float.pi, 0))
        case .sleeveFront:
            return Pose(position: SCNVector3(-armX, armMidY, 0),
                        eulerAngles: SCNVector3(0, Float.pi / 2, 0))
        case .skirtFront:
            return Pose(position: SCNVector3(0, legH * 0.5 + hipBodyH, hipR + 0.005),
                        eulerAngles: SCNVector3(0, 0, 0))
        case .skirtBack:
            return Pose(position: SCNVector3(0, legH * 0.5 + hipBodyH, -(hipR + 0.005)),
                        eulerAngles: SCNVector3(0, Float.pi, 0))
        case .pants:
            return Pose(position: SCNVector3(0, legH * 0.5, hipR + 0.005),
                        eulerAngles: SCNVector3(0, 0, 0))
        case .collar:
            return Pose(position: SCNVector3(0, shoulderY + bodyH * 0.025, bR * 0.2),
                        eulerAngles: SCNVector3(Float.pi * 0.15, 0, 0))
        case .cuff:
            return Pose(position: SCNVector3(-armX, shoulderY - armH - 0.01, 0),
                        eulerAngles: SCNVector3(0, Float.pi / 2, 0))
        case .waistband:
            return Pose(position: SCNVector3(0, legH + hipBodyH, wR * 0.5),
                        eulerAngles: SCNVector3(Float.pi / 2, 0, 0))
        case .other:
            return Pose(position: SCNVector3(bR * 3, torsoMidY, 0),
                        eulerAngles: SCNVector3(0, Float.pi / 2, 0))
        }
    }

    // MARK: - テクスチャ描画

    private func renderPatternImage(from data: PatternData, bbox: CGRect) -> NSImage? {
        let texSize = CGSize(width: 512, height: 512)
        let scaleX = texSize.width  / bbox.width
        let scaleY = texSize.height / bbox.height

        func tx(_ x: CGFloat) -> CGFloat { (x - bbox.minX) * scaleX }
        func ty(_ y: CGFloat) -> CGFloat { texSize.height - (y - bbox.minY) * scaleY }

        let image = NSImage(size: texSize)
        image.lockFocus()

        // 白背景（完全不透明）
        NSColor(white: 1.0, alpha: 1.0).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: texSize),
                     xRadius: 8, yRadius: 8).fill()

        // 枠線
        NSColor(white: 0.6, alpha: 0.4).setStroke()
        let border = NSBezierPath(roundedRect: NSRect(x: 1, y: 1,
                                                      width: texSize.width - 2,
                                                      height: texSize.height - 2),
                                  xRadius: 8, yRadius: 8)
        border.lineWidth = 1.5
        border.stroke()

        // 線（青・太め）
        NSColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1.0).setStroke()
        for line in data.lines {
            let path = NSBezierPath()
            path.lineWidth = 4.0
            path.move(to: CGPoint(x: tx(line.x1), y: ty(line.y1)))
            path.line(to: CGPoint(x: tx(line.x2), y: ty(line.y2)))
            path.stroke()
        }

        // 曲線（赤・太め）
        NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0).setStroke()
        for curve in data.curves {
            guard curve.nodes.count >= 2 else { continue }
            let path = NSBezierPath()
            path.lineWidth = 4.0
            path.move(to: CGPoint(x: tx(curve.nodes[0].x), y: ty(curve.nodes[0].y)))
            for i in 0..<curve.nodes.count - 1 {
                let f = curve.nodes[i], t = curve.nodes[i + 1]
                path.curve(
                    to:            CGPoint(x: tx(t.x),    y: ty(t.y)),
                    controlPoint1: CGPoint(x: tx(f.cp2x), y: ty(f.cp2y)),
                    controlPoint2: CGPoint(x: tx(t.cp1x), y: ty(t.cp1y))
                )
            }
            path.stroke()
        }

        // 円弧（緑・太め）
        NSColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1.0).setStroke()
        for arc in data.arcs {
            let path = NSBezierPath()
            path.lineWidth = 4.0
            path.appendArc(
                withCenter: CGPoint(x: tx(arc.cx), y: ty(arc.cy)),
                radius: arc.radius * (scaleX + scaleY) / 2,
                startAngle: -arc.startAngle,
                endAngle: -arc.endAngle,
                clockwise: true
            )
            path.stroke()
        }

        image.unlockFocus()
        return image
    }

    // MARK: - バウンディングボックス

    private func boundingBox(of data: PatternData) -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity

        func expand(_ x: CGFloat, _ y: CGFloat) {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }

        for l in data.lines   { expand(l.x1, l.y1); expand(l.x2, l.y2) }
        for c in data.curves  { for n in c.nodes { expand(n.x, n.y) } }
        for a in data.arcs    { expand(a.cx - a.radius, a.cy - a.radius)
                                expand(a.cx + a.radius, a.cy + a.radius) }

        guard minX != .infinity else { return .zero }
        let pad: CGFloat = 20
        return CGRect(x: minX - pad, y: minY - pad,
                      width:  maxX - minX + pad * 2,
                      height: maxY - minY + pad * 2)
    }

    // MARK: - ライティング

    private func addLights(to scene: SCNScene) {
        let bodyH = Float(measurement.height * 0.1)

        let ambient = SCNLight(); ambient.type = .ambient
        ambient.color = NSColor(white: 0.35, alpha: 1)
        let an = SCNNode(); an.light = ambient
        scene.rootNode.addChildNode(an)

        let main = SCNLight(); main.type = .directional
        main.color = NSColor(white: 0.85, alpha: 1); main.castsShadow = true
        let mn = SCNNode(); mn.light = main
        mn.position = SCNVector3(bodyH, bodyH * 2, bodyH * 2)
        mn.look(at: SCNVector3(0, bodyH * 0.6, 0))
        scene.rootNode.addChildNode(mn)

        let fill = SCNLight(); fill.type = .directional
        fill.color = NSColor(white: 0.3, alpha: 1)
        let fn = SCNNode(); fn.light = fill
        fn.position = SCNVector3(-bodyH, bodyH, -bodyH)
        fn.look(at: SCNVector3(0, bodyH * 0.6, 0))
        scene.rootNode.addChildNode(fn)
    }

    private func addFloor(to scene: SCNScene) {
        let floor = SCNFloor()
        floor.reflectivity = 0.05
        floor.firstMaterial?.diffuse.contents = NSColor(white: 0.25, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
    }
}
