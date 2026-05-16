//
//  CanvasView.swift
//  SewingCAD
//

import SwiftUI
import AppKit

// MARK: - スナップ結果
enum SnapResult {
    case none(CGPoint)
    case grid(CGPoint)
    case point(CGPoint, PatternPoint)
    case intersection(CGPoint)
    case midpoint(CGPoint)

    var position: CGPoint {
        switch self {
        case .none(let p), .grid(let p), .point(let p, _), .intersection(let p), .midpoint(let p):
            return p
        }
    }

    var color: Color {
        switch self {
        case .none: return .clear
        case .grid: return .gray
        case .point: return .blue
        case .intersection: return .green
        case .midpoint: return .orange
        }
    }

    var label: String {
        switch self {
        case .none: return ""
        case .grid: return "グリッド"
        case .point(_, let p): return p.name
        case .intersection: return "交点"
        case .midpoint: return "中点"
        }
    }
}

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
    @State private var parallelSourceLine: PatternLine? = nil
    @State private var perpendicularSourceLine: PatternLine? = nil
    @State private var extendSourceLine: PatternLine? = nil
    @State private var arcCenter: CGPoint? = nil
    @State private var arcStart: CGPoint? = nil
    @State private var showTextInput: Bool = false
    @State private var textInputPosition: CGPoint = .zero
    @State private var textInputValue: String = ""
    @State private var selectedTextID: UUID? = nil
    @Binding var selectedArcID: UUID?
    @Binding var gradingPointOut: PatternPoint?
    @Binding var seamOverrideLineOut: PatternLine?
    @Binding var resetOffsetTrigger: Bool
    @State private var groupSelectedArcIDs: Set<UUID> = []
    @State private var groupSelectedTextIDs: Set<UUID> = []

    // フェーズ1: スナップ
    @State private var snapResult: SnapResult = .none(.zero)
    @State private var snapEnabled: Bool = true
    @State private var gridSnapEnabled: Bool = true
    @State private var pointSnapEnabled: Bool = true
    @State private var intersectionSnapEnabled: Bool = true
    @State private var midpointSnapEnabled: Bool = false

    // フェーズ1: 寸法入力
    @State private var showLineInput: Bool = false
    @State private var lineInputFromPoint: PatternPoint? = nil

    // フェーズ1: 交点ツール用
    @State private var intersectionLine1: PatternLine? = nil

    // addLine用: 始点点
    @State private var lineStartPoint: PatternPoint? = nil

    // フェーズ2: 鏡像
    @State private var showMirror: Bool = false
    @State private var mirrorAxisLine: PatternLine? = nil

    // フェーズ2: ノッチ
    @State private var notchTargetLine: PatternLine? = nil
    @State private var notchT: CGFloat = 0.5

    // フェーズ2: 縫い代個別設定
    @State private var seamOverrideLine: PatternLine? = nil
    @State private var seamOverrideWidth: String = ""

    // フェーズ2: グレーディング
    @State private var gradingPoint: PatternPoint? = nil

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

    // MARK: - スナップ計算
    private func computeSnap(for rawCanvas: CGPoint) -> SnapResult {
        guard snapEnabled else { return .none(rawCanvas) }

        let snapRadius: CGFloat = 15 / scale

        // 1. 点スナップ（最優先）
        if pointSnapEnabled {
            if let nearest = canvasState.points.min(by: {
                distance($0.position, rawCanvas) < distance($1.position, rawCanvas)
            }), distance(nearest.position, rawCanvas) < snapRadius {
                return .point(nearest.position, nearest)
            }
        }

        // 2. 交点スナップ
        if intersectionSnapEnabled {
            for i in 0..<canvasState.lines.count {
                for j in (i+1)..<canvasState.lines.count {
                    if let pt = lineIntersection(canvasState.lines[i], canvasState.lines[j]) {
                        if distance(pt, rawCanvas) < snapRadius {
                            return .intersection(pt)
                        }
                    }
                }
            }
        }

        // 3. 中点スナップ
        if midpointSnapEnabled {
            for line in canvasState.lines {
                let mid = CGPoint(
                    x: (line.startPoint.x + line.endPoint.x) / 2,
                    y: (line.startPoint.y + line.endPoint.y) / 2
                )
                if distance(mid, rawCanvas) < snapRadius {
                    return .midpoint(mid)
                }
            }
        }

        // 4. グリッドスナップ
        if gridSnapEnabled {
            let gridSize: CGFloat = 37.8  // 1cm
            let snappedX = round(rawCanvas.x / gridSize) * gridSize
            let snappedY = round(rawCanvas.y / gridSize) * gridSize
            let snapped = CGPoint(x: snappedX, y: snappedY)
            if distance(snapped, rawCanvas) < snapRadius * 1.5 {
                return .grid(snapped)
            }
        }

        return .none(rawCanvas)
    }

    // 2直線の交点を計算
    private func lineIntersection(_ l1: PatternLine, _ l2: PatternLine) -> CGPoint? {
        let p1 = l1.startPoint, p2 = l1.endPoint
        let p3 = l2.startPoint, p4 = l2.endPoint
        let d1x = p2.x - p1.x, d1y = p2.y - p1.y
        let d2x = p4.x - p3.x, d2y = p4.y - p3.y
        let denom = d1x * d2y - d1y * d2x
        guard abs(denom) > 0.001 else { return nil }
        let t = ((p3.x - p1.x) * d2y - (p3.y - p1.y) * d2x) / denom
        // 線分の延長上も含む（無限直線として交点を求める）
        return CGPoint(x: p1.x + t * d1x, y: p1.y + t * d1y)
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

                    // 用紙サイズグリッド表示（設定の用紙サイズに連動）
                    if canvasState.showPaperGrid {
                        let paperW: CGFloat = canvasState.currentPaperSize.width * scale
                        let paperH: CGFloat = canvasState.currentPaperSize.height * scale
                        let gridCols = Int(ceil(geometry.size.width / paperW)) + 1
                        let gridRows = Int(ceil(geometry.size.height / paperH)) + 1
                        let startCol = Int(floor(-offset.width / paperW))
                        let startRow = Int(floor(-offset.height / paperH))
                        ForEach(startCol..<(startCol + gridCols), id: \.self) { col in
                            ForEach(startRow..<(startRow + gridRows), id: \.self) { row in
                                let x = offset.width + CGFloat(col) * paperW
                                let y = offset.height + CGFloat(row) * paperH
                                if col >= 0 && row >= 0 {
                                    Path { path in
                                        path.addRect(CGRect(x: x, y: y, width: paperW, height: paperH))
                                    }
                                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                                    Text("\(canvasState.paperSize.rawValue)-\(row * (startCol + gridCols) + col + 1)")
                                        .font(.system(size: 9))
                                        .foregroundColor(.gray.opacity(0.5))
                                        .position(CGPoint(x: x + 14, y: y + 14))
                                }
                            }
                        }
                    }
                    
                    // 線を描画
                    ForEach(canvasState.lines) { line in
                        let p1 = toScreen(line.startPoint)
                        let p2 = toScreen(line.endPoint)
                        let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                        let isSelected = selectedLine?.id == line.id
                        let isIntersectionSource = intersectionLine1?.id == line.id
                        ZStack {
                            Path { path in
                                path.move(to: p1)
                                path.addLine(to: p2)
                            }
                            .stroke(
                                isIntersectionSource ? Color.purple :
                                isSelected ? Color.blue : Color.black,
                                lineWidth: isSelected || isIntersectionSource ? 2.5 : 1.5
                            )
                            Text(String(format: "%.1fcm", line.lengthCm))
                                .font(.system(size: 9))
                                .foregroundColor(isSelected ? Color.blue : Color.gray)
                                .position(CGPoint(x: mid.x + 8, y: mid.y - 8))
                            if isSelected {
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .position(p1)
                                Rectangle()
                                    .fill(Color.green)
                                    .frame(width: 10, height: 10)
                                    .position(p2)
                            }
                        }
                    }

                    // addLine: 始点選択中のプレビュー線
                    if currentTool == .addLine, let startPt = lineStartPoint {
                        let p1 = toScreen(startPt.position)
                        let p2 = toScreen(snapResult.position)
                        Path { path in
                            path.move(to: p1)
                            path.addLine(to: p2)
                        }
                        .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        // プレビュー長さ表示
                        let previewLength = distance(startPt.position, snapResult.position) / 37.8
                        Text(String(format: "%.1fcm", previewLength))
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                            .position(CGPoint(x: (p1.x + p2.x) / 2 + 8, y: (p1.y + p2.y) / 2 - 8))
                    }

                    // 縫い代
                    if canvasState.showSeamAllowance {
                        ForEach(canvasState.lines) { line in
                            let p1 = toScreen(line.startPoint)
                            let p2 = toScreen(line.endPoint)
                            let dx = p2.x - p1.x, dy = p2.y - p1.y
                            let len = sqrt(dx * dx + dy * dy)
                            if len > 0 {
                                // 個別設定があればそちらを使い、なければデフォルト値
                                let width = canvasState.seamWidth(for: line.id)
                                let nx = -dy / len * width * 37.8 * scale
                                let ny =  dx / len * width * 37.8 * scale
                                let hasOverride = canvasState.seamOverrides.contains(where: { $0.lineID == line.id })
                                Path { path in
                                    path.move(to: CGPoint(x: p1.x + nx, y: p1.y + ny))
                                    path.addLine(to: CGPoint(x: p2.x + nx, y: p2.y + ny))
                                }
                                .stroke(
                                    hasOverride ? Color.blue.opacity(0.6) : Color.red.opacity(0.5),
                                    style: StrokeStyle(lineWidth: hasOverride ? 1.5 : 1, dash: [4, 4])
                                )
                            }
                        }
                    }

                    // 円弧
                    ForEach(canvasState.arcs) { arc in
                        let isArcSelected = groupSelectedArcIDs.contains(arc.id) || selectedArcID == arc.id
                        Path { path in
                            let screenCenter = toScreen(arc.center)
                            let screenRadius = arc.radius * scale
                            path.addArc(center: screenCenter, radius: screenRadius,
                                       startAngle: .radians(arc.startAngle * .pi / 180),
                                       endAngle: .radians(arc.endAngle * .pi / 180),
                                       clockwise: false)
                        }
                        .stroke(isArcSelected ? Color.orange : Color.black, lineWidth: isArcSelected ? 2.5 : 1.5)
                        if isArcSelected {
                            Circle().fill(Color.orange).frame(width: 8, height: 8)
                                .position(toScreen(arc.center))
                        }
                    }

                    // テキスト
                    ForEach(canvasState.texts) { annotation in
                        let isTextSelected = groupSelectedTextIDs.contains(annotation.id)
                        Text(annotation.text)
                            .font(.system(size: annotation.fontSize * scale))
                            .foregroundColor(isTextSelected ? Color.orange :
                                           selectedTextID == annotation.id ? Color.blue : Color.black)
                            .background(isTextSelected ? Color.orange.opacity(0.1) : Color.clear)
                            .position(toScreen(annotation.position))
                    }

                    // 曲線
                    ForEach(canvasState.curves) { curve in
                        bezierPath(for: curve.nodes)
                            .stroke(curve.id == selectedCurveID ? Color.blue : Color.black, lineWidth: 1.5)
                        if curve.id != selectedCurveID {
                            ForEach(0..<curve.nodes.count, id: \.self) { i in
                                Circle().fill(Color.gray).frame(width: 5, height: 5)
                                    .position(toScreen(curve.nodes[i].point))
                            }
                        }
                        if curve.id == selectedCurveID {
                            ForEach(0..<curve.nodes.count, id: \.self) { i in
                                let node = curve.nodes[i]
                                let sp = toScreen(node.point)
                                let scp1 = toScreen(node.controlPoint1)
                                let scp2 = toScreen(node.controlPoint2)
                                let isFirst = i == 0, isLast = i == curve.nodes.count - 1
                                Path { path in
                                    if !isFirst { path.move(to: scp1); path.addLine(to: sp) }
                                    if !isLast { path.move(to: sp); path.addLine(to: scp2) }
                                }
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                Circle().fill(Color.blue).frame(width: 8, height: 8).position(sp)
                                if !isFirst { Circle().fill(Color.orange).frame(width: 6, height: 6).position(scp1) }
                                if !isLast  { Circle().fill(Color.orange).frame(width: 6, height: 6).position(scp2) }
                            }
                        }
                    }

                    // 描画中の曲線プレビュー
                    if curveNodes.count >= 2 {
                        bezierPath(for: curveNodes).stroke(Color.blue.opacity(0.5), lineWidth: 1.5)
                    }
                    ForEach(0..<curveNodes.count, id: \.self) { i in
                        Circle().fill(Color.blue.opacity(0.7)).frame(width: 6, height: 6)
                            .position(toScreen(curveNodes[i].point))
                    }

                    // 点
                    ForEach(canvasState.points) { point in
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
                        .position(toScreen(point.position))
                    }

                    // 寸法線
                    ForEach(canvasState.lines) { line in
                        let p1 = toScreen(line.startPoint), p2 = toScreen(line.endPoint)
                        let dx = p2.x - p1.x, dy = p2.y - p1.y
                        let len = sqrt(dx * dx + dy * dy)
                        if len > 0 {
                            let nx = -dy / len * 20, ny = dx / len * 20
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

                    // グループ選択矩形
                    if let start = groupSelectStart, let end = groupSelectEnd {
                        let rect = CGRect(
                            x: min(toScreen(start).x, toScreen(end).x),
                            y: min(toScreen(start).y, toScreen(end).y),
                            width: abs(toScreen(end).x - toScreen(start).x),
                            height: abs(toScreen(end).y - toScreen(start).y)
                        )
                        Path { path in path.addRect(rect) }
                            .stroke(Color.blue.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        Path { path in path.addRect(rect) }.fill(Color.blue.opacity(0.1))
                    }

                    // Shiftスナップのプレビュー（旧機能、互換）
                    if let preview = shiftSnapPreview, let selected = selectedPoint {
                        let sp = toScreen(preview), ss = toScreen(selected.position)
                        Path { path in path.move(to: ss); path.addLine(to: sp) }
                            .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        Circle().fill(Color.blue.opacity(0.7)).frame(width: 8, height: 8).position(sp)
                    }

                    // ★ スナップカーソル表示
                    if case .none = snapResult {} else {
                        let sp = toScreen(snapResult.position)
                        // 十字線と円をすべてスクリーン座標で描画（position修飾子は使わない）
                        Path { path in
                            // 横線
                            path.move(to: CGPoint(x: sp.x - 12, y: sp.y))
                            path.addLine(to: CGPoint(x: sp.x + 12, y: sp.y))
                            // 縦線
                            path.move(to: CGPoint(x: sp.x, y: sp.y - 12))
                            path.addLine(to: CGPoint(x: sp.x, y: sp.y + 12))
                        }
                        .stroke(snapResult.color, lineWidth: 1.5)
                        Circle()
                            .stroke(snapResult.color, lineWidth: 2)
                            .frame(width: 18, height: 18)
                            .position(sp)
                        Text(snapResult.label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(snapResult.color)
                            .padding(2)
                            .background(Color.white.opacity(0.75))
                            .cornerRadius(3)
                            .position(CGPoint(x: sp.x + 16, y: sp.y - 14))
                    }

                    // ★ ノッチ描画（標準記号：逆三角形▽）
                    ForEach(canvasState.notches) { notch in
                        if let line = canvasState.lines.first(where: { $0.id == notch.lineID }) {
                            let pos = CGPoint(
                                x: line.startPoint.x + (line.endPoint.x - line.startPoint.x) * notch.t,
                                y: line.startPoint.y + (line.endPoint.y - line.startPoint.y) * notch.t
                            )
                            let screenPos = toScreen(pos)
                            let dx = line.endPoint.x - line.startPoint.x
                            let dy = line.endPoint.y - line.startPoint.y
                            let len = sqrt(dx*dx + dy*dy)
                            // 線に垂直な方向（外側）
                            let nx = len > 0 ? -dy/len : 0
                            let ny = len > 0 ?  dx/len : 1
                            // 線に平行な方向
                            let tx = len > 0 ? dx/len : 1
                            let ty = len > 0 ? dy/len : 0
                            let s = notch.size * scale
                            // 逆三角形：頂点が線の内側、底辺が外側
                            let tip   = screenPos  // 線上の点（三角形の頂点）
                            let left  = CGPoint(x: screenPos.x + nx*s - tx*s*0.6, y: screenPos.y + ny*s - ty*s*0.6)
                            let right = CGPoint(x: screenPos.x + nx*s + tx*s*0.6, y: screenPos.y + ny*s + ty*s*0.6)
                            Path { path in
                                path.move(to: tip)
                                path.addLine(to: left)
                                path.addLine(to: right)
                                path.closeSubpath()
                            }
                            .fill(Color.black)
                        }
                    }

                    // ★ グレーディング表示
                    if canvasState.showGrading {
                        ForEach(canvasState.gradingSizes.filter { $0 != canvasState.activeGradeSize }, id: \.self) { size in
                            ForEach(canvasState.lines) { line in
                                // 端点に最も近い点をIDで特定（閾値を広めに）
                                let p1 = canvasState.points.min(by: {
                                    distance($0.position, line.startPoint) < distance($1.position, line.startPoint)
                                })
                                let p2 = canvasState.points.min(by: {
                                    distance($0.position, line.endPoint) < distance($1.position, line.endPoint)
                                })
                                // 近い点がある場合はグレード座標、ない場合はそのまま
                                let gp1 = (p1.map { distance($0.position, line.startPoint) < 5 } == true)
                                    ? p1.map { canvasState.gradedPosition(of: $0, for: size) } ?? line.startPoint
                                    : line.startPoint
                                let gp2 = (p2.map { distance($0.position, line.endPoint) < 5 } == true)
                                    ? p2.map { canvasState.gradedPosition(of: $0, for: size) } ?? line.endPoint
                                    : line.endPoint
                                Path { path in
                                    path.move(to: toScreen(gp1))
                                    path.addLine(to: toScreen(gp2))
                                }
                                .stroke(gradeColor(size), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                            }
                        }
                    }
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
                        Text("0").font(.system(size: 9)).foregroundColor(.red.opacity(0.7))
                            .position(CGPoint(x: originScreen.x + 12, y: originScreen.y - 12))
                    }

                    // スケールバー
                    let scaleBarPx = 5 * CGFloat(37.8) * scale
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
                    Text("5cm").font(.system(size: 9)).foregroundColor(.black.opacity(0.6))
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
                        let rawCanvas = toCanvas(location)
                        // スナップ計算（常時）
                        snapResult = computeSnap(for: rawCanvas)

                        if isShift && selectedPoint != nil && currentTool == .addPoint {
                            shiftSnapPreview = snapToAngle(rawCanvas)
                        } else {
                            shiftSnapPreview = nil
                        }
                    },
                    onDragBegan: { location, isShift in
                        isShiftPressed = isShift
                        let rawCanvasPos = toCanvas(location)
                        // マウス移動時に計算済みのsnapResultをそのまま使う（再計算ではなくキャッシュ利用）
                        let snap = snapResult
                        let canvasPos = isShift ? snapToAngle(rawCanvasPos) : snap.position

                        switch currentTool {
                        // 選択・削除・グループ・補助系は生座標で判定（線や点への近接判定のため）
                        case .select:
                            handleSelectBegan(canvasPos: rawCanvasPos)
                        case .delete:
                            deleteNearestElement(to: rawCanvasPos)
                        case .groupSelect:
                            handleGroupSelectBegan(canvasPos: rawCanvasPos)
                        case .parallel:
                            handleParallel(canvasPos: rawCanvasPos)
                        case .perpendicular:
                            handlePerpendicular(canvasPos: rawCanvasPos)
                        case .extend:
                            handleExtend(canvasPos: rawCanvasPos)
                        case .midpoint:
                            if let line = canvasState.lines.first(where: {
                                distanceToLine(from: rawCanvasPos, lineStart: $0.startPoint, lineEnd: $0.endPoint) < 15 / scale
                            }) { addMidpoint(of: line) }
                        case .intersection:
                            handleIntersection(canvasPos: rawCanvasPos)

                        // 作図系はスナップ座標を使う
                        case .arc:
                            handleArc(canvasPos: canvasPos)
                        case .text:
                            textInputPosition = canvasPos
                            textInputValue = ""
                            showTextInput = true
                        case .addPoint:
                            handleAddPoint(snap: snap)
                        case .addLine:
                            handleAddLineBegan(snap: snap)
                        case .addCurve:
                            addCurveNode(at: canvasPos)
                        case .lineInput:
                            // スナップで点があればそれを使い、なければスナップ座標に新規点を作成
                            if case .point(_, let pt) = snap {
                                lineInputFromPoint = pt
                            } else {
                                let newPoint = PatternPoint(position: canvasPos, name: "P\(canvasState.points.count + 1)")
                                canvasState.points.append(newPoint)
                                canvasState.saveSnapshot()
                                lineInputFromPoint = newPoint
                            }
                            showLineInput = true
                        // フェーズ2
                        case .mirror:
                            handleMirror(canvasPos: rawCanvasPos)
                        case .notch:
                            handleNotch(canvasPos: rawCanvasPos)
                        case .seamOverride:
                            handleSeamOverride(canvasPos: rawCanvasPos)
                        case .grading:
                            handleGrading(canvasPos: rawCanvasPos)
                        }
                    },
                    onDragChanged: { location in
                        let canvasPos = toCanvas(location)
                        switch currentTool {
                        case .select:
                            handleSelectChanged(canvasPos: canvasPos)
                        case .groupSelect:
                            handleGroupSelectChanged(canvasPos: canvasPos)
                        default:
                            break
                        }
                    },
                    onDragEnded: { location in
                        let rawCanvasPos = toCanvas(location)
                        let snap = computeSnap(for: rawCanvasPos)
                        let canvasPos = isShiftPressed ? snapToAngle(rawCanvasPos) : snap.position

                        switch currentTool {
                        case .select:
                            handleSelectEnded()
                        case .addPoint:
                            break // handled in began
                        case .addLine:
                            handleAddLineEnded(canvasPos: canvasPos, snap: snap)
                        case .groupSelect:
                            handleGroupSelectEnded(canvasPos: rawCanvasPos)
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
                            if let text = canvasState.texts.first(where: { distance($0.position, canvasPos) < 30 / scale }) {
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
                            lineStartPoint = nil
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
        // ★ スナップ設定バー（CanvasNSViewの上に被せる、SwiftUIレイヤー）
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                snapToggle("点",      $pointSnapEnabled,        .blue)
                snapToggle("交点",    $intersectionSnapEnabled,  .green)
                snapToggle("中点",    $midpointSnapEnabled,      .orange)
                snapToggle("グリッド", $gridSnapEnabled,          .gray)
                Divider().frame(height: 16)
                snapToggle("スナップ", $snapEnabled,             .purple)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.92))
            .cornerRadius(8)
            .shadow(radius: 2)
            .padding(8)
        }
        .sheet(item: $lineToSplit) { line in
            LineSplitView(line: line, onSplit: { t in
                splitLine(line: line, t: t)
                lineToSplit = nil
            }, onCancel: { lineToSplit = nil })
        }
        .sheet(isPresented: $showTextInput) {
            TextInputView(text: $textInputValue, onConfirm: {
                if !textInputValue.isEmpty {
                    if let id = selectedTextID,
                       let index = canvasState.texts.firstIndex(where: { $0.id == id }) {
                        canvasState.texts[index].text = textInputValue
                        canvasState.saveSnapshot()
                        statusMessage = "テキストを編集しました"
                    } else {
                        canvasState.texts.append(TextAnnotation(position: textInputPosition, text: textInputValue))
                        canvasState.saveSnapshot()
                        statusMessage = "テキストを追加しました"
                    }
                }
                showTextInput = false; selectedTextID = nil
            }, onCancel: { showTextInput = false; selectedTextID = nil })
        }
        // ★ 寸法入力シート
        .sheet(isPresented: $showLineInput) {
            if let fromPt = lineInputFromPoint {
                LineInputView(fromPoint: fromPt, onConfirm: { lengthCm, angleDeg in
                    let rad = angleDeg * .pi / 180
                    let px = lengthCm * 37.8
                    let endPos = CGPoint(
                        x: fromPt.position.x + cos(rad) * px,
                        y: fromPt.position.y + sin(rad) * px
                    )
                    let newPoint = PatternPoint(position: endPos, name: "P\(canvasState.points.count + 1)")
                    canvasState.points.append(newPoint)
                    canvasState.lines.append(PatternLine(startPoint: fromPt.position, endPoint: endPos))
                    canvasState.saveSnapshot()
                    selectedPoint = newPoint
                    statusMessage = String(format: "\(fromPt.name) から %.2fcm / %.1f° の線を引きました", lengthCm, angleDeg)
                    showLineInput = false
                    lineInputFromPoint = nil
                    // 連続入力：次の始点として新しい点を自動設定
                    lineInputFromPoint = newPoint
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showLineInput = true
                    }
                }, onCancel: {
                    showLineInput = false
                    lineInputFromPoint = nil
                })
            }
        }
        .sheet(isPresented: $showMirror) {
            MirrorView(onConfirm: { axis, keepOriginal in
                showMirror = false
                if axis == .line {
                    statusMessage = "軸にする線をクリックしてください"
                } else {
                    executeMirror(axis: axis, keepOriginal: keepOriginal)
                }
            }, onCancel: { showMirror = false })
        }
        .sheet(item: $notchTargetLine) { line in
            NotchInputView(line: line, t: notchT, onConfirm: { size in
                canvasState.notches.append(NotchData(lineID: line.id, t: notchT, size: size))
                canvasState.saveSnapshot()
                statusMessage = "ノッチを追加しました"
                notchTargetLine = nil
            }, onCancel: { notchTargetLine = nil })
        }
        .onChange(of: resetOffsetTrigger) { _, _ in
            offset = CGSize(width: 40, height: 40)
        }
        .onChange(of: currentTool) { _, tool in
            // 鏡像ツールはグループ選択状態を引き継ぐ（リセットしない）
            if tool == .mirror {
                selectedCurveID = nil; selectedPoint = nil; selectedLine = nil
                selectedArcID = nil; parallelSourceLine = nil; perpendicularSourceLine = nil
                extendSourceLine = nil; arcCenter = nil; arcStart = nil
                intersectionLine1 = nil; lineStartPoint = nil
                mirrorAxisLine = nil
                // groupSelectedPointIDs・groupSelectedLineIDs は保持
                statusMessage = groupSelectedPointIDs.isEmpty
                    ? "先に「範囲」ツールで対象を選択してから鏡像ツールを使ってください"
                    : "「鏡像」ボタンをクリックして反転軸を選択してください"
                showMirror = !groupSelectedPointIDs.isEmpty
                return
            }
            resetToolState()
            switch tool {
            case .select:       statusMessage = "点または曲線をクリックして選択"
            case .addPoint:     statusMessage = "キャンバスをクリックして点を追加"
            case .addLine:      statusMessage = "始点の点をクリックしてください"
            case .addCurve:     statusMessage = "クリックでノードを追加、Enterキーで確定"
            case .delete:       statusMessage = "削除する要素をクリックしてください"
            case .groupSelect:  statusMessage = "ドラッグで範囲を選択してください"
            case .parallel:     statusMessage = "平行線を引く線をクリックしてください"
            case .perpendicular:statusMessage = "垂直線を引く線をクリックしてください"
            case .extend:       statusMessage = "延長する線をクリックしてください"
            case .midpoint:     statusMessage = "中点を追加する線をクリックしてください"
            case .arc:          statusMessage = "円弧の中心をクリックしてください"
            case .text:         statusMessage = "テキストを追加する位置をクリックしてください"
            case .lineInput:    statusMessage = "始点をクリック（または空白をクリックで点を作成）"
            case .intersection: statusMessage = "交点を取る1本目の線をクリックしてください"
            case .mirror:       statusMessage = "反転するグループを範囲選択してから実行、または選択済みで軸線をクリック"
            case .notch:        statusMessage = "ノッチを追加する線をクリックしてください"
            case .seamOverride: statusMessage = "縫い代を個別設定する線をクリックしてください"
            case .grading:      statusMessage = "グレーディングする点をクリックしてください"
            }
        }
    }

    // MARK: - スナップ設定トグルボタン
    @ViewBuilder
    private func snapToggle(_ label: String, _ binding: Binding<Bool>, _ color: Color) -> some View {
        Button(action: { binding.wrappedValue.toggle() }) {
            Text(label)
                .font(.system(size: 10))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(binding.wrappedValue ? color.opacity(0.2) : Color.gray.opacity(0.1))
                .foregroundColor(binding.wrappedValue ? color : .gray)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(binding.wrappedValue ? color : Color.gray.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - ツール別ハンドラ

    private func handleAddPoint(snap: SnapResult) {
        if let line = canvasState.lines.first(where: {
            distanceToLine(from: snap.position, lineStart: $0.startPoint, lineEnd: $0.endPoint) < 10 / scale
        }) {
            lineToSplit = line
            splitClickPosition = snap.position
        } else {
            let newPoint = PatternPoint(position: snap.position, name: "P\(canvasState.points.count + 1)")
            canvasState.points.append(newPoint)
            selectedPoint = newPoint
            statusMessage = "\(newPoint.name) を追加しました"
            canvasState.saveSnapshot()
        }
    }

    private func handleAddLineBegan(snap: SnapResult) {
        // スナップ結果を優先して使う
        let targetPoint: PatternPoint
        if case .point(_, let pt) = snap {
            // 点スナップ：既存の点にそのまま吸い寄せ
            targetPoint = pt
        } else {
            // グリッド・交点・中点・なし：スナップ座標に新規点を作成
            let newPoint = PatternPoint(position: snap.position, name: "P\(canvasState.points.count + 1)")
            canvasState.points.append(newPoint)
            canvasState.saveSnapshot()
            targetPoint = newPoint
        }

        if let start = lineStartPoint, start.id != targetPoint.id {
            canvasState.lines.append(PatternLine(startPoint: start.position, endPoint: targetPoint.position))
            canvasState.saveSnapshot()
            statusMessage = "\(start.name) → \(targetPoint.name) に線を引きました"
            lineStartPoint = targetPoint  // 連続入力
        } else {
            lineStartPoint = targetPoint
            statusMessage = "終点をクリックしてください (始点: \(targetPoint.name))"
        }
        selectedPoint = targetPoint
        selectedLine = nil
    }

    private func handleAddLineEnded(canvasPos: CGPoint, snap: SnapResult) {
        // dragEndedでは何もしない（beganで処理済み）
    }

    private func handleSelectBegan(canvasPos: CGPoint) {
        if let curveID = selectedCurveID,
           let curveIndex = canvasState.curves.firstIndex(where: { $0.id == curveID }) {
            let curve = canvasState.curves[curveIndex]
            for (i, node) in curve.nodes.enumerated() {
                let cp1Canvas = node.controlPoint1
                let cp2Canvas = node.controlPoint2
                if distance(canvasPos, cp1Canvas) < 10 / scale {
                    draggingControlPoint = (curveID: curveID, nodeIndex: i, isCP1: true); return
                }
                if distance(canvasPos, cp2Canvas) < 10 / scale {
                    draggingControlPoint = (curveID: curveID, nodeIndex: i, isCP1: false); return
                }
            }
        }
        if let point = nearestPoint(to: canvasPos, threshold: 20 / scale) {
            if let curve = canvasState.curves.first(where: { curve in
                curve.nodes.contains(where: { distance($0.point, point.position) < 1.0 })
            }) {
                if selectedCurveID == curve.id {
                    draggingPointID = point.id; selectedPoint = point; selectedLine = nil; return
                }
                selectedCurveID = curve.id; selectedPoint = nil
                statusMessage = "曲線を選択中 / もう一度クリックで点を移動"
                return
            }
            draggingPointID = point.id; selectedPoint = point; selectedCurveID = nil; selectedLine = nil
            statusMessage = "\(point.name) を移動中"
            return
        }
        if let curve = nearestCurve(to: canvasPos) {
            selectedCurveID = curve.id; selectedPoint = nil; selectedLine = nil
            statusMessage = "曲線を選択中 / コントロールポイントをドラッグで編集"
            return
        }
        if let index = canvasState.lines.firstIndex(where: {
            distanceToLine(from: canvasPos, lineStart: $0.startPoint, lineEnd: $0.endPoint) < 15 / scale
        }) {
            selectedLine = canvasState.lines[index]; selectedPoint = nil; selectedCurveID = nil
            statusMessage = "線を選択中"
            return
        }
        if let arc = canvasState.arcs.first(where: {
            abs(distance($0.center, canvasPos) - $0.radius) < 20 / scale
        }) {
            selectedArcID = arc.id; selectedPoint = nil; selectedLine = nil; selectedCurveID = nil; selectedTextID = nil
            statusMessage = "円弧を選択中: 半径\(String(format: "%.1f", arc.radius / 37.8))cm"
            return
        }
        if let text = canvasState.texts.first(where: { distance($0.position, canvasPos) < 30 / scale }) {
            selectedTextID = text.id; selectedPoint = nil; selectedLine = nil; selectedCurveID = nil
            statusMessage = "テキストを選択中 / ドラッグで移動"
            return
        }
        selectedLine = nil; selectedCurveID = nil; selectedPoint = nil; selectedTextID = nil
    }

    private func handleSelectChanged(canvasPos: CGPoint) {
        if let id = selectedTextID,
           let index = canvasState.texts.firstIndex(where: { $0.id == id }) {
            canvasState.texts[index].position = canvasPos; return
        }
        if let id = selectedArcID,
           let index = canvasState.arcs.firstIndex(where: { $0.id == id }) {
            canvasState.arcs[index].center = canvasPos; return
        }
        if let cp = draggingControlPoint,
           let curveIndex = canvasState.curves.firstIndex(where: { $0.id == cp.curveID }) {
            if cp.isCP1 { canvasState.curves[curveIndex].nodes[cp.nodeIndex].controlPoint1 = canvasPos }
            else        { canvasState.curves[curveIndex].nodes[cp.nodeIndex].controlPoint2 = canvasPos }
            return
        }
        if let id = draggingPointID { movePoint(id: id, to: canvasPos) }
    }

    private func handleSelectEnded() {
        if draggingControlPoint != nil || draggingPointID != nil { canvasState.saveSnapshot() }
        draggingControlPoint = nil; draggingPointID = nil
    }

    private func handleGroupSelectBegan(canvasPos: CGPoint) {
        let hasSelection = !groupSelectedPointIDs.isEmpty || !groupSelectedLineIDs.isEmpty ||
                          !groupSelectedArcIDs.isEmpty || !groupSelectedTextIDs.isEmpty
        let nearSelected = canvasState.points.first(where: {
            groupSelectedPointIDs.contains($0.id) && distance($0.position, canvasPos) < 20 / scale
        })
        if hasSelection && nearSelected != nil {
            groupDragStart = canvasPos
        } else {
            groupSelectStart = canvasPos; groupSelectEnd = canvasPos
            groupSelectedPointIDs = []; groupSelectedLineIDs = []; groupDragStart = nil
        }
    }

    private func handleGroupSelectChanged(canvasPos: CGPoint) {
        if let dragStart = groupDragStart {
            let delta = CGPoint(x: canvasPos.x - dragStart.x, y: canvasPos.y - dragStart.y)
            moveGroupSelected(delta: delta); groupDragStart = canvasPos
        } else {
            groupSelectEnd = canvasPos
        }
    }

    private func handleGroupSelectEnded(canvasPos: CGPoint) {
        if groupDragStart != nil {
            canvasState.saveSnapshot(); groupDragStart = nil
        } else if let start = groupSelectStart, let end = groupSelectEnd {
            let minX = min(start.x, end.x), maxX = max(start.x, end.x)
            let minY = min(start.y, end.y), maxY = max(start.y, end.y)
            groupSelectedPointIDs = Set(canvasState.points.filter {
                $0.position.x >= minX && $0.position.x <= maxX && $0.position.y >= minY && $0.position.y <= maxY
            }.map { $0.id })
            groupSelectedLineIDs = Set(canvasState.lines.filter {
                $0.startPoint.x >= minX && $0.startPoint.x <= maxX && $0.startPoint.y >= minY && $0.startPoint.y <= maxY &&
                $0.endPoint.x >= minX && $0.endPoint.x <= maxX && $0.endPoint.y >= minY && $0.endPoint.y <= maxY
            }.map { $0.id })
            groupSelectedArcIDs = Set(canvasState.arcs.filter {
                $0.center.x >= minX && $0.center.x <= maxX && $0.center.y >= minY && $0.center.y <= maxY
            }.map { $0.id })
            groupSelectedTextIDs = Set(canvasState.texts.filter {
                $0.position.x >= minX && $0.position.x <= maxX && $0.position.y >= minY && $0.position.y <= maxY
            }.map { $0.id })
            statusMessage = "点\(groupSelectedPointIDs.count)個、線\(groupSelectedLineIDs.count)本を選択"
        }
        groupSelectStart = nil; groupSelectEnd = nil
    }

    private func handleParallel(canvasPos: CGPoint) {
        if let line = canvasState.lines.first(where: {
            distanceToLine(from: canvasPos, lineStart: $0.startPoint, lineEnd: $0.endPoint) < 15 / scale
        }) {
            parallelSourceLine = line
            statusMessage = "平行線の距離をクリックで指定してください"
        } else if let source = parallelSourceLine {
            addParallelLine(to: source, clickPoint: canvasPos)
        }
    }

    private func handlePerpendicular(canvasPos: CGPoint) {
        if let line = canvasState.lines.first(where: {
            distanceToLine(from: canvasPos, lineStart: $0.startPoint, lineEnd: $0.endPoint) < 15 / scale
        }) {
            perpendicularSourceLine = line
            statusMessage = "垂直線の基点をクリックしてください"
        } else if let source = perpendicularSourceLine {
            addPerpendicularLine(to: source, fromPoint: canvasPos)
        }
    }

    private func handleExtend(canvasPos: CGPoint) {
        if let line = canvasState.lines.first(where: {
            distanceToLine(from: canvasPos, lineStart: $0.startPoint, lineEnd: $0.endPoint) < 15 / scale
        }) {
            extendSourceLine = line
            statusMessage = "延長先をクリックしてください"
        } else if let source = extendSourceLine {
            extendLine(source, to: canvasPos)
        }
    }

    private func handleArc(canvasPos: CGPoint) {
        if arcCenter == nil {
            arcCenter = canvasPos; statusMessage = "円弧の開始点をクリックしてください"
        } else if arcStart == nil {
            arcStart = canvasPos; statusMessage = "円弧の終了点をクリックしてください"
        } else if let center = arcCenter, let start = arcStart {
            addArc(center: center, start: start, end: canvasPos)
        }
    }

    // ★ 交点ツール
    private func handleIntersection(canvasPos: CGPoint) {
        if intersectionLine1 == nil {
            if let line = canvasState.lines.first(where: {
                distanceToLine(from: canvasPos, lineStart: $0.startPoint, lineEnd: $0.endPoint) < 15 / scale
            }) {
                intersectionLine1 = line
                statusMessage = "2本目の線をクリックしてください"
            }
        } else if let l1 = intersectionLine1 {
            if let l2 = canvasState.lines.first(where: {
                $0.id != l1.id &&
                distanceToLine(from: canvasPos, lineStart: $0.startPoint, lineEnd: $0.endPoint) < 15 / scale
            }) {
                if let pt = lineIntersection(l1, l2) {
                    let newPoint = PatternPoint(position: pt, name: "P\(canvasState.points.count + 1)")
                    canvasState.points.append(newPoint)
                    canvasState.saveSnapshot()
                    selectedPoint = newPoint
                    statusMessage = "\(newPoint.name) を交点に追加しました"
                } else {
                    statusMessage = "2本の線が平行で交点がありません"
                }
                intersectionLine1 = nil
            }
        }
    }

    // MARK: - フェーズ2ハンドラ

    // 鏡像
    private func handleMirror(canvasPos: CGPoint) {
        showMirror = true
    }

    private func executeMirror(axis: MirrorView.MirrorAxis, keepOriginal: Bool) {
        let selectedIDs = groupSelectedPointIDs
        let selectedLineIDs = groupSelectedLineIDs
        guard !selectedIDs.isEmpty else {
            statusMessage = "先に範囲選択ツールで対象を選択してください"
            return
        }
        let targetPoints = canvasState.points.filter { selectedIDs.contains($0.id) }

        // 軸を選択範囲の端点に設定（隣接してコピーされるように）
        let minX = targetPoints.map { $0.position.x }.min() ?? 0
        let maxX = targetPoints.map { $0.position.x }.max() ?? 0
        let minY = targetPoints.map { $0.position.y }.min() ?? 0
        let maxY = targetPoints.map { $0.position.y }.max() ?? 0
        // 垂直軸→右端、水平軸→下端を基準に反転
        let axisX = maxX
        let axisY = maxY

        var newPoints: [PatternPoint] = []
        // 元の点→新しい点の座標マッピング（線のミラーに使用）
        var posMap: [CGPoint: CGPoint] = [:]

        for pt in targetPoints {
            var newPos: CGPoint
            switch axis {
            case .vertical:
                newPos = CGPoint(x: 2 * axisX - pt.position.x, y: pt.position.y)
            case .horizontal:
                newPos = CGPoint(x: pt.position.x, y: 2 * axisY - pt.position.y)
            case .line:
                if let axisLine = mirrorAxisLine {
                    newPos = reflectPoint(pt.position, over: axisLine)
                } else {
                    newPos = CGPoint(x: 2 * axisX - pt.position.x, y: pt.position.y)
                }
            }
            posMap[pt.position] = newPos
            let newPt = PatternPoint(position: newPos, name: "\(pt.name)'")
            newPoints.append(newPt)
        }

        // 線をミラー（座標マッピングで対応）
        let targetLines = canvasState.lines.filter { selectedLineIDs.contains($0.id) }
        var newLines: [PatternLine] = []
        for line in targetLines {
            let newStart = posMap[line.startPoint] ?? reflectAny(line.startPoint, axis: axis, axisX: axisX, axisY: axisY)
            let newEnd   = posMap[line.endPoint]   ?? reflectAny(line.endPoint,   axis: axis, axisX: axisX, axisY: axisY)
            newLines.append(PatternLine(startPoint: newStart, endPoint: newEnd))
        }

        if !keepOriginal {
            canvasState.points.removeAll { selectedIDs.contains($0.id) }
            canvasState.lines.removeAll { selectedLineIDs.contains($0.id) }
        }
        canvasState.points.append(contentsOf: newPoints)
        canvasState.lines.append(contentsOf: newLines)
        canvasState.saveSnapshot()
        statusMessage = "鏡像コピーしました（\(newPoints.count)点 / \(newLines.count)本）"
    }

    private func reflectAny(_ p: CGPoint, axis: MirrorView.MirrorAxis, axisX: CGFloat, axisY: CGFloat) -> CGPoint {
        switch axis {
        case .vertical:   return CGPoint(x: 2*axisX - p.x, y: p.y)
        case .horizontal: return CGPoint(x: p.x, y: 2*axisY - p.y)
        case .line:
            if let axisLine = mirrorAxisLine { return reflectPoint(p, over: axisLine) }
            return CGPoint(x: 2*axisX - p.x, y: p.y)
        }
    }

    private func reflectPoint(_ p: CGPoint, over line: PatternLine) -> CGPoint {
        let dx = line.endPoint.x - line.startPoint.x
        let dy = line.endPoint.y - line.startPoint.y
        let len2 = dx*dx + dy*dy
        guard len2 > 0 else { return p }
        let t = ((p.x - line.startPoint.x)*dx + (p.y - line.startPoint.y)*dy) / len2
        let foot = CGPoint(x: line.startPoint.x + t*dx, y: line.startPoint.y + t*dy)
        return CGPoint(x: 2*foot.x - p.x, y: 2*foot.y - p.y)
    }

    // ノッチ
    private func handleNotch(canvasPos: CGPoint) {
        if let line = canvasState.lines.first(where: {
            distanceToLine(from: canvasPos, lineStart: $0.startPoint, lineEnd: $0.endPoint) < 15 / scale
        }) {
            // クリック位置のt値を計算
            let dx = line.endPoint.x - line.startPoint.x
            let dy = line.endPoint.y - line.startPoint.y
            let len2 = dx*dx + dy*dy
            guard len2 > 0 else { return }
            let t = ((canvasPos.x - line.startPoint.x)*dx + (canvasPos.y - line.startPoint.y)*dy) / len2
            notchT = max(0.05, min(0.95, t))
            notchTargetLine = line  // item:ベースのsheetが自動で開く
        }
    }

    // 縫い代個別設定
    private func handleSeamOverride(canvasPos: CGPoint) {
        if let line = canvasState.lines.first(where: {
            distanceToLine(from: canvasPos, lineStart: $0.startPoint, lineEnd: $0.endPoint) < 15 / scale
        }) {
            seamOverrideLine = line
            seamOverrideLineOut = line
            seamOverrideWidth = String(format: "%.1f", canvasState.seamWidth(for: line.id))
        }
    }

    // グレーディング
    private func handleGrading(canvasPos: CGPoint) {
        if let pt = nearestPoint(to: canvasPos, threshold: 20 / scale) {
            gradingPoint = pt
            gradingPointOut = pt
            statusMessage = "点 \(pt.name) を選択中 / 右パネルでオフセットを入力"
        }
    }

    // グレードカラー
    private func gradeColor(_ size: String) -> Color {
        let colors: [Color] = [.red, .green, .orange, .purple, .pink]
        let index = (canvasState.gradingSizes.firstIndex(of: size) ?? 0) % colors.count
        return colors[index]
    }

    // MARK: - 既存ユーティリティ

    private func resetToolState() {
        curveNodes = []; selectedCurveID = nil; selectedPoint = nil; selectedLine = nil
        selectedArcID = nil; groupSelectStart = nil; groupSelectEnd = nil
        groupSelectedPointIDs = []; groupSelectedLineIDs = []
        parallelSourceLine = nil; perpendicularSourceLine = nil; extendSourceLine = nil
        arcCenter = nil; arcStart = nil
        groupSelectedArcIDs = []; groupSelectedTextIDs = []
        intersectionLine1 = nil; lineStartPoint = nil
        mirrorAxisLine = nil; notchTargetLine = nil
        seamOverrideLine = nil; gradingPoint = nil
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
        statusMessage = "ノード\(curveNodes.count)個 / Enterキーで確定"
    }

    private func finalizeCurve() {
        guard curveNodes.count >= 2 else {
            statusMessage = "2点以上クリックしてから確定してください"; return
        }
        let curve = CurveData(nodes: curveNodes)
        canvasState.curves.append(curve)
        canvasState.saveSnapshot()
        selectedCurveID = curve.id; curveNodes = []
        statusMessage = "曲線を追加しました / コントロールポイントをドラッグで編集"
    }

    private func nearestPoint(to location: CGPoint, threshold: CGFloat) -> PatternPoint? {
        canvasState.points.first { distance($0.position, location) < threshold }
    }

    private func nearestCurve(to location: CGPoint) -> CurveData? {
        let threshold: CGFloat = 15 / scale
        for curve in canvasState.curves {
            for node in curve.nodes {
                if distance(node.point, location) < threshold { return curve }
            }
            for i in 0..<curve.nodes.count - 1 {
                let from = curve.nodes[i], to = curve.nodes[i + 1]
                for j in 0..<20 {
                    let t0 = CGFloat(j) / 20, t1 = CGFloat(j + 1) / 20
                    let p0 = bezierPoint(from: from, to: to, t: t0)
                    let p1 = bezierPoint(from: from, to: to, t: t1)
                    if distanceToLine(from: location, lineStart: p0, lineEnd: p1) < threshold { return curve }
                }
            }
        }
        return nil
    }

    private func bezierPoint(from: CurveNode, to: CurveNode, t: CGFloat) -> CGPoint {
        let cp1 = from.controlPoint2, cp2 = to.controlPoint1, mt = 1 - t
        return CGPoint(
            x: mt*mt*mt*from.point.x + 3*mt*mt*t*cp1.x + 3*mt*t*t*cp2.x + t*t*t*to.point.x,
            y: mt*mt*mt*from.point.y + 3*mt*mt*t*cp1.y + 3*mt*t*t*cp2.y + t*t*t*to.point.y
        )
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func movePoint(id: UUID, to position: CGPoint) {
        guard let index = canvasState.points.firstIndex(where: { $0.id == id }) else { return }
        let oldPosition = canvasState.points[index].position
        canvasState.points[index].position = position
        if selectedPoint?.id == id { selectedPoint = canvasState.points[index] }
        canvasState.lines = canvasState.lines.map { line in
            var l = line
            if l.startPoint == oldPosition { l.startPoint = position }
            if l.endPoint == oldPosition { l.endPoint = position }
            return l
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

    private func deleteNearestElement(to location: CGPoint) {
        let threshold: CGFloat = 20 / scale
        if let curve = nearestCurve(to: location),
           let index = canvasState.curves.firstIndex(where: { $0.id == curve.id }) {
            canvasState.curves.remove(at: index)
            if selectedCurveID == curve.id { selectedCurveID = nil }
            statusMessage = "曲線を削除しました"; canvasState.saveSnapshot(); return
        }
        if let index = canvasState.points.firstIndex(where: { distance($0.position, location) < threshold }) {
            let del = canvasState.points[index]
            canvasState.points.remove(at: index)
            canvasState.lines.removeAll { $0.startPoint == del.position || $0.endPoint == del.position }
            if selectedPoint?.id == del.id { selectedPoint = nil }
            statusMessage = "\(del.name) を削除しました"; canvasState.saveSnapshot(); return
        }
        if let index = canvasState.lines.firstIndex(where: {
            distanceToLine(from: location, lineStart: $0.startPoint, lineEnd: $0.endPoint) < threshold
        }) {
            canvasState.lines.remove(at: index); statusMessage = "線を削除しました"; canvasState.saveSnapshot(); return
        }
        if let index = canvasState.arcs.firstIndex(where: {
            abs(distance($0.center, location) - $0.radius) < threshold
        }) {
            canvasState.arcs.remove(at: index); statusMessage = "円弧を削除しました"; canvasState.saveSnapshot(); return
        }
        if let index = canvasState.texts.firstIndex(where: { distance($0.position, location) < threshold }) {
            canvasState.texts.remove(at: index); statusMessage = "テキストを削除しました"; canvasState.saveSnapshot()
        }
    }

    private func splitLine(line: PatternLine, t: CGFloat) {
        guard let index = canvasState.lines.firstIndex(where: { $0.id == line.id }) else { return }
        let splitPoint = CGPoint(
            x: line.startPoint.x + (line.endPoint.x - line.startPoint.x) * t,
            y: line.startPoint.y + (line.endPoint.y - line.startPoint.y) * t
        )
        let newPoint = PatternPoint(position: splitPoint, name: "P\(canvasState.points.count + 1)")
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
        let dx = position.x - selected.position.x, dy = position.y - selected.position.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return position }
        let angle = atan2(dy, dx)
        let snapAngles: [CGFloat] = [0, .pi/4, .pi/2, 3 * .pi/4, .pi, -3 * .pi/4, -.pi/2, -.pi/4]
        let nearestAngle = snapAngles.min(by: { abs(angle - $0) < abs(angle - $1) }) ?? angle
        return CGPoint(x: selected.position.x + cos(nearestAngle) * dist,
                      y: selected.position.y + sin(nearestAngle) * dist)
    }

    private func moveGroupSelected(delta: CGPoint) {
        let selectedPositions = canvasState.points.filter { groupSelectedPointIDs.contains($0.id) }.map { $0.position }
        func isSelected(_ p: CGPoint) -> Bool {
            selectedPositions.contains(where: { abs($0.x - p.x) < 0.1 && abs($0.y - p.y) < 0.1 })
        }
        canvasState.points = canvasState.points.map { pt in
            guard groupSelectedPointIDs.contains(pt.id) else { return pt }
            var p = pt; p.position = CGPoint(x: p.position.x + delta.x, y: p.position.y + delta.y); return p
        }
        canvasState.lines = canvasState.lines.map { line in
            var l = line
            if groupSelectedLineIDs.contains(line.id) {
                l.startPoint = CGPoint(x: l.startPoint.x + delta.x, y: l.startPoint.y + delta.y)
                l.endPoint = CGPoint(x: l.endPoint.x + delta.x, y: l.endPoint.y + delta.y)
            } else {
                if isSelected(l.startPoint) { l.startPoint = CGPoint(x: l.startPoint.x + delta.x, y: l.startPoint.y + delta.y) }
                if isSelected(l.endPoint)   { l.endPoint   = CGPoint(x: l.endPoint.x   + delta.x, y: l.endPoint.y   + delta.y) }
            }
            return l
        }
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
        canvasState.arcs = canvasState.arcs.map { arc in
            guard groupSelectedArcIDs.contains(arc.id) else { return arc }
            var a = arc; a.center = CGPoint(x: a.center.x + delta.x, y: a.center.y + delta.y); return a
        }
        canvasState.texts = canvasState.texts.map { text in
            guard groupSelectedTextIDs.contains(text.id) else { return text }
            var t = text; t.position = CGPoint(x: t.position.x + delta.x, y: t.position.y + delta.y); return t
        }
    }

    private func deleteGroupSelected() {
        canvasState.saveSnapshot()
        let deletedPositions = canvasState.points.filter { groupSelectedPointIDs.contains($0.id) }.map { $0.position }
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
        canvasState.arcs.removeAll { groupSelectedArcIDs.contains($0.id) }
        canvasState.texts.removeAll { groupSelectedTextIDs.contains($0.id) }
        groupSelectedPointIDs = []; groupSelectedLineIDs = []; groupSelectedArcIDs = []; groupSelectedTextIDs = []
        statusMessage = "削除しました"
    }

    private func addParallelLine(to source: PatternLine, clickPoint: CGPoint) {
        let dx = source.endPoint.x - source.startPoint.x, dy = source.endPoint.y - source.startPoint.y
        let len = sqrt(dx * dx + dy * dy); guard len > 0 else { return }
        let nx = -dy / len, ny = dx / len
        let dist = (clickPoint.x - source.startPoint.x) * nx + (clickPoint.y - source.startPoint.y) * ny
        canvasState.lines.append(PatternLine(
            startPoint: CGPoint(x: source.startPoint.x + nx * dist, y: source.startPoint.y + ny * dist),
            endPoint:   CGPoint(x: source.endPoint.x   + nx * dist, y: source.endPoint.y   + ny * dist)
        ))
        canvasState.saveSnapshot(); parallelSourceLine = nil; statusMessage = "平行線を追加しました"
    }

    private func addPerpendicularLine(to source: PatternLine, fromPoint: CGPoint) {
        let dx = source.endPoint.x - source.startPoint.x, dy = source.endPoint.y - source.startPoint.y
        let len = sqrt(dx * dx + dy * dy); guard len > 0 else { return }
        let t = ((fromPoint.x - source.startPoint.x) * dx + (fromPoint.y - source.startPoint.y) * dy) / (len * len)
        let foot = CGPoint(x: source.startPoint.x + t * dx, y: source.startPoint.y + t * dy)
        canvasState.lines.append(PatternLine(startPoint: fromPoint, endPoint: foot))
        canvasState.saveSnapshot(); perpendicularSourceLine = nil; statusMessage = "垂直線を追加しました"
    }

    private func extendLine(_ source: PatternLine, to point: CGPoint) {
        let dx = source.endPoint.x - source.startPoint.x, dy = source.endPoint.y - source.startPoint.y
        let len = sqrt(dx * dx + dy * dy); guard len > 0 else { return }
        let t = ((point.x - source.startPoint.x) * dx + (point.y - source.startPoint.y) * dy) / (len * len)
        if let index = canvasState.lines.firstIndex(where: { $0.id == source.id }) {
            if t > 1 {
                canvasState.lines[index].endPoint = CGPoint(x: source.startPoint.x + dx * t, y: source.startPoint.y + dy * t)
            } else if t < 0 {
                canvasState.lines[index].startPoint = CGPoint(x: source.startPoint.x + dx * t, y: source.startPoint.y + dy * t)
            }
        }
        canvasState.saveSnapshot(); extendSourceLine = nil; statusMessage = "線を延長しました"
    }

    private func addMidpoint(of line: PatternLine) {
        let mid = CGPoint(x: (line.startPoint.x + line.endPoint.x) / 2, y: (line.startPoint.y + line.endPoint.y) / 2)
        let newPoint = PatternPoint(position: mid, name: "P\(canvasState.points.count + 1)")
        canvasState.points.append(newPoint); canvasState.saveSnapshot()
        statusMessage = "\(newPoint.name) を中点に追加しました"
    }

    private func addArc(center: CGPoint, start: CGPoint, end: CGPoint) {
        let dx1 = start.x - center.x, dy1 = start.y - center.y
        let radius = sqrt(dx1 * dx1 + dy1 * dy1)
        let startAngle = atan2(dy1, dx1) * 180 / .pi
        let dx2 = end.x - center.x, dy2 = end.y - center.y
        let endAngle = atan2(dy2, dx2) * 180 / .pi
        canvasState.arcs.append(ArcData(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle))
        canvasState.saveSnapshot(); arcCenter = nil; arcStart = nil; statusMessage = "円弧を追加しました"
    }

    private func distanceToLine(from point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x, dy = lineEnd.y - lineStart.y
        let length = sqrt(dx * dx + dy * dy); guard length > 0 else { return .infinity }
        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / (length * length)))
        let ex = point.x - (lineStart.x + t * dx), ey = point.y - (lineStart.y + t * dy)
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
        view.onScroll = onScroll; view.onMouseMove = onMouseMove
        view.onDragBegan = onDragBegan; view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded; view.onDoubleClick = onDoubleClick
        view.onEnterKey = onEnterKey; view.onDeleteKey = onDeleteKey
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.onScroll = onScroll; nsView.onMouseMove = onMouseMove
        nsView.onDragBegan = onDragBegan; nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded; nsView.onDoubleClick = onDoubleClick
        nsView.onEnterKey = onEnterKey; nsView.onDeleteKey = onDeleteKey
    }
}
