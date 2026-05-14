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
}
