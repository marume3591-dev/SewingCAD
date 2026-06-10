//
//  Preview3DView.swift
//  SewingCAD
//
//  3Dプレビュー: StandardBodyGenerator メッシュを使用、
//  パターンはボディの実際の径・高さに合わせて配置。
//

import SwiftUI
import SceneKit
import CoreData

// MARK: - パーツ配置情報

struct PartPlacement {
    let patternData: PatternData
    let part: PatternPart
}

// MARK: - Preview3DView

struct Preview3DView: View {
    let canvasState: CanvasState
    @ObservedObject var projectManager: ProjectManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MeasurementProfile.createdAt, ascending: true)],
        animation: .default)
    private var measurements: FetchedResults<MeasurementProfile>

    @State private var selectedMeasurementID: NSManagedObjectID? = nil
    @State private var showPatterns: Bool = true

    private var selectedMeasurement: MeasurementProfile? {
        guard let id = selectedMeasurementID else { return measurements.first }
        return measurements.first { $0.objectID == id }
    }

    private func buildPlacements() -> [PartPlacement] {
        if let project = projectManager.currentProject, !project.parts.isEmpty {
            return project.parts.compactMap { part -> PartPlacement? in
                let data: PatternData
                if projectManager.activePartID == part.id {
                    data = canvasState.toPatternData()
                } else {
                    guard let d = projectManager.loadPatternData(for: part.id) else { return nil }
                    data = d
                }
                guard !data.lines.isEmpty || !data.curves.isEmpty || !data.arcs.isEmpty else { return nil }
                return PartPlacement(patternData: data, part: part)
            }
        }
        let data = canvasState.toPatternData()
        guard !data.lines.isEmpty || !data.curves.isEmpty || !data.arcs.isEmpty else { return [] }
        let fallback = PatternPart(name: "パターン", type: .bodiceFront, fileName: "")
        return [PartPlacement(patternData: data, part: fallback)]
    }

    var body: some View {
        let placements = showPatterns ? buildPlacements() : []

        VStack(spacing: 0) {
            // ツールバー
            HStack(spacing: 12) {
                Text("3D プレビュー").font(.headline)
                Divider().frame(height: 20)

                if measurements.isEmpty {
                    Text("計測データなし")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                } else {
                    Picker("ボディ", selection: Binding(
                        get: { selectedMeasurementID ?? measurements.first?.objectID },
                        set: { selectedMeasurementID = $0 }
                    )) {
                        ForEach(measurements) { m in
                            Text(m.name ?? "").tag(Optional(m.objectID))
                        }
                    }
                    .pickerStyle(.menu).frame(width: 140).font(.system(size: 12))
                }

                Divider().frame(height: 20)
                Toggle("パターンを表示", isOn: $showPatterns).font(.system(size: 12))
                Spacer()
                Text("ドラッグ: 回転 / ピンチ: ズーム / 右ドラッグ: 移動")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if showPatterns && placements.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24)).foregroundColor(.secondary)
                    Text("表示できるパターンがありません")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                    Text("キャンバスに線・曲線を描くか、プロジェクトのパーツを選択してください")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.underPageBackgroundColor))
            } else {
                MeshSceneKitView(
                    placements: placements,
                    measurement: selectedMeasurement,
                    patternOpacity: 1.0
                )
            }

            Divider()

            // ステータスバー
            HStack {
                if let m = selectedMeasurement {
                    Text(String(format: "身長: %.0fcm  バスト: %.0fcm  ウエスト: %.0fcm  ヒップ: %.0fcm",
                               m.value(for: 19), m.value(for: 1), m.value(for: 3), m.value(for: 5)))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                } else {
                    Text("標準体型 158cm B83 W64 H91")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                if placements.isEmpty {
                    Text("パターン: なし").font(.system(size: 11)).foregroundColor(.secondary)
                } else {
                    Text("表示中: " + placements.map { $0.part.name }.joined(separator: " / "))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

// MARK: - SceneKit View（メッシュ対応版）

struct MeshSceneKitView: NSViewRepresentable {
    let placements: [PartPlacement]
    let measurement: MeasurementProfile?
    var patternOpacity: Double = 1.0

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        scnView.scene = buildScene()
        let cam = makeCamera()
        scnView.scene?.rootNode.addChildNode(cam)
        scnView.pointOfView = cam
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

    // ── シーン構築（internal: SceneKitView互換ラッパーからも使用）──

    func buildScene() -> SCNScene {
        let scene = SCNScene()
        addLights(to: scene)
        addFloor(to: scene)

        // StandardBodyGenerator でメッシュ生成
        let stdM = makeStandardMeasurement()
        let mesh = StandardBodyGenerator.generate(m: stdM)

        // モーフィング適用
        let finalMesh: BodyMesh
        if let profile = measurement {
            let engine = MorphingEngine()
            finalMesh = engine.morph(base: mesh, measurement: profile)
        } else {
            finalMesh = mesh
        }

        // ボディノード（肌色マテリアル）
        let bodyGeo  = finalMesh.buildGeometry(theme: .skin)
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.name = "body"
        // ウエストY=0原点 → ワールドY=0が足底になるようにオフセット
        // 足底ローカルY = (3cm - 111cm) / 100 = -1.08m
        // waistOffsetY = waistHeight/100 だと足底がY=-0.10mになるため +0.10m 補正
        let floorOffset: CGFloat = 0.10   // 足底を床(Y=0)に合わせる補正
        let waistOffsetY = CGFloat(stdM.waistHeight / 100.0) + floorOffset
        bodyNode.position = SCNVector3(0, waistOffsetY, 0)
        scene.rootNode.addChildNode(bodyNode)

        // パターンノード（ボディと同じオフセットを適用）
        for placement in placements {
            let nodes = makePatternNodes(for: placement, mesh: finalMesh, stdM: stdM)
            for node in nodes {
                node.position.y += waistOffsetY
                scene.rootNode.addChildNode(node)
            }
        }

        return scene
    }

    private func makeCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.01
        camera.zFar  = 100
        let node = SCNNode()
        node.camera  = camera
        node.name    = "mainCamera"
        // 身長の0.55 を注視点に、前方 2.0m
        let h = CGFloat(makeStandardMeasurement().height) / 100.0
        node.position = SCNVector3(0, h * 0.52, h * 1.85)
        node.look(at: SCNVector3(0, h * 0.52, 0))
        return node
    }

    // ── パターンノード生成（ボディ形状に合わせた配置）──────

    // 旧シグネチャ互換（内部では makePatternNodes を呼ぶ）
    private func makePatternNode(
        for placement: PartPlacement,
        mesh: BodyMesh,
        stdM: StandardMeasurement
    ) -> SCNNode? {
        makePatternNodes(for: placement, mesh: mesh, stdM: stdM).first
    }

    /// パターン1枚から左右ミラーを含む複数SCNNodeを生成する
    private func makePatternNodes(
        for placement: PartPlacement,
        mesh: BodyMesh,
        stdM: StandardMeasurement
    ) -> [SCNNode] {
        let data = placement.patternData
        let bbox = boundingBox(of: data)
        guard bbox.width > 1, bbox.height > 1 else { return [] }
        guard let image = renderPatternImage(from: data, bbox: bbox) else { return [] }

        let unitPerPx: CGFloat = 1.0 / 37.8 / 100.0   // 1px → cm → m
        let planeW = CGFloat(bbox.width  * unitPerPx)
        let planeH = CGFloat(bbox.height * unitPerPx)

        // 共通マテリアル
        let mat = SCNMaterial()
        mat.diffuse.contents    = image
        mat.isDoubleSided       = true
        mat.transparencyMode    = .default
        mat.writesToDepthBuffer = false
        mat.transparency        = (patternOpacity < 0.01) ? 1.0 : CGFloat(patternOpacity)

        func makePlaneNode(name: String) -> SCNNode {
            let plane = SCNPlane(width: planeW, height: planeH)
            plane.materials = [mat]
            let n = SCNNode(geometry: plane)
            n.name = name
            return n
        }

        let type = placement.part.type

        // メッシュ実寸からポーズ計算（Z オフセットを 0.02m に拡大）
        let pose = meshBasedPose(
            for: type, mesh: mesh, stdM: stdM,
            planeW: Float(planeW), planeH: Float(planeH)
        )

        switch type {
        // ── 前後身頃・スカート：右半身＋左半身ミラー ──
        case .bodiceFront, .bodiceBack, .skirtFront, .skirtBack:
            // 右半身: 中心線(X=0)から右へ planeW/2 だけオフセット
            let right = makePlaneNode(name: "pattern_\(type.rawValue)_R")
            right.position    = SCNVector3(planeW / 2, pose.position.y, pose.position.z)
            right.eulerAngles = pose.eulerAngles

            // 左半身: X軸ミラー（scale.x = -1 で画像も反転）
            let left = makePlaneNode(name: "pattern_\(type.rawValue)_L")
            left.position    = SCNVector3(-(planeW / 2), pose.position.y, pose.position.z)
            left.eulerAngles = pose.eulerAngles
            left.scale       = SCNVector3(-1, 1, 1)
            return [right, left]

        // ── 袖：左腕(pose)＋右腕(X反転) ──
        case .sleeveFront:
            let leftArm = makePlaneNode(name: "pattern_sleeve_L")
            leftArm.position    = pose.position          // X < 0（左腕外側）
            leftArm.eulerAngles = pose.eulerAngles       // Y軸90°のみ

            let rightArm = makePlaneNode(name: "pattern_sleeve_R")
            rightArm.position    = SCNVector3(-pose.position.x, pose.position.y, pose.position.z)
            rightArm.eulerAngles = SCNVector3(pose.eulerAngles.x, -pose.eulerAngles.y, 0)
            return [leftArm, rightArm]

        // ── その他：1枚 ──
        default:
            let node = makePlaneNode(name: "pattern_\(type.rawValue)")
            node.position    = pose.position
            node.eulerAngles = pose.eulerAngles
            return [node]
        }
    }

    // ── メッシュ実寸ベースのポーズ計算 ─────────────────────

    private struct Pose {
        var position: SCNVector3
        var eulerAngles: SCNVector3
    }

    private func meshBasedPose(
        for type: PatternPartType,
        mesh: BodyMesh,
        stdM: StandardMeasurement,
        planeW: Float, planeH: Float
    ) -> Pose {
        // stdM から直接ボディ座標を算出
        // ウエスト = Y原点(0)、上方向が+Y

        let wH = stdM.waistHeight       // ウエスト床高 cm
        let h  = stdM.height            // 身長 cm

        // 肩線Y（ウエスト基準）
        // StandardBodyData の肩スライス = 床から141cm、ウエスト原点 = 111cm
        // ローカルY = (141 - 111) / 100 = 0.30m、身長スケールで補正
        let shoulderY = CGFloat((141.0 - 111.0) / 100.0 * Double(h / 158.0))
        let waistY:   CGFloat = 0.0

        // 前後Z: StandardBodyData の実測値ベース（bust最大rz=13.5cm, hip=13.2cm）
        let zGap:      CGFloat = 0.025
        let bustFrontZ = CGFloat(stdM.bust  * 0.162 / 100.0) + zGap   // ≈ bust周/6.17 = 前後半径
        let hipFrontZ  = CGFloat(stdM.hip   * 0.145 / 100.0) + zGap

        // 片側肩幅X
        let shoulderX = CGFloat(stdM.shoulder / 2.0 / 100.0) + 0.01

        let ph = CGFloat(planeH)

        switch type {
        case .bodiceFront:
            // 中央X=0、上端を肩線に合わせる
            return Pose(position: SCNVector3(0, shoulderY - ph * 0.5, bustFrontZ),
                        eulerAngles: SCNVector3(0, 0, 0))
        case .bodiceBack:
            return Pose(position: SCNVector3(0, shoulderY - ph * 0.5, -bustFrontZ),
                        eulerAngles: SCNVector3(0, Float.pi, 0))
        case .sleeveFront:
            // 肩の外側に縦置き（Y軸90°回転）、腕の傾きはなし（垂直のほうが自然）
            let sleeveX = shoulderX + CGFloat(planeW) * 0.5
            return Pose(position: SCNVector3(-sleeveX, shoulderY - ph * 0.5, 0),
                        eulerAngles: SCNVector3(0, Float.pi / 2, 0))
        case .skirtFront:
            return Pose(position: SCNVector3(0, waistY - ph * 0.5, hipFrontZ),
                        eulerAngles: SCNVector3(0, 0, 0))
        case .skirtBack:
            return Pose(position: SCNVector3(0, waistY - ph * 0.5, -hipFrontZ),
                        eulerAngles: SCNVector3(0, Float.pi, 0))
        case .pants:
            return Pose(position: SCNVector3(0, waistY - ph * 0.5, hipFrontZ),
                        eulerAngles: SCNVector3(0, 0, 0))
        case .collar:
            let neckZ = CGFloat(stdM.neck * 0.16 / 100.0) + zGap
            return Pose(position: SCNVector3(0, shoulderY + 0.07, neckZ),
                        eulerAngles: SCNVector3(Float.pi * 0.15, 0, 0))
        case .cuff:
            let cuffX = shoulderX + CGFloat(planeW) * 0.5
            return Pose(position: SCNVector3(-cuffX, shoulderY - ph * 1.5, 0),
                        eulerAngles: SCNVector3(0, Float.pi / 2, 0))
        case .waistband:
            let wbZ = CGFloat(stdM.waist * 0.16 / 100.0)
            return Pose(position: SCNVector3(0, waistY, wbZ),
                        eulerAngles: SCNVector3(Float.pi / 2, 0, 0))
        case .other:
            return Pose(position: SCNVector3(shoulderX * 2.2, waistY, 0),
                        eulerAngles: SCNVector3(0, Float.pi / 2, 0))
        }
    }
    // ── パターン画像レンダリング ────────────────────────────

    private func renderPatternImage(from data: PatternData, bbox: CGRect) -> NSImage? {
        let texSize = CGSize(width: 512, height: 512)
        let scaleX  = texSize.width  / bbox.width
        let scaleY  = texSize.height / bbox.height

        func tx(_ x: CGFloat) -> CGFloat { (x - bbox.minX) * scaleX }
        func ty(_ y: CGFloat) -> CGFloat { texSize.height - (y - bbox.minY) * scaleY }

        let image = NSImage(size: texSize)
        image.lockFocus()

        // 背景（半透明白）
        NSColor(white: 1.0, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: texSize), xRadius: 8, yRadius: 8).fill()

        // 枠線
        NSColor(white: 0.6, alpha: 0.4).setStroke()
        let border = NSBezierPath(roundedRect: NSRect(x: 1, y: 1,
                                                     width: texSize.width-2, height: texSize.height-2),
                                  xRadius: 8, yRadius: 8)
        border.lineWidth = 1.5; border.stroke()

        // 直線（濃い青）
        NSColor(red: 0.08, green: 0.28, blue: 0.80, alpha: 1.0).setStroke()
        for line in data.lines {
            let path = NSBezierPath(); path.lineWidth = 4.0
            path.move(to: CGPoint(x: tx(line.x1), y: ty(line.y1)))
            path.line(to: CGPoint(x: tx(line.x2), y: ty(line.y2)))
            path.stroke()
        }

        // 曲線（赤）
        NSColor(red: 0.82, green: 0.18, blue: 0.18, alpha: 1.0).setStroke()
        for curve in data.curves {
            guard curve.nodes.count >= 2 else { continue }
            let path = NSBezierPath(); path.lineWidth = 4.0
            path.move(to: CGPoint(x: tx(curve.nodes[0].x), y: ty(curve.nodes[0].y)))
            for i in 0..<curve.nodes.count - 1 {
                let f = curve.nodes[i], t = curve.nodes[i+1]
                path.curve(to:         CGPoint(x: tx(t.x),    y: ty(t.y)),
                           controlPoint1: CGPoint(x: tx(f.cp2x), y: ty(f.cp2y)),
                           controlPoint2: CGPoint(x: tx(t.cp1x), y: ty(t.cp1y)))
            }
            path.stroke()
        }

        // 円弧（緑）
        NSColor(red: 0.10, green: 0.60, blue: 0.28, alpha: 1.0).setStroke()
        for arc in data.arcs {
            let path = NSBezierPath(); path.lineWidth = 4.0
            path.appendArc(withCenter: CGPoint(x: tx(arc.cx), y: ty(arc.cy)),
                           radius: arc.radius * (scaleX + scaleY) / 2,
                           startAngle: -arc.startAngle, endAngle: -arc.endAngle, clockwise: true)
            path.stroke()
        }

        image.unlockFocus()
        return image
    }

    // ── バウンディングボックス ──────────────────────────────

    private func boundingBox(of data: PatternData) -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        func expand(_ x: CGFloat, _ y: CGFloat) {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }
        for l in data.lines  { expand(l.x1, l.y1); expand(l.x2, l.y2) }
        for c in data.curves { for n in c.nodes { expand(n.x, n.y) } }
        for a in data.arcs   {
            expand(a.cx - a.radius, a.cy - a.radius)
            expand(a.cx + a.radius, a.cy + a.radius)
        }
        guard minX != .infinity else { return .zero }
        let pad: CGFloat = 20
        return CGRect(x: minX-pad, y: minY-pad,
                      width: maxX-minX+pad*2, height: maxY-minY+pad*2)
    }

    // ── 標準計測値生成 ────────────────────────────────────

    private func makeStandardMeasurement() -> StandardMeasurement {
        var s = StandardMeasurement()
        guard let profile = measurement else { return s }
        func v(_ id: Int) -> Float {
            let r = Float(profile.value(for: id)); return r > 0 ? r : 0
        }
        if v(19) > 0 { s.height      = v(19) }
        if v(1)  > 0 { s.bust        = v(1)  }
        if v(3)  > 0 { s.waist       = v(3)  }
        if v(5)  > 0 { s.hip         = v(5)  }
        if v(15) > 0 { s.shoulder    = v(15) }
        if v(12) > 0 { s.neck        = v(12) }
        if v(2)  > 0 { s.underBust   = v(2)  }
        if v(21) > 0 { s.backLength  = v(21) }
        if v(25) > 0 { s.sleeveLen   = v(25) }
        if v(7)  > 0 { s.upperArm    = v(7)  }
        if v(9)  > 0 { s.wrist       = v(9)  }
        if v(13) > 0 { s.thigh       = v(13) }
        if v(14) > 0 { s.calf        = v(14) }
        if v(30) > 0 { s.inseam      = v(30) }
        if v(26) > 0 { s.waistHeight = v(26) }
        if v(27) > 0 { s.hipHeight   = v(27) }
        return s
    }

    // ── ライト・フロア ────────────────────────────────────

    private func addLights(to scene: SCNScene) {
        let h = CGFloat(makeStandardMeasurement().height) / 100.0

        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(white: 0.35, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let main = SCNNode(); main.light = SCNLight()
        main.light?.type = .directional
        main.light?.color = NSColor(white: 0.85, alpha: 1)
        main.light?.castsShadow = true
        main.light?.shadowMode  = .deferred
        main.position = SCNVector3(h, h * 2, h * 2)
        main.look(at: SCNVector3(0, h * 0.6, 0))
        scene.rootNode.addChildNode(main)

        let fill = SCNNode(); fill.light = SCNLight()
        fill.light?.type  = .directional
        fill.light?.color = NSColor(red: 0.55, green: 0.65, blue: 1.0, alpha: 1)
        fill.light?.intensity = 400
        fill.position = SCNVector3(-h, h, -h)
        fill.look(at: SCNVector3(0, h * 0.6, 0))
        scene.rootNode.addChildNode(fill)
    }

    private func addFloor(to scene: SCNScene) {
        let floor = SCNFloor()
        floor.reflectivity = 0.05
        floor.firstMaterial?.diffuse.contents = NSColor(white: 0.25, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
    }
}

// MARK: - 旧 SceneKitView の互換ラッパー
// ContentView 等が SceneKitView(placements:measurement:patternOpacity:) で呼ぶ場合のため

// MARK: - 旧 SceneKitView 互換ラッパー
// ContentView 等が SceneKitView(placements:measurement:patternOpacity:) で呼ぶ場合のため

struct SceneKitView: NSViewRepresentable {
    let placements: [PartPlacement]
    let measurement: MeasurementProfile?
    var patternOpacity: Double = 1.0

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = true
        v.backgroundColor = NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
        v.scene = MeshSceneKitView(
            placements: placements,
            measurement: measurement,
            patternOpacity: patternOpacity
        ).buildScene()
        return v
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.scene = MeshSceneKitView(
            placements: placements,
            measurement: measurement,
            patternOpacity: patternOpacity
        ).buildScene()
    }
}
