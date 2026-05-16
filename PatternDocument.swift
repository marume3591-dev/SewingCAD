//
//  PatternDocument.swift
//  SewingCAD
//

import Foundation
import AppKit

struct PatternData: Codable {
    var points: [SavedPoint]
    var lines: [SavedLine]
    var curves: [SavedCurve]
    var arcs: [SavedArc]
    var texts: [SavedText]
    var notches: [SavedNotch]
    var seamOverrides: [SavedSeamOverride]
    var gradePoints: [SavedGradePoint]
}

struct SavedPoint: Codable { var id: UUID; var x: CGFloat; var y: CGFloat; var name: String }
struct SavedLine: Codable { var x1: CGFloat; var y1: CGFloat; var x2: CGFloat; var y2: CGFloat }
struct SavedCurve: Codable { var nodes: [SavedCurveNode] }
struct SavedCurveNode: Codable { var x: CGFloat; var y: CGFloat; var cp1x: CGFloat; var cp1y: CGFloat; var cp2x: CGFloat; var cp2y: CGFloat }
struct SavedArc: Codable { var cx: CGFloat; var cy: CGFloat; var radius: CGFloat; var startAngle: CGFloat; var endAngle: CGFloat }
struct SavedText: Codable { var x: CGFloat; var y: CGFloat; var text: String; var fontSize: CGFloat }
struct SavedNotch: Codable { var lineID: UUID; var t: CGFloat; var size: CGFloat }
struct SavedSeamOverride: Codable { var lineID: UUID; var width: CGFloat; var side: String }
struct SavedGradePoint: Codable { var pointID: UUID; var sizeName: String; var dx: CGFloat; var dy: CGFloat }

class PatternDocument {
    static func save(_ data: PatternData) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "pattern.json"
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let encoded = try JSONEncoder().encode(data)
                        try encoded.write(to: url)
                    } catch { print("保存失敗: \(error)") }
                }
            }
        }
    }

    static func load(completion: @escaping (PatternData?) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.begin { response in
                guard response == .OK, let url = panel.url else { completion(nil); return }
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try Data(contentsOf: url)
                        let decoded = try JSONDecoder().decode(PatternData.self, from: data)
                        DispatchQueue.main.async { completion(decoded) }
                    } catch {
                        print("読み込み失敗: \(error)")
                        DispatchQueue.main.async { completion(nil) }
                    }
                }
            }
        }
    }
}
