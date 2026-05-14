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

    @State private var offset: CGSize = CGSize(width: 40, height: 40)
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
    @Binding var selectedArcID: UUID?

    @State private var groupSelectedArcIDs: Set<UUID> = []
    @State private var groupSelectedTextIDs: Set<UUID> = []

    private func toScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale + offset.width, y: p.y * scale + offset.height)
    }

    private func toCanvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.width) / scale, y: (p.y - offset.height) / scale)
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
                    // 用紙境界線
                    let paperW = canvasState.currentPaperSize.width * scale
                    let paperH = canvasState.currentPaperSize.height * scale
                    let paperX = offset.width
                    let paperY = offset.height
                    Path { path in
                        path.addRect(CGRect(x: paperX, y: paperY, width: paperW, height: paperH))
                    }
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)

                    // 線を描画（寸法付き）
                    ForEach(canvasState.lines) { line in
                        let p1 = toScreen(line.startPoint)
                        let p2 = toScreen(line.endPoint)
                        let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                        let isSelected = selectedLine?.id == line.id
                        ZStack {
                            Path { path in
                                path.move(to: p1)
                                path.addLine(to: p2)
                            }
                            .stroke(isSelected ? Color.blue : Color.black, lineWidth: isSelected ? 2.5 : 1.5)
                            Text(String(format: "%.1fcm", line.lengthCm))
                                .font(.system(size: 9))
                                .foregroundColor(isSelected ? Color.blue : Color.gray)
                                .position(CGPoint(x: mid.x + 8, y: mid.y - 8))

                            // 選択中の線のみ起点・終点を表示
                            if isSelected {
                                // 起点（赤い四角）
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .position(p1)
                                // 終点（緑の四角）
                                Rectangle()
                                    .fill(Color.green)
                                    .frame(width: 10, height: 10)
                                    .position(p2)
                            }
                        }
                    }
                    
                    // 縫い代を描画
                    if canvasState.showSeamAllowance {
                        ForEach(canvasState.lines) { line in
                            let p1 = toScreen(line.startPoint)
                            let p2 = toScreen(line.endPoint)
                            let dx = p2.x - p1.x
                            let dy = p2.y - p1.y
                            let len = sqrt(dx * dx + dy * dy)
                            if len > 0 {
                                let nx = -dy / len * canvasState.seamAllowance * 37.8 * scale
                                let ny = dx / len * canvasState.seamAllowance * 37.8 * scale
                                let sp1 = CGPoint(x: p1.x + nx, y: p1.y + ny)
                                let sp2 = CGPoint(x: p2.x + nx, y: p2.y + ny)
                                Path { path in
                                    path.move(to: sp1)
                                    path.addLine(to: sp2)
                                }
                                .stroke(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            }
                        }
                    }
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
                    ForEach(canvasState.lines) { line in
                        let p1 = toScreen(line.startPoint)
                        let p2 = toScreen(line.endPoint)
                        let dx = p2.x - p1.x
                        let dy = p2.y - p1.y
                        let len = sqrt(dx * dx + dy * dy)
                        if len > 0 {
                            let nx = -dy / len * 20
                            let ny = dx / len * 20
                            Path { path in
                                path.move(to: CGPoint(x: p1.x + nx * 0.3, y: p1.y + ny * 0.3))
                                path.addLine(to: CGPoint(x: p1.x + nx * 1.2, y: p1.y + ny * 1.2))
                                path.move(to: CGPoint(x: p2.x + nx * 0.3, y: p2.y + ny * 0.3))
                                path.addLine(to: CGPoint(x: p2.x + nx * 1.2, y: p2.y + ny * 1.2))
                                path.move(to: CGPoint(x: p1.x + nx, y: p1.y + ny))
                                path.addLine(to: CGPoint(x: p2.x + nx, y: p2.y + ny))
                            }
                            .stroke(Color.blue.opacity(0.4), lineWidth: 0.8)
                        }
                    }

                    // Shiftスナップのプレビュー
                    if let preview = shiftSnapPreview, let selected = selectedPoint {
                        let screenPreview = toScreen(preview)
                        let screenSelected = toScreen(selected.position)
                        Path { path in
                            path.move(to: screenSelected)
                            path.addLine(to: screenPreview)
                        }
                        .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        Circle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: 8, height: 8)
                            .position(screenPreview)
                    }
                    // グループ選択の矩形プレビュー
                    if let start = groupSelectStart, let end = groupSelectEnd {
                        let rect = CGRect(
                            x: min(toScreen(start).x, toScreen(end).x),
                            y: min(toScreen(start).y, toScreen(end).y),
                            width: abs(toScreen(end).x - toScreen(start).x),
                            height: abs(toScreen(end).y - toScreen(start).y)
                        )
                        Path { path in
                            path.addRect(rect)
                        }
                        .stroke(Color.blue.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        Path { path in
                            path.addRect(rect)
                        }
                        .fill(Color.blue.opacity(0.1))
                    }
                    // 原点マーカー
                    let originScreen = toScreen(.zero)
                    if originScreen.x >= 0 && originScreen.x <= geometry.size.width &&
                       originScreen.y >= 0 && originScreen.y <= geometry.size.height {
                        Path { path in
                            path.move(to: CGPoint(x: originScreen.x - 10, y: originScreen.y))
                            path.addLine(to: CGPoint(x: originScreen.x + 10, y: originScreen.y))
                            path.move(to: CGPoint(x: originScreen.x, y: originScreen.y - 10))
                            path.addLine(to: CGPoint(x: originScreen.x, y: originScreen.y + 10))
                        }
                        .stroke(Color.red.opacity(0.7), lineWidth: 1.5)
                        Text("0")
                            .font(.system(size: 9))
                            .foregroundColor(.red.opacity(0.7))
                            .position(CGPoint(x: originScreen.x + 12, y: originScreen.y - 12))
                    }

                    // スケールバー（画面左下に表示）
                    let scaleBarCm: CGFloat = 5
                    let scaleBarPx = scaleBarCm * 37.8 * scale
                    let scaleBarX: CGFloat = 20
                    let scaleBarY = geometry.size.height - 20
                    Path { path in
                        path.move(to: CGPoint(x: scaleBarX, y: scaleBarY))
                        path.addLine(to: CGPoint(x: scaleBarX + scaleBarPx, y: scaleBarY))
                        path.move(to: CGPoint(x: scaleBarX, y: scaleBarY - 4))
                        path.addLine(to: CGPoint(x: scaleBarX, y: scaleBarY + 4))
                        path.move(to: CGPoint(x: scaleBarX + scaleBarPx, y: scaleBarY - 4))
                        path.addLine(to: CGPoint(x: scaleBarX + scaleBarPx, y: scaleBarY + 4))
                    }
                    .stroke(Color.black.opacity(0.6), lineWidth: 1.5)
                    Text("5cm")
                        .font(.system(size: 9))
                        .foregroundColor(.black.opacity(0.6))
                        .position(CGPoint(x: scaleBarX + scaleBarPx / 2, y: scaleBarY - 10))
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
                    },
                    onDragBegan: { location, isShift in
                        isShiftPressed = isShift
                        let rawCanvasPos = toCanvas(location)
                        let canvasPos = isShift ? snapToAngle(rawCanvasPos) : rawCanvasPos
                        print("onDragBegan tool:\(currentTool) pos:\(canvasPos)")
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
                                if let curve = canvasState.curves.first(where: { curve in
                                    curve.nodes.contains(where: { distance($0.point, point.position) < 1.0 })
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

                            if let index = canvasState.lines.firstIndex(where: { line in
                                distanceToLine(from: canvasPos, lineStart: line.startPoint, lineEnd: line.endPoint) < 15 / scale
                            }) {
                                selectedLine = canvasState.lines[index]
                                selectedPoint = nil
                                selectedCurveID = nil
                                statusMessage = "線を選択中"
                                return
                            }
                            if let index = canvasState.lines.firstIndex(where: { line in
                                distanceToLine(from: canvasPos, lineStart: line.startPoint, lineEnd: line.endPoint) < 15 / scale
                            }) {
                                selectedLine = canvasState.lines[index]
                                selectedPoint = nil
                                selectedCurveID = nil
                                statusMessage = "線を選択中"
                                return
                            }

                            // 円弧の選択確認
                            print("scale:\(scale) threshold:\(20 / scale)")
                            print("arcs count: \(canvasState.arcs.count)")
                            for arc in canvasState.arcs {
                                let d = distance(arc.center, canvasPos)
                                print("arc center:\(arc.center) radius:\(arc.radius) distance:\(d) diff:\(abs(d - arc.radius))")
                            }
                            if let arc = canvasState.arcs.first(where: {
                                abs(distance($0.center, canvasPos) - $0.radius) < 20 / scale
                            }) {
                                selectedArcID = arc.id
                                selectedPoint = nil
                                selectedLine = nil
                                selectedCurveID = nil
                                selectedTextID = nil
                                statusMessage = "円弧を選択中: 半径\(String(format: "%.1f", arc.radius / 37.8))cm"
                                return
                            }
                            
                            // テキストの選択確認
                            if let text = canvasState.texts.first(where: {
                                distance($0.position, canvasPos) < 30 / scale
                            }) {
                                selectedTextID = text.id
                                selectedPoint = nil
                                selectedLine = nil
                                selectedCurveID = nil
                                draggingPointID = nil
                                statusMessage = "テキストを選択中 / ドラッグで移動"
                                return
                            }
                            
                            selectedLine = nil
                            selectedCurveID = nil
                            selectedPoint = nil
                            selectedTextID = nil

                        case .delete:
                            deleteNearestElement(to: canvasPos)

                        case .groupSelect:
                            let hasSelection = !groupSelectedPointIDs.isEmpty ||
                                              !groupSelectedLineIDs.isEmpty ||
                                              !groupSelectedArcIDs.isEmpty ||
                                              !groupSelectedTextIDs.isEmpty
                            let nearSelectedPoint = canvasState.points.first(where: {
                                groupSelectedPointIDs.contains($0.id) &&
                                distance($0.position, canvasPos) < 20 / scale
                            })
                            let nearSelectedArc = canvasState.arcs.first(where: {
                                groupSelectedArcIDs.contains($0.id) &&
                                distance($0.center, canvasPos) < 20 / scale
                            })
                            let nearSelectedText = canvasState.texts.first(where: {
                                groupSelectedTextIDs.contains($0.id) &&
                                distance($0.position, canvasPos) < 20 / scale
                            })
                            if hasSelection && (nearSelectedPoint != nil || nearSelectedArc != nil || nearSelectedText != nil) {
                                groupDragStart = canvasPos
                            } else {
                                groupSelectStart = canvasPos
                                groupSelectEnd = canvasPos
                                groupSelectedPointIDs = []
                                groupSelectedLineIDs = []
                                groupDragStart = nil
                            }
                        case .parallel:
                            if let line = canvasState.lines.first(where: { line in
                                distanceToLine(from: canvasPos, lineStart: line.startPoint, lineEnd: line.endPoint) < 15 / scale
                            }) {
                                parallelSourceLine = line
                                statusMessage = "平行線の距離をクリックで指定してください"
                            } else if let source = parallelSourceLine {
                                addParallelLine(to: source, clickPoint: canvasPos)
                            }

                        case .perpendicular:
                            if let line = canvasState.lines.first(where: { line in
                                distanceToLine(from: canvasPos, lineStart: line.startPoint, lineEnd: line.endPoint) < 15 / scale
                            }) {
                                perpendicularSourceLine = line
                                statusMessage = "垂直線の基点をクリックしてください"
                            } else if let source = perpendicularSourceLine {
                                addPerpendicularLine(to: source, fromPoint: canvasPos)                            }

                        case .extend:
                            if let line = canvasState.lines.first(where: { line in
                                distanceToLine(from: canvasPos, lineStart: line.startPoint, lineEnd: line.endPoint) < 15 / scale
                            }) {
                                extendSourceLine = line
                                statusMessage = "延長先をクリックしてください"
                            } else if let source = extendSourceLine {
                                extendLine(source, to: canvasPos)
                            }

                        case .midpoint:
                            if let line = canvasState.lines.first(where: { line in
                                distanceToLine(from: canvasPos, lineStart: line.startPoint, lineEnd: line.endPoint) < 15 / scale
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
                    },
                    onDragChanged: { location in
                        let canvasPos = toCanvas(location)
                        switch currentTool {
                        case .select:
                            // テキストの移動
                            if let id = selectedTextID,
                               let index = canvasState.texts.firstIndex(where: { $0.id == id }) {
                                canvasState.texts[index].position = canvasPos
                                return
                            }
                            // 円弧の移動
                            if let id = selectedArcID,
                               let index = canvasState.arcs.firstIndex(where: { $0.id == id }) {
                                canvasState.arcs[index].center = canvasPos
                                return
                            }

                            if let cp = draggingControlPoint,
                               let curveIndex = canvasState.curves.firstIndex(where: { $0.id == cp.curveID }) {
                                if cp.isCP1 {
                                    canvasState.curves[curveIndex].nodes[cp.nodeIndex].controlPoint1 = canvasPos
                                } else {
                                    canvasState.curves[curveIndex].nodes[cp.nodeIndex].controlPoint2 = canvasPos
                                }
                                return
                            }
                            if let id = draggingPointID {
                                movePoint(id: id, to: canvasPos)
                            }
                        case .groupSelect:
                            if let dragStart = groupDragStart {
                                // グループ移動
                                let delta = CGPoint(x: canvasPos.x - dragStart.x, y: canvasPos.y - dragStart.y)
                                moveGroupSelected(delta: delta)
                                groupDragStart = canvasPos
                            } else {
                                groupSelectEnd = canvasPos
                            }
                        default:
                            break
                        }
                    },
                    onDragEnded: { location in
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
                            if let line = canvasState.lines.first(where: { line in
                                distanceToLine(from: canvasPos, lineStart: line.startPoint, lineEnd: line.endPoint) < 10 / scale
                            }) {
                                lineToSplit = line
                                splitClickPosition = canvasPos
                            } else {
                                let newPoint = PatternPoint(
                                    position: canvasPos,
                                    name: "P\(canvasState.points.count + 1)"
                                )
                                canvasState.points.append(newPoint)
                                selectedPoint = newPoint
                                statusMessage = "\(newPoint.name) を追加しました"
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
                                let minX = min(start.x, end.x)
                                let maxX = max(start.x, end.x)
                                let minY = min(start.y, end.y)
                                let maxY = max(start.y, end.y)
                                // 範囲内の点を選択
                                groupSelectedPointIDs = Set(canvasState.points.filter { point in
                                    point.position.x >= minX && point.position.x <= maxX &&
                                    point.position.y >= minY && point.position.y <= maxY
                                }.map { $0.id })
                                // 範囲内の線を選択（両端点が範囲内）
                                groupSelectedLineIDs = Set(canvasState.lines.filter { line in
                                    (line.startPoint.x >= minX && line.startPoint.x <= maxX &&
                                     line.startPoint.y >= minY && line.startPoint.y <= maxY) &&
                                    (line.endPoint.x >= minX && line.endPoint.x <= maxX &&
                                     line.endPoint.y >= minY && line.endPoint.y <= maxY)
                                }.map { $0.id })
                                groupSelectedArcIDs = Set(canvasState.arcs.filter { arc in
                                        arc.center.x >= minX && arc.center.x <= maxX &&
                                        arc.center.y >= minY && arc.center.y <= maxY
                                    }.map { $0.id })
                                    groupSelectedTextIDs = Set(canvasState.texts.filter { text in
                                        text.position.x >= minX && text.position.x <= maxX &&
                                        text.position.y >= minY && text.position.y <= maxY
                                    }.map { $0.id })
                                    statusMessage = "点\(groupSelectedPointIDs.count)個、線\(groupSelectedLineIDs.count)本を選択"
                                }
                            groupSelectStart = nil
                            groupSelectEnd = nil
                            
                        default:
                            break
                        }
                        draggingPointID = nil
                    },
                    onDoubleClick: { location in
                            let canvasPos = toCanvas(location)
                            if currentTool == .addCurve {
                                finalizeCurve()
                            } else if currentTool == .select {
                                // テキストのダブルクリックで編集
                                if let text = canvasState.texts.first(where: {
                                    distance($0.position, canvasPos) < 30 / scale
                                }) {
                                    selectedTextID = text.id
                                    textInputValue = text.text
                                    textInputPosition = text.position
                                    showTextInput = true
                                }
                            }
                        },
                    onEnterKey: {
                        if currentTool == .addCurve {
                            finalizeCurve()
                        } else if currentTool == .addLine {
                            selectedPoint = nil
                            statusMessage = "始点をクリックしてください"
                        }
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
            extendSourceLine = nil
            arcCenter = nil
            arcStart = nil
            groupSelectedArcIDs = []
            groupSelectedTextIDs = []
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
        // 選択された点の元の位置を記録
        let selectedPositions = canvasState.points
            .filter { groupSelectedPointIDs.contains($0.id) }
            .map { $0.position }

        func isSelected(_ p: CGPoint) -> Bool {
            selectedPositions.contains(where: { abs($0.x - p.x) < 0.1 && abs($0.y - p.y) < 0.1 })
        }
        
        // 点を移動
        canvasState.points = canvasState.points.map { point in
            guard groupSelectedPointIDs.contains(point.id) else { return point }
            var p = point
            p.position = CGPoint(x: p.position.x + delta.x, y: p.position.y + delta.y)
            return p
        }

        // 線を移動
        canvasState.lines = canvasState.lines.map { line in
            var l = line
            if groupSelectedLineIDs.contains(line.id) {
                l.startPoint = CGPoint(x: l.startPoint.x + delta.x, y: l.startPoint.y + delta.y)
                l.endPoint = CGPoint(x: l.endPoint.x + delta.x, y: l.endPoint.y + delta.y)
            } else {
                if isSelected(l.startPoint) {
                    l.startPoint = CGPoint(x: l.startPoint.x + delta.x, y: l.startPoint.y + delta.y)
                }
                if isSelected(l.endPoint) {
                    l.endPoint = CGPoint(x: l.endPoint.x + delta.x, y: l.endPoint.y + delta.y)
                }
            }
            return l
        }
        
        // 曲線を移動（選択された点に接続している曲線）
        canvasState.curves = canvasState.curves.map { curve in
            var c = curve
            c.nodes = c.nodes.map { node in
                var n = node
                if isSelected(node.point) {
                    n.point = CGPoint(x: n.point.x + delta.x, y: n.point.y + delta.y)
                    n.controlPoint1 = CGPoint(x: n.controlPoint1.x + delta.x, y: n.controlPoint1.y + delta.y)
                    n.controlPoint2 = CGPoint(x: n.controlPoint2.x + delta.x, y: n.controlPoint2.y + delta.y)
                }
                return n
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

    // 垂直線を追加
    private func addPerpendicularLine(to source: PatternLine, fromPoint: CGPoint) {
        let dx = source.endPoint.x - source.startPoint.x
        let dy = source.endPoint.y - source.startPoint.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return }
        let t = ((fromPoint.x - source.startPoint.x) * dx + (fromPoint.y - source.startPoint.y) * dy) / (len * len)
        let footX = source.startPoint.x + t * dx
        let footY = source.startPoint.y + t * dy
        let foot = CGPoint(x: footX, y: footY)
        canvasState.lines.append(PatternLine(startPoint: fromPoint, endPoint: foot))
        canvasState.saveSnapshot()
        perpendicularSourceLine = nil
        statusMessage = "垂直線を追加しました"
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
        print("addArc center:\(center) radius:\(radius) startAngle:\(startAngle) endAngle:\(endAngle)")
        let arc = ArcData(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle)
        canvasState.arcs.append(arc)
        canvasState.saveSnapshot()
        arcCenter = nil
        arcStart = nil
        statusMessage = "円弧を追加しました"
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
    }
}
