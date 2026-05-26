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

// MARK: - 縫い代

enum SeamSide: String, Codable {
    case both, left, right
}

struct SeamAllowanceOverride: Identifiable {
    let id = UUID()
    var lineID: UUID
    var width: CGFloat   // cm
    var side: SeamSide
}

// MARK: - ノッチ（合いじるし）
// CanvasView では NotchData という名前で参照しているため typealias で統一
struct Notch: Identifiable {
    let id = UUID()
    var lineID: UUID
    var t: CGFloat      // 0.0〜1.0（線上の位置）
    var size: CGFloat   // px単位
}
typealias NotchData = Notch

// MARK: - グレーディング

struct GradePoint: Identifiable {
    let id = UUID()
    var pointID: UUID
    var sizeName: String
    var dx: CGFloat     // cm
    var dy: CGFloat     // cm
}

// MARK: - CanvasState

class CanvasState: ObservableObject {
    @Published var points: [PatternPoint] = []
    @Published var lines: [PatternLine] = []
    @Published var curves: [CurveData] = []
    @Published var arcs: [ArcData] = []
    @Published var texts: [TextAnnotation] = []
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    // フェーズ2
    @Published var seamOverrides: [SeamAllowanceOverride] = []
    @Published var notches: [Notch] = []
    @Published var gradePoints: [GradePoint] = []
    @Published var gradingSizes: [String] = ["S", "M", "L"]
    @Published var activeGradeSize: String = "M"
    @Published var showGrading: Bool = false
    @Published var showPaperGrid: Bool = true

    // 設定
    @Published var showGrid: Bool = true
    @Published var paperSize: PaperSize = .a4 {
        didSet {
            if paperSize != .custom { currentPaperSize = paperSize.size }
        }
    }
    @Published var customPaperWidth: CGFloat = 794 {
        didSet {
            if paperSize == .custom {
                currentPaperSize = CGSize(width: customPaperWidth, height: customPaperHeight)
            }
        }
    }
    @Published var customPaperHeight: CGFloat = 1123 {
        didSet {
            if paperSize == .custom {
                currentPaperSize = CGSize(width: customPaperWidth, height: customPaperHeight)
            }
        }
    }
    @Published var showSeamAllowance: Bool = false
    @Published var seamAllowance: CGFloat = 1.0
    @Published var currentPaperSize: CGSize = PaperSize.a4.size

    private var history: [Snapshot] = []
    private var historyIndex: Int = -1
    private let maxHistory = 50

    struct Snapshot {
        var points: [PatternPoint]
        var lines: [PatternLine]
        var curves: [CurveData]
        var arcs: [ArcData]
        var texts: [TextAnnotation]
        var seamOverrides: [SeamAllowanceOverride]
        var notches: [Notch]
        var gradePoints: [GradePoint]
    }

    init() { saveSnapshot() }

    // MARK: - ユーティリティ

    /// 指定した線の縫い代幅（個別設定がなければデフォルト値）
    func seamWidth(for lineID: UUID) -> CGFloat {
        seamOverrides.first(where: { $0.lineID == lineID })?.width ?? seamAllowance
    }

    /// 指定サイズでの点の座標（グレードオフセット適用済み）
    func gradedPosition(of point: PatternPoint, for sizeName: String) -> CGPoint {
        guard let gp = gradePoints.first(where: { $0.pointID == point.id && $0.sizeName == sizeName }) else {
            return point.position
        }
        return CGPoint(
            x: point.position.x + gp.dx * 37.8,
            y: point.position.y + gp.dy * 37.8
        )
    }

    // MARK: - 履歴

    func saveSnapshot() {
        if historyIndex < history.count - 1 { history.removeSubrange((historyIndex + 1)...) }
        history.append(Snapshot(
            points: points, lines: lines, curves: curves, arcs: arcs, texts: texts,
            seamOverrides: seamOverrides, notches: notches, gradePoints: gradePoints
        ))
        if history.count > maxHistory { history.removeFirst() }
        historyIndex = history.count - 1
        canUndo = historyIndex > 0
        canRedo = historyIndex < history.count - 1
    }

    func undo() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        apply(history[historyIndex])
    }

    func redo() {
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
        apply(history[historyIndex])
    }

    private func apply(_ s: Snapshot) {
        points = s.points; lines = s.lines; curves = s.curves
        arcs = s.arcs; texts = s.texts
        seamOverrides = s.seamOverrides; notches = s.notches; gradePoints = s.gradePoints
        canUndo = historyIndex > 0
        canRedo = historyIndex < history.count - 1
    }

    // MARK: - 保存・読み込み

    func toPatternData() -> PatternData {
        let savedPoints = points.map { SavedPoint(id: $0.id, x: $0.position.x, y: $0.position.y, name: $0.name) }
        let savedLines  = lines.map  { SavedLine(x1: $0.startPoint.x, y1: $0.startPoint.y, x2: $0.endPoint.x, y2: $0.endPoint.y,
                                                 label: $0.label ) }
        let savedCurves = curves.map { curve in
            SavedCurve(nodes: curve.nodes.map {
                SavedCurveNode(x: $0.point.x, y: $0.point.y,
                               cp1x: $0.controlPoint1.x, cp1y: $0.controlPoint1.y,
                               cp2x: $0.controlPoint2.x, cp2y: $0.controlPoint2.y)
            },
            label: curve.label
            )
        }
        let savedArcs   = arcs.map  { SavedArc(cx: $0.center.x, cy: $0.center.y, radius: $0.radius, startAngle: $0.startAngle, endAngle: $0.endAngle) }
        let savedTexts  = texts.map { SavedText(x: $0.position.x, y: $0.position.y, text: $0.text, fontSize: $0.fontSize) }
        let savedNotches = notches.map { SavedNotch(lineID: $0.lineID, t: $0.t, size: $0.size) }
        let savedSeamOverrides = seamOverrides.map { SavedSeamOverride(lineID: $0.lineID, width: $0.width, side: $0.side.rawValue) }
        let savedGradePoints = gradePoints.map { SavedGradePoint(pointID: $0.pointID, sizeName: $0.sizeName, dx: $0.dx, dy: $0.dy) }

        return PatternData(
            points: savedPoints, lines: savedLines, curves: savedCurves,
            arcs: savedArcs, texts: savedTexts,
            notches: savedNotches, seamOverrides: savedSeamOverrides, gradePoints: savedGradePoints
        )
    }

    func load(from data: PatternData) {
        points = data.points.map { PatternPoint(position: CGPoint(x: $0.x, y: $0.y), name: $0.name) }
        lines  = data.lines.map  { PatternLine(startPoint: CGPoint(x: $0.x1, y: $0.y1), endPoint: CGPoint(x: $0.x2, y: $0.y2),
                                               label: $0.label) }
        curves = data.curves.map { savedCurve in
            CurveData(nodes: savedCurve.nodes.map {
                CurveNode(point: CGPoint(x: $0.x, y: $0.y),
                          controlPoint1: CGPoint(x: $0.cp1x, y: $0.cp1y),
                          controlPoint2: CGPoint(x: $0.cp2x, y: $0.cp2y))
            },
            label: savedCurve.label
            )
        }
        arcs   = data.arcs.map  { ArcData(center: CGPoint(x: $0.cx, y: $0.cy), radius: $0.radius, startAngle: $0.startAngle, endAngle: $0.endAngle) }
        texts  = data.texts.map { TextAnnotation(position: CGPoint(x: $0.x, y: $0.y), text: $0.text, fontSize: $0.fontSize) }
        notches = data.notches.map { Notch(lineID: $0.lineID, t: $0.t, size: $0.size) }
        seamOverrides = data.seamOverrides.map {
            SeamAllowanceOverride(lineID: $0.lineID, width: $0.width, side: SeamSide(rawValue: $0.side) ?? .both)
        }
        gradePoints = data.gradePoints.map { GradePoint(pointID: $0.pointID, sizeName: $0.sizeName, dx: $0.dx, dy: $0.dy) }
        history = []; historyIndex = -1
        saveSnapshot()
    }

    func reset() {
        points = []; lines = []; curves = []; arcs = []; texts = []
        seamOverrides = []; notches = []; gradePoints = []
        history = []; historyIndex = -1
        canUndo = false; canRedo = false
    }
}

// MARK: - 曲線データ

struct CurveNode {
    var point: CGPoint
    var controlPoint1: CGPoint
    var controlPoint2: CGPoint
}

struct CurveData: Identifiable {
    let id = UUID()
    var nodes: [CurveNode]
    var isSelected: Bool = false
    var label: String = ""
}
