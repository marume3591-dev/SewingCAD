//
//  ProjectData.swift
//  SewingCAD
//

import Foundation

// パターンパーツの種類
enum PatternPartType: String, Codable, CaseIterable {
    case bodiceFront = "前身頃"
    case bodiceBack  = "後身頃"
    case sleeveFront = "袖"
    case skirtFront  = "前スカート"
    case skirtBack   = "後スカート"
    case pants       = "パンツ"
    case collar      = "衿"
    case cuff        = "袖口"
    case waistband   = "ウエストバンド"
    case other       = "その他"
}

// 1パーツ = 1パターンファイル
struct PatternPart: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String               // 例："前身頃"
    var type: PatternPartType      // 種類
    var fileName: String           // 例："bodice_front.json"
    var isLocked: Bool = false     // 編集ロック
}

// 接合部定義
struct SeamConnection: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String               // 例："袖ぐり"
    var fromPartID: UUID           // 接合元パーツID
    var fromLabel: String          // 接合元の曲線ラベル
    var toPartID: UUID             // 接合先パーツID
    var toLabel: String            // 接合先の曲線ラベル
    var ease: CGFloat = 0.0        // イーズ量(cm)
}

// プロジェクト全体
struct ProjectData: Codable {
    var id: UUID = UUID()
    var name: String               // プロジェクト名
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var parts: [PatternPart] = []
    var connections: [SeamConnection] = []
}
