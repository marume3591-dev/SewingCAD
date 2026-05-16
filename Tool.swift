//
//  Tool.swift
//  SewingCAD
//

import Foundation

enum Tool {
    case select
    case addPoint
    case addLine
    case delete
    case addCurve
    case groupSelect
    case parallel      // 平行線
    case perpendicular // 垂直線
    case extend        // 線の延長
    case midpoint      // 中点
    case arc           // 円弧
    case text          // テキスト
    case lineInput
    case intersection
    // フェーズ2
    case mirror        // 鏡像コピー
    case notch         // ノッチ（合いじるし）
    case seamOverride  // 縫い代個別設定
    case grading       // グレーディング
}
