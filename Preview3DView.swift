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

    // Coordinatorでタスクの重複実行を防ぐ
    class Coordinator {
        var buildTask: DispatchWorkItem?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        // 空シーンをまず表示
        let empty = SCNScene()
        let cam = makeCamera()
        empty.rootNode.addChildNode(cam)
        scnView.scene = empty
        scnView.pointOfView = cam
        // バックグラウンドでシーン構築
        scheduleBuild(into: scnView, coordinator: context.coordinator)
        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        scheduleBuild(into: scnView, coordinator: context.coordinator)
    }

    private func scheduleBuild(into scnView: SCNView, coordinator: Coordinator) {
        // 前回のタスクをキャンセル
        coordinator.buildTask?.cancel()

        // ① メインスレッドでCoreDataから値を読み取る（ここは安全）
        let stdM = makeStandardMeasurement()

        let task = DispatchWorkItem {
            // ② バックグラウンドでSCNScene構築（CoreDataオブジェクトは使わない）
            let scene = buildSceneWith(stdM: stdM)

            DispatchQueue.main.async {
                guard !(coordinator.buildTask?.isCancelled ?? true) else { return }
                // ③ メインスレッドでSCNViewに反映
                let pov = scnView.pointOfView
                if let pov = pov {
                    scene.rootNode.addChildNode(pov)
                    scnView.scene = scene
                    scnView.pointOfView = pov
                } else {
                    let cam = makeCamera()
                    scene.rootNode.addChildNode(cam)
                    scnView.scene = scene
                    scnView.pointOfView = cam
                }
            }
        }

        coordinator.buildTask = task
        DispatchQueue.global(qos: .userInitiated).async(execute: task)
    }
    // ── シーン構築（CoreData不使用・スレッドセーフ）──

    func buildSceneWith(stdM: StandardMeasurement) -> SCNScene {
        let scene = SCNScene()
        addLights(to: scene)
        addFloor(to: scene)

        // StandardBodyGenerator でメッシュ生成
        let mesh = StandardBodyGenerator.generate(m: stdM)

        // MorphingEngineはBodyMesh(純粋なSwift値型)のみ操作するのでスレッドセーフ
        let engine = MorphingEngine()
        let finalMesh = engine.morph(base: mesh, stdM: stdM)

        // ボディノード（肌色マテリアル）
        let bodyGeo  = finalMesh.buildGeometry(theme: BodyMesh.ColorTheme.skin)
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.name = "body"
        // BodyMeshの座標系: ウエスト(床から111cm)=Y0原点
        // ワールドY=0が床になるよう 111cm = 1.11m 上に移動
        let waistOffsetY: CGFloat = 1.11
        bodyNode.position = SCNVector3(0, waistOffsetY, 0)
        scene.rootNode.addChildNode(bodyNode)

        // パターンノード（PatternMeshBuilder内でwaistOffsetY適用済みなので追加オフセット不要）
        for placement in placements {
            let nodes = makePatternNodes(for: placement, mesh: finalMesh, stdM: stdM)
            for node in nodes {
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

    /// パターン1枚からボディ曲面に貼り付いた複数SCNNodeを生成する（方法B）
    private func makePatternNodes(
        for placement: PartPlacement,
        mesh: BodyMesh,
        stdM: StandardMeasurement
    ) -> [SCNNode] {
        let data = placement.patternData
        let bbox = PatternMeshBuilder.boundingBox(of: data)
        guard bbox.width > 1, bbox.height > 1 else { return [] }
        let image = renderPatternImage(from: data, bbox: bbox)

        // BodyMeshの座標系: ウエスト(床から111cm)=Y0原点
        let waistOffsetY: CGFloat = 1.11

        return PatternMeshBuilder.build(
            patternData: data,
            bodyMesh: mesh,
            partType: placement.part.type,
            stdM: stdM,
            waistOffsetY: waistOffsetY,
            image: image
        )
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

    // ── 標準計測値生成 ────────────────────────────────────

    func makeStandardMeasurement() -> StandardMeasurement {
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
        // makeStandardMeasurement()はCoreDataアクセスのためメインスレッドで実行済み
        let meshView = MeshSceneKitView(
            placements: placements,
            measurement: measurement,
            patternOpacity: patternOpacity
        )
        let stdM = meshView.makeStandardMeasurement()  // メインスレッドで安全
        v.scene = meshView.buildSceneWith(stdM: stdM)
        return v
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        let meshView = MeshSceneKitView(
            placements: placements,
            measurement: measurement,
            patternOpacity: patternOpacity
        )
        let stdM = meshView.makeStandardMeasurement()  // メインスレッドで安全
        nsView.scene = meshView.buildSceneWith(stdM: stdM)
    }
}
