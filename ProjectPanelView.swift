//
//  ProjectPanelView.swift
//  SewingCAD
//

import SwiftUI

struct ProjectPanelView: View {
    @ObservedObject var projectManager: ProjectManager
    @ObservedObject var canvasState: CanvasState
    @State private var showAddPart = false
    @State private var newPartName = ""
    @State private var newPartType: PatternPartType = .bodiceFront
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var showConnectionSheet = false
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ヘッダー
            HStack {
                Text("プロジェクト")
                    .font(.headline)
                Spacer()
                Button(action: { showNewProject = true }) {
                    Image(systemName: "plus.square")
                }
                .help("新規プロジェクト")
                Button(action: {
                    projectManager.loadProject { success in
                        if success, let id = projectManager.activePartID {
                            loadPart(id: id)
                        }
                    }
                }) {
                    Image(systemName: "folder")
                }
                .help("プロジェクトを開く")
                Button(action: {
                    if let id = projectManager.activePartID {
                        projectManager.savePatternData(canvasState.toPatternData(), for: id)
                    }
                    projectManager.saveProject()
                }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("プロジェクトを保存")
                .disabled(projectManager.currentProject == nil)
            }
            .padding(10)

            Divider()

            if let project = projectManager.currentProject {

                // プロジェクト名
                Text(project.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                Divider()

                // パーツ一覧
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(project.parts) { part in
                            PartRowView(
                                part: part,
                                isActive: projectManager.activePartID == part.id,
                                onSelect: { switchToPart(part) },
                                onDelete: {
                                    if projectManager.activePartID == part.id {
                                        canvasState.reset()
                                        projectManager.activePartID = nil
                                    }
                                    projectManager.removePart(id: part.id)
                                }
                            )
                        }
                    }
                    .padding(4)
                }

                Divider()

                // パーツ追加
                Button(action: { showAddPart = true }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("パーツを追加")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 10)
                .padding(.top, 8)

                Divider()
                    .padding(.top, 8)

                // 接合部セクション
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("接合部")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { showConnectionSheet = true }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11))
                        }
                        .disabled(project.parts.count < 2)
                        .help("接合部を追加")
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)

                    if project.connections.isEmpty {
                        Text("接合部がありません")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 6)
                    } else {
                        ForEach(project.connections) { conn in
                            ConnectionRowView(
                                connection: conn,
                                project: project,
                                canvasState: canvasState,
                                projectManager: projectManager,
                                onDelete: {
                                    projectManager.removeConnection(id: conn.id)
                                }
                            )
                        }
                        .padding(.bottom, 6)
                    }
                }

            } else {
                // プロジェクト未作成
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("プロジェクトを\n作成または開いてください")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("新規プロジェクト") {
                        showNewProject = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }

            Spacer()
        }
        .frame(width: 220)

        // 新規プロジェクトシート
        .sheet(isPresented: $showNewProject) {
            VStack(alignment: .leading, spacing: 16) {
                Text("新規プロジェクト")
                    .font(.headline)
                HStack {
                    Text("名前:")
                    TextField("例：ブラウス2026", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                }
                Text("※作成後に保存先フォルダを選択します")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                HStack {
                    Spacer()
                    Button("キャンセル") {
                        showNewProject = false
                    }
                    .buttonStyle(.bordered)
                    Button("作成") {
                        isCreating = true
                        projectManager.newProject(name: newProjectName) { success in
                            isCreating = false
                            if success {
                                showNewProject = false
                                newProjectName = ""
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newProjectName.isEmpty || isCreating)
                }
            }
            .padding(24)
            .frame(width: 340)
        }

        // パーツ追加シート
        .sheet(isPresented: $showAddPart) {
            VStack(alignment: .leading, spacing: 16) {
                Text("パーツを追加")
                    .font(.headline)
                HStack {
                    Text("名前:")
                    TextField("例：前身頃", text: $newPartName)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("種類:")
                    Picker("", selection: $newPartType) {
                        ForEach(PatternPartType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                HStack {
                    Spacer()
                    Button("キャンセル") {
                        showAddPart = false
                        newPartName = ""
                    }
                    .buttonStyle(.bordered)
                    Button("追加") {
                        let part = projectManager.addPart(
                            name: newPartName,
                            type: newPartType
                        )
                        switchToPart(part)
                        showAddPart = false
                        newPartName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newPartName.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 320)
        }

        // 接合部追加シート
        .sheet(isPresented: $showConnectionSheet) {
            if let project = projectManager.currentProject {
                AddConnectionView(
                    project: project,
                    canvasState: canvasState,
                    projectManager: projectManager,
                    onAdd: { connection in
                        projectManager.addConnection(connection)
                        showConnectionSheet = false
                    },
                    onCancel: {
                        showConnectionSheet = false
                    }
                )
            }
        }
    }

    // MARK: - パーツ切り替え
    private func switchToPart(_ part: PatternPart) {
        guard projectManager.activePartID != part.id else { return }
        // 現在のパーツを同期保存
        if let currentID = projectManager.activePartID {
            projectManager.savePatternData(canvasState.toPatternData(), for: currentID)
        }
        projectManager.activePartID = part.id
        loadPart(id: part.id)
    }

    private func loadPart(id: UUID) {
        if let data = projectManager.loadPatternData(for: id) {
            canvasState.load(from: data)
        } else {
            canvasState.reset()
        }
    }
}

// MARK: - パーツ行
struct PartRowView: View {
    let part: PatternPart
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: part.type))
                .font(.system(size: 12))
                .foregroundColor(isActive ? .white : .accentColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(part.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : .primary)
                Text(part.type.rawValue)
                    .font(.system(size: 10))
                    .foregroundColor(isActive ? .white.opacity(0.8) : .secondary)
            }
            Spacer()
            if isHovered && !isActive {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor :
                      (isHovered ? Color.gray.opacity(0.1) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }

    private func iconName(for type: PatternPartType) -> String {
        switch type {
        case .bodiceFront, .bodiceBack: return "person.crop.rectangle"
        case .sleeveFront:              return "oval.portrait"
        case .skirtFront, .skirtBack:   return "rectangle.bottomhalf.filled"
        case .pants:                    return "rectangle.split.2x1"
        case .collar:                   return "oval"
        case .cuff:                     return "rectangle"
        case .waistband:                return "minus.rectangle"
        case .other:                    return "square.dashed"
        }
    }
}

// MARK: - 接合部行
struct ConnectionRowView: View {
    let connection: SeamConnection
    let project: ProjectData
    let canvasState: CanvasState
    let projectManager: ProjectManager
    let onDelete: () -> Void
    @State private var isHovered = false

    var fromPartName: String {
        project.parts.first(where: { $0.id == connection.fromPartID })?.name ?? "?"
    }
    var toPartName: String {
        project.parts.first(where: { $0.id == connection.toPartID })?.name ?? "?"
    }

    // 接合部の長さ差分を計算
    var lengthDiff: CGFloat? {
        let fromLength = curveLength(label: connection.fromLabel, partID: connection.fromPartID)
        let toLength = curveLength(label: connection.toLabel, partID: connection.toPartID)
        guard let f = fromLength, let t = toLength else { return nil }
        return t - f - connection.ease
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(fromPartName)[\(connection.fromLabel)] ↔ \(toPartName)[\(connection.toLabel)]")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let diff = lengthDiff {
                        HStack(spacing: 4) {
                            Image(systemName: abs(diff) < 0.1 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(abs(diff) < 0.1 ? .green : .orange)
                            Text(abs(diff) < 0.1
                                 ? "一致"
                                 : String(format: "差分: %+.2fcm", diff))
                                .font(.system(size: 10))
                                .foregroundColor(abs(diff) < 0.1 ? .green : .orange)
                        }
                    } else {
                        Text("曲線未設定")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHovered ? Color.gray.opacity(0.05) : Color.clear)
        .onHover { isHovered = $0 }
    }

    // ラベル付き曲線の長さを取得
    private func curveLength(label: String, partID: UUID) -> CGFloat? {
        // アクティブパーツならcanvasStateから直接取得
        if projectManager.activePartID == partID {
            return lengthFromState(label: label, state: canvasState)
        }
        // 非アクティブパーツはファイルから読み込み
        guard let data = projectManager.loadPatternData(for: partID) else { return nil }
        return lengthFromData(label: label, data: data)
    }

    private func lengthFromState(label: String, state: CanvasState) -> CGFloat? {
        // ラベル付き曲線を探す
        if let curve = state.curves.first(where: { $0.label == label }) {
            return calcCurveLength(curve)
        }
        // ラベル付き線分を探す
        if let line = state.lines.first(where: { $0.label == label }) {
            return line.lengthCm
        }
        return nil
    }

    private func lengthFromData(label: String, data: PatternData) -> CGFloat? {
        // SavedCurveのlabelから検索
        if let savedCurve = data.curves.first(where: { $0.label == label }) {
            let nodes = savedCurve.nodes.map {
                CurveNode(
                    point: CGPoint(x: $0.x, y: $0.y),
                    controlPoint1: CGPoint(x: $0.cp1x, y: $0.cp1y),
                    controlPoint2: CGPoint(x: $0.cp2x, y: $0.cp2y)
                )
            }
            return calcCurveLength(CurveData(nodes: nodes))
        }
        // SavedLineのlabelから検索
        if let savedLine = data.lines.first(where: { $0.label == label }) {
            let dx = savedLine.x2 - savedLine.x1
            let dy = savedLine.y2 - savedLine.y1
            return sqrt(dx*dx + dy*dy) / 37.8
        }
        return nil
    }

    private func calcCurveLength(_ curve: CurveData) -> CGFloat {
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
                length += sqrt(pow(p.x - prev.x, 2) + pow(p.y - prev.y, 2))
                prev = p
            }
        }
        return length / 37.8
    }
}

// MARK: - 接合部追加シート
struct AddConnectionView: View {
    let project: ProjectData
    let canvasState: CanvasState
    let projectManager: ProjectManager
    let onAdd: (SeamConnection) -> Void
    let onCancel: () -> Void

    @State private var connectionName = ""
    @State private var fromPartID: UUID?
    @State private var fromLabel = ""
    @State private var toPartID: UUID?
    @State private var toLabel = ""
    @State private var ease: String = "0.0"

    // 各パーツのラベル一覧を取得
    func labelsForPart(_ partID: UUID) -> [String] {
        var labels: [String] = []
        if projectManager.activePartID == partID {
            labels += canvasState.curves.compactMap { $0.label.isEmpty ? nil : $0.label }
            labels += canvasState.lines.compactMap { $0.label.isEmpty ? nil : $0.label }
        } else if let data = projectManager.loadPatternData(for: partID) {
            labels += data.curves.compactMap { $0.label.isEmpty ? nil : $0.label }
            labels += data.lines.compactMap { $0.label.isEmpty ? nil : $0.label }
        }
        return labels
    }

    var canAdd: Bool {
        !connectionName.isEmpty &&
        fromPartID != nil && !fromLabel.isEmpty &&
        toPartID != nil && !toLabel.isEmpty &&
        fromPartID != toPartID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("接合部を追加")
                .font(.headline)

            Text("接合部とは、2つのパーツを縫い合わせる箇所です。\n例：身頃の袖ぐり ↔ 袖の袖山")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Divider()

            HStack {
                Text("名前:")
                    .frame(width: 80, alignment: .leading)
                TextField("例：袖ぐり", text: $connectionName)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            // パーツA
            VStack(alignment: .leading, spacing: 8) {
                Text("パーツA（接合元）")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    Text("パーツ:")
                        .frame(width: 80, alignment: .leading)
                    Picker("", selection: $fromPartID) {
                        Text("選択してください").tag(nil as UUID?)
                        ForEach(project.parts) { part in
                            Text(part.name).tag(part.id as UUID?)
                        }
                    }
                    .labelsHidden()
                }
                HStack {
                    Text("曲線ラベル:")
                        .frame(width: 80, alignment: .leading)
                    if let id = fromPartID {
                        let labels = labelsForPart(id)
                        if labels.isEmpty {
                            TextField("ラベル名を入力", text: $fromLabel)
                                .textFieldStyle(.roundedBorder)
                            Text("（ラベル未設定）")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        } else {
                            Picker("", selection: $fromLabel) {
                                Text("選択").tag("")
                                ForEach(labels, id: \.self) { label in
                                    Text(label).tag(label)
                                }
                            }
                            .labelsHidden()
                        }
                    } else {
                        Text("先にパーツを選択")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // パーツB
            VStack(alignment: .leading, spacing: 8) {
                Text("パーツB（接合先）")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    Text("パーツ:")
                        .frame(width: 80, alignment: .leading)
                    Picker("", selection: $toPartID) {
                        Text("選択してください").tag(nil as UUID?)
                        ForEach(project.parts.filter { $0.id != fromPartID }) { part in
                            Text(part.name).tag(part.id as UUID?)
                        }
                    }
                    .labelsHidden()
                }
                HStack {
                    Text("曲線ラベル:")
                        .frame(width: 80, alignment: .leading)
                    if let id = toPartID {
                        let labels = labelsForPart(id)
                        if labels.isEmpty {
                            TextField("ラベル名を入力", text: $toLabel)
                                .textFieldStyle(.roundedBorder)
                            Text("（ラベル未設定）")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        } else {
                            Picker("", selection: $toLabel) {
                                Text("選択").tag("")
                                ForEach(labels, id: \.self) { label in
                                    Text(label).tag(label)
                                }
                            }
                            .labelsHidden()
                        }
                    } else {
                        Text("先にパーツを選択")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Text("イーズ量:")
                    .frame(width: 80, alignment: .leading)
                TextField("0.0", text: $ease)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("cm（袖山の場合は1.5〜3cm程度）")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Spacer()
                Button("キャンセル") { onCancel() }
                    .buttonStyle(.bordered)
                Button("追加") {
                    let conn = SeamConnection(
                        name: connectionName,
                        fromPartID: fromPartID!,
                        fromLabel: fromLabel,
                        toPartID: toPartID!,
                        toLabel: toLabel,
                        ease: CGFloat(Double(ease) ?? 0)
                    )
                    onAdd(conn)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
