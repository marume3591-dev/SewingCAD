//
//  TextAnnotation.swift
//  SewingCAD
//

import Foundation

struct TextAnnotation: Identifiable {
    let id = UUID()
    var position: CGPoint
    var text: String
    var fontSize: CGFloat = 14
}
