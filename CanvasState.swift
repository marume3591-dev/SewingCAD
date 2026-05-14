//
//  CanvasState.swift
//  SewingCAD
//

import SwiftUI

enum PaperSize: String, CaseIterable {
    case a4 = "A4"
    case a3 = "A3"
    case a2 = "A2"
    case a1 = "A1"
    case custom = "カスタム"

    var size: CGSize {
        switch self {
        case .a4: return CGSize(width: 794, height: 1123)
        case .a3: return CGSize(width: 1123, height: 1587)
        case .a2: return CGSize(width: 1587, height: 2245)
        case .a1: return CGSize(width: 2245, height: 3175)
        case .custom: return CGSize(width: 794, height: 1123)
        }
    }
}

class CanvasState: ObservableObject {
    @Published var points: [PatternPoint] = []
    @Published var lines: [PatternLine] = []
    @Published var curves: [CurveData] = []
    @Published var arcs: [ArcData] = []
    @Published var texts: [TextAnnotation] = []
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    // 設定
    @Published var showGrid: Bool = true
    @Published var paperSize: PaperSize = .a4
    @Published var customPaperWidth: CGFloat = 794
    @Published var customPaperHeight: CGFloat = 1123
    @Published var showSeamAllowance: Bool = false
    @Published var seamAllowance: CGFloat = 1.0

    var currentPaperSize: CGSize {
        paperSize == .custom ? CGSize(width: customPaperWidth, height: customPaperHeight) : paperSize.size
    }

    private var history: [Snapshot] = []
    private var historyIndex: Int = -1
    private let maxHistory = 50

    struct Snapshot {
        var points: [PatternPoint]
        var lines: [PatternLine]
        var curves: [CurveData]
        var arcs: [ArcData]
        var texts: [TextAnnotation]
    }

    init() {
        saveSnapshot()
    }

    func saveSnapshot() {
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(Snapshot(points: points, lines: lines, curves: curves, arcs: arcs, texts: texts))
        if history.count > maxHistory {
            history.removeFirst()
        }
        historyIndex = history.count - 1
        canUndo = historyIndex > 0
        canRedo = historyIndex < history.count - 1
    }

    func undo() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        let snapshot = history[historyIndex]
        points = snapshot.points
        lines = snapshot.lines
        curves = snapshot.curves
        arcs = snapshot.arcs
        texts = snapshot.texts
        canUndo = historyIndex > 0
        canRedo = historyIndex < history.count - 1
    }

    func redo() {
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
        let snapshot = history[historyIndex]
        points = snapshot.points
        lines = snapshot.lines
        curves = snapshot.curves
        arcs = snapshot.arcs
        texts = snapshot.texts
        canUndo = historyIndex > 0
        canRedo = historyIndex < history.count - 1
    }

    func toPatternData() -> PatternData {
        let savedPoints = points.map {
            SavedPoint(id: $0.id, x: $0.position.x, y: $0.position.y, name: $0.name)
        }
        let savedLines = lines.map {
            SavedLine(x1: $0.startPoint.x, y1: $0.startPoint.y,
                     x2: $0.endPoint.x, y2: $0.endPoint.y)
        }
        let savedCurves = curves.map { curve in
            SavedCurve(nodes: curve.nodes.map {
                SavedCurveNode(
                    x: $0.point.x, y: $0.point.y,
                    cp1x: $0.controlPoint1.x, cp1y: $0.controlPoint1.y,
                    cp2x: $0.controlPoint2.x, cp2y: $0.controlPoint2.y
                )
            })
        }
        let savedArcs = arcs.map {
            SavedArc(cx: $0.center.x, cy: $0.center.y,
                    radius: $0.radius,
                    startAngle: $0.startAngle,
                    endAngle: $0.endAngle)
        }
        let savedTexts = texts.map {
            SavedText(x: $0.position.x, y: $0.position.y,
                     text: $0.text, fontSize: $0.fontSize)
        }
        return PatternData(points: savedPoints, lines: savedLines, curves: savedCurves,
                          arcs: savedArcs, texts: savedTexts)
    }

    func load(from data: PatternData) {
        points = data.points.map {
            PatternPoint(position: CGPoint(x: $0.x, y: $0.y), name: $0.name)
        }
        lines = data.lines.map {
            PatternLine(startPoint: CGPoint(x: $0.x1, y: $0.y1),
                       endPoint: CGPoint(x: $0.x2, y: $0.y2))
        }
        curves = data.curves.map { savedCurve in
            CurveData(nodes: savedCurve.nodes.map {
                CurveNode(
                    point: CGPoint(x: $0.x, y: $0.y),
                    controlPoint1: CGPoint(x: $0.cp1x, y: $0.cp1y),
                    controlPoint2: CGPoint(x: $0.cp2x, y: $0.cp2y)
                )
            })
        }
        arcs = data.arcs.map {
            ArcData(center: CGPoint(x: $0.cx, y: $0.cy),
                   radius: $0.radius,
                   startAngle: $0.startAngle,
                   endAngle: $0.endAngle)
        }
        texts = data.texts.map {
            TextAnnotation(position: CGPoint(x: $0.x, y: $0.y),
                          text: $0.text, fontSize: $0.fontSize)
        }
        history = []
        historyIndex = -1
        saveSnapshot()
    }

    func reset() {
        points = []
        lines = []
        curves = []
        arcs = []
        texts = []
        history = []
        historyIndex = -1
        canUndo = false
        canRedo = false
    }
}

struct CurveNode {
    var point: CGPoint
    var controlPoint1: CGPoint
    var controlPoint2: CGPoint
}

struct CurveData: Identifiable {
    let id = UUID()
    var nodes: [CurveNode]
    var isSelected: Bool = false
}
