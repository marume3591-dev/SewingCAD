//
//  ArcData.swift
//  SewingCAD
//

import Foundation

struct ArcData: Identifiable {
    let id = UUID()
    var center: CGPoint
    var radius: CGFloat
    var startAngle: CGFloat  // 度
    var endAngle: CGFloat    // 度
}
