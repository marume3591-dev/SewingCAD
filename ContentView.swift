//
//  ContentView.swift
//  SewingCAD
//

import SwiftUI
import CoreData

struct ContentView: View {
    @StateObject private var canvasState = CanvasState()
    @State private var currentTool: Tool = .addPoint
    @State private var selectedPoint: PatternPoint? = nil
    @State private var selectedLine: PatternLine? = nil
    @State private var selectedCurveID: UUID? = nil
    @State private var mousePosition: CGPoint = .zero
    @State private var statusMessage: String = "点を追加するにはキャンバスをクリックしてください"
    @State private var scale: CGFloat = 1.0
    @State private var showMeasurements = false
    @State private var showSettings = false
    @State private var duplicateNameAlert = false
    @State private var originalLine: PatternLine? = nil
    @State private var editingAngle: String = ""
    @State private var editingLength: String = ""
    @State private var isLineEdited: Bool = false
    @State private var isSettingInitialValues: Bool = false
    @State private var rightPanelWidth: CGFloat = 200
    @State private var selectedArcID: UUID? = nil
    @State private var isArcEdited: Bool = false
    @State private var originalArc: ArcData? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 上ツールバー
            HStack(spacing: 12) {
                Button(action: {
                    canvasState.reset()
                    selectedPoint = nil
                    selectedLine = nil
                    statusMessage = "新規パターンを作成しました"
                }) {
                    Label("New", systemImage: "doc")
                }
                Button(action: {
                    PatternDocument.save(canvasState.toPatternData())
                }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                Button(action: {
                    PatternDocument.load { data in
                        guard let data = data else { return }
                        canvasState.load(from: data)
                        selectedPoint = nil
                        selectedLine = nil
                        statusMessage = "読み込みました"
                    }
                }) {
                    Label("Open", systemImage: "folder")
                }
                Divider().frame(height: 24)
                Button(action: {
                    canvasState.undo()
                    selectedPoint = nil
                    if let id = selectedLine?.id {
                        selectedLine = canvasState.lines.first(where: { $0.id == id })
                    }
                    isLineEdited = false
                    statusMessage = "元に戻しました"
                }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canvasState.canUndo)
                Button(action: {
                    canvasState.redo()
                    selectedPoint = nil
                    if let id = selectedLine?.id {
                        selectedLine = canvasState.lines.first(where: { $0.id == id })
                    }
                    isLineEdited = false
                    statusMessage = "やり直しました"
                }) {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!canvasState.canRedo)
                Divider().frame(height: 24)
                Button(action: {
                    scale = min(scale * 1.25, 10.0)
                    statusMessage = String(format: "ズーム: %.0f%%", scale * 100)
                }) {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                Button(action: {
                    scale = max(scale * 0.8, 0.1)
                    statusMessage = String(format: "ズーム: %.0f%%", scale * 100)
                }) {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                Divider().frame(height: 24)
                Text(String(format: "%.0f%%", scale * 100))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Divider().frame(height: 24)
                Button(action: {
                    PDFExporter.export(canvasState: canvasState, scale: scale)
                }) {
                    Label("PDF出力", systemImage: "doc.richtext")
                }
                Divider().frame(height: 24)
                Button(action: { showMeasurements.toggle() }) {
                    Label("計測", systemImage: "ruler")
                }
                .background(showMeasurements ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
                Button(action: { showSettings.toggle() }) {
                    Label("設定", systemImage: "gearshape")
                }
                .background(showSettings ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                // 左ツールバー
                VStack(spacing: 4) {
                    ToolButton(icon: "arrow.up.left.and.arrow.down.right",
                              label: "選択",
                              tool: .select,
                              currentTool: $currentTool)
                    ToolButton(icon: "circle.fill",
                              label: "点",
                              tool: .addPoint,
                              currentTool: $currentTool)
                    ToolButton(icon: "line.diagonal",
                              label: "線",
                              tool: .addLine,
                              currentTool: $currentTool)
                    ToolButton(icon: "scribble",
                              label: "曲線",
                              tool: .addCurve,
                              currentTool: $currentTool)
                    ToolButton(icon: "trash",
                              label: "削除",
                              tool: .delete,
                              currentTool: $currentTool)
                    ToolButton(icon: "selection.pin.in.out",
                              label: "範囲",
                              tool: .groupSelect,
                              currentTool: $currentTool)
                    ToolButton(icon: "arrow.left.and.right",
                              label: "平行",
                              tool: .parallel,
                              currentTool: $currentTool)
                    ToolButton(icon: "arrow.up.and.down",
                              label: "垂直",
                              tool: .perpendicular,
                              currentTool: $currentTool)
                    ToolButton(icon: "arrow.right.to.line",
                              label: "延長",
                              tool: .extend,
                              currentTool: $currentTool)
                    ToolButton(icon: "circle.dotted",
                              label: "中点",
                              tool: .midpoint,
                              currentTool: $currentTool)
                    ToolButton(icon: "circle",
                              label: "円弧",
                              tool: .arc,
                              currentTool: $currentTool)
                    ToolButton(icon: "text.cursor",
                              label: "テキスト",
                              tool: .text,
                              currentTool: $currentTool)
                    Spacer()
                }
                .padding(4)
                .frame(width: 50)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // メインキャンバス
                CanvasView(
                    canvasState: canvasState,
                    currentTool: $currentTool,
                    selectedPoint: $selectedPoint,
                    selectedLine: $selectedLine,
                    mousePosition: $mousePosition,
                    statusMessage: $statusMessage,
                    scale: $scale,
                    selectedCurveID: $selectedCurveID,
                    selectedArcID: $selectedArcID
                )
                .clipped()
                .onChange(of: selectedPoint) { _, _ in
                    duplicateNameAlert = false
                }
                .onChange(of: selectedLine?.id) { _, newID in
                    if let newID = newID,
                       let line = canvasState.lines.first(where: { $0.id == newID }) {
                        originalLine = line
                        isSettingInitialValues = true
                        editingAngle = String(format: "%.1f", line.angle)
                        editingLength = String(format: "%.2f", line.lengthCm)
                        isLineEdited = false
                        isSettingInitialValues = false
                    } else {
                        originalLine = nil
                        editingAngle = ""
                        editingLength = ""
                        isLineEdited = false
                    }
                }
                .onChange(of: selectedArcID) { _, newID in
                    if let newID = newID,
                       let arc = canvasState.arcs.first(where: { $0.id == newID }) {
                        originalArc = arc
                        isArcEdited = false
                    } else {
                        originalArc = nil
                        isArcEdited = false
                    }
                }
                // リサイズハンドル
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 4)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = rightPanelWidth - value.translation.width
                                rightPanelWidth = max(150, min(400, newWidth))
                            }
                    )
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }

                // 右パネル
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tool options")
                            .font(.headline)
                            .padding(.bottom, 4)

                        if selectedPoint != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("名前:")
                                        .font(.system(size: 13))
                                    TextField("", text: Binding(
                                        get: { selectedPoint?.name ?? "" },
                                        set: { newName in
                                            if let id = selectedPoint?.id,
                                               let index = canvasState.points.firstIndex(where: { $0.id == id }) {
                                                let isDuplicate = canvasState.points.contains {
                                                    $0.name == newName && $0.id != id
                                                }
                                                if isDuplicate {
                                                    duplicateNameAlert = true
                                                } else {
                                                    duplicateNameAlert = false
                                                    canvasState.points[index].name = newName
                                                    selectedPoint = canvasState.points[index]
                                                }
                                            }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 13))
                                }
                                if duplicateNameAlert {
                                    Text("⚠️ 同じ名前の点が存在します")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red)
                                }
                                HStack {
                                    Text("X:")
                                        .font(.system(size: 13))
                                    TextField("", text: Binding(
                                        get: { String(format: "%.1f", (selectedPoint?.position.x ?? 0) / 37.8) },
                                        set: { newValue in
                                            if let x = Double(newValue),
                                               let id = selectedPoint?.id,
                                               let index = canvasState.points.firstIndex(where: { $0.id == id }) {
                                                let oldPos = canvasState.points[index].position
                                                let newPos = CGPoint(x: CGFloat(x) * 37.8, y: oldPos.y)
                                                canvasState.points[index].position = newPos
                                                canvasState.lines = canvasState.lines.map { line in
                                                    var l = line
                                                    if l.startPoint == oldPos { l.startPoint = newPos }
                                                    if l.endPoint == oldPos { l.endPoint = newPos }
                                                    return l
                                                }
                                                selectedPoint = canvasState.points[index]
                                            }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 13))
                                    Text("cm")
                                        .font(.system(size: 13))
                                }
                                HStack {
                                    Text("Y:")
                                        .font(.system(size: 13))
                                    TextField("", text: Binding(
                                        get: { String(format: "%.1f", (selectedPoint?.position.y ?? 0) / 37.8) },
                                        set: { newValue in
                                            if let y = Double(newValue),
                                               let id = selectedPoint?.id,
                                               let index = canvasState.points.firstIndex(where: { $0.id == id }) {
                                                let oldPos = canvasState.points[index].position
                                                let newPos = CGPoint(x: oldPos.x, y: CGFloat(y) * 37.8)
                                                canvasState.points[index].position = newPos
                                                canvasState.lines = canvasState.lines.map { line in
                                                    var l = line
                                                    if l.startPoint == oldPos { l.startPoint = newPos }
                                                    if l.endPoint == oldPos { l.endPoint = newPos }
                                                    return l
                                                }
                                                selectedPoint = canvasState.points[index]
                                            }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 13))
                                    Text("cm")
                                        .font(.system(size: 13))
                                }
                                Button("座標確定") {
                                    canvasState.saveSnapshot()
                                }
                                .buttonStyle(.bordered)
                                .font(.system(size: 12))
                                
                                Button("複製") {
                                    if let point = selectedPoint {
                                        let offset = CGPoint(x: 20, y: 20)
                                        let newPoint = PatternPoint(
                                            position: CGPoint(
                                                x: point.position.x + offset.x,
                                                y: point.position.y + offset.y
                                            ),
                                            name: "\(point.name)'"
                                        )
                                        canvasState.points.append(newPoint)
                                        selectedPoint = newPoint
                                        canvasState.saveSnapshot()
                                        statusMessage = "\(point.name) を複製しました"
                                    }
                                }
                                .buttonStyle(.bordered)
                                .font(.system(size: 12))
                                
                            }
                        } else if let curveID = selectedCurveID,
                                  let curve = canvasState.curves.first(where: { $0.id == curveID }) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("曲線")
                                    .font(.headline)
                                    .padding(.bottom, 4)
                                Text("ノード数: \(curve.nodes.count)")
                                    .font(.system(size: 13))
                                Text(String(format: "概算長さ: %.2f cm", curveLength(curve)))
                                    .font(.system(size: 13))
                                Text("コントロールポイントを\nドラッグで形を編集")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        } else if let arcID = selectedArcID,
                                  let arc = canvasState.arcs.first(where: { $0.id == arcID }) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("円弧")
                                    .font(.headline)
                                    .padding(.bottom, 4)
                                Text(String(format: "半径: %.2f cm", arc.radius / 37.8))
                                    .font(.system(size: 13))
                                HStack {
                                    Text("半径:")
                                        .font(.system(size: 13))
                                    TextField("", text: Binding(
                                        get: { String(format: "%.2f", arc.radius / 37.8) },
                                        set: { newValue in
                                            if let r = Double(newValue),
                                               let index = canvasState.arcs.firstIndex(where: { $0.id == arcID }) {
                                                canvasState.arcs[index].radius = CGFloat(r) * 37.8
                                                isArcEdited = true
                                            }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 13))
                                    Text("cm")
                                        .font(.system(size: 13))
                                }
                                HStack {
                                    Text("開始角:")
                                        .font(.system(size: 13))
                                    TextField("", text: Binding(
                                        get: { String(format: "%.1f", arc.startAngle) },
                                        set: { newValue in
                                            if let a = Double(newValue),
                                               let index = canvasState.arcs.firstIndex(where: { $0.id == arcID }) {
                                                canvasState.arcs[index].startAngle = CGFloat(a)
                                                isArcEdited = true
                                            }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 13))
                                    Text("°")
                                        .font(.system(size: 13))
                                }
                                HStack {
                                    Text("終了角:")
                                        .font(.system(size: 13))
                                    TextField("", text: Binding(
                                        get: { String(format: "%.1f", arc.endAngle) },
                                        set: { newValue in
                                            if let a = Double(newValue),
                                               let index = canvasState.arcs.firstIndex(where: { $0.id == arcID }) {
                                                canvasState.arcs[index].endAngle = CGFloat(a)
                                                isArcEdited = true
                                            }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 13))
                                    Text("°")
                                        .font(.system(size: 13))
                                }
                                HStack {
                                    Button("確定") {
                                        canvasState.saveSnapshot()
                                        if let id = selectedArcID,
                                           let arc = canvasState.arcs.first(where: { $0.id == id }) {
                                            originalArc = arc
                                        }
                                        isArcEdited = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .font(.system(size: 12))
                                    .disabled(!isArcEdited)

                                    Button("キャンセル") {
                                        if let original = originalArc,
                                           let index = canvasState.arcs.firstIndex(where: { $0.id == original.id }) {
                                            canvasState.arcs[index] = original
                                            isArcEdited = false
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.system(size: 12))
                                    .disabled(!isArcEdited)
                                }
                            }
                        } else if selectedLine != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("線")
                                    .font(.headline)
                                    .padding(.bottom, 4)
                                Text(String(format: "長さ: %.2f cm", selectedLine?.lengthCm ?? 0))
                                    .font(.system(size: 13))
                                HStack {
                                    Text("角度:")
                                        .font(.system(size: 13))
                                    TextField("", text: $editingAngle)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 13))
                                        .onChange(of: editingAngle) { _, newValue in
                                            guard !isSettingInitialValues else { return }
                                            isLineEdited = true
                                            applyAngle(newValue)
                                        }
                                    Text("°")
                                        .font(.system(size: 13))
                                }
                                HStack {
                                    Text("長さ:")
                                        .font(.system(size: 13))
                                    TextField("", text: $editingLength)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 13))
                                        .onChange(of: editingLength) { _, newValue in
                                            guard !isSettingInitialValues else { return }
                                            isLineEdited = true
                                            applyLength(newValue)
                                        }
                                    Text("cm")
                                        .font(.system(size: 13))
                                }
                                HStack {
                                    Button("確定") {
                                        canvasState.saveSnapshot()
                                        if let id = selectedLine?.id,
                                           let line = canvasState.lines.first(where: { $0.id == id }) {
                                            originalLine = line
                                        }
                                        isLineEdited = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .font(.system(size: 12))
                                    .disabled(!isLineEdited)

                                    Button("キャンセル") {
                                        if let original = originalLine,
                                           let index = canvasState.lines.firstIndex(where: { $0.id == original.id }) {
                                            let currentEndPoint = canvasState.lines[index].endPoint
                                            canvasState.lines[index] = original
                                            selectedLine = original
                                            if let pointIndex = canvasState.points.firstIndex(where: { calcDistance($0.position, currentEndPoint) < 1.0 }) {
                                                canvasState.points[pointIndex].position = original.endPoint
                                            }
                                            isSettingInitialValues = true
                                            editingAngle = String(format: "%.1f", original.angle)
                                            editingLength = String(format: "%.2f", original.lengthCm)
                                            isLineEdited = false
                                            isSettingInitialValues = false
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.system(size: 12))
                                    .disabled(!isLineEdited)

                                    Button("起点と終点を入れ替え") {
                                        if let id = selectedLine?.id,
                                           let index = canvasState.lines.firstIndex(where: { $0.id == id }) {
                                            let temp = canvasState.lines[index].startPoint
                                            canvasState.lines[index].startPoint = canvasState.lines[index].endPoint
                                            canvasState.lines[index].endPoint = temp
                                            selectedLine = canvasState.lines[index]
                                            isSettingInitialValues = true
                                            editingAngle = String(format: "%.1f", canvasState.lines[index].angle)
                                            editingLength = String(format: "%.2f", canvasState.lines[index].lengthCm)
                                            isSettingInitialValues = false
                                            canvasState.saveSnapshot()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.system(size: 12))
                                }
                            }
                        } else {
                            Text("点または線を選択してください")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                        }

                        Spacer()
                    }
                    .padding(12)
                    .frame(width: rightPanelWidth)
                    .background(Color(NSColor.windowBackgroundColor))

                    // 計測テーブル
                    if showMeasurements {
                        Divider()
                        MeasurementView()
                            .environment(\.managedObjectContext,
                                         PersistenceController.shared.container.viewContext)
                            .frame(width: 280)
                            .background(Color(NSColor.windowBackgroundColor))
                    }

                    // 設定パネル
                    if showSettings {
                        Divider()
                        SettingsView(canvasState: canvasState)
                            .background(Color(NSColor.windowBackgroundColor))
                    }
                }
            }

            Divider()

            // 下部ステータスバー
            HStack {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "X: %.1f  Y: %.1f (cm)",
                           mousePosition.x / 37.8,
                           mousePosition.y / 37.8))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private func applyAngle(_ newValue: String) {
        guard let angle = Double(newValue),
              let id = selectedLine?.id,
              let index = canvasState.lines.firstIndex(where: { $0.id == id }) else { return }
        let oldEndPoint = canvasState.lines[index].endPoint
        canvasState.lines[index].update(angle: CGFloat(angle), lengthCm: canvasState.lines[index].lengthCm)
        let newEndPoint = canvasState.lines[index].endPoint
        if let pointIndex = canvasState.points.firstIndex(where: { calcDistance($0.position, oldEndPoint) < 1.0 }) {
            canvasState.points[pointIndex].position = newEndPoint
        }
        selectedLine = canvasState.lines[index]
    }

    private func applyLength(_ newValue: String) {
        guard let length = Double(newValue),
              let id = selectedLine?.id,
              let index = canvasState.lines.firstIndex(where: { $0.id == id }) else { return }
        let oldEndPoint = canvasState.lines[index].endPoint
        canvasState.lines[index].update(angle: canvasState.lines[index].angle, lengthCm: CGFloat(length))
        let newEndPoint = canvasState.lines[index].endPoint
        if let pointIndex = canvasState.points.firstIndex(where: { calcDistance($0.position, oldEndPoint) < 1.0 }) {
            canvasState.points[pointIndex].position = newEndPoint
        }
        selectedLine = canvasState.lines[index]
    }

    private func curveLength(_ curve: CurveData) -> CGFloat {
        var length: CGFloat = 0
        let steps = 50
        for i in 0..<curve.nodes.count - 1 {
            let from = curve.nodes[i]
            let to = curve.nodes[i + 1]
            var prev = from.point
            for j in 1...steps {
                let t = CGFloat(j) / CGFloat(steps)
                let mt = 1 - t
                let p = CGPoint(
                    x: mt*mt*mt*from.point.x + 3*mt*mt*t*from.controlPoint2.x + 3*mt*t*t*to.controlPoint1.x + t*t*t*to.point.x,
                    y: mt*mt*mt*from.point.y + 3*mt*mt*t*from.controlPoint2.y + 3*mt*t*t*to.controlPoint1.y + t*t*t*to.point.y
                )
                length += calcDistance(prev, p)
                prev = p
            }
        }
        return length / 37.8
    }

    private func calcDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}

struct ToolButton: View {
    let icon: String
    let label: String
    let tool: Tool
    @Binding var currentTool: Tool

    var body: some View {
        Button(action: {
            currentTool = tool
        }) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(width: 42, height: 42)
            .background(currentTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext,
                     PersistenceController.preview.container.viewContext)
}
