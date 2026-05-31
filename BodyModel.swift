//
//  BodyModel.swift
//  SewingCAD
//
//  計測値（バスト・ウエスト・ヒップ・身長）から
//  SceneKitの簡易マネキンノードを生成する。
//

import SceneKit

struct BodyMeasurements {
    var height: CGFloat   // cm
    var bust: CGFloat     // cm（胸囲）
    var waist: CGFloat    // cm（胴囲）
    var hip: CGFloat      // cm（腰囲）

    // デフォルト値（身長160cm、9号サイズ相当）
    static let `default` = BodyMeasurements(height: 160, bust: 83, waist: 64, hip: 91)
}

class BodyModel {

    /// 計測値から簡易マネキンノードを生成して返す
    static func makeNode(from m: BodyMeasurements) -> SCNNode {
        let root = SCNNode()

        // 単位変換: cm → SceneKit単位（1unit = 10cm）
        let unit: CGFloat = 0.1

        let h      = m.height * unit        // 全身高さ
        let bR     = (m.bust / .pi) * unit  // 胸の半径（周囲÷π÷2 だが見た目優先で近似）
        let wR     = (m.waist / .pi) * unit
        let hipR   = (m.hip / .pi) * unit

        // --- 各パーツのY位置（下から積み上げ） ---
        let legH   = h * 0.47
        let hipH   = h * 0.12
        let torsoH = h * 0.28
        let neckH  = h * 0.05
        let headH  = h * 0.12

        let legY   = legH / 2
        let hipY   = legH + hipH / 2
        let torsoY = legH + hipH + torsoH / 2
        let neckY  = legH + hipH + torsoH + neckH / 2
        let headY  = legH + hipH + torsoH + neckH + headH / 2

        // --- 足（左右の円柱） ---
        let legR = hipR * 0.28
        for side in [-1.0, 1.0] {
            let leg = SCNCylinder(radius: legR, height: legH)
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(Float(side * legR * 1.05), Float(legY), 0)
            legNode.geometry?.firstMaterial?.diffuse.contents = bodyColor
            root.addChildNode(legNode)
        }

        // --- 腰（楕円体で近似：X方向にhipR、Y方向に小さく） ---
        let hipSphere = SCNSphere(radius: hipR)
        // 楕円に見せるためscaleでY方向を圧縮
        let hipNode = SCNNode(geometry: hipSphere)
        hipNode.position = SCNVector3(0, Float(hipY), 0)
        hipNode.scale = SCNVector3(1.0, Float(hipH / (hipR * 2)), 0.82)
        hipNode.geometry?.firstMaterial?.diffuse.contents = bodyColor
        root.addChildNode(hipNode)

        // --- 胴体（円筒：ウエストとバストの中間径） ---
        let torsoAvgR = (wR + bR) / 2
        let torso = SCNCylinder(radius: torsoAvgR, height: torsoH)
        // 上がバスト径、下がウエスト径になるよう ひし形っぽく
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.position = SCNVector3(0, Float(torsoY), 0)
        torsoNode.scale = SCNVector3(1.0, 1.0, 0.78) // 前後に薄く
        torsoNode.geometry?.firstMaterial?.diffuse.contents = bodyColor
        root.addChildNode(torsoNode)

        // --- 胸（バスト位置に球を2つ）---
        let bustSphereR = bR * 0.36
        let bustY = legH + hipH + torsoH * 0.68
        for side in [-1.0, 1.0] {
            let s = SCNSphere(radius: bustSphereR)
            let sNode = SCNNode(geometry: s)
            sNode.position = SCNVector3(Float(side * bR * 0.38), Float(bustY), Float(torsoAvgR * 0.65))
            sNode.geometry?.firstMaterial?.diffuse.contents = bodyColor
            root.addChildNode(sNode)
        }

        // --- 肩（左右の球） ---
        let shoulderR = bR * 0.22
        let shoulderY = legH + hipH + torsoH
        for side in [-1.0, 1.0] {
            let s = SCNSphere(radius: shoulderR)
            let sNode = SCNNode(geometry: s)
            sNode.position = SCNVector3(Float(side * (bR + shoulderR * 0.6)), Float(shoulderY), 0)
            sNode.geometry?.firstMaterial?.diffuse.contents = bodyColor
            root.addChildNode(sNode)
        }

        // --- 腕（左右の円柱） ---
        let armH = h * 0.30
        let armR = bR * 0.14
        let armY = shoulderY + armH * 0.5 - shoulderR
        for side in [-1.0, 1.0] {
            let arm = SCNCylinder(radius: armR, height: armH)
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(Float(side * (bR + shoulderR * 1.1)), Float(shoulderY - armH / 2), 0)
            armNode.geometry?.firstMaterial?.diffuse.contents = bodyColor
            root.addChildNode(armNode)
        }
        _ = armY // suppress warning

        // --- 首 ---
        let neck = SCNCylinder(radius: bR * 0.16, height: neckH)
        let neckNode = SCNNode(geometry: neck)
        neckNode.position = SCNVector3(0, Float(neckY), 0)
        neckNode.geometry?.firstMaterial?.diffuse.contents = bodyColor
        root.addChildNode(neckNode)

        // --- 頭 ---
        let head = SCNSphere(radius: headH / 2)
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, Float(headY), 0)
        headNode.geometry?.firstMaterial?.diffuse.contents = bodyColor
        root.addChildNode(headNode)

        // 全体を床（Y=0）が足元になるよう位置調整（すでにY=0が足元）
        return root
    }

    private static var bodyColor: NSColor {
        NSColor(red: 0.88, green: 0.82, blue: 0.76, alpha: 1.0) // マネキン肌色
    }
}
