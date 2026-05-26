//
//  PatternLine.swift
//  SewingCAD
//

import Foundation

struct PatternLine: Identifiable, Equatable {
    let id = UUID()
    var startPoint: CGPoint
    var endPoint: CGPoint
    var label: String = "" 

    // 長さ（px）
    var length: CGFloat {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        return sqrt(dx * dx + dy * dy)
    }

    // 長さ（cm）
    var lengthCm: CGFloat {
        length / 37.8
    }

    // 角度（度）起点からの角度
    var angle: CGFloat {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let rad = atan2(dy, dx)
        var deg = rad * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    // 角度と長さから終点を計算
    mutating func update(angle: CGFloat, lengthCm: CGFloat) {
        let rad = angle * .pi / 180
        let px = lengthCm * 37.8
        endPoint = CGPoint(
            x: startPoint.x + cos(rad) * px,
            y: startPoint.y + sin(rad) * px
        )
    }
}
