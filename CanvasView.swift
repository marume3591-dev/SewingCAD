//
//  CanvasView.swift
//  SewingCAD
//

import SwiftUI
import AppKit

struct CanvasView: View {
    @ObservedObject var canvasState: CanvasState
    @Binding var currentTool: Tool
    @Binding var selectedPoint: PatternPoint?
    @Binding var selectedLine: PatternLine?
    @Binding var mousePosition: CGPoint
    @Binding var statusMessage: String
    @Binding var scale: CGFloat
    @Binding var selectedCurveID: UUID?
    @Binding var selectedArcID: UUID?
    @Binding var gradingPointOut: PatternPoint?
    @Binding var seamOverrideLineOut: PatternLine?
    @Binding var resetOffsetTrigger: Bool
    @ObservedObject var projectManager: ProjectManager

    @State private var offset: CGSize = CGSize(width: 40, height: 40)
    @State private var ghostPartsData: [(id: UUID, name: String, data: PatternData, offsetX: CGFloat)] = []
    @State private var draggingPointID: UUID? = nil
    @State private var curveNodes: [CurveNode] = []
    @State private var draggingCurveNodeIndex: Int? = nil
    @State private var draggingControlPoint: (curveID: UUID, nodeIndex: Int, isCP1: Bool)? = nil
    @State private var lineToSplit: PatternLine? = nil
    @State private var splitClickPosition: CGPoint = .zero
    @State private var isShiftPressed: Bool = false
    @State private var shiftSnapPreview: CGPoint? = nil
    @State private var groupSelectStart: CGPoint? = nil
    @State private var groupSelectEnd: CGPoint? = nil
    @State private var groupSelectedPointIDs: Set<UUID> = []
    @State private var groupSelectedLineIDs: Set<UUID> = []
    @State private var groupDragStart: CGPoint? = nil
    // 平行線・垂直線用
    @State private var parallelSourceLine: PatternLine? = nil
    @State private var perpendicularSourceLine: PatternLine? = nil

    // ▼ 修正1: 垂直ツールのプレビュー用 State を追加
    @State private var perpendicularPreview: (from: CGPoint, foot: CGPoint)? = nil

    // 線の延長用
    @State private var extendSourceLine: PatternLine? = nil

    // 円弧用
    @State private var arcCenter: CGPoint? = nil
    @State private var arcStart: CGPoint? = nil

    // テキスト用
    @State private var showTextInput: Bool = false
    @State private var textInputPosition: CGPoint = .zero
    @State private var textInputValue: String = ""
    @State private var selectedTextID: UUID? = nil

    @State private var groupSelectedArcIDs: Set<UUID> = []
    @State private var groupSelectedTextIDs: Set<UUID> = []
    @State private var groupSelectedCurveIDs: Set<UUID> = []

    private func toScreen(_ p: CGPoint) -> CGPoint {
        let activeIndex: Int = {
            guard let project = projectManager.currentProject,
                  let id = projectManager.activePartID else { return 0 }
            return project.parts.firstIndex(where: { $0.id == id }) ?? 0
        }()
        let spacingPx: CGFloat = 60
        let activeOffsetX = (canvasState.currentPaperSize.width + spacingPx) * CGFloat(activeIndex) * scale
        return CGPoint(x: p.x * scale + offset.width + activeOffsetX, y: p.y * scale + offset.height)
    }

    private func toCanvas(_ p: CGPoint) -> CGPoint {
        let activeIndex: Int = {
            guard let project = projectManager.currentProject,
                  let id = projectManager.activePartID else { return 0 }
            return project.parts.firstIndex(where: { $0.id == id }) ?? 0
        }()
        let spacingPx: CGFloat = 60
        let activeOffsetX = (canvasState.currentPaperSize.width + spacingPx) * CGFloat(activeIndex) * scale
        return CGPoint(x: (p.x - offset.width - activeOffsetX) / scale, y: (p.y - offset.height) / scale)
    }

    private func bezierPath(for nodes: [CurveNode]) -> Path {
        var path = Path()
        guard nodes.count >= 2 else { return path }
        path.move(to: toScreen(nodes[0].point))
        for i in 0..<nodes.count - 1 {
            let from = nodes[i]
            let to = nodes[i + 1]
            path.addCurve(
                to: toScreen(to.point),
                control1: toScreen(from.controlPoint2),
                control2: toScreen(to.controlPoint1)
            )
        }
        return path
    }

    // ▼ 修正2: 垂直線の足（射影点）を計算するヘルパー
    private func calcPerpendicularFoot(source: PatternLine, fromPoint: CGPoint) -> CGPoint {
        let dx = source.endPoint.x - source.startPoint.x
        let dy = source.endPoint.y - source.startPoint.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return source.startPoint }
        let t = ((fromPoint.x - source.startPoint.x) * dx + (fromPoint.y - source.startPoint.y) * dy) / len2
        return CGPoint(x: source.startPoint.x + t * dx, y: source.startPoint.y + t * dy)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.gray.opacity(0.3)

                ZStack {
                    Color.white

                    // グリッド
                    if canvasState.showGrid {
                        Canvas { context, size in
                            let gridSize: CGFloat = 37.8 * scale
                            let color = Color.gray.opacity(0.15)
                            let offsetX = offset.width.truncatingRemainder(dividingBy: gridSize)
                            let offsetY = offset.height.truncatingRemainder(dividingBy: gridSize)
                            var x = offsetX
                            while x < size.width {
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                                context.stroke(path, with: .color(color), lineWidth: 0.5)
                                x += gridSize
                            }
                            var y = offsetY
                            while y < size.height {
                                var path = Path()
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(path, with: .color(color), lineWidth: 0.5)
                                y += gridSize
                            }
                        }
                    }
                    // 用紙境界線（アクティブパーツ）
                    let paperW = canvasState.currentPaperSize.width * scale
                    let paperH = canvasState.currentPaperSize.height * scale
                    let paperY = offset.height

                    // アクティブパーツのプロジェクト内インデックスに基づいてX位置を固定
                    let activeIndex: Int = {
                        guard let project = projectManager.currentProject,
                              let id = projectManager.activePartID else { return 0 }
                        return project.parts.firstIndex(where: { $0.id == id }) ?? 0
                    }()
                    let spacing: CGFloat = 60 * scale
                    let paperX = offset.width + (paperW + spacing) * CGFloat(activeIndex)

                    Path { path in
                        path.addRect(CGRect(x: paperX, y: paperY, width: paperW, height: paperH))
                    }
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)

                    // アクティブパーツ名を原点の上に表示
                    if let project = projectManager.currentProject,
                       let id = projectManager.activePartID,
                       let part = project.parts.first(where: { $0.id == id }) {
                        let originScreen = toScreen(.zero)
                        Text(part.name)
                            .font(.system(size: max(12, 14 * scale), weight: .bold))
                            .foregroundColor(Color.black.opacity(0.7))
                            .background(Color.white.opacity(0.75))
                            .position(CGPoint(x: originScreen.x - 50, y: originScreen.y - 28))
                    }

                    // ── 他パーツのゴースト表示（Canvas で一括描画）──
                    if canvasState.showPaperGrid && !ghostPartsData.isEmpty {
                        let ghosts = ghostPartsData
                        let sc = scale
                        let ox = offset.width
                        let oy = paperY
                        let pw = paperW
                        let ph = paperH
                        Canvas { ctx, _ in
                            for ghost in ghosts {
                                let rx = ghost.offsetX * sc + ox
                                // 枠線
                                var rectPath = Path()
                                rectPath.addRect(CGRect(x: rx, y: oy, width: pw, height: ph))
                                ctx.stroke(rectPath, with: .color(.blue.opacity(0.15)), lineWidth: 0.8)
                                // 線
                                for line in ghost.data.lines {
                                    var lp = Path()
                                    lp.move(to: CGPoint(x: line.x1 * sc + rx, y: line.y1 * sc + oy))
                                    lp.addLine(to: CGPoint(x: line.x2 * sc + rx, y: line.y2 * sc + oy))
                                    ctx.stroke(lp, with: .color(.blue.opacity(0.25)), lineWidth: 1.0)
                                }
                                // 点
                                for pt in ghost.data.points {
                                    let pr = CGRect(
                                        x: pt.x * sc + rx - 2,
                                        y: pt.y * sc + oy - 2,
                                        width: 4, height: 4)
                                    var pp = Path()
                                    pp.addEllipse(in: pr)
                                    ctx.fill(pp, with: .color(.blue.opacity(0.2)))
                                }
                            }
                        }
                        // パーツ名ラベル（赤で表示）
                        ForEach(ghostPartsData, id: \.id) { ghost in
                            let rx = ghost.offsetX * scale + offset.width
                            Text(ghost.name)
                                .font(.system(size: max(9, 11 * scale), weight: .semibold))
                                .foregroundColor(Color.red.opacity(0.8))
                                .position(CGPoint(x: rx + paperW / 2, y: paperY + 16))
                        }
                    }

                    // 線を描画（Canvas一括）
                    drawLinesLayer()
                    
                    // 縫い代を描画
                    if canvasState.showSeamAllowance { drawSeamAllowanceLayer() }
                    // 円弧を描画
                    ForEach(canvasState.arcs) { arc in
                        let isArcSelected = groupSelectedArcIDs.contains(arc.id) || selectedArcID == arc.id
                        Path { path in
                            let screenCenter = toScreen(arc.center)
                            let screenRadius = arc.radius * scale
                            let startRad = arc.startAngle * .pi / 180
                            let endRad = arc.endAngle * .pi / 180
                            path.addArc(center: screenCenter,
                                       radius: screenRadius,
                                       startAngle: .radians(startRad),
                                       endAngle: .radians(endRad),
                                       clockwise: false)
                        }
                        .stroke(isArcSelected ? Color.orange : Color.black, lineWidth: isArcSelected ? 2.5 : 1.5)
                        // 選択中は中心点を表示
                        if isArcSelected {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                                .position(toScreen(arc.center))
                        }
                    }
                    
                    // テキストを描画
                    ForEach(canvasState.texts) { annotation in
                        let isTextSelected = groupSelectedTextIDs.contains(annotation.id)
                        Text(annotation.text)
                            .font(.system(size: annotation.fontSize * scale))
                            .foregroundColor(isTextSelected ? Color.orange :
                                           selectedTextID == annotation.id ? Color.blue : Color.black)
                            .background(isTextSelected ? Color.orange.opacity(0.1) : Color.clear)
                            .position(toScreen(annotation.position))
                    }
                    // 曲線を描画
                    ForEach(canvasState.curves) { curve in
                        bezierPath(for: curve.nodes)
                            .stroke(
                                curve.id == selectedCurveID ? Color.blue : Color.black,
                                lineWidth: 1.5
                            )
                        if curve.id != selectedCurveID {
                            ForEach(0..<curve.nodes.count, id: \.self) { i in
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 5, height: 5)
                                    .position(toScreen(curve.nodes[i].point))
                            }
                        }
                        if curve.id == selectedCurveID {
                            ForEach(0..<curve.nodes.count, id: \.self) { i in
                                let node = curve.nodes[i]
                                let screenPoint = toScreen(node.point)
                                let screenCP1 = toScreen(node.controlPoint1)
                                let screenCP2 = toScreen(node.controlPoint2)
                                let isFirst = i == 0
                                let isLast = i == curve.nodes.count - 1

                                Path { path in
                                    if !isFirst { path.move(to: screenCP1); path.addLine(to: screenPoint) }
                                    if !isLast { path.move(to: screenPoint); path.addLine(to: screenCP2) }
                                }
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1)

                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                    .position(screenPoint)

                                if !isFirst {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 6, height: 6)
                                        .position(screenCP1)
                                }

                                if !isLast {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 6, height: 6)
                                        .position(screenCP2)
                                }
                            }
                        }
                    }

                    // 描画中の曲線プレビュー
                    if curveNodes.count >= 2 {
                        bezierPath(for: curveNodes)
                            .stroke(Color.blue.opacity(0.5), lineWidth: 1.5)
                    }

                    ForEach(0..<curveNodes.count, id: \.self) { i in
                        Circle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: 6, height: 6)
                            .position(toScreen(curveNodes[i].point))
                    }

                    // 点と名前を描画
                    ForEach(canvasState.points) { point in
                        let screenPos = toScreen(point.position)
                        ZStack {
                            Circle()
                                .fill(selectedPoint?.id == point.id ? Color.red :
                                      groupSelectedPointIDs.contains(point.id) ? Color.orange : Color.blue)
                                .frame(width: 8, height: 8)
                            Text(point.name)
                                .font(.system(size: 10))
                                .foregroundColor(.black)
                                .offset(x: 10, y: -10)
                        }
                        .position(screenPos)
                    }

                    // 寸法線を描画
                    drawDimensionLayer()

                    // Shiftスナップのプレビュー
                    if let preview = shiftSnapPreview, let selected = selectedPoint {
                        drawShiftSnap(preview: preview, selected: selected)
                    }

                    // 垂直ツールのガイド線プレビュー
                    if let preview = perpendicularPreview {
                        drawPerpendicularPreview(preview: preview)
                    }

                    // グループ選択の矩形プレビュー
                    if let start = groupSelectStart, let end = groupSelectEnd {
                        drawGroupSelectRect(start: start, end: end)
                    }
                    // 原点マーカー＋スケールバー
                    drawOriginAndScaleBar(size: geometry.size)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()

                CanvasNSViewRepresentable(
                    onScroll: { delta in
                        offset = CGSize(width: offset.width + delta.x, height: offset.height - delta.y)
                    },
                    onMouseMove: { location, isShift in
                        mousePosition = location
                        isShiftPressed = isShift
                        if isShift && selectedPoint != nil && currentTool == .addPoint {
                            let canvasPos = toCanvas(location)
                            shiftSnapPreview = snapToAngle(canvasPos)
                        } else {
                            shiftSnapPreview = nil
                        }
                        // ▼ 修正4: 垂直ツールで線選択済みの場合、マウス移動でガイド線プレビューを更新
                        if currentTool == .perpendicular, let source = perpendicularSourceLine {
                            let canvasPos = toCanvas(location)
                            // 近くの点にスナップ
                            let snapped = nearestPoint(to: canvasPos, threshold: 20 / scale)
                            let fromPoint = snapped?.position ?? canvasPos
                            let foot = calcPerpendicularFoot(source: source, fromPoint: fromPoint)
                            perpendicularPreview = (from: fromPoint, foot: foot)
                        } else {
                            perpendicularPreview = nil
                        }
                    },
                    onDragBegan: { location, isShift in
                        handleDragBegan(location: location, isShift: isShift)
                    },
                    onDragChanged: { location in
                        handleDragChanged(location: location)
                    },
                    onDragEnded: { location in
                        handleDragEnded(location: location)
                    },
                    onDoubleClick: { location in
                        handleDoubleClick(location: location)
                    },
                    onEnterKey: {
                        if currentTool == .addCurve {
                            finalizeCurve()
                        } else if currentTool == .addLine {
                            selectedPoint = nil
                            statusMessage = "始点をクリックしてください"
                        }
                    },
                    onSelectAll: {
                        selectAll()
                    },
                    onDeleteKey: {
                        if !groupSelectedPointIDs.isEmpty || !groupSelectedLineIDs.isEmpty ||
                           !groupSelectedArcIDs.isEmpty || !groupSelectedTextIDs.isEmpty {
                            deleteGroupSelected()
                        } else if let id = selectedArcID,
                                  let index = canvasState.arcs.firstIndex(where: { $0.id == id }) {
                            canvasState.arcs.remove(at: index)
                            selectedArcID = nil
                            canvasState.saveSnapshot()
                            statusMessage = "円弧を削除しました"
                        } else if let id = selectedTextID,
                                  let index = canvasState.texts.firstIndex(where: { $0.id == id }) {
                            canvasState.texts.remove(at: index)
                            selectedTextID = nil
                            canvasState.saveSnapshot()
                            statusMessage = "テキストを削除しました"
                        }
                    }
                )
            }
        }
        .sheet(item: $lineToSplit) { line in
            LineSplitView(
                line: line,
                onSplit: { t in
                    splitLine(line: line, t: t)
                    lineToSplit = nil
                },
                onCancel: {
                    lineToSplit = nil
                }
            )
        }
        .sheet(isPresented: $showTextInput) {
            TextInputView(
                text: $textInputValue,
                onConfirm: {
                    if !textInputValue.isEmpty {
                        if let id = selectedTextID,
                           let index = canvasState.texts.firstIndex(where: { $0.id == id }) {
                            // 既存テキストの編集
                            canvasState.texts[index].text = textInputValue
                            canvasState.saveSnapshot()
                            statusMessage = "テキストを編集しました"
                        } else {
                            // 新規テキストの追加
                            let annotation = TextAnnotation(
                                position: textInputPosition,
                                text: textInputValue
                            )
                            canvasState.texts.append(annotation)
                            canvasState.saveSnapshot()
                            statusMessage = "テキストを追加しました"
                        }
                    }
                    showTextInput = false
                    selectedTextID = nil
                },
                onCancel: {
                    showTextInput = false
                    selectedTextID = nil
                }
            )
        }
        
        .onChange(of: resetOffsetTrigger) { _, _ in
            offset = CGSize(width: 40, height: 40)
        }
        .onChange(of: projectManager.activePartID) { _, _ in
            updateGhostParts()
        }
        .onAppear {
            updateGhostParts()
        }
        .onChange(of: currentTool) { _, tool in
            curveNodes = []
            selectedCurveID = nil
            selectedPoint = nil
            selectedLine = nil
            selectedArcID = nil
            groupSelectStart = nil
            groupSelectEnd = nil
            groupSelectedPointIDs = []
            groupSelectedLineIDs = []
            parallelSourceLine = nil
            perpendicularSourceLine = nil
            perpendicularPreview = nil  // ▼ ツール切替時にプレビューをクリア
            extendSourceLine = nil
            arcCenter = nil
            arcStart = nil
            groupSelectedArcIDs = []
            groupSelectedTextIDs = []
            groupSelectedCurveIDs = []
            switch tool {
            case .select:
                statusMessage = "点または曲線をクリックして選択"
            case .addPoint:
                statusMessage = "キャンバスをクリックして点を追加"
            case .addLine:
                statusMessage = "始点をクリックしてください"
            case .addCurve:
                statusMessage = "クリックでノードを追加、Enterキーで確定"
            case .delete:
                statusMessage = "削除する要素をクリックしてください"
            case .groupSelect:
                statusMessage = "ドラッグで範囲を選択してください"
            case .parallel:
                statusMessage = "平行線を引く線をクリックしてください"
            case .perpendicular:
                statusMessage = "垂直線を引く線をクリックしてください"
            case .extend:
                statusMessage = "延長する線をクリックしてください"
            case .midpoint:
                statusMessage = "中点を追加する線をクリックしてください"
            case .arc:
                statusMessage = "円弧の中心をクリックしてください"
            case .text:
                statusMessage = "テキストを追加する位置をクリックしてください"
            default:
                break
            }
        }
    }

    // MARK: - ViewBuilder ヘルパー

    @ViewBuilder
    private func drawPerpendicularPreview(preview: (from: CGPoint, foot: CGPoint)) -> some View {
        let screenFrom = toScreen(preview.from)
        let screenFoot = toScreen(preview.foot)
        let mid = CGPoint(x: (screenFrom.x + screenFoot.x) / 2,
                          y: (screenFrom.y + screenFoot.y) / 2)
        let dx = preview.foot.x - preview.from.x
        let dy = preview.foot.y - preview.from.y
        let perpLenCm = sqrt(dx*dx + dy*dy) / 37.8

        // 線上の位置情報を計算
        let footInfo: (distFromStart: CGFloat, totalLen: CGFloat, ratio: CGFloat)? = {
            guard let src = perpendicularSourceLine else { return nil }
            let sx = src.endPoint.x - src.startPoint.x
            let sy = src.endPoint.y - src.startPoint.y
            let total = sqrt(sx*sx + sy*sy)
            guard total > 0 else { return nil }
            let t = ((preview.foot.x - src.startPoint.x) * sx
                   + (preview.foot.y - src.startPoint.y) * sy) / (total * total)
            let tClamped = max(0, min(1, t))
            return (distFromStart: tClamped * total / 37.8,
                    totalLen: total / 37.8,
                    ratio: CGFloat(tClamped))
        }()

        Path { p in p.move(to: screenFrom); p.addLine(to: screenFoot) }
            .stroke(Color.purple.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        Circle().fill(Color.purple.opacity(0.8)).frame(width: 8, height: 8).position(screenFrom)
        Circle().stroke(Color.purple, lineWidth: 2).frame(width: 10, height: 10).position(screenFoot)

        // 直角マーク
        if let source = perpendicularSourceLine {
            let len = sqrt(dx*dx + dy*dy)
            if len > 0 {
                let ux = dx/len; let uy = dy/len
                let sx = source.endPoint.x - source.startPoint.x
                let sy = source.endPoint.y - source.startPoint.y
                let slen = sqrt(sx*sx + sy*sy)
                if slen > 0 {
                    let sux = sx/slen; let suy = sy/slen
                    let cs: CGFloat = 8 / scale
                    let q1 = CGPoint(x: preview.foot.x + ux*cs, y: preview.foot.y + uy*cs)
                    let q2 = CGPoint(x: q1.x + sux*cs, y: q1.y + suy*cs)
                    let q3 = CGPoint(x: preview.foot.x + sux*cs, y: preview.foot.y + suy*cs)
                    Path { p in p.move(to: toScreen(q1)); p.addLine(to: toScreen(q2)); p.addLine(to: toScreen(q3)) }
                        .stroke(Color.purple.opacity(0.7), lineWidth: 1)
                }
            }
        }

        // 垂直線の長さ
        Text(String(format: "垂直: %.2fcm", perpLenCm))
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.purple)
            .background(Color.white.opacity(0.8))
            .position(CGPoint(x: mid.x + 14, y: mid.y - 8))

        // 線上の位置情報（足マーカーの上に表示）
        if let info = footInfo {
            let screenFoot2 = toScreen(preview.foot)
            let label = String(format: "始点から %.2fcm / 残り %.2fcm (%.0f%%)",
                               info.distFromStart,
                               info.totalLen - info.distFromStart,
                               info.ratio * 100)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(red: 0.6, green: 0.0, blue: 0.6))
                .background(Color.white.opacity(0.85))
                .position(CGPoint(x: screenFoot2.x + 8, y: screenFoot2.y - 18))

            // 始点側の距離ライン表示（線源上に小さなマーカー）
            if let src = perpendicularSourceLine {
                let screenStart = toScreen(src.startPoint)
                let screenEnd   = toScreen(src.endPoint)
                // 始点〜足 の区間を強調
                Path { p in
                    p.move(to: screenStart)
                    p.addLine(to: screenFoot2)
                }
                .stroke(Color.orange.opacity(0.6), lineWidth: 2)
                // 始点距離ラベル
                let startMid = CGPoint(x: (screenStart.x + screenFoot2.x) / 2,
                                       y: (screenStart.y + screenFoot2.y) / 2)
                Text(String(format: "%.2fcm", info.distFromStart))
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .background(Color.white.opacity(0.8))
                    .position(CGPoint(x: startMid.x, y: startMid.y - 10))
                // 終点距離ラベル
                let endMid = CGPoint(x: (screenFoot2.x + screenEnd.x) / 2,
                                     y: (screenFoot2.y + screenEnd.y) / 2)
                Text(String(format: "%.2fcm", info.totalLen - info.distFromStart))
                    .font(.system(size: 9))
                    .foregroundColor(Color.gray)
                    .background(Color.white.opacity(0.8))
                    .position(CGPoint(x: endMid.x, y: endMid.y - 10))
            }
        }
    }

    @ViewBuilder
    private func drawGroupSelectRect(start: CGPoint, end: CGPoint) -> some View {
        let s = toScreen(start); let e = toScreen(end)
        let rect = CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                          width: abs(e.x - s.x), height: abs(e.y - s.y))
        Path { p in p.addRect(rect) }
            .stroke(Color.blue.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        Path { p in p.addRect(rect) }.fill(Color.blue.opacity(0.1))
    }

    @ViewBuilder
    private func drawShiftSnap(preview: CGPoint, selected: PatternPoint) -> some View {
        let sp = toScreen(preview); let ss = toScreen(selected.position)
        Path { p in p.move(to: ss); p.addLine(to: sp) }
            .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        Circle().fill(Color.blue.opacity(0.7)).frame(width: 8, height: 8).position(sp)
    }

    @ViewBuilder
    private func drawOriginAndScaleBar(size: CGSize) -> some View {
        let orig = toScreen(.zero)
        if orig.x >= 0 && orig.x <= size.width && orig.y >= 0 && orig.y <= size.height {
            Path { p in
                p.move(to: CGPoint(x: orig.x - 10, y: orig.y))
                p.addLine(to: CGPoint(x: orig.x + 10, y: orig.y))
                p.move(to: CGPoint(x: orig.x, y: orig.y - 10))
                p.addLine(to: CGPoint(x: orig.x, y: orig.y + 10))
            }.stroke(Color.red.opacity(0.7), lineWidth: 1.5)
            Text("0").font(.system(size: 9)).foregroundColor(.red.opacity(0.7))
                .position(CGPoint(x: orig.x + 12, y: orig.y - 12))
        }
        let barPx: CGFloat = 5 * 37.8 * scale
        let barX: CGFloat = 20; let barY = size.height - 20
        Path { p in
            p.move(to: CGPoint(x: barX, y: barY)); p.addLine(to: CGPoint(x: barX + barPx, y: barY))
            p.move(to: CGPoint(x: barX, y: barY - 4)); p.addLine(to: CGPoint(x: barX, y: barY + 4))
            p.move(to: CGPoint(x: barX + barPx, y: barY - 4)); p.addLine(to: CGPoint(x: barX + barPx, y: barY + 4))
        }.stroke(Color.black.opacity(0.6), lineWidth: 1.5)
        Text("5cm").font(.system(size: 9)).foregroundColor(.black.opacity(0.6))
            .position(CGPoint(x: barX + barPx / 2, y: barY - 10))
    }

        // MARK: - 描画レイヤー関数

    @ViewBuilder
    private func drawLinesLayer() -> some View {
        let lines = canvasState.lines
        let selID = selectedLine?.id
        ForEach(lines) { line in
            let p1 = toScreen(line.startPoint)
            let p2 = toScreen(line.endPoint)
            let isSelected = selID == line.id
            let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            Path { path in path.move(to: p1); path.addLine(to: p2) }
                .stroke(isSelected ? Color.blue : Color.black,
                        lineWidth: isSelected ? 2.5 : 1.5)
            Text(String(format: "%.1fcm", line.lengthCm))
                .font(.system(size: 9))
                .foregroundColor(isSelected ? Color.blue : Color.gray)
                .position(CGPoint(x: mid.x + 8, y: mid.y - 8))
            if isSelected {
                Rectangle().fill(Color.red).frame(width: 10, height: 10).position(p1)
                Rectangle().fill(Color.green).frame(width: 10, height: 10).position(p2)
            }
        }
    }

    @ViewBuilder
    private func drawSeamAllowanceLayer() -> some View {
        let sa = canvasState.seamAllowance * 37.8 * scale
        Canvas { ctx, _ in
            for line in canvasState.lines {
                let p1 = toScreen(line.startPoint)
                let p2 = toScreen(line.endPoint)
                let dx = p2.x - p1.x; let dy = p2.y - p1.y
                let len = sqrt(dx*dx + dy*dy)
                guard len > 0 else { continue }
                let nx = -dy / len * sa; let ny = dx / len * sa
                var path = Path()
                path.move(to: CGPoint(x: p1.x + nx, y: p1.y + ny))
                path.addLine(to: CGPoint(x: p2.x + nx, y: p2.y + ny))
                ctx.stroke(path, with: .color(.red.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    @ViewBuilder
    private func drawDimensionLayer() -> some View {
        Canvas { ctx, _ in
            for line in canvasState.lines {
                let p1 = toScreen(line.startPoint)
                let p2 = toScreen(line.endPoint)
                let dx = p2.x - p1.x; let dy = p2.y - p1.y
                let len = sqrt(dx*dx + dy*dy)
                guard len > 0 else { continue }
                let nx = -dy / len * 20; let ny = dx / len * 20
                var path = Path()
                path.move(to: CGPoint(x: p1.x + nx*0.3, y: p1.y + ny*0.3))
                path.addLine(to: CGPoint(x: p1.x + nx*1.2, y: p1.y + ny*1.2))
                path.move(to: CGPoint(x: p2.x + nx*0.3, y: p2.y + ny*0.3))
                path.addLine(to: CGPoint(x: p2.x + nx*1.2, y: p2.y + ny*1.2))
                path.move(to: CGPoint(x: p1.x + nx, y: p1.y + ny))
                path.addLine(to: CGPoint(x: p2.x + nx, y: p2.y + ny))
                ctx.stroke(path, with: .color(.blue.opacity(0.4)), lineWidth: 0.8)
            }
        }
    }

        // MARK: - ドラッグハンドラ関数

    private func handleDragBegan(location: CGPoint, isShift: Bool) {
        isShiftPressed = isShift
        let rawCanvasPos = toCanvas(location)
        let canvasPos = isShift ? snapToAngle(rawCanvasPos) : rawCanvasPos
        switch currentTool {
        case .select:
            if let curveID = selectedCurveID,
               let curveIndex = canvasState.curves.firstIndex(where: { $0.id == curveID }) {
                let curve = canvasState.curves[curveIndex]
                for (i, node) in curve.nodes.enumerated() {
                    let cp1Canvas = toCanvas(toScreen(node.controlPoint1))
                    let cp2Canvas = toCanvas(toScreen(node.controlPoint2))
                    if distance(canvasPos, cp1Canvas) < 10 / scale {
                        draggingControlPoint = (curveID: curveID, nodeIndex: i, isCP1: true)
                        return
                    }
                    if distance(canvasPos, cp2Canvas) < 10 / scale {
                        draggingControlPoint = (curveID: curveID, nodeIndex: i, isCP1: false)
                        return
                    }
                }
            }
            if let point = nearestPoint(to: canvasPos, threshold: 20 / scale) {
                if let curve = canvasState.curves.first(where: { c in
                    c.nodes.contains(where: { distance($0.point, point.position) < 1.0 })
                }) {
                    if selectedCurveID == curve.id {
                        draggingPointID = point.id
                        selectedPoint = point
                        selectedLine = nil
                        statusMessage = "\(point.name) を移動中"
                        return
                    }
                    selectedCurveID = curve.id
                    selectedPoint = nil
                    statusMessage = "曲線を選択中 / もう一度クリックで点を移動"
                    return
                }
                draggingPointID = point.id
                selectedPoint = point
                selectedCurveID = nil
                selectedLine = nil
                statusMessage = "\(point.name) を移動中"
                return
            }
            if let curve = nearestCurve(to: canvasPos) {
                selectedCurveID = curve.id
                selectedPoint = nil
                selectedLine = nil
                statusMessage = "曲線を選択中 / コントロールポイントをドラッグで編集"
                return
            }
            if let index = canvasState.lines.firstIndex(where: { l in
                distanceToLine(from: canvasPos, lineStart: l.startPoint, lineEnd: l.endPoint) < 15 / scale
            }) {
                selectedLine = canvasState.lines[index]
                selectedPoint = nil
                selectedCurveID = nil
                statusMessage = "線を選択中"
                return
            }
            if let arc = canvasState.arcs.first(where: {
                abs(distance($0.center, canvasPos) - $0.radius) < 20 / scale
            }) {
                selectedArcID = arc.id
                selectedPoint = nil; selectedLine = nil
                selectedCurveID = nil; selectedTextID = nil
                statusMessage = "円弧を選択中: 半径\(String(format: "%.1f", arc.radius / 37.8))cm"
                return
            }
            if let text = canvasState.texts.first(where: {
                distance($0.position, canvasPos) < 30 / scale
            }) {
                selectedTextID = text.id
                selectedPoint = nil; selectedLine = nil
                selectedCurveID = nil; draggingPointID = nil
                statusMessage = "テキストを選択中 / ドラッグで移動"
                return
            }
            selectedLine = nil; selectedCurveID = nil
            selectedPoint = nil; selectedTextID = nil

        case .delete:
            deleteNearestElement(to: canvasPos)

        case .groupSelect:
            let hasSelection = !groupSelectedPointIDs.isEmpty || !groupSelectedLineIDs.isEmpty ||
                               !groupSelectedArcIDs.isEmpty  || !groupSelectedTextIDs.isEmpty
            let nearPt  = canvasState.points.first(where: { groupSelectedPointIDs.contains($0.id) && distance($0.position, canvasPos) < 20 / scale })
            let nearArc = canvasState.arcs.first(where:   { groupSelectedArcIDs.contains($0.id)   && distance($0.center, canvasPos)   < 20 / scale })
            let nearTxt = canvasState.texts.first(where:  { groupSelectedTextIDs.contains($0.id)  && distance($0.position, canvasPos)  < 20 / scale })
            if hasSelection && (nearPt != nil || nearArc != nil || nearTxt != nil) {
                groupDragStart = canvasPos
            } else {
                groupSelectStart = canvasPos
                groupSelectEnd = canvasPos
                groupSelectedPointIDs = []
                groupSelectedLineIDs = []
                groupDragStart = nil
            }

        case .parallel:
            if let line = canvasState.lines.first(where: { l in
                distanceToLine(from: canvasPos, lineStart: l.startPoint, lineEnd: l.endPoint) < 15 / scale
            }) {
                parallelSourceLine = line
                statusMessage = "平行線の距離をクリックで指定してください"
            } else if let source = parallelSourceLine {
                addParallelLine(to: source, clickPoint: canvasPos)
            }

        case .perpendicular:
            if perpendicularSourceLine == nil {
                if let line = canvasState.lines.first(where: { l in
                    distanceToLine(from: canvasPos, lineStart: l.startPoint, lineEnd: l.endPoint) < 15 / scale
                }) {
                    perpendicularSourceLine = line
                    statusMessage = "垂直線の基点をクリックしてください（点にスナップします）"
                }
            } else if let source = perpendicularSourceLine {
                let snapped = nearestPoint(to: canvasPos, threshold: 20 / scale)
                addPerpendicularLine(to: source, fromPoint: snapped?.position ?? canvasPos)
            }

        case .extend:
            if let line = canvasState.lines.first(where: { l in
                distanceToLine(from: canvasPos, lineStart: l.startPoint, lineEnd: l.endPoint) < 15 / scale
            }) {
                extendSourceLine = line
                statusMessage = "延長先をクリックしてください"
            } else if let source = extendSourceLine {
                extendLine(source, to: canvasPos)
            }

        case .midpoint:
            if let line = canvasState.lines.first(where: { l in
                distanceToLine(from: canvasPos, lineStart: l.startPoint, lineEnd: l.endPoint) < 15 / scale
            }) {
                addMidpoint(of: line)
            }

        case .arc:
            if arcCenter == nil {
                arcCenter = canvasPos
                statusMessage = "円弧の開始点をクリックしてください"
            } else if arcStart == nil {
                arcStart = canvasPos
                statusMessage = "円弧の終了点をクリックしてください"
            } else if let center = arcCenter, let start = arcStart {
                addArc(center: center, start: start, end: canvasPos)
            }

        case .text:
            textInputPosition = canvasPos
            textInputValue = ""
            showTextInput = true

        default:
            break
        }
    }

    private func handleDragChanged(location: CGPoint) {
        let canvasPos = toCanvas(location)
        switch currentTool {
        case .select:
            if let id = selectedTextID,
               let index = canvasState.texts.firstIndex(where: { $0.id == id }) {
                canvasState.texts[index].position = canvasPos; return
            }
            if let id = selectedArcID,
               let index = canvasState.arcs.firstIndex(where: { $0.id == id }) {
                canvasState.arcs[index].center = canvasPos; return
            }
            if let cp = draggingControlPoint,
               let ci = canvasState.curves.firstIndex(where: { $0.id == cp.curveID }) {
                if cp.isCP1 {
                    canvasState.curves[ci].nodes[cp.nodeIndex].controlPoint1 = canvasPos
                } else {
                    canvasState.curves[ci].nodes[cp.nodeIndex].controlPoint2 = canvasPos
                }
                return
            }
            if let id = draggingPointID { movePoint(id: id, to: canvasPos) }
        case .groupSelect:
            if let dragStart = groupDragStart {
                let delta = CGPoint(x: canvasPos.x - dragStart.x, y: canvasPos.y - dragStart.y)
                moveGroupSelected(delta: delta)
                groupDragStart = canvasPos
            } else {
                groupSelectEnd = canvasPos
            }
        default:
            break
        }
    }

    private func handleDragEnded(location: CGPoint) {
        let rawCanvasPos = toCanvas(location)
        let canvasPos = isShiftPressed ? snapToAngle(rawCanvasPos) : rawCanvasPos
        switch currentTool {
        case .select:
            if draggingControlPoint != nil || draggingPointID != nil {
                canvasState.saveSnapshot()
            }
            draggingControlPoint = nil
            draggingPointID = nil
        case .addPoint:
            if let line = canvasState.lines.first(where: { l in
                distanceToLine(from: canvasPos, lineStart: l.startPoint, lineEnd: l.endPoint) < 10 / scale
            }) {
                lineToSplit = line
                splitClickPosition = canvasPos
            } else {
                let name = "P\(canvasState.points.count + 1)"
                let newPoint = PatternPoint(position: canvasPos, name: name)
                canvasState.points.append(newPoint)
                selectedPoint = newPoint
                statusMessage = "\(name) を追加しました"
                canvasState.saveSnapshot()
            }
        case .addLine:
            if let point = nearestPoint(to: canvasPos, threshold: 20 / scale) {
                pointTapped(point)
            }
        case .addCurve:
            addCurveNode(at: canvasPos)
        case .groupSelect:
            if groupDragStart != nil {
                canvasState.saveSnapshot()
                groupDragStart = nil
            } else if let start = groupSelectStart, let end = groupSelectEnd {
                applyGroupSelect(start: start, end: end)
            }
            groupSelectStart = nil
            groupSelectEnd = nil
        default:
            break
        }
        draggingPointID = nil
    }

        private func handleDoubleClick(location: CGPoint) {
        let canvasPos = toCanvas(location)
        if currentTool == .addCurve {
            finalizeCurve()
        } else if currentTool == .select {
            if let text = canvasState.texts.first(where: {
                distance($0.position, canvasPos) < 30 / scale
            }) {
                selectedTextID = text.id
                textInputValue = text.text
                textInputPosition = text.position
                showTextInput = true
            }
        }
    }

    private func addCurveNode(at point: CGPoint) {
        let snapPoint = nearestPoint(to: point, threshold: 20 / scale)
        let nodePoint = snapPoint?.position ?? point
        let node = CurveNode(
            point: nodePoint,
            controlPoint1: CGPoint(x: nodePoint.x - 30, y: nodePoint.y),
            controlPoint2: CGPoint(x: nodePoint.x + 30, y: nodePoint.y)
        )
        curveNodes.append(node)
        if snapPoint != nil {
            statusMessage = "\(snapPoint!.name) をノードに追加 / Enterキーで確定"
        } else {
            statusMessage = "ノード\(curveNodes.count)個 / Enterキーで確定"
        }
    }

    private func finalizeCurve() {
        guard curveNodes.count >= 2 else {
            statusMessage = "2点以上クリックしてから確定してください"
            return
        }
        let curve = CurveData(nodes: curveNodes)
        canvasState.curves.append(curve)
        canvasState.saveSnapshot()
        selectedCurveID = curve.id
        curveNodes = []
        statusMessage = "曲線を追加しました / コントロールポイントをドラッグで編集"
    }

    private func nearestPoint(to location: CGPoint, threshold: CGFloat) -> PatternPoint? {
        canvasState.points.first { point in
            distance(point.position, location) < threshold
        }
    }

    private func nearestCurve(to location: CGPoint) -> CurveData? {
        let threshold: CGFloat = 15 / scale
        for curve in canvasState.curves {
            for node in curve.nodes {
                if distance(node.point, location) < threshold { return curve }
            }
            for i in 0..<curve.nodes.count - 1 {
                let from = curve.nodes[i]
                let to = curve.nodes[i + 1]
                let steps = 20
                for j in 0..<steps {
                    let t0 = CGFloat(j) / CGFloat(steps)
                    let t1 = CGFloat(j + 1) / CGFloat(steps)
                    let p0 = bezierPoint(from: from, to: to, t: t0)
                    let p1 = bezierPoint(from: from, to: to, t: t1)
                    if distanceToLine(from: location, lineStart: p0, lineEnd: p1) < threshold {
                        return curve
                    }
                }
            }
        }
        return nil
    }

    private func bezierPoint(from: CurveNode, to: CurveNode, t: CGFloat) -> CGPoint {
        let cp1 = from.controlPoint2
        let cp2 = to.controlPoint1
        let mt = 1 - t
        return CGPoint(
            x: mt*mt*mt*from.point.x + 3*mt*mt*t*cp1.x + 3*mt*t*t*cp2.x + t*t*t*to.point.x,
            y: mt*mt*mt*from.point.y + 3*mt*mt*t*cp1.y + 3*mt*t*t*cp2.y + t*t*t*to.point.y
        )
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func movePoint(id: UUID, to position: CGPoint) {
        guard let index = canvasState.points.firstIndex(where: { $0.id == id }) else { return }
        let oldPosition = canvasState.points[index].position
        canvasState.points[index].position = position
        if selectedPoint?.id == id {
            selectedPoint = canvasState.points[index]
        }
        canvasState.lines = canvasState.lines.map { line in
            var newLine = line
            if newLine.startPoint == oldPosition { newLine.startPoint = position }
            if newLine.endPoint == oldPosition { newLine.endPoint = position }
            return newLine
        }
        let delta = CGPoint(x: position.x - oldPosition.x, y: position.y - oldPosition.y)
        canvasState.curves = canvasState.curves.map { curve in
            var c = curve
            c.nodes = c.nodes.map { node in
                var n = node
                if distance(n.point, oldPosition) < 1.0 {
                    n.point = position
                    n.controlPoint1 = CGPoint(x: n.controlPoint1.x + delta.x, y: n.controlPoint1.y + delta.y)
                    n.controlPoint2 = CGPoint(x: n.controlPoint2.x + delta.x, y: n.controlPoint2.y + delta.y)
                }
                return n
            }
            return c
        }
    }

    private func pointTapped(_ point: PatternPoint) {
        if let selected = selectedPoint, selected.id != point.id {
            canvasState.lines.append(PatternLine(startPoint: selected.position, endPoint: point.position))
            selectedPoint = point
            statusMessage = "\(selected.name) → \(point.name) に線を引きました"
            canvasState.saveSnapshot()
        } else {
            selectedPoint = point
            statusMessage = "終点をクリックしてください"
        }
    }

    private func deleteNearestElement(to location: CGPoint) {
        let threshold: CGFloat = 20 / scale

        if let curve = nearestCurve(to: location),
           let index = canvasState.curves.firstIndex(where: { $0.id == curve.id }) {
            canvasState.curves.remove(at: index)
            if selectedCurveID == curve.id { selectedCurveID = nil }
            statusMessage = "曲線を削除しました"
            canvasState.saveSnapshot()
            return
        }

        if let index = canvasState.points.firstIndex(where: { distance($0.position, location) < threshold }) {
            let deletedPoint = canvasState.points[index]
            canvasState.points.remove(at: index)
            canvasState.lines.removeAll {
                $0.startPoint == deletedPoint.position || $0.endPoint == deletedPoint.position
            }
            if selectedPoint?.id == deletedPoint.id { selectedPoint = nil }
            statusMessage = "\(deletedPoint.name) を削除しました"
            canvasState.saveSnapshot()
            return
        }

        if let index = canvasState.lines.firstIndex(where: { line in
            distanceToLine(from: location, lineStart: line.startPoint, lineEnd: line.endPoint) < threshold
        }) {
            canvasState.lines.remove(at: index)
            statusMessage = "線を削除しました"
            canvasState.saveSnapshot()
        }
        // 円弧を削除
        if let index = canvasState.arcs.firstIndex(where: { arc in
            abs(distance(arc.center, location) - arc.radius) < threshold
        }) {
            canvasState.arcs.remove(at: index)
            statusMessage = "円弧を削除しました"
            canvasState.saveSnapshot()
            return
        }

        // テキストを削除
        if let index = canvasState.texts.firstIndex(where: {
            distance($0.position, location) < threshold
        }) {
            canvasState.texts.remove(at: index)
            statusMessage = "テキストを削除しました"
            canvasState.saveSnapshot()
        }
    }

    private func splitLine(line: PatternLine, t: CGFloat) {
        guard let index = canvasState.lines.firstIndex(where: { $0.id == line.id }) else { return }
        let splitPoint = CGPoint(
            x: line.startPoint.x + (line.endPoint.x - line.startPoint.x) * t,
            y: line.startPoint.y + (line.endPoint.y - line.startPoint.y) * t
        )
        let newPoint = PatternPoint(
            position: splitPoint,
            name: "P\(canvasState.points.count + 1)"
        )
        canvasState.points.append(newPoint)
        canvasState.lines.remove(at: index)
        canvasState.lines.append(PatternLine(startPoint: line.startPoint, endPoint: splitPoint))
        canvasState.lines.append(PatternLine(startPoint: splitPoint, endPoint: line.endPoint))
        selectedPoint = newPoint
        statusMessage = "\(newPoint.name) を追加して線を分割しました"
        canvasState.saveSnapshot()
    }

    private func snapToAngle(_ position: CGPoint) -> CGPoint {
        guard let selected = selectedPoint else { return position }
        let dx = position.x - selected.position.x
        let dy = position.y - selected.position.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return position }
        let angle = atan2(dy, dx)
        let snapAngles: [CGFloat] = [0, .pi/4, .pi/2, 3 * .pi/4, .pi, -3 * .pi/4, -.pi/2, -.pi/4]
        let nearestAngle = snapAngles.min(by: {
            abs(angle - $0) < abs(angle - $1)
        }) ?? angle
        return CGPoint(
            x: selected.position.x + cos(nearestAngle) * dist,
            y: selected.position.y + sin(nearestAngle) * dist
        )
    }
    
    private func moveGroupSelected(delta: CGPoint) {
        // 移動前の選択点座標スナップショット（座標比較用）
        // 閾値を広めにとって浮動小数点誤差を吸収
        let selectedPositions: [CGPoint] = canvasState.points
            .filter { groupSelectedPointIDs.contains($0.id) }
            .map { $0.position }

        func isSelectedPos(_ p: CGPoint) -> Bool {
            selectedPositions.contains(where: { abs($0.x - p.x) < 2.0 && abs($0.y - p.y) < 2.0 })
        }

        // 点を移動
        canvasState.points = canvasState.points.map { point in
            guard groupSelectedPointIDs.contains(point.id) else { return point }
            var p = point
            p.position = CGPoint(x: p.position.x + delta.x, y: p.position.y + delta.y)
            return p
        }

        // 線を移動（端点が選択点と一致するものも追従）
        canvasState.lines = canvasState.lines.map { line in
            var l = line
            let sSelected = groupSelectedLineIDs.contains(line.id) || isSelectedPos(l.startPoint)
            let eSelected = groupSelectedLineIDs.contains(line.id) || isSelectedPos(l.endPoint)
            if sSelected {
                l.startPoint = CGPoint(x: l.startPoint.x + delta.x, y: l.startPoint.y + delta.y)
            }
            if eSelected {
                l.endPoint = CGPoint(x: l.endPoint.x + delta.x, y: l.endPoint.y + delta.y)
            }
            return l
        }

        // 曲線を移動（IDで選択されたもの全体 OR ノード点が選択点に一致するもの）
        canvasState.curves = canvasState.curves.map { curve in
            var c = curve
            if groupSelectedCurveIDs.contains(curve.id) {
                // 曲線全体を移動
                c.nodes = c.nodes.map { node in
                    var n = node
                    n.point         = CGPoint(x: n.point.x         + delta.x, y: n.point.y         + delta.y)
                    n.controlPoint1 = CGPoint(x: n.controlPoint1.x + delta.x, y: n.controlPoint1.y + delta.y)
                    n.controlPoint2 = CGPoint(x: n.controlPoint2.x + delta.x, y: n.controlPoint2.y + delta.y)
                    return n
                }
            } else {
                // ノード点が選択点と一致するものだけ移動
                c.nodes = c.nodes.map { node in
                    var n = node
                    if isSelectedPos(node.point) {
                        n.point         = CGPoint(x: n.point.x         + delta.x, y: n.point.y         + delta.y)
                        n.controlPoint1 = CGPoint(x: n.controlPoint1.x + delta.x, y: n.controlPoint1.y + delta.y)
                        n.controlPoint2 = CGPoint(x: n.controlPoint2.x + delta.x, y: n.controlPoint2.y + delta.y)
                    }
                    return n
                }
            }
            return c
        }

        // 円弧を移動
        canvasState.arcs = canvasState.arcs.map { arc in
            guard groupSelectedArcIDs.contains(arc.id) else { return arc }
            var a = arc
            a.center = CGPoint(x: a.center.x + delta.x, y: a.center.y + delta.y)
            return a
        }

        // テキストを移動
        canvasState.texts = canvasState.texts.map { text in
            guard groupSelectedTextIDs.contains(text.id) else { return text }
            var t = text
            t.position = CGPoint(x: t.position.x + delta.x, y: t.position.y + delta.y)
            return t
        }
    }
    
    private func deleteGroupSelected() {
        canvasState.saveSnapshot()
        let deletedPositions = canvasState.points
            .filter { groupSelectedPointIDs.contains($0.id) }
            .map { $0.position }
        canvasState.points.removeAll { groupSelectedPointIDs.contains($0.id) }
        canvasState.lines.removeAll { line in
            groupSelectedLineIDs.contains(line.id) ||
            deletedPositions.contains(where: { abs($0.x - line.startPoint.x) < 0.1 && abs($0.y - line.startPoint.y) < 0.1 }) ||
            deletedPositions.contains(where: { abs($0.x - line.endPoint.x) < 0.1 && abs($0.y - line.endPoint.y) < 0.1 })
        }
        canvasState.curves.removeAll { curve in
            groupSelectedCurveIDs.contains(curve.id) ||
            curve.nodes.contains(where: { node in
                deletedPositions.contains(where: { abs($0.x - node.point.x) < 0.1 && abs($0.y - node.point.y) < 0.1 })
            })
        }
        groupSelectedPointIDs = []
        groupSelectedLineIDs = []
        
        // 円弧を削除
        canvasState.arcs.removeAll { groupSelectedArcIDs.contains($0.id) }
        // テキストを削除
        canvasState.texts.removeAll { groupSelectedTextIDs.contains($0.id) }
        groupSelectedArcIDs = []
        groupSelectedTextIDs = []
        
        statusMessage = "削除しました"
    }

    // 平行線を追加
    private func addParallelLine(to source: PatternLine, clickPoint: CGPoint) {
        let dx = source.endPoint.x - source.startPoint.x
        let dy = source.endPoint.y - source.startPoint.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return }
        let nx = -dy / len
        let ny = dx / len
        let dotX = clickPoint.x - source.startPoint.x
        let dotY = clickPoint.y - source.startPoint.y
        let dist = dotX * nx + dotY * ny
        let newStart = CGPoint(x: source.startPoint.x + nx * dist, y: source.startPoint.y + ny * dist)
        let newEnd = CGPoint(x: source.endPoint.x + nx * dist, y: source.endPoint.y + ny * dist)
        canvasState.lines.append(PatternLine(startPoint: newStart, endPoint: newEnd))
        canvasState.saveSnapshot()
        parallelSourceLine = nil
        statusMessage = "平行線を追加しました"
    }

    // ▼ 修正6: 垂直線を追加 — 始点スナップ済み + 足に PatternPoint を追加
    private func addPerpendicularLine(to source: PatternLine, fromPoint: CGPoint) {
        let foot = calcPerpendicularFoot(source: source, fromPoint: fromPoint)

        // 始点: 既存点があればそれを使い、なければ新規点を追加
        let startPoint: PatternPoint
        if let existing = canvasState.points.first(where: { distance($0.position, fromPoint) < 1.0 }) {
            startPoint = existing
        } else {
            let newStart = PatternPoint(
                position: fromPoint,
                name: "P\(canvasState.points.count + 1)"
            )
            canvasState.points.append(newStart)
            startPoint = newStart
        }

        // 終点（足）: 既存点があればそれを使い、なければ新規点を追加
        let endPoint: PatternPoint
        if let existing = canvasState.points.first(where: { distance($0.position, foot) < 1.0 }) {
            endPoint = existing
        } else {
            let newEnd = PatternPoint(
                position: foot,
                name: "P\(canvasState.points.count + 1)"
            )
            canvasState.points.append(newEnd)
            endPoint = newEnd
        }

        canvasState.lines.append(PatternLine(startPoint: startPoint.position, endPoint: endPoint.position))
        canvasState.saveSnapshot()
        perpendicularSourceLine = nil
        perpendicularPreview = nil
        statusMessage = "垂直線を追加しました (\(startPoint.name) → \(endPoint.name))"
    }

    // 線を延長
    private func extendLine(_ source: PatternLine, to point: CGPoint) {
        let dx = source.endPoint.x - source.startPoint.x
        let dy = source.endPoint.y - source.startPoint.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return }
        let t = ((point.x - source.startPoint.x) * dx + (point.y - source.startPoint.y) * dy) / (len * len)
        if let index = canvasState.lines.firstIndex(where: { $0.id == source.id }) {
            if t > 1 {
                canvasState.lines[index].endPoint = CGPoint(
                    x: source.startPoint.x + dx * t,
                    y: source.startPoint.y + dy * t
                )
            } else if t < 0 {
                canvasState.lines[index].startPoint = CGPoint(
                    x: source.startPoint.x + dx * t,
                    y: source.startPoint.y + dy * t
                )
            }
        }
        canvasState.saveSnapshot()
        extendSourceLine = nil
        statusMessage = "線を延長しました"
    }

    // 中点を追加
    private func addMidpoint(of line: PatternLine) {
        let mid = CGPoint(
            x: (line.startPoint.x + line.endPoint.x) / 2,
            y: (line.startPoint.y + line.endPoint.y) / 2
        )
        let newPoint = PatternPoint(position: mid, name: "P\(canvasState.points.count + 1)")
        canvasState.points.append(newPoint)
        canvasState.saveSnapshot()
        statusMessage = "\(newPoint.name) を中点に追加しました"
    }

    // 円弧を追加
    private func addArc(center: CGPoint, start: CGPoint, end: CGPoint) {
        let dx1 = start.x - center.x
        let dy1 = start.y - center.y
        let radius = sqrt(dx1 * dx1 + dy1 * dy1)
        let startAngle = atan2(dy1, dx1) * 180 / .pi
        let dx2 = end.x - center.x
        let dy2 = end.y - center.y
        let endAngle = atan2(dy2, dx2) * 180 / .pi
        let arc = ArcData(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle)
        canvasState.arcs.append(arc)
        canvasState.saveSnapshot()
        arcCenter = nil
        arcStart = nil
        statusMessage = "円弧を追加しました"
    }
    
    // 範囲選択を確定
    private func applyGroupSelect(start: CGPoint, end: CGPoint) {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)

        let pointIDs: Set<UUID> = Set(canvasState.points.filter { p in
            p.position.x >= minX && p.position.x <= maxX &&
            p.position.y >= minY && p.position.y <= maxY
        }.map { $0.id })

        let lineIDs: Set<UUID> = Set(canvasState.lines.filter { l in
            l.startPoint.x >= minX && l.startPoint.x <= maxX &&
            l.startPoint.y >= minY && l.startPoint.y <= maxY &&
            l.endPoint.x >= minX && l.endPoint.x <= maxX &&
            l.endPoint.y >= minY && l.endPoint.y <= maxY
        }.map { $0.id })

        let arcIDs: Set<UUID> = Set(canvasState.arcs.filter { a in
            a.center.x >= minX && a.center.x <= maxX &&
            a.center.y >= minY && a.center.y <= maxY
        }.map { $0.id })

        let textIDs: Set<UUID> = Set(canvasState.texts.filter { t in
            t.position.x >= minX && t.position.x <= maxX &&
            t.position.y >= minY && t.position.y <= maxY
        }.map { $0.id })

        let curveIDs: Set<UUID> = Set(canvasState.curves.filter { curve in
            curve.nodes.allSatisfy { node in
                node.point.x >= minX && node.point.x <= maxX &&
                node.point.y >= minY && node.point.y <= maxY
            }
        }.map { $0.id })
        groupSelectedPointIDs = pointIDs
        groupSelectedLineIDs  = lineIDs
        groupSelectedArcIDs   = arcIDs
        groupSelectedTextIDs  = textIDs
        groupSelectedCurveIDs = curveIDs
        statusMessage = "点\(pointIDs.count)個、線\(lineIDs.count)本、曲線\(curveIDs.count)本を選択"
    }

    // 全要素を選択
    private func selectAll() {
        let pointIDs: Set<UUID> = Set(canvasState.points.map { $0.id })
        let lineIDs:  Set<UUID> = Set(canvasState.lines.map  { $0.id })
        let arcIDs:   Set<UUID> = Set(canvasState.arcs.map   { $0.id })
        let textIDs:  Set<UUID> = Set(canvasState.texts.map  { $0.id })
        let curveIDs: Set<UUID> = Set(canvasState.curves.map { $0.id })
        groupSelectedPointIDs = pointIDs
        groupSelectedLineIDs  = lineIDs
        groupSelectedArcIDs   = arcIDs
        groupSelectedTextIDs  = textIDs
        groupSelectedCurveIDs = curveIDs
        currentTool = .groupSelect
        statusMessage = "全て選択: 点\(pointIDs.count)個、線\(lineIDs.count)本、曲線\(curveIDs.count)本"
    }

    // ゴーストデータを更新（パーツ切替・起動時に呼ぶ）
    private func updateGhostParts() {
        guard let project = projectManager.currentProject else {
            ghostPartsData = []
            return
        }
        let spacing: CGFloat = 60  // px単位（scale非依存）
        let paperW = canvasState.currentPaperSize.width  // px

        // プロジェクト全パーツを固定順で並べる
        // アクティブパーツは offsetX=0（アクティブ枠と重なる位置）
        // 他パーツは全パーツのインデックスに基づいた固定位置
        var result: [(id: UUID, name: String, data: PatternData, offsetX: CGFloat)] = []
        for (idx, part) in project.parts.enumerated() {
            guard part.id != projectManager.activePartID else { continue }
            guard let data = projectManager.loadPatternData(for: part.id) else { continue }
            // 全パーツ順の idx をそのまま使って固定位置を決める
            let offsetX = (paperW + spacing) * CGFloat(idx)
            result.append((id: part.id, name: part.name, data: data, offsetX: offsetX))
        }
        ghostPartsData = result
    }

    private func distanceToLine(from point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return CGFloat.infinity }
        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / (length * length)))
        let nearestX = lineStart.x + t * dx
        let nearestY = lineStart.y + t * dy
        let ex = point.x - nearestX
        let ey = point.y - nearestY
        return sqrt(ex * ex + ey * ey)
    }
}

struct CanvasNSViewRepresentable: NSViewRepresentable {
    var onScroll: (CGPoint) -> Void
    var onMouseMove: (CGPoint, Bool) -> Void
    var onDragBegan: (CGPoint, Bool) -> Void
    var onDragChanged: (CGPoint) -> Void
    var onDragEnded: (CGPoint) -> Void
    var onDoubleClick: (CGPoint) -> Void
    var onEnterKey: () -> Void
    var onSelectAll: () -> Void
    var onDeleteKey: () -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.onScroll = onScroll
        view.onMouseMove = onMouseMove
        view.onDragBegan = onDragBegan
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onDoubleClick = onDoubleClick
        view.onEnterKey = onEnterKey
        view.onDeleteKey = onDeleteKey
        view.onSelectAll = onSelectAll
        
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onMouseMove = onMouseMove
        nsView.onDragBegan = onDragBegan
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        nsView.onDoubleClick = onDoubleClick
        nsView.onEnterKey = onEnterKey
        nsView.onDeleteKey = onDeleteKey
        nsView.onSelectAll = onSelectAll
    }
}
