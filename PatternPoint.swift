//
//  PatternPoint.swift
//  SewingCAD
//

import Foundation

struct PatternPoint: Identifiable, Equatable {
    let id = UUID()
    var position: CGPoint
    var name: String
}

