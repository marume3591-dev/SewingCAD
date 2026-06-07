//
//  SceneKitBodyView.swift
//  SewingCAD
//

import SwiftUI
import SceneKit
import CoreData

// MARK: - カメラプリセット

enum CameraPreset: String, CaseIterable {
    case front  = "正面"
    case back   = "背面"
    case side   = "横"
    case top    = "上"

    var position: SCNVector3 {
        switch self {
        case .front: return SCNVector3(0,  0.3,  1.8)
        case .back:  return SCNVector3(0,  0.3, -1.8)
        case .side:  return SCNVector3(1.8, 0.3,  0)
        case .top:   return SCNVector3(0,  2.2,  0.01)
        }
    }

    var icon: String {
        switch self {
        case .front: return "person.fill"
        case .back:  return "person.fill.turn.right"
        case .side:  return "person.fill.turn.left"
        case .top:   return "arrow.down.circle"
        }
    }
}

// MARK: - ボディカラーテーマ

enum BodyColorTheme: String, CaseIterable {
    case skin       = "肌色"
    case blueprint  = "設計図"
    case xray       = "透過"
    case monochrome = "モノクロ"

    var diffuse: NSColor {
        switch self {
        case .skin:       return NSColor(red: 0.95, green: 0.82, blue: 0.72, alpha: 1.0)
        case .blueprint:  return NSColor(red: 0.25, green: 0.55, blue: 0.90, alpha: 1.0)
        case .xray:       return NSColor(red: 0.50, green: 0.90, blue: 0.85, alpha: 0.45)
        case .monochrome: return NSColor(white: 0.80, alpha: 1.0)
        }
    }

    var opacity: CGFloat {
        switch self {
        case .xray: return 0.45
        default:    return 1.0
        }
    }

    var isTransparent: Bool { self == .xray }
}

// MARK: - SwiftUI ラッパー

struct SceneKitBodyView: NSViewRepresentable {
    @ObservedObject var viewModel: Body3DViewModel

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = context.coordinator.scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = NSColor(white: 0.12, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        context.coordinator.update(with: viewModel, in: scnView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        let scene = SCNScene()
        private var bodyNode: SCNNode?
        private var wireNode: SCNNode?
        private weak var viewModel: Body3DViewModel?

        init(viewModel: Body3DViewModel) {
            self.viewModel = viewModel
            super.init()
            setupScene()
        }

        private func setupScene() {
            scene.background.contents = NSColor(white: 0.12, alpha: 1)

            let cam = SCNNode()
            cam.camera = SCNCamera()
            cam.camera?.zFar = 100
            cam.camera?.zNear = 0.01
            cam.position = CameraPreset.front.position
            scene.rootNode.addChildNode(cam)

            let mainLight = SCNNode()
            mainLight.light = SCNLight()
            mainLight.light?.type = .directional
            mainLight.light?.color = NSColor(white: 1.0, alpha: 1)
            mainLight.light?.intensity = 1200
            mainLight.light?.castsShadow = true
            mainLight.light?.shadowMode = .deferred
            mainLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0)
            scene.rootNode.addChildNode(mainLight)

            let fillLight = SCNNode()
            fillLight.light = SCNLight()
            fillLight.light?.type = .directional
            fillLight.light?.color = NSColor(red: 0.6, green: 0.7, blue: 1.0, alpha: 1)
            fillLight.light?.intensity = 400
            fillLight.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 2, 0)
            scene.rootNode.addChildNode(fillLight)

            let backLight = SCNNode()
            backLight.light = SCNLight()
            backLight.light?.type = .directional
            backLight.light?.color = NSColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 1)
            backLight.light?.intensity = 300
            backLight.eulerAngles = SCNVector3(Float.pi / 6, Float.pi, 0)
            scene.rootNode.addChildNode(backLight)

            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.color = NSColor(white: 0.25, alpha: 1)
            scene.rootNode.addChildNode(ambientLight)

            setupGrid()
            if let vm = viewModel { update(with: vm, in: nil) }
        }

        private func setupGrid() {
            let gridSize: CGFloat = 2.0
            let divisions = 20
            let step = gridSize / CGFloat(divisions)
            var positions: [SCNVector3] = []
            var indices: [Int32] = []
            var idx: Int32 = 0
            let y: CGFloat = -0.75
            for i in 0...divisions {
                let t = -gridSize / 2 + CGFloat(i) * step
                positions.append(contentsOf: [
                    SCNVector3(t, y, -gridSize / 2), SCNVector3(t, y,  gridSize / 2),
                    SCNVector3(-gridSize / 2, y, t), SCNVector3( gridSize / 2, y, t),
                ])
                indices.append(contentsOf: [idx, idx+1, idx+2, idx+3])
                idx += 4
            }
            let geo = SCNGeometry(
                sources: [SCNGeometrySource(vertices: positions)],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .line)]
            )
            let mat = SCNMaterial()
            mat.diffuse.contents = NSColor(white: 0.30, alpha: 1)
            geo.materials = [mat]
            scene.rootNode.addChildNode(SCNNode(geometry: geo))
        }

        func update(with vm: Body3DViewModel, in scnView: SCNView?) {
            bodyNode?.removeFromParentNode()
            wireNode?.removeFromParentNode()

            let mesh = vm.currentMesh
            let geo  = mesh.buildGeometry(theme: vm.colorTheme)
            let node = SCNNode(geometry: geo)
            scene.rootNode.addChildNode(node)
            bodyNode = node

            if vm.showWireframe {
                let wGeo  = mesh.buildWireframeGeometry()
                let wNode = SCNNode(geometry: wGeo)
                scene.rootNode.addChildNode(wNode)
                wireNode = wNode
            }

            if vm.cameraPresetChanged, let scnView = scnView {
                vm.cameraPresetChanged = false
                let target = vm.cameraPreset.position
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.5
                scnView.pointOfView?.position = target
                scnView.pointOfView?.look(at: SCNVector3(0, 0.2, 0))
                SCNTransaction.commit()
            }
        }
    }
}

// MARK: - ViewModel

class Body3DViewModel: ObservableObject {
    @Published var currentMesh: BodyMesh
    @Published var showWireframe: Bool = false
    @Published var selectedMeasurement: MeasurementProfile? = nil
    @Published var appliedLabel: String = "標準体型"
    @Published var colorTheme: BodyColorTheme = .skin
    @Published var cameraPreset: CameraPreset = .front
    var cameraPresetChanged: Bool = false

    private let baseMesh: BodyMesh
    private let morphingEngine = MorphingEngine()

    init() {
        self.baseMesh    = StandardBodyGenerator.generate()
        self.currentMesh = StandardBodyGenerator.generate()
    }

    func apply(measurement: MeasurementProfile?) {
        if let m = measurement {
            currentMesh  = morphingEngine.morph(base: baseMesh, measurement: m)
            appliedLabel = m.name ?? "不明"
        } else {
            currentMesh  = morphingEngine.morphToStandard(base: baseMesh)
            appliedLabel = "標準体型"
        }
        selectedMeasurement = measurement
    }

    func resetToStandard() { apply(measurement: nil) }

    func setCamera(_ preset: CameraPreset) {
        cameraPreset        = preset
        cameraPresetChanged = true
        objectWillChange.send()
    }
}

// MARK: - BodyMesh 拡張（テーマ対応）

extension BodyMesh {
    func buildGeometry(theme: BodyColorTheme) -> SCNGeometry {
        var positions: [SCNVector3] = []
        var normals:   [SCNVector3] = []
        var uvCoords:  [CGPoint]    = []
        var indices:   [Int32]      = []

        for v in vertices {
            positions.append(SCNVector3(v.position.x, v.position.y, v.position.z))
            normals.append(SCNVector3(v.normal.x, v.normal.y, v.normal.z))
            uvCoords.append(CGPoint(x: CGFloat(v.uv.x), y: CGFloat(v.uv.y)))
        }
        for poly in polygons {
            indices.append(contentsOf: [Int32(poly.v0), Int32(poly.v1), Int32(poly.v2)])
        }

        let geo = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: uvCoords),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let mat = SCNMaterial()
        mat.diffuse.contents   = theme.diffuse
        mat.specular.contents  = NSColor.white
        mat.shininess          = theme == .blueprint ? 0.8 : 0.3
        mat.isDoubleSided      = true
        mat.transparency       = theme.opacity
        if theme.isTransparent {
            mat.blendMode           = .alpha
            mat.writesToDepthBuffer = false
        }
        geo.materials = [mat]
        return geo
    }
}

// MARK: - パネルビュー

struct Body3DPanel: View {
    @StateObject private var viewModel = Body3DViewModel()
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MeasurementProfile.createdAt, ascending: true)],
        animation: .default)
    private var measurements: FetchedResults<MeasurementProfile>

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("3D ボディ").font(.headline)
                Spacer()
                Toggle("ワイヤー", isOn: $viewModel.showWireframe)
                    .toggleStyle(.checkbox).font(.system(size: 12))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            SceneKitBodyView(viewModel: viewModel).frame(minHeight: 300)

            Divider()

            // カメラプリセット
            VStack(alignment: .leading, spacing: 6) {
                Text("視点").font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.horizontal, 12).padding(.top, 8)
                HStack(spacing: 6) {
                    ForEach(CameraPreset.allCases, id: \.self) { preset in
                        Button(action: { viewModel.setCamera(preset) }) {
                            VStack(spacing: 2) {
                                Image(systemName: preset.icon).font(.system(size: 14))
                                Text(preset.rawValue).font(.system(size: 9))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(viewModel.cameraPreset == preset
                                ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 6)
            }

            Divider()

            // カラーテーマ
            VStack(alignment: .leading, spacing: 6) {
                Text("表示スタイル").font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.horizontal, 12).padding(.top, 8)
                HStack(spacing: 6) {
                    ForEach(BodyColorTheme.allCases, id: \.self) { theme in
                        Button(action: { viewModel.colorTheme = theme }) {
                            HStack(spacing: 4) {
                                Circle().fill(Color(theme.diffuse))
                                    .frame(width: 10, height: 10)
                                    .opacity(theme == .xray ? 0.5 : 1.0)
                                Text(theme.rawValue).font(.system(size: 10))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(viewModel.colorTheme == theme
                                ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 6)
            }

            Divider()

            // 体型選択
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("体型").font(.system(size: 11)).foregroundColor(.secondary)
                        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)

                    bodyRow(
                        isSelected: viewModel.selectedMeasurement == nil,
                        title: "標準体型",
                        subtitle: "158cm  B83  W64  H91"
                    ) { viewModel.resetToStandard() }

                    ForEach(measurements) { m in
                        bodyRow(
                            isSelected: viewModel.selectedMeasurement?.objectID == m.objectID,
                            title: m.name ?? "",
                            subtitle: String(format: "B%.0f  W%.0f  H%.0f",
                                           m.value(for: 1), m.value(for: 3), m.value(for: 5))
                        ) { viewModel.apply(measurement: m) }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor).font(.system(size: 11))
                        Text("適用中: \(viewModel.appliedLabel)")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func bodyRow(isSelected: Bool, title: String, subtitle: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.accentColor).font(.system(size: 13))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12))
                    Text(subtitle).font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
