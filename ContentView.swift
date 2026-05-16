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
    @State private var pdfOutputMode: PDFOutputMode = .finishedLine
    @State private var resetOffsetTrigger: Bool = false

    // フェーズ2用パネル参照（CanvasViewの状態をミラー）
    @State private var gradingPointForPanel: PatternPoint? = nil
    @State private var seamOverrideLineForPanel: PatternLine? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 上ツールバー
            HStack(spacing: 12) {
                Button(action: {
                    canvasState.reset()
                    selectedPoint = nil; selectedLine = nil
                    statusMessage = "新規パターンを作成しました"
                }) { Label("New", systemImage: "doc") }
                Button(action: { PatternDocument.save(canvasState.toPatternData()) }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                Button(action: {
                    PatternDocument.load { data in
                        guard let data = data else { return }
                        canvasState.load(from: data)
                        selectedPoint = nil; selectedLine = nil; statusMessage = "読み込みました"
                    }
                }) { Label("Open", systemImage: "folder") }
                Divider().frame(height: 24)
                Button(action: {
                    canvasState.undo(); selectedPoint = nil
                    if let id = selectedLine?.id { selectedLine = canvasState.lines.first(where: { $0.id == id }) }
                    isLineEdited = false; statusMessage = "元に戻しました"
                }) { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!canvasState.canUndo)
                Button(action: {
                    canvasState.redo(); selectedPoint = nil
                    if let id = selectedLine?.id { selectedLine = canvasState.lines.first(where: { $0.id == id }) }
                    isLineEdited = false; statusMessage = "やり直しました"
                }) { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(!canvasState.canRedo)
                Divider().frame(height: 24)
                Button(action: {
                    scale = min(scale * 1.25, 10.0)
                    statusMessage = String(format: "ズーム: %.0f%%", scale * 100)
                }) { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                Button(action: {
                    scale = max(scale * 0.8, 0.1)
                    statusMessage = String(format: "ズーム: %.0f%%", scale * 100)
                }) { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                Button(action: {
                    scale = 1.0
                    resetOffsetTrigger.toggle()
                    statusMessage = "原点に戻りました"
                }) {
                    Label("原点", systemImage: "house")
                }
                Divider().frame(height: 24)
                Text(String(format: "%.0f%%", scale * 100))
                    .font(.system(size: 12)).foregroundColor(.secondary)
                Divider().frame(height: 24)
                Button(action: {
                    PDFExporter.export(canvasState: canvasState, scale: scale, mode: pdfOutputMode)
                }) {
                    Label("PDF出力", systemImage: "doc.richtext")
                }
                Picker("", selection: $pdfOutputMode) {
                    ForEach(PDFOutputMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Button(action: {
                    DXFExporter.export(canvasState: canvasState)
                }) {
                    Label("DXF出力", systemImage: "square.and.arrow.up")
                }
                Divider().frame(height: 24)
                Button(action: { showMeasurements.toggle() }) { Label("計測", systemImage: "ruler") }
                    .background(showMeasurements ? Color.accentColor.opacity(0.2) : Color.clear).cornerRadius(6)
                Button(action: { showSettings.toggle() }) { Label("設定", systemImage: "gearshape") }
                    .background(showSettings ? Color.accentColor.opacity(0.2) : Color.clear).cornerRadius(6)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                // 左ツールバー
                ScrollView {
                    VStack(spacing: 4) {
                        // 基本ツール
                        toolSectionLabel("基本")
                        ToolButton(icon: "arrow.up.left.and.arrow.down.right", label: "選択",   tool: .select,        currentTool: $currentTool)
                        ToolButton(icon: "circle.fill",                         label: "点",     tool: .addPoint,      currentTool: $currentTool)
                        ToolButton(icon: "line.diagonal",                       label: "線",     tool: .addLine,       currentTool: $currentTool)
                        ToolButton(icon: "scribble",                            label: "曲線",   tool: .addCurve,      currentTool: $currentTool)
                        ToolButton(icon: "trash",                               label: "削除",   tool: .delete,        currentTool: $currentTool)
                        ToolButton(icon: "selection.pin.in.out",                label: "範囲",   tool: .groupSelect,   currentTool: $currentTool)

                        Divider().padding(.vertical, 2)
                        // 作図補助
                        toolSectionLabel("作図")
                        ToolButton(icon: "arrow.left.and.right",                label: "平行",   tool: .parallel,      currentTool: $currentTool)
                        ToolButton(icon: "arrow.up.and.down",                   label: "垂直",   tool: .perpendicular, currentTool: $currentTool)
                        ToolButton(icon: "arrow.right.to.line",                 label: "延長",   tool: .extend,        currentTool: $currentTool)
                        ToolButton(icon: "circle.dotted",                       label: "中点",   tool: .midpoint,      currentTool: $currentTool)
                        ToolButton(icon: "circle",                              label: "円弧",   tool: .arc,           currentTool: $currentTool)
                        ToolButton(icon: "text.cursor",                         label: "テキスト", tool: .text,         currentTool: $currentTool)

                        Divider().padding(.vertical, 2)
                        // フェーズ2
                        toolSectionLabel("パターン")
                        ToolButton(icon: "rectangle.lefthalf.inset.filled",     label: "鏡像",    tool: .mirror,       currentTool: $currentTool)
                        ToolButton(icon: "minus.circle",                         label: "ノッチ",  tool: .notch,        currentTool: $currentTool)
                        ToolButton(icon: "arrow.left.and.right.square",          label: "縫い代",  tool: .seamOverride, currentTool: $currentTool)
                        ToolButton(icon: "square.3.layers.3d",                   label: "グレード", tool: .grading,     currentTool: $currentTool)
                        ToolButton(icon: "ruler.fill",                          label: "寸法入力", tool: .lineInput,    currentTool: $currentTool)
                        ToolButton(icon: "point.topleft.down.curvedto.point.bottomright.up", label: "交点", tool: .intersection, currentTool: $currentTool)

                        Spacer()
                    }
                    .padding(4)
                }
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
                    selectedArcID: $selectedArcID,
                    gradingPointOut: $gradingPointForPanel,
                    seamOverrideLineOut: $seamOverrideLineForPanel,
                    resetOffsetTrigger: $resetOffsetTrigger
                )
                .clipped()
                .onChange(of: selectedPoint) { _, _ in duplicateNameAlert = false }
                .onChange(of: selectedLine?.id) { _, newID in
                    if let newID = newID, let line = canvasState.lines.first(where: { $0.id == newID }) {
                        originalLine = line
                        isSettingInitialValues = true
                        editingAngle = String(format: "%.1f", line.angle)
                        editingLength = String(format: "%.2f", line.lengthCm)
                        isLineEdited = false; isSettingInitialValues = false
                    } else {
                        originalLine = nil; editingAngle = ""; editingLength = ""; isLineEdited = false
                    }
                }
                .onChange(of: selectedArcID) { _, newID in
                    if let newID = newID, let arc = canvasState.arcs.first(where: { $0.id == newID }) {
                        originalArc = arc; isArcEdited = false
                    } else { originalArc = nil; isArcEdited = false }
                }

                // リサイズハンドル
                Rectangle()
                    .fill(Color.gray.opacity(0.3)).frame(width: 4)
                    .gesture(DragGesture().onChanged { value in
                        let newWidth = rightPanelWidth - value.translation.width
                        rightPanelWidth = max(150, min(400, newWidth))
                    })
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }

                // 右パネル
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tool options").font(.headline).padding(.bottom, 4)

                        if selectedPoint != nil {
                            pointPanel
                        } else if currentTool == .grading {
                            GradingView(canvasState: canvasState, selectedPoint: gradingPointForPanel)
                        } else if currentTool == .seamOverride, let line = seamOverrideLineForPanel {
                            seamOverridePanel(line)
                        } else if let curveID = selectedCurveID,
                                  let curve = canvasState.curves.first(where: { $0.id == curveID }) {
                            curvePanel(curve)
                        } else if let arcID = selectedArcID,
                                  let arc = canvasState.arcs.first(where: { $0.id == arcID }) {
                            arcPanel(arc, arcID: arcID)
                        } else if selectedLine != nil {
                            linePanel
                        } else {
                            Text("点または線を選択してください")
                                .foregroundColor(.secondary).font(.system(size: 13))
                        }
                        Spacer()
                    }
                    .padding(12).frame(width: rightPanelWidth)
                    .background(Color(NSColor.windowBackgroundColor))

                    if showMeasurements {
                        Divider()
                        MeasurementView()
                            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                            .frame(width: 280).background(Color(NSColor.windowBackgroundColor))
                    }
                    if showSettings {
                        Divider()
                        SettingsView(canvasState: canvasState)
                            .background(Color(NSColor.windowBackgroundColor))
                    }
                }
            }

            Divider()

            // ステータスバー
            HStack {
                Text(statusMessage).font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
                Text(String(format: "X: %.1f  Y: %.1f (cm)", mousePosition.x / 37.8, mousePosition.y / 37.8))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    // MARK: - ツールラベル
    @ViewBuilder
    private func toolSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
    }

    // MARK: - 右パネル：縫い代個別設定
    @ViewBuilder
    private func seamOverridePanel(_ line: PatternLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("縫い代（個別設定）").font(.headline).padding(.bottom, 4)
            Text(String(format: "線の長さ: %.2f cm", line.lengthCm)).font(.system(size: 13))
            let currentWidth = canvasState.seamWidth(for: line.id)
            HStack {
                Text("幅:").font(.system(size: 13))
                TextField("", text: Binding(
                    get: { String(format: "%.1f", currentWidth) },
                    set: { newVal in
                        if let v = Double(newVal) {
                            if let idx = canvasState.seamOverrides.firstIndex(where: { $0.lineID == line.id }) {
                                canvasState.seamOverrides[idx].width = CGFloat(v)
                            } else {
                                canvasState.seamOverrides.append(SeamAllowanceOverride(lineID: line.id, width: CGFloat(v), side: .both))
                            }
                        }
                    }
                )).textFieldStyle(.roundedBorder).frame(width: 60).font(.system(size: 13))
                Text("cm").font(.system(size: 13))
            }
            Button("確定") {
                canvasState.showSeamAllowance = true
                canvasState.saveSnapshot()
                statusMessage = "縫い代を設定しました"
            }.buttonStyle(.borderedProminent).font(.system(size: 12))
            Button("リセット（デフォルトに戻す）") {
                canvasState.seamOverrides.removeAll { $0.lineID == line.id }
                canvasState.saveSnapshot()
            }.buttonStyle(.bordered).font(.system(size: 11))
        }
    }

    // MARK: - 右パネル：点
    @ViewBuilder
    private var pointPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("名前:").font(.system(size: 13))
                TextField("", text: Binding(
                    get: { selectedPoint?.name ?? "" },
                    set: { newName in
                        if let id = selectedPoint?.id,
                           let index = canvasState.points.firstIndex(where: { $0.id == id }) {
                            let isDuplicate = canvasState.points.contains { $0.name == newName && $0.id != id }
                            if isDuplicate { duplicateNameAlert = true }
                            else {
                                duplicateNameAlert = false
                                canvasState.points[index].name = newName
                                selectedPoint = canvasState.points[index]
                            }
                        }
                    }
                )).textFieldStyle(.roundedBorder).font(.system(size: 13))
            }
            if duplicateNameAlert {
                Text("⚠️ 同じ名前の点が存在します").font(.system(size: 11)).foregroundColor(.red)
            }
            coordField("X:", keyPath: \.x)
            coordField("Y:", keyPath: \.y)
            Button("座標確定") { canvasState.saveSnapshot() }.buttonStyle(.bordered).font(.system(size: 12))
            Button("複製") {
                if let point = selectedPoint {
                    let newPoint = PatternPoint(
                        position: CGPoint(x: point.position.x + 20, y: point.position.y + 20),
                        name: "\(point.name)'"
                    )
                    canvasState.points.append(newPoint)
                    selectedPoint = newPoint
                    canvasState.saveSnapshot()
                    statusMessage = "\(point.name) を複製しました"
                }
            }.buttonStyle(.bordered).font(.system(size: 12))
        }
    }

    @ViewBuilder
    private func coordField(_ label: String, keyPath: WritableKeyPath<CGPoint, CGFloat>) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            TextField("", text: Binding(
                get: {
                    String(format: "%.1f", (selectedPoint?.position[keyPath: keyPath] ?? 0) / 37.8)
                },
                set: { newValue in
                    if let v = Double(newValue),
                       let id = selectedPoint?.id,
                       let index = canvasState.points.firstIndex(where: { $0.id == id }) {
                        let oldPos = canvasState.points[index].position
                        var newPos = oldPos
                        newPos[keyPath: keyPath] = CGFloat(v) * 37.8
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
            )).textFieldStyle(.roundedBorder).font(.system(size: 13))
            Text("cm").font(.system(size: 13))
        }
    }

    // MARK: - 右パネル：曲線
    @ViewBuilder
    private func curvePanel(_ curve: CurveData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("曲線").font(.headline).padding(.bottom, 4)
            Text("ノード数: \(curve.nodes.count)").font(.system(size: 13))
            Text(String(format: "概算長さ: %.2f cm", curveLength(curve))).font(.system(size: 13))
            Text("コントロールポイントを\nドラッグで形を編集")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    // MARK: - 右パネル：円弧
    @ViewBuilder
    private func arcPanel(_ arc: ArcData, arcID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("円弧").font(.headline).padding(.bottom, 4)
            arcField("半径:", arcID: arcID, keyPath: \.radius, unit: "cm", scale: 1/37.8)
            arcAngleField("開始角:", arcID: arcID, keyPath: \.startAngle)
            arcAngleField("終了角:", arcID: arcID, keyPath: \.endAngle)
            HStack {
                Button("確定") {
                    canvasState.saveSnapshot()
                    if let arc = canvasState.arcs.first(where: { $0.id == arcID }) { originalArc = arc }
                    isArcEdited = false
                }.buttonStyle(.borderedProminent).font(.system(size: 12)).disabled(!isArcEdited)
                Button("キャンセル") {
                    if let original = originalArc,
                       let index = canvasState.arcs.firstIndex(where: { $0.id == original.id }) {
                        canvasState.arcs[index] = original; isArcEdited = false
                    }
                }.buttonStyle(.bordered).font(.system(size: 12)).disabled(!isArcEdited)
            }
        }
    }

    @ViewBuilder
    private func arcField(_ label: String, arcID: UUID, keyPath: WritableKeyPath<ArcData, CGFloat>, unit: String, scale: CGFloat) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            TextField("", text: Binding(
                get: {
                    guard let arc = canvasState.arcs.first(where: { $0.id == arcID }) else { return "" }
                    return String(format: "%.2f", arc[keyPath: keyPath] * scale)
                },
                set: { newValue in
                    if let v = Double(newValue),
                       let index = canvasState.arcs.firstIndex(where: { $0.id == arcID }) {
                        canvasState.arcs[index][keyPath: keyPath] = CGFloat(v) / scale
                        isArcEdited = true
                    }
                }
            )).textFieldStyle(.roundedBorder).font(.system(size: 13))
            Text(unit).font(.system(size: 13))
        }
    }

    @ViewBuilder
    private func arcAngleField(_ label: String, arcID: UUID, keyPath: WritableKeyPath<ArcData, CGFloat>) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            TextField("", text: Binding(
                get: {
                    guard let arc = canvasState.arcs.first(where: { $0.id == arcID }) else { return "" }
                    return String(format: "%.1f", arc[keyPath: keyPath])
                },
                set: { newValue in
                    if let v = Double(newValue),
                       let index = canvasState.arcs.firstIndex(where: { $0.id == arcID }) {
                        canvasState.arcs[index][keyPath: keyPath] = CGFloat(v)
                        isArcEdited = true
                    }
                }
            )).textFieldStyle(.roundedBorder).font(.system(size: 13))
            Text("°").font(.system(size: 13))
        }
    }

    // MARK: - 右パネル：線
    @ViewBuilder
    private var linePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("線").font(.headline).padding(.bottom, 4)
            Text(String(format: "長さ: %.2f cm", selectedLine?.lengthCm ?? 0)).font(.system(size: 13))
            HStack {
                Text("角度:").font(.system(size: 13))
                TextField("", text: $editingAngle)
                    .textFieldStyle(.roundedBorder).font(.system(size: 13))
                    .onChange(of: editingAngle) { _, newValue in
                        guard !isSettingInitialValues else { return }
                        isLineEdited = true; applyAngle(newValue)
                    }
                Text("°").font(.system(size: 13))
            }
            HStack {
                Text("長さ:").font(.system(size: 13))
                TextField("", text: $editingLength)
                    .textFieldStyle(.roundedBorder).font(.system(size: 13))
                    .onChange(of: editingLength) { _, newValue in
                        guard !isSettingInitialValues else { return }
                        isLineEdited = true; applyLength(newValue)
                    }
                Text("cm").font(.system(size: 13))
            }
            HStack {
                Button("確定") {
                    canvasState.saveSnapshot()
                    if let id = selectedLine?.id, let line = canvasState.lines.first(where: { $0.id == id }) {
                        originalLine = line
                    }
                    isLineEdited = false
                }.buttonStyle(.borderedProminent).font(.system(size: 12)).disabled(!isLineEdited)
                Button("キャンセル") {
                    if let original = originalLine,
                       let index = canvasState.lines.firstIndex(where: { $0.id == original.id }) {
                        let currentEnd = canvasState.lines[index].endPoint
                        canvasState.lines[index] = original; selectedLine = original
                        if let pi = canvasState.points.firstIndex(where: { calcDistance($0.position, currentEnd) < 1.0 }) {
                            canvasState.points[pi].position = original.endPoint
                        }
                        isSettingInitialValues = true
                        editingAngle = String(format: "%.1f", original.angle)
                        editingLength = String(format: "%.2f", original.lengthCm)
                        isLineEdited = false; isSettingInitialValues = false
                    }
                }.buttonStyle(.bordered).font(.system(size: 12)).disabled(!isLineEdited)
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
                }.buttonStyle(.bordered).font(.system(size: 12))
            }
        }
    }

    // MARK: - ユーティリティ
    private func applyAngle(_ newValue: String) {
        guard let angle = Double(newValue), let id = selectedLine?.id,
              let index = canvasState.lines.firstIndex(where: { $0.id == id }) else { return }
        let oldEnd = canvasState.lines[index].endPoint
        canvasState.lines[index].update(angle: CGFloat(angle), lengthCm: canvasState.lines[index].lengthCm)
        let newEnd = canvasState.lines[index].endPoint
        if let pi = canvasState.points.firstIndex(where: { calcDistance($0.position, oldEnd) < 1.0 }) {
            canvasState.points[pi].position = newEnd
        }
        selectedLine = canvasState.lines[index]
    }

    private func applyLength(_ newValue: String) {
        guard let length = Double(newValue), let id = selectedLine?.id,
              let index = canvasState.lines.firstIndex(where: { $0.id == id }) else { return }
        let oldEnd = canvasState.lines[index].endPoint
        canvasState.lines[index].update(angle: canvasState.lines[index].angle, lengthCm: CGFloat(length))
        let newEnd = canvasState.lines[index].endPoint
        if let pi = canvasState.points.firstIndex(where: { calcDistance($0.position, oldEnd) < 1.0 }) {
            canvasState.points[pi].position = newEnd
        }
        selectedLine = canvasState.lines[index]
    }

    private func curveLength(_ curve: CurveData) -> CGFloat {
        var length: CGFloat = 0
        let steps = 50
        for i in 0..<curve.nodes.count - 1 {
            let from = curve.nodes[i], to = curve.nodes[i + 1]
            var prev = from.point
            for j in 1...steps {
                let t = CGFloat(j) / CGFloat(steps), mt = 1 - t
                let p = CGPoint(
                    x: mt*mt*mt*from.point.x + 3*mt*mt*t*from.controlPoint2.x + 3*mt*t*t*to.controlPoint1.x + t*t*t*to.point.x,
                    y: mt*mt*mt*from.point.y + 3*mt*mt*t*from.controlPoint2.y + 3*mt*t*t*to.controlPoint1.y + t*t*t*to.point.y
                )
                length += calcDistance(prev, p); prev = p
            }
        }
        return length / 37.8
    }

    private func calcDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}

struct ToolButton: View {
    let icon: String
    let label: String
    let tool: Tool
    @Binding var currentTool: Tool

    var body: some View {
        Button(action: { currentTool = tool }) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.system(size: 9))
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
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
