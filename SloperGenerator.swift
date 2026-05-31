//
//  SloperGenerator.swift
//  SewingCAD
//
//  新文化式原型（成人女子用）の自動生成
//  入力: バスト(B)・ウエスト(W)・ヒップ(H)・背丈・身長
//  出力: PatternData（線・曲線・点）
//
//  ※作図式は新文化式を基準としています。
//  　曲線部分は近似値のため、実際の型紙と差異が出る場合があります。
//

import Foundation

// MARK: - 入力寸法

struct SloperMeasurements {
    var bust: CGFloat        // バスト (cm)
    var waist: CGFloat       // ウエスト (cm)
    var hip: CGFloat         // ヒップ (cm)
    var backLength: CGFloat  // 背丈 (cm) ※首の後ろからウエストまで
    var height: CGFloat      // 身長 (cm)

    // 背丈が未入力の場合の推定値
    static func estimatedBackLength(height: CGFloat) -> CGFloat {
        return height * 0.239 + 1.0
    }
}

// MARK: - 原型生成結果

struct SloperResult {
    var bodiceBack: PatternData    // 後ろ身頃
    var bodiceFront: PatternData   // 前身頃
    var sleeve: PatternData        // 袖
    var skirtBack: PatternData     // 後ろスカート
    var skirtFront: PatternData    // 前スカート
}

// MARK: - 原型生成クラス

class SloperGenerator {

    // px変換係数: 1cm = 37.8px
    private static let pxPerCm: CGFloat = 37.8

    static func generate(from m: SloperMeasurements) -> SloperResult {
        return SloperResult(
            bodiceBack:  generateBodiceBack(m),
            bodiceFront: generateBodiceFront(m),
            sleeve:      generateSleeve(m),
            skirtBack:   generateSkirtBack(m),
            skirtFront:  generateSkirtFront(m)
        )
    }

    // MARK: - px変換

    private static func px(_ cm: CGFloat) -> CGFloat { cm * pxPerCm }

    // MARK: - 後ろ身頃

    private static func generateBodiceBack(_ m: SloperMeasurements) -> PatternData {
        let B = m.bust
        let W = m.waist
        let BL = m.backLength

        // 各部寸法（新文化式）
        let mihaaba   = B / 2 + 6.0      // 身幅（半身）
        let sehaaba   = B / 8 + 7.0      // 背幅
        let aToBL     = B / 12 + 13.7    // 後ろ首付け根〜バストライン
        let backNeckW = B / 24 + 3.4     // 後ろ襟ぐり幅
        let backNeckD = backNeckW / 3.0  // 後ろ襟ぐり深さ
        let shoulderSlant: CGFloat = 2.0 // 後ろ肩傾斜（落ち量cm）
        let shoulderLen = B / 8 + 4.7 + 1.8 // 肩線長さ（肩ダーツ1.8含む）

        // ウエストダーツ量
        let totalDartBack = (mihaaba - (W / 2 + 1.5)) * 0.6

        // ────────────────────────────────
        // 座標系: 後ろ中心を X=0
        // Y=0 を SNP（後ろ肩首点）の高さとし、全体が原点より下に収まるようにする
        // BNPはSNPより backNeckD 下
        // ────────────────────────────────

        let offsetY = px(backNeckD)  // 全体をこの分下にずらす

        // 基準点
        let BNP = CGPoint(x: 0, y: offsetY)                              // 後ろ首付け根
        let WCB = CGPoint(x: 0, y: offsetY + px(BL))                    // ウエスト後ろ中心
        let BLS = CGPoint(x: px(mihaaba), y: offsetY + px(aToBL))       // バストライン脇
        let WLS = CGPoint(x: px(mihaaba), y: offsetY + px(BL))          // ウエストライン脇

        // SNP（後ろ肩首点）: Y=0（原点）
        let SNP = CGPoint(x: px(backNeckW), y: 0)

        // SP（肩先点）: SNPから肩傾斜に沿ってshoulderLen
        let slopeDx = sehaaba - backNeckW
        let slopeDy = shoulderSlant
        let slopeLen = sqrt(slopeDx * slopeDx + slopeDy * slopeDy)
        let shoulderUx = slopeDx / slopeLen
        let shoulderUy = slopeDy / slopeLen
        let SP = CGPoint(
            x: SNP.x + px(shoulderUx * shoulderLen),
            y: SNP.y + px(shoulderUy * shoulderLen)
        )

        // ウエストダーツ
        let dartCX  = px(sehaaba * 0.55)
        let dartTip = CGPoint(x: dartCX, y: offsetY + px(aToBL) - px(3.0))
        let dartL   = CGPoint(x: dartCX - px(totalDartBack / 2), y: offsetY + px(BL))
        let dartR   = CGPoint(x: dartCX + px(totalDartBack / 2), y: offsetY + px(BL))

        var lines: [SavedLine] = []

        // 後ろ中心線（BNP→WCB）垂直
        lines.append(SavedLine(x1: BNP.x, y1: BNP.y, x2: WCB.x, y2: WCB.y))
        // ウエストライン（ダーツで分割）
        lines.append(SavedLine(x1: WCB.x, y1: WCB.y, x2: dartL.x, y2: dartL.y))
        lines.append(SavedLine(x1: dartR.x, y1: dartR.y, x2: WLS.x, y2: WLS.y))
        // ウエストダーツ
        lines.append(SavedLine(x1: dartL.x, y1: dartL.y, x2: dartTip.x, y2: dartTip.y))
        lines.append(SavedLine(x1: dartTip.x, y1: dartTip.y, x2: dartR.x, y2: dartR.y))
        // 脇線（WLS→BLS）
        lines.append(SavedLine(x1: WLS.x, y1: WLS.y, x2: BLS.x, y2: BLS.y))
        // 肩線（SNP→SP）
        lines.append(SavedLine(x1: SNP.x, y1: SNP.y, x2: SP.x, y2: SP.y))

        // 後ろ襟ぐりカーブ（BNP→SNP）
        // BNPから横方向、SNPから下方向で滑らかに繋ぐ
        let neckCurveNodes = [
            SavedCurveNode(
                x: BNP.x, y: BNP.y,
                cp1x: BNP.x, cp1y: BNP.y,
                cp2x: BNP.x + px(backNeckW * 0.5), cp2y: BNP.y
            ),
            SavedCurveNode(
                x: SNP.x, y: SNP.y,
                cp1x: SNP.x, cp1y: SNP.y + px(backNeckD * 0.5),
                cp2x: SNP.x, cp2y: SNP.y
            )
        ]

        // 袖ぐりカーブ（SP→BLS）
        // SP: 右下方向へ、BLS: 上方向から来る、で凸型カーブ
        let ahHeight = BLS.y - SP.y  // SPからBLSまでの高さ
        let ahWidth  = BLS.x - SP.x  // SPからBLSまでの横幅
        let ahCurveNodes = [
            SavedCurveNode(
                x: SP.x, y: SP.y,
                cp1x: SP.x, cp1y: SP.y,
                cp2x: SP.x + ahWidth * 0.3, cp2y: SP.y + ahHeight * 0.6
            ),
            SavedCurveNode(
                x: BLS.x, y: BLS.y,
                cp1x: BLS.x - ahWidth * 0.15, cp1y: BLS.y - ahHeight * 0.4,
                cp2x: BLS.x, cp2y: BLS.y
            )
        ]

        let savedCurves = [
            SavedCurve(nodes: neckCurveNodes),
            SavedCurve(nodes: ahCurveNodes)
        ]

        let points = [
            SavedPoint(id: UUID(), x: BNP.x, y: BNP.y, name: "BNP"),
            SavedPoint(id: UUID(), x: SNP.x, y: SNP.y, name: "SNP"),
            SavedPoint(id: UUID(), x: SP.x,  y: SP.y,  name: "SP"),
            SavedPoint(id: UUID(), x: WCB.x, y: WCB.y, name: "WCB"),
            SavedPoint(id: UUID(), x: WLS.x, y: WLS.y, name: "WS"),
        ]

        return PatternData(points: points, lines: lines, curves: savedCurves, arcs: [], texts: [
            SavedText(x: px(mihaaba / 2), y: offsetY + px(BL / 2), text: "後ろ身頃", fontSize: 14)
        ], notches: [], seamOverrides: [], gradePoints: [])
    }

    // MARK: - 前身頃

    private static func generateBodiceFront(_ m: SloperMeasurements) -> PatternData {
        let B = m.bust
        let W = m.waist
        let BL = m.backLength

        let mihaaba    = B / 2 + 6.0
        let munehaaba  = B / 8 + 6.2      // 胸幅
        let aToBL      = B / 12 + 13.7    // 前中心上端〜バストライン
        let frontNeckW = B / 24 + 3.4     // 前襟ぐり幅
        let frontNeckD = frontNeckW + 1.0  // 前襟ぐり深さ
        let shoulderSlant: CGFloat = 3.0   // 前肩傾斜（落ち量cm）
        let shoulderLen = B / 8 + 4.7     // 前肩線長さ
        let frontWaistDart = (mihaaba - (W / 2 + 1.5)) * 0.4

        // ────────────────────────────────
        // 座標系: 前中心を X=0、前中心上端を Y=0
        // X軸: 前中心→脇方向（右が正）
        // Y軸: 上→下（下が正）
        // ────────────────────────────────

        // 基準点
        let FCN  = CGPoint(x: 0, y: 0)               // 前中心上端（襟ぐり基点）
        let FW   = CGPoint(x: 0, y: px(BL))           // 前中心ウエスト
        let BLC  = CGPoint(x: 0,          y: px(aToBL)) // バストライン前中心
        let BLS  = CGPoint(x: px(mihaaba), y: px(aToBL)) // バストライン脇
        let WLS  = CGPoint(x: px(mihaaba), y: px(BL))   // ウエストライン脇

        // FNP（前首点）: 前中心から下にfrontNeckD
        let FNP  = CGPoint(x: 0, y: px(frontNeckD))

        // SNP（前肩首点）: 前中心から横にfrontNeckW、わずかに下
        let SNP  = CGPoint(x: px(frontNeckW), y: px(frontNeckD * 0.1))

        // SP（前肩先点）
        let slopeDx = munehaaba - frontNeckW
        let slopeDy = shoulderSlant
        let slopeLen = sqrt(slopeDx * slopeDx + slopeDy * slopeDy)
        let shoulderUx = slopeDx / slopeLen
        let shoulderUy = slopeDy / slopeLen
        let SP = CGPoint(
            x: SNP.x + px(shoulderUx * shoulderLen),
            y: SNP.y + px(shoulderUy * shoulderLen)
        )

        // BP（バストポイント）: 前中心からB/8+2.5、BLより2cm上
        let BP = CGPoint(x: px(B / 8 + 2.5), y: px(aToBL) - px(2.0))

        // 胸ぐせダーツ（袖ぐり側に向けて開く・約10〜12度）
        let dartHalfAngle: CGFloat = 6.0 * .pi / 180  // 片側6度
        let bpToSP = atan2(SP.y - BP.y, SP.x - BP.x)
        let dartLen = px(7.0)
        let dartTip1 = CGPoint(
            x: BP.x + cos(bpToSP - dartHalfAngle) * dartLen,
            y: BP.y + sin(bpToSP - dartHalfAngle) * dartLen
        )
        let dartTip2 = CGPoint(
            x: BP.x + cos(bpToSP + dartHalfAngle) * dartLen,
            y: BP.y + sin(bpToSP + dartHalfAngle) * dartLen
        )

        // ウエストダーツ
        let dartCX   = px(B / 8 + 2.5)                              // BPのX位置に合わせる
        let dartTip3 = CGPoint(x: dartCX, y: px(aToBL) - px(3.0))  // BLより3cm上
        let dartL    = CGPoint(x: dartCX - px(frontWaistDart / 2), y: px(BL))
        let dartR    = CGPoint(x: dartCX + px(frontWaistDart / 2), y: px(BL))

        // 袖ぐり補助点
        let AH_mid = CGPoint(x: px(munehaaba), y: (SP.y + BLS.y) / 2 + px(1.0))

        var lines: [SavedLine] = []

        // 前中心線（FCN→FW）
        lines.append(SavedLine(x1: FCN.x, y1: FCN.y, x2: FW.x, y2: FW.y))
        // ウエストライン（ダーツで分割）
        lines.append(SavedLine(x1: FW.x, y1: FW.y, x2: dartL.x, y2: dartL.y))
        lines.append(SavedLine(x1: dartR.x, y1: dartR.y, x2: WLS.x, y2: WLS.y))
        // ウエストダーツ
        lines.append(SavedLine(x1: dartL.x, y1: dartL.y, x2: dartTip3.x, y2: dartTip3.y))
        lines.append(SavedLine(x1: dartTip3.x, y1: dartTip3.y, x2: dartR.x, y2: dartR.y))
        // 脇線（WLS→BLS）
        lines.append(SavedLine(x1: WLS.x, y1: WLS.y, x2: BLS.x, y2: BLS.y))
        // 肩線（SNP→SP）
        lines.append(SavedLine(x1: SNP.x, y1: SNP.y, x2: SP.x, y2: SP.y))
        // 胸ぐせダーツ（BP→袖ぐり側）
        lines.append(SavedLine(x1: BP.x, y1: BP.y, x2: dartTip1.x, y2: dartTip1.y))
        lines.append(SavedLine(x1: BP.x, y1: BP.y, x2: dartTip2.x, y2: dartTip2.y))

        // 前襟ぐりカーブ（FCN→FNP→SNP）
        // FCNから下向き、FNPで折れて横向き、SNPへ
        let neckCurveNodes = [
            SavedCurveNode(
                x: FCN.x, y: FCN.y,
                cp1x: FCN.x, cp1y: FCN.y,
                cp2x: FCN.x, cp2y: FCN.y + px(frontNeckD * 0.5)
            ),
            SavedCurveNode(
                x: FNP.x, y: FNP.y,
                cp1x: FNP.x, cp1y: FNP.y + px(0.5),
                cp2x: FNP.x + px(frontNeckW * 0.5), cp2y: FNP.y
            ),
            SavedCurveNode(
                x: SNP.x, y: SNP.y,
                cp1x: SNP.x - px(frontNeckW * 0.3), cp1y: SNP.y,
                cp2x: SNP.x, cp2y: SNP.y
            )
        ]

        // 袖ぐりカーブ（SP→BLS）
        // 前身頃: SP(munehaaba側)→BLS(X=0側)なのでXは減少方向
        let ahHeight = BLS.y - SP.y   // 正（下向き）
        let ahWidth  = SP.x - BLS.x   // 正（SP側がX大きい）
        let ahCurveNodes = [
            SavedCurveNode(
                x: SP.x, y: SP.y,
                cp1x: SP.x, cp1y: SP.y,
                cp2x: SP.x - ahWidth * 0.15, cp2y: SP.y + ahHeight * 0.4
            ),
            SavedCurveNode(
                x: BLS.x, y: BLS.y,
                cp1x: BLS.x + ahWidth * 0.3, cp1y: BLS.y - ahHeight * 0.5,
                cp2x: BLS.x, cp2y: BLS.y
            )
        ]

        let savedCurves = [
            SavedCurve(nodes: neckCurveNodes),
            SavedCurve(nodes: ahCurveNodes)
        ]

        let points = [
            SavedPoint(id: UUID(), x: FCN.x, y: FCN.y, name: "FCN"),
            SavedPoint(id: UUID(), x: FNP.x, y: FNP.y, name: "FNP"),
            SavedPoint(id: UUID(), x: SNP.x, y: SNP.y, name: "SNP"),
            SavedPoint(id: UUID(), x: SP.x,  y: SP.y,  name: "SP"),
            SavedPoint(id: UUID(), x: BP.x,  y: BP.y,  name: "BP"),
            SavedPoint(id: UUID(), x: FW.x,  y: FW.y,  name: "WF"),
        ]

        return PatternData(points: points, lines: lines, curves: savedCurves, arcs: [], texts: [
            SavedText(x: px(mihaaba / 2), y: px(BL / 2), text: "前身頃", fontSize: 14)
        ], notches: [], seamOverrides: [], gradePoints: [])
    }

    // MARK: - 袖

    private static func generateSleeve(_ m: SloperMeasurements) -> PatternData {
        let B = m.bust
        let height = m.height

        // 袖丈（身長から算出）
        let sleeveLength = height * 0.31 + 5.0
        // 袖山高（AH寸法から算出: AH≒B/4+3程度）
        let AH = B / 4 + 3.0
        let sleeveHeight = AH * 0.68
        // 袖幅（前後袖幅）
        let sleeveWidth = AH / .pi * 2 + 2.0

        let origin = CGPoint.zero
        // 袖山頂点
        let top    = CGPoint(x: px(sleeveWidth / 2), y: 0)
        // 袖口
        let hemL   = CGPoint(x: 0,                  y: px(sleeveLength))
        let hemR   = CGPoint(x: px(sleeveWidth),    y: px(sleeveLength))
        // 袖幅線（BL相当）
        let capL   = CGPoint(x: 0,                  y: px(sleeveHeight))
        let capR   = CGPoint(x: px(sleeveWidth),    y: px(sleeveHeight))

        var lines: [SavedLine] = []
        // 袖口
        lines.append(SavedLine(x1: hemL.x, y1: hemL.y, x2: hemR.x, y2: hemR.y))
        // 袖下線
        lines.append(SavedLine(x1: capL.x, y1: capL.y, x2: hemL.x, y2: hemL.y))
        lines.append(SavedLine(x1: capR.x, y1: capR.y, x2: hemR.x, y2: hemR.y))

        // 袖山カーブ（capL → top → capR）
        let cpL1 = CGPoint(x: capL.x + px(sleeveWidth * 0.15), y: capL.y - px(sleeveHeight * 0.3))
        let cpL2 = CGPoint(x: top.x - px(sleeveWidth * 0.2),   y: top.y + px(sleeveHeight * 0.15))
        let cpR1 = CGPoint(x: top.x + px(sleeveWidth * 0.2),   y: top.y + px(sleeveHeight * 0.15))
        let cpR2 = CGPoint(x: capR.x - px(sleeveWidth * 0.15), y: capR.y - px(sleeveHeight * 0.3))

        let capCurveNodes = [
            SavedCurveNode(x: capL.x, y: capL.y, cp1x: capL.x, cp1y: capL.y, cp2x: cpL1.x, cp2y: cpL1.y),
            SavedCurveNode(x: top.x,  y: top.y,  cp1x: cpL2.x, cp1y: cpL2.y, cp2x: cpR1.x, cp2y: cpR1.y),
            SavedCurveNode(x: capR.x, y: capR.y, cp1x: cpR2.x, cp1y: cpR2.y, cp2x: capR.x, cp2y: capR.y)
        ]

        let points = [
            SavedPoint(id: UUID(), x: top.x,  y: top.y,  name: "袖山頂点"),
            SavedPoint(id: UUID(), x: capL.x, y: capL.y, name: "後AH"),
            SavedPoint(id: UUID(), x: capR.x, y: capR.y, name: "前AH"),
        ]

        return PatternData(points: points, lines: lines, curves: [SavedCurve(nodes: capCurveNodes)],
                          arcs: [], texts: [
            SavedText(x: px(sleeveWidth / 2), y: px(sleeveLength / 2), text: "袖", fontSize: 14)
        ], notches: [], seamOverrides: [], gradePoints: [])
    }

    // MARK: - 後ろスカート

    private static func generateSkirtBack(_ m: SloperMeasurements) -> PatternData {
        let H = m.hip
        let W = m.waist
        let skirtLength: CGFloat = 60.0     // スカート丈（標準値・後から変更可）
        let hipLine: CGFloat = 18.0         // ウエストからヒップラインまで

        let halfHip   = H / 4 + 1.0        // 後ろ半身ヒップ
        let halfWaist = W / 4 + 1.5        // 後ろ半身ウエスト
        let dartAmount = halfHip - halfWaist
        let dart1 = dartAmount * 0.6       // 第1ダーツ
        let dart2 = dartAmount * 0.4       // 第2ダーツ

        // ────────────────────────────────
        // ウエスト幅 = halfWaist（細い）
        // ヒップ幅  = halfHip（広い）
        // 脇線: WL_side(halfWaist) → HL_side(halfHip) にカーブで広がる
        // 裾線: HL_sideと同じX（スカートはヒップ幅で垂直に落ちる）
        // ────────────────────────────────

        let WL_center  = CGPoint(x: 0,             y: 0)
        let WL_side    = CGPoint(x: px(halfWaist),  y: 0)
        let HL_center  = CGPoint(x: 0,             y: px(hipLine))
        let HL_side    = CGPoint(x: px(halfHip),    y: px(hipLine))
        let HEM_center = CGPoint(x: 0,             y: px(skirtLength))
        let HEM_side   = CGPoint(x: px(halfHip),    y: px(skirtLength))

        // ダーツ位置
        // d2Rがhalf Waist内に収まるよう余裕を持たせる
        let d1X   = px(halfWaist * 0.30)
        let d1Top = CGPoint(x: d1X, y: px(hipLine * 0.75))
        let d1L   = CGPoint(x: d1X - px(dart1 / 2), y: 0)
        let d1R   = CGPoint(x: d1X + px(dart1 / 2), y: 0)

        // d2はd1Rより右、かつd2R < WL_sideに収まるよう計算
        let d2X   = min(px(halfWaist * 0.62), px(halfWaist) - px(dart2 / 2) - px(0.5))
        let d2Top = CGPoint(x: d2X, y: px(hipLine * 0.6))
        let d2L   = CGPoint(x: d2X - px(dart2 / 2), y: 0)
        let d2R   = CGPoint(x: d2X + px(dart2 / 2), y: 0)

        var lines: [SavedLine] = []
        // 後ろ中心線
        lines.append(SavedLine(x1: WL_center.x, y1: WL_center.y, x2: HEM_center.x, y2: HEM_center.y))
        // 裾線
        lines.append(SavedLine(x1: HEM_center.x, y1: HEM_center.y, x2: HEM_side.x, y2: HEM_side.y))
        // ヒップ〜裾の脇線（垂直）
        lines.append(SavedLine(x1: HL_side.x, y1: HL_side.y, x2: HEM_side.x, y2: HEM_side.y))
        // ウエストライン（ダーツで分割）
        lines.append(SavedLine(x1: WL_center.x, y1: WL_center.y, x2: d1L.x, y2: d1L.y))
        lines.append(SavedLine(x1: d1R.x, y1: d1R.y, x2: d2L.x, y2: d2L.y))
        lines.append(SavedLine(x1: d2R.x, y1: d2R.y, x2: WL_side.x, y2: WL_side.y))
        // ダーツ1
        lines.append(SavedLine(x1: d1L.x, y1: d1L.y, x2: d1Top.x, y2: d1Top.y))
        lines.append(SavedLine(x1: d1Top.x, y1: d1Top.y, x2: d1R.x, y2: d1R.y))
        // ダーツ2
        lines.append(SavedLine(x1: d2L.x, y1: d2L.y, x2: d2Top.x, y2: d2Top.y))
        lines.append(SavedLine(x1: d2Top.x, y1: d2Top.y, x2: d2R.x, y2: d2R.y))

        // 脇線カーブ（WL_side→HL_side）
        // WL_sideからほぼ垂直に下り、ヒップ付近で外に広がる
        let sideDx = HL_side.x - WL_side.x
        let sideDy = HL_side.y - WL_side.y
        let sideCP1 = CGPoint(x: WL_side.x + sideDx * 0.1, y: WL_side.y + sideDy * 0.4)
        let sideCP2 = CGPoint(x: HL_side.x - sideDx * 0.1, y: HL_side.y - sideDy * 0.3)
        let sideCurveNodes = [
            SavedCurveNode(x: WL_side.x, y: WL_side.y,
                           cp1x: WL_side.x, cp1y: WL_side.y,
                           cp2x: sideCP1.x, cp2y: sideCP1.y),
            SavedCurveNode(x: HL_side.x, y: HL_side.y,
                           cp1x: sideCP2.x, cp1y: sideCP2.y,
                           cp2x: HL_side.x, cp2y: HL_side.y)
        ]

        let points = [
            SavedPoint(id: UUID(), x: WL_center.x, y: WL_center.y, name: "WCB"),
            SavedPoint(id: UUID(), x: WL_side.x,   y: WL_side.y,   name: "WS"),
            SavedPoint(id: UUID(), x: HL_center.x, y: HL_center.y, name: "HCB"),
            SavedPoint(id: UUID(), x: HL_side.x,   y: HL_side.y,   name: "HS"),
        ]

        return PatternData(points: points, lines: lines,
                          curves: [SavedCurve(nodes: sideCurveNodes)],
                          arcs: [], texts: [
            SavedText(x: px(halfHip / 2), y: px(skirtLength / 2), text: "後ろスカート", fontSize: 14)
        ], notches: [], seamOverrides: [], gradePoints: [])
    }

    // MARK: - 前スカート

    private static func generateSkirtFront(_ m: SloperMeasurements) -> PatternData {
        let H = m.hip
        let W = m.waist
        let skirtLength: CGFloat = 60.0
        let hipLine: CGFloat = 18.0

        let halfHip   = H / 4 - 1.0
        let halfWaist = W / 4 - 1.5
        let dartAmount = halfHip - halfWaist
        let dart1 = dartAmount * 0.7

        let WL_center  = CGPoint(x: 0,            y: 0)
        let WL_side    = CGPoint(x: px(halfWaist), y: 0)
        let HL_side    = CGPoint(x: px(halfHip),   y: px(hipLine))
        let HEM_center = CGPoint(x: 0,            y: px(skirtLength))
        let HEM_side   = CGPoint(x: px(halfHip),   y: px(skirtLength))

        // ダーツ（前は1本・ウエスト幅内に収める）
        let dX   = px(halfWaist * 0.45)
        let dTop = CGPoint(x: dX, y: px(hipLine * 0.65))
        let dL   = CGPoint(x: dX - px(dart1 / 2), y: 0)
        let dR   = CGPoint(x: dX + px(dart1 / 2), y: 0)

        var lines: [SavedLine] = []
        // 前中心線
        lines.append(SavedLine(x1: WL_center.x, y1: WL_center.y, x2: HEM_center.x, y2: HEM_center.y))
        // 裾線
        lines.append(SavedLine(x1: HEM_center.x, y1: HEM_center.y, x2: HEM_side.x, y2: HEM_side.y))
        // ヒップ〜裾の脇線（垂直）
        lines.append(SavedLine(x1: HL_side.x, y1: HL_side.y, x2: HEM_side.x, y2: HEM_side.y))
        // ウエストライン（ダーツで分割）
        lines.append(SavedLine(x1: WL_center.x, y1: WL_center.y, x2: dL.x, y2: dL.y))
        lines.append(SavedLine(x1: dR.x, y1: dR.y, x2: WL_side.x, y2: WL_side.y))
        // ダーツ
        lines.append(SavedLine(x1: dL.x, y1: dL.y, x2: dTop.x, y2: dTop.y))
        lines.append(SavedLine(x1: dTop.x, y1: dTop.y, x2: dR.x, y2: dR.y))

        // 脇線カーブ（WL_side→HL_side）
        let sideDx = HL_side.x - WL_side.x
        let sideDy = HL_side.y - WL_side.y
        let sideCP1 = CGPoint(x: WL_side.x + sideDx * 0.1, y: WL_side.y + sideDy * 0.4)
        let sideCP2 = CGPoint(x: HL_side.x - sideDx * 0.1, y: HL_side.y - sideDy * 0.3)
        let sideCurveNodes = [
            SavedCurveNode(x: WL_side.x, y: WL_side.y,
                           cp1x: WL_side.x, cp1y: WL_side.y,
                           cp2x: sideCP1.x, cp2y: sideCP1.y),
            SavedCurveNode(x: HL_side.x, y: HL_side.y,
                           cp1x: sideCP2.x, cp1y: sideCP2.y,
                           cp2x: HL_side.x, cp2y: HL_side.y)
        ]

        let points = [
            SavedPoint(id: UUID(), x: WL_center.x, y: WL_center.y, name: "WCF"),
            SavedPoint(id: UUID(), x: WL_side.x,   y: WL_side.y,   name: "WS"),
        ]

        return PatternData(points: points, lines: lines,
                          curves: [SavedCurve(nodes: sideCurveNodes)],
                          arcs: [], texts: [
            SavedText(x: px(halfHip / 2), y: px(skirtLength / 2), text: "前スカート", fontSize: 14)
        ], notches: [], seamOverrides: [], gradePoints: [])
    }
}

// MARK: - 対象種別

enum SloperGender {
    case female
    case male
    case child
}

enum SloperChildAge: String, CaseIterable {
    case infant   = "乳幼児（0〜3歳）"
    case toddler  = "幼児（3〜6歳）"
    case primary  = "小学生（6〜12歳）"
    case junior   = "中学生（12〜15歳）"
}

// MARK: - 男性用・子供用入力寸法

struct SloperMeasurementsMale {
    var chest: CGFloat       // 胸囲 (cm)
    var waist: CGFloat       // ウエスト (cm)
    var hip: CGFloat         // ヒップ (cm)
    var backLength: CGFloat  // 背丈 (cm)
    var height: CGFloat      // 身長 (cm)

    static func estimatedBackLength(height: CGFloat) -> CGFloat {
        return height * 0.245 + 1.5
    }
}

struct SloperMeasurementsChild {
    var chest: CGFloat       // 胸囲 (cm)
    var waist: CGFloat       // ウエスト (cm)
    var hip: CGFloat         // ヒップ (cm)
    var height: CGFloat      // 身長 (cm)
    var age: SloperChildAge

    var backLength: CGFloat {
        // 身長から背丈を推定
        switch age {
        case .infant:  return height * 0.22
        case .toddler: return height * 0.23
        case .primary: return height * 0.235
        case .junior:  return height * 0.238
        }
    }
}

// MARK: - 男性用原型生成

class SloperGeneratorMale {
    private static let pxPerCm: CGFloat = 37.8
    private static func px(_ cm: CGFloat) -> CGFloat { cm * pxPerCm }

    static func generate(from m: SloperMeasurementsMale) -> SloperResult {
        return SloperResult(
            bodiceBack:  generateBodiceBack(m),
            bodiceFront: generateBodiceFront(m),
            sleeve:      generateSleeve(m),
            skirtBack:   emptyPattern(),  // 男性用はパンツが主なのでスカートなし
            skirtFront:  emptyPattern()
        )
    }

    private static func emptyPattern() -> PatternData {
        PatternData(points: [], lines: [], curves: [], arcs: [], texts: [],
                    notches: [], seamOverrides: [], gradePoints: [])
    }

    // MARK: 後ろ身頃（男性）
    private static func generateBodiceBack(_ m: SloperMeasurementsMale) -> PatternData {
        let C = m.chest   // 胸囲
        let W = m.waist
        let BL = m.backLength

        // 男性用文化式近似値
        let mihaaba   = C / 2 + 8.0      // 身幅（半身）
        let sehaaba   = C / 8 + 8.5      // 背幅（男性は広め）
        let aToBL     = C / 10 + 15.0    // 首付け根〜バストライン
        let backNeckW = C / 24 + 3.8     // 後ろ襟ぐり幅
        let backNeckD = backNeckW / 4.0  // 後ろ襟ぐり深さ（男性は浅め）
        let shoulderSlant: CGFloat = 1.5  // 肩傾斜（男性は水平に近い）
        let shoulderLen = C / 8 + 5.5 + 1.5  // 肩線長さ

        let totalDartBack = (mihaaba - (W / 2 + 2.0)) * 0.6

        let offsetY = px(backNeckD)

        let BNP = CGPoint(x: 0,             y: offsetY)
        let WCB = CGPoint(x: 0,             y: offsetY + px(BL))
        let BLS = CGPoint(x: px(mihaaba),    y: offsetY + px(aToBL))
        let WLS = CGPoint(x: px(mihaaba),    y: offsetY + px(BL))
        let SNP = CGPoint(x: px(backNeckW),  y: 0)

        let slopeDx = sehaaba - backNeckW
        let slopeDy = shoulderSlant
        let slopeLen = sqrt(slopeDx * slopeDx + slopeDy * slopeDy)
        let SP = CGPoint(
            x: SNP.x + px(slopeDx / slopeLen * shoulderLen),
            y: SNP.y + px(slopeDy / slopeLen * shoulderLen)
        )

        let dartCX  = px(sehaaba * 0.55)
        let dartTip = CGPoint(x: dartCX, y: offsetY + px(aToBL) - px(3.0))
        let dartL   = CGPoint(x: dartCX - px(totalDartBack / 2), y: offsetY + px(BL))
        let dartR   = CGPoint(x: dartCX + px(totalDartBack / 2), y: offsetY + px(BL))

        var lines: [SavedLine] = []
        lines.append(SavedLine(x1: BNP.x, y1: BNP.y, x2: WCB.x, y2: WCB.y))
        lines.append(SavedLine(x1: WCB.x, y1: WCB.y, x2: dartL.x, y2: dartL.y))
        lines.append(SavedLine(x1: dartR.x, y1: dartR.y, x2: WLS.x, y2: WLS.y))
        lines.append(SavedLine(x1: dartL.x, y1: dartL.y, x2: dartTip.x, y2: dartTip.y))
        lines.append(SavedLine(x1: dartTip.x, y1: dartTip.y, x2: dartR.x, y2: dartR.y))
        lines.append(SavedLine(x1: WLS.x, y1: WLS.y, x2: BLS.x, y2: BLS.y))
        lines.append(SavedLine(x1: SNP.x, y1: SNP.y, x2: SP.x, y2: SP.y))

        let neckNodes = [
            SavedCurveNode(x: BNP.x, y: BNP.y,
                           cp1x: BNP.x, cp1y: BNP.y,
                           cp2x: BNP.x + px(backNeckW * 0.5), cp2y: BNP.y),
            SavedCurveNode(x: SNP.x, y: SNP.y,
                           cp1x: SNP.x, cp1y: SNP.y + px(backNeckD * 0.5),
                           cp2x: SNP.x, cp2y: SNP.y)
        ]

        let ahH = BLS.y - SP.y
        let ahW = BLS.x - SP.x
        let ahNodes = [
            SavedCurveNode(x: SP.x, y: SP.y,
                           cp1x: SP.x, cp1y: SP.y,
                           cp2x: SP.x + ahW * 0.3, cp2y: SP.y + ahH * 0.6),
            SavedCurveNode(x: BLS.x, y: BLS.y,
                           cp1x: BLS.x - ahW * 0.15, cp1y: BLS.y - ahH * 0.4,
                           cp2x: BLS.x, cp2y: BLS.y)
        ]

        return PatternData(
            points: [
                SavedPoint(id: UUID(), x: BNP.x, y: BNP.y, name: "BNP"),
                SavedPoint(id: UUID(), x: SNP.x, y: SNP.y, name: "SNP"),
                SavedPoint(id: UUID(), x: SP.x,  y: SP.y,  name: "SP"),
                SavedPoint(id: UUID(), x: WCB.x, y: WCB.y, name: "WCB"),
                SavedPoint(id: UUID(), x: WLS.x, y: WLS.y, name: "WS"),
            ],
            lines: lines,
            curves: [SavedCurve(nodes: neckNodes), SavedCurve(nodes: ahNodes)],
            arcs: [], texts: [
                SavedText(x: px(mihaaba / 2), y: offsetY + px(BL / 2), text: "後ろ身頃（男）", fontSize: 14)
            ], notches: [], seamOverrides: [], gradePoints: [])
    }

    // MARK: 前身頃（男性）
    private static func generateBodiceFront(_ m: SloperMeasurementsMale) -> PatternData {
        let C = m.chest
        let W = m.waist
        let BL = m.backLength

        let mihaaba   = C / 2 + 8.0
        let munehaaba = C / 8 + 7.0      // 胸幅（男性は広め）
        let aToBL     = C / 10 + 15.0
        let frontNeckW = C / 24 + 3.8
        let frontNeckD = frontNeckW + 0.5  // 男性は前襟ぐりが浅め
        let shoulderSlant: CGFloat = 2.0
        let shoulderLen = C / 8 + 5.5
        let frontWaistDart = (mihaaba - (W / 2 + 2.0)) * 0.4

        let FCN  = CGPoint(x: 0, y: 0)
        let FW   = CGPoint(x: 0, y: px(BL))
        let BLC  = CGPoint(x: 0,             y: px(aToBL))
        let BLS  = CGPoint(x: px(mihaaba),    y: px(aToBL))
        let WLS  = CGPoint(x: px(mihaaba),    y: px(BL))
        let FNP  = CGPoint(x: 0,             y: px(frontNeckD))
        let SNP  = CGPoint(x: px(frontNeckW), y: px(frontNeckD * 0.1))

        let slopeDx = munehaaba - frontNeckW
        let slopeDy = shoulderSlant
        let slopeLen = sqrt(slopeDx * slopeDx + slopeDy * slopeDy)
        let SP = CGPoint(
            x: SNP.x + px(slopeDx / slopeLen * shoulderLen),
            y: SNP.y + px(slopeDy / slopeLen * shoulderLen)
        )

        let dartCX   = px(C / 8 + 2.5)
        let dartTip3 = CGPoint(x: dartCX, y: px(aToBL) - px(3.0))
        let dartL    = CGPoint(x: dartCX - px(frontWaistDart / 2), y: px(BL))
        let dartR    = CGPoint(x: dartCX + px(frontWaistDart / 2), y: px(BL))

        var lines: [SavedLine] = []
        lines.append(SavedLine(x1: FCN.x, y1: FCN.y, x2: FW.x, y2: FW.y))
        lines.append(SavedLine(x1: FW.x, y1: FW.y, x2: dartL.x, y2: dartL.y))
        lines.append(SavedLine(x1: dartR.x, y1: dartR.y, x2: WLS.x, y2: WLS.y))
        lines.append(SavedLine(x1: dartL.x, y1: dartL.y, x2: dartTip3.x, y2: dartTip3.y))
        lines.append(SavedLine(x1: dartTip3.x, y1: dartTip3.y, x2: dartR.x, y2: dartR.y))
        lines.append(SavedLine(x1: WLS.x, y1: WLS.y, x2: BLS.x, y2: BLS.y))
        lines.append(SavedLine(x1: SNP.x, y1: SNP.y, x2: SP.x, y2: SP.y))

        let neckNodes = [
            SavedCurveNode(x: FCN.x, y: FCN.y,
                           cp1x: FCN.x, cp1y: FCN.y,
                           cp2x: FCN.x, cp2y: FCN.y + px(frontNeckD * 0.5)),
            SavedCurveNode(x: FNP.x, y: FNP.y,
                           cp1x: FNP.x, cp1y: FNP.y + px(0.5),
                           cp2x: FNP.x + px(frontNeckW * 0.5), cp2y: FNP.y),
            SavedCurveNode(x: SNP.x, y: SNP.y,
                           cp1x: SNP.x - px(frontNeckW * 0.3), cp1y: SNP.y,
                           cp2x: SNP.x, cp2y: SNP.y)
        ]

        let ahH = BLS.y - SP.y
        let ahW = SP.x - BLS.x
        let ahNodes = [
            SavedCurveNode(x: SP.x, y: SP.y,
                           cp1x: SP.x, cp1y: SP.y,
                           cp2x: SP.x - ahW * 0.15, cp2y: SP.y + ahH * 0.4),
            SavedCurveNode(x: BLS.x, y: BLS.y,
                           cp1x: BLS.x + ahW * 0.3, cp1y: BLS.y - ahH * 0.5,
                           cp2x: BLS.x, cp2y: BLS.y)
        ]

        return PatternData(
            points: [
                SavedPoint(id: UUID(), x: FCN.x, y: FCN.y, name: "FCN"),
                SavedPoint(id: UUID(), x: FNP.x, y: FNP.y, name: "FNP"),
                SavedPoint(id: UUID(), x: SNP.x, y: SNP.y, name: "SNP"),
                SavedPoint(id: UUID(), x: SP.x,  y: SP.y,  name: "SP"),
                SavedPoint(id: UUID(), x: FW.x,  y: FW.y,  name: "WF"),
            ],
            lines: lines,
            curves: [SavedCurve(nodes: neckNodes), SavedCurve(nodes: ahNodes)],
            arcs: [], texts: [
                SavedText(x: px(munehaaba / 2), y: px(BL / 2), text: "前身頃（男）", fontSize: 14)
            ], notches: [], seamOverrides: [], gradePoints: [])
    }

    // MARK: 袖（男性）
    private static func generateSleeve(_ m: SloperMeasurementsMale) -> PatternData {
        let C = m.height
        let sleeveLength = m.height * 0.325 + 3.0  // 男性は腕が長め
        let AH = m.chest / 4 + 4.0
        let sleeveHeight = AH * 0.70
        let sleeveWidth  = AH / .pi * 2 + 3.0       // 男性は袖幅広め

        let top  = CGPoint(x: px(sleeveWidth / 2), y: 0)
        let capL = CGPoint(x: 0,                   y: px(sleeveHeight))
        let capR = CGPoint(x: px(sleeveWidth),     y: px(sleeveHeight))
        let hemL = CGPoint(x: 0,                   y: px(sleeveLength))
        let hemR = CGPoint(x: px(sleeveWidth),     y: px(sleeveLength))

        var lines: [SavedLine] = []
        lines.append(SavedLine(x1: hemL.x, y1: hemL.y, x2: hemR.x, y2: hemR.y))
        lines.append(SavedLine(x1: capL.x, y1: capL.y, x2: hemL.x, y2: hemL.y))
        lines.append(SavedLine(x1: capR.x, y1: capR.y, x2: hemR.x, y2: hemR.y))

        let cpL1 = CGPoint(x: capL.x + px(sleeveWidth * 0.15), y: capL.y - px(sleeveHeight * 0.3))
        let cpL2 = CGPoint(x: top.x - px(sleeveWidth * 0.2),   y: top.y + px(sleeveHeight * 0.15))
        let cpR1 = CGPoint(x: top.x + px(sleeveWidth * 0.2),   y: top.y + px(sleeveHeight * 0.15))
        let cpR2 = CGPoint(x: capR.x - px(sleeveWidth * 0.15), y: capR.y - px(sleeveHeight * 0.3))

        let capNodes = [
            SavedCurveNode(x: capL.x, y: capL.y, cp1x: capL.x, cp1y: capL.y, cp2x: cpL1.x, cp2y: cpL1.y),
            SavedCurveNode(x: top.x,  y: top.y,  cp1x: cpL2.x, cp1y: cpL2.y, cp2x: cpR1.x, cp2y: cpR1.y),
            SavedCurveNode(x: capR.x, y: capR.y, cp1x: cpR2.x, cp1y: cpR2.y, cp2x: capR.x, cp2y: capR.y)
        ]

        _ = C
        return PatternData(
            points: [
                SavedPoint(id: UUID(), x: top.x,  y: top.y,  name: "袖山頂点"),
                SavedPoint(id: UUID(), x: capL.x, y: capL.y, name: "後AH"),
                SavedPoint(id: UUID(), x: capR.x, y: capR.y, name: "前AH"),
            ],
            lines: lines,
            curves: [SavedCurve(nodes: capNodes)],
            arcs: [], texts: [
                SavedText(x: px(sleeveWidth / 2), y: px(sleeveLength / 2), text: "袖（男）", fontSize: 14)
            ], notches: [], seamOverrides: [], gradePoints: [])
    }
}

// MARK: - 子供用原型生成

class SloperGeneratorChild {
    private static let pxPerCm: CGFloat = 37.8
    private static func px(_ cm: CGFloat) -> CGFloat { cm * pxPerCm }

    static func generate(from m: SloperMeasurementsChild) -> SloperResult {
        return SloperResult(
            bodiceBack:  generateBodiceBack(m),
            bodiceFront: generateBodiceFront(m),
            sleeve:      generateSleeve(m),
            skirtBack:   generateSkirtBack(m),
            skirtFront:  generateSkirtFront(m)
        )
    }

    // MARK: 後ろ身頃（子供）
    private static func generateBodiceBack(_ m: SloperMeasurementsChild) -> PatternData {
        let C = m.chest
        let W = m.waist
        let BL = m.backLength

        // 子供用文化式近似値（体型差が少ないためシンプル）
        let mihaaba   = C / 2 + 4.0
        let sehaaba   = C / 8 + 4.5
        let aToBL     = C / 12 + 10.0
        let backNeckW = C / 24 + 2.5
        let backNeckD = backNeckW / 3.0
        let shoulderSlant: CGFloat = 1.5
        let shoulderLen = C / 8 + 3.5 + 1.0

        // 子供はダーツが少ない
        let totalDart = max(0, (mihaaba - (W / 2 + 1.0)) * 0.5)

        let offsetY = px(backNeckD)
        let BNP = CGPoint(x: 0,            y: offsetY)
        let WCB = CGPoint(x: 0,            y: offsetY + px(BL))
        let BLS = CGPoint(x: px(mihaaba),   y: offsetY + px(aToBL))
        let WLS = CGPoint(x: px(mihaaba),   y: offsetY + px(BL))
        let SNP = CGPoint(x: px(backNeckW), y: 0)

        let slopeDx = sehaaba - backNeckW
        let slopeDy = shoulderSlant
        let slopeLen = sqrt(slopeDx * slopeDx + slopeDy * slopeDy)
        let SP = CGPoint(
            x: SNP.x + px(slopeDx / slopeLen * shoulderLen),
            y: SNP.y + px(slopeDy / slopeLen * shoulderLen)
        )

        var lines: [SavedLine] = []
        lines.append(SavedLine(x1: BNP.x, y1: BNP.y, x2: WCB.x, y2: WCB.y))
        lines.append(SavedLine(x1: SNP.x, y1: SNP.y, x2: SP.x,  y2: SP.y))

        if totalDart > 0.5 {
            let dartCX  = px(sehaaba * 0.55)
            let dartTip = CGPoint(x: dartCX, y: offsetY + px(aToBL) - px(2.0))
            let dartL   = CGPoint(x: dartCX - px(totalDart / 2), y: offsetY + px(BL))
            let dartR   = CGPoint(x: dartCX + px(totalDart / 2), y: offsetY + px(BL))
            lines.append(SavedLine(x1: WCB.x, y1: WCB.y, x2: dartL.x, y2: dartL.y))
            lines.append(SavedLine(x1: dartR.x, y1: dartR.y, x2: WLS.x, y2: WLS.y))
            lines.append(SavedLine(x1: dartL.x, y1: dartL.y, x2: dartTip.x, y2: dartTip.y))
            lines.append(SavedLine(x1: dartTip.x, y1: dartTip.y, x2: dartR.x, y2: dartR.y))
        } else {
            lines.append(SavedLine(x1: WCB.x, y1: WCB.y, x2: WLS.x, y2: WLS.y))
        }
        lines.append(SavedLine(x1: WLS.x, y1: WLS.y, x2: BLS.x, y2: BLS.y))

        let neckNodes = [
            SavedCurveNode(x: BNP.x, y: BNP.y,
                           cp1x: BNP.x, cp1y: BNP.y,
                           cp2x: BNP.x + px(backNeckW * 0.5), cp2y: BNP.y),
            SavedCurveNode(x: SNP.x, y: SNP.y,
                           cp1x: SNP.x, cp1y: SNP.y + px(backNeckD * 0.5),
                           cp2x: SNP.x, cp2y: SNP.y)
        ]
        let ahH = BLS.y - SP.y
        let ahW = BLS.x - SP.x
        let ahNodes = [
            SavedCurveNode(x: SP.x, y: SP.y,
                           cp1x: SP.x, cp1y: SP.y,
                           cp2x: SP.x + ahW * 0.3, cp2y: SP.y + ahH * 0.6),
            SavedCurveNode(x: BLS.x, y: BLS.y,
                           cp1x: BLS.x - ahW * 0.15, cp1y: BLS.y - ahH * 0.4,
                           cp2x: BLS.x, cp2y: BLS.y)
        ]

        return PatternData(
            points: [
                SavedPoint(id: UUID(), x: BNP.x, y: BNP.y, name: "BNP"),
                SavedPoint(id: UUID(), x: SNP.x, y: SNP.y, name: "SNP"),
                SavedPoint(id: UUID(), x: SP.x,  y: SP.y,  name: "SP"),
            ],
            lines: lines,
            curves: [SavedCurve(nodes: neckNodes), SavedCurve(nodes: ahNodes)],
            arcs: [], texts: [
                SavedText(x: px(mihaaba / 2), y: offsetY + px(BL / 2), text: "後ろ身頃（子）", fontSize: 14)
            ], notches: [], seamOverrides: [], gradePoints: [])
    }

    // MARK: 前身頃（子供）
    private static func generateBodiceFront(_ m: SloperMeasurementsChild) -> PatternData {
        let C = m.chest
        let W = m.waist
        let BL = m.backLength

        let mihaaba    = C / 2 + 4.0
        let munehaaba  = C / 8 + 4.0
        let aToBL      = C / 12 + 10.0
        let frontNeckW = C / 24 + 2.5
        let frontNeckD = frontNeckW + 0.5
        let shoulderSlant: CGFloat = 2.0
        let shoulderLen = C / 8 + 3.5
        let frontWaistDart = max(0, (mihaaba - (W / 2 + 1.0)) * 0.4)

        let FCN  = CGPoint(x: 0, y: 0)
        let FW   = CGPoint(x: 0, y: px(BL))
        let BLS  = CGPoint(x: px(mihaaba),    y: px(aToBL))
        let WLS  = CGPoint(x: px(mihaaba),    y: px(BL))
        let FNP  = CGPoint(x: 0,             y: px(frontNeckD))
        let SNP  = CGPoint(x: px(frontNeckW), y: px(frontNeckD * 0.1))

        let slopeDx = munehaaba - frontNeckW
        let slopeDy = shoulderSlant
        let slopeLen = sqrt(slopeDx * slopeDx + slopeDy * slopeDy)
        let SP = CGPoint(
            x: SNP.x + px(slopeDx / slopeLen * shoulderLen),
            y: SNP.y + px(slopeDy / slopeLen * shoulderLen)
        )

        var lines: [SavedLine] = []
        lines.append(SavedLine(x1: FCN.x, y1: FCN.y, x2: FW.x, y2: FW.y))
        lines.append(SavedLine(x1: SNP.x, y1: SNP.y, x2: SP.x, y2: SP.y))

        if frontWaistDart > 0.5 {
            let dartCX   = px(C / 8 + 2.0)
            let dartTip3 = CGPoint(x: dartCX, y: px(aToBL) - px(2.0))
            let dartL    = CGPoint(x: dartCX - px(frontWaistDart / 2), y: px(BL))
            let dartR    = CGPoint(x: dartCX + px(frontWaistDart / 2), y: px(BL))
            lines.append(SavedLine(x1: FW.x, y1: FW.y, x2: dartL.x, y2: dartL.y))
            lines.append(SavedLine(x1: dartR.x, y1: dartR.y, x2: WLS.x, y2: WLS.y))
            lines.append(SavedLine(x1: dartL.x, y1: dartL.y, x2: dartTip3.x, y2: dartTip3.y))
            lines.append(SavedLine(x1: dartTip3.x, y1: dartTip3.y, x2: dartR.x, y2: dartR.y))
        } else {
            lines.append(SavedLine(x1: FW.x, y1: FW.y, x2: WLS.x, y2: WLS.y))
        }
        lines.append(SavedLine(x1: WLS.x, y1: WLS.y, x2: BLS.x, y2: BLS.y))

        let neckNodes = [
            SavedCurveNode(x: FCN.x, y: FCN.y,
                           cp1x: FCN.x, cp1y: FCN.y,
                           cp2x: FCN.x, cp2y: FCN.y + px(frontNeckD * 0.5)),
            SavedCurveNode(x: FNP.x, y: FNP.y,
                           cp1x: FNP.x, cp1y: FNP.y + px(0.5),
                           cp2x: FNP.x + px(frontNeckW * 0.5), cp2y: FNP.y),
            SavedCurveNode(x: SNP.x, y: SNP.y,
                           cp1x: SNP.x - px(frontNeckW * 0.3), cp1y: SNP.y,
                           cp2x: SNP.x, cp2y: SNP.y)
        ]
        let ahH = BLS.y - SP.y
        let ahW = SP.x - BLS.x
        let ahNodes = [
            SavedCurveNode(x: SP.x, y: SP.y,
                           cp1x: SP.x, cp1y: SP.y,
                           cp2x: SP.x - ahW * 0.15, cp2y: SP.y + ahH * 0.4),
            SavedCurveNode(x: BLS.x, y: BLS.y,
                           cp1x: BLS.x + ahW * 0.3, cp1y: BLS.y - ahH * 0.5,
                           cp2x: BLS.x, cp2y: BLS.y)
        ]

        return PatternData(
            points: [
                SavedPoint(id: UUID(), x: FCN.x, y: FCN.y, name: "FCN"),
                SavedPoint(id: UUID(), x: FNP.x, y: FNP.y, name: "FNP"),
                SavedPoint(id: UUID(), x: SNP.x, y: SNP.y, name: "SNP"),
                SavedPoint(id: UUID(), x: SP.x,  y: SP.y,  name: "SP"),
            ],
            lines: lines,
            curves: [SavedCurve(nodes: neckNodes), SavedCurve(nodes: ahNodes)],
            arcs: [], texts: [
                SavedText(x: px(munehaaba / 2), y: px(BL / 2), text: "前身頃（子）", fontSize: 14)
            ], notches: [], seamOverrides: [], gradePoints: [])
    }

    // MARK: 袖（子供）
    private static func generateSleeve(_ m: SloperMeasurementsChild) -> PatternData {
        let sleeveLength: CGFloat
        switch m.age {
        case .infant:  sleeveLength = m.height * 0.28
        case .toddler: sleeveLength = m.height * 0.29
        case .primary: sleeveLength = m.height * 0.30
        case .junior:  sleeveLength = m.height * 0.31
        }
        let AH = m.chest / 4 + 2.0
        let sleeveHeight = AH * 0.65
        let sleeveWidth  = AH / .pi * 2 + 1.5

        let top  = CGPoint(x: px(sleeveWidth / 2), y: 0)
        let capL = CGPoint(x: 0,                   y: px(sleeveHeight))
        let capR = CGPoint(x: px(sleeveWidth),     y: px(sleeveHeight))
        let hemL = CGPoint(x: 0,                   y: px(sleeveLength))
        let hemR = CGPoint(x: px(sleeveWidth),     y: px(sleeveLength))

        var lines: [SavedLine] = []
        lines.append(SavedLine(x1: hemL.x, y1: hemL.y, x2: hemR.x, y2: hemR.y))
        lines.append(SavedLine(x1: capL.x, y1: capL.y, x2: hemL.x, y2: hemL.y))
        lines.append(SavedLine(x1: capR.x, y1: capR.y, x2: hemR.x, y2: hemR.y))

        let cpL1 = CGPoint(x: capL.x + px(sleeveWidth * 0.15), y: capL.y - px(sleeveHeight * 0.3))
        let cpL2 = CGPoint(x: top.x - px(sleeveWidth * 0.2),   y: top.y + px(sleeveHeight * 0.15))
        let cpR1 = CGPoint(x: top.x + px(sleeveWidth * 0.2),   y: top.y + px(sleeveHeight * 0.15))
        let cpR2 = CGPoint(x: capR.x - px(sleeveWidth * 0.15), y: capR.y - px(sleeveHeight * 0.3))

        let capNodes = [
            SavedCurveNode(x: capL.x, y: capL.y, cp1x: capL.x, cp1y: capL.y, cp2x: cpL1.x, cp2y: cpL1.y),
            SavedCurveNode(x: top.x,  y: top.y,  cp1x: cpL2.x, cp1y: cpL2.y, cp2x: cpR1.x, cp2y: cpR1.y),
            SavedCurveNode(x: capR.x, y: capR.y, cp1x: cpR2.x, cp1y: cpR2.y, cp2x: capR.x, cp2y: capR.y)
        ]

        return PatternData(
            points: [
                SavedPoint(id: UUID(), x: top.x,  y: top.y,  name: "袖山頂点"),
                SavedPoint(id: UUID(), x: capL.x, y: capL.y, name: "後AH"),
                SavedPoint(id: UUID(), x: capR.x, y: capR.y, name: "前AH"),
            ],
            lines: lines,
            curves: [SavedCurve(nodes: capNodes)],
            arcs: [], texts: [
                SavedText(x: px(sleeveWidth / 2), y: px(sleeveLength / 2), text: "袖（子）", fontSize: 14)
            ], notches: [], seamOverrides: [], gradePoints: [])
    }

    // MARK: スカート（子供・前後共通ベース）
    private static func generateSkirtBack(_ m: SloperMeasurementsChild) -> PatternData {
        let H = m.hip
        let W = m.waist
        let skirtLength = m.height * 0.30
        let hipLine: CGFloat = 14.0

        let halfHip   = H / 4 + 1.0
        let halfWaist = W / 4 + 1.5
        let dartAmount = max(0, halfHip - halfWaist)
        let dart1 = dartAmount * 0.6
        let dart2 = dartAmount * 0.4

        let WL_center  = CGPoint(x: 0,            y: 0)
        let WL_side    = CGPoint(x: px(halfWaist), y: 0)
        let HL_center  = CGPoint(x: 0,            y: px(hipLine))
        let HL_side    = CGPoint(x: px(halfHip),   y: px(hipLine))
        let HEM_center = CGPoint(x: 0,            y: px(skirtLength))
        let HEM_side   = CGPoint(x: px(halfHip),   y: px(skirtLength))

        var lines: [SavedLine] = []
        lines.append(SavedLine(x1: WL_center.x, y1: WL_center.y, x2: HEM_center.x, y2: HEM_center.y))
        lines.append(SavedLine(x1: HEM_center.x, y1: HEM_center.y, x2: HEM_side.x, y2: HEM_side.y))
        lines.append(SavedLine(x1: HL_side.x, y1: HL_side.y, x2: HEM_side.x, y2: HEM_side.y))

        if dart1 > 0.3 {
            let d1X   = px(halfWaist * 0.30)
            let d1Top = CGPoint(x: d1X, y: px(hipLine * 0.7))
            let d1L   = CGPoint(x: d1X - px(dart1 / 2), y: 0)
            let d1R   = CGPoint(x: d1X + px(dart1 / 2), y: 0)
            let d2X   = min(px(halfWaist * 0.62), px(halfWaist) - px(dart2 / 2) - px(0.5))
            let d2Top = CGPoint(x: d2X, y: px(hipLine * 0.55))
            let d2L   = CGPoint(x: d2X - px(dart2 / 2), y: 0)
            let d2R   = CGPoint(x: d2X + px(dart2 / 2), y: 0)
            lines.append(SavedLine(x1: WL_center.x, y1: WL_center.y, x2: d1L.x, y2: d1L.y))
            lines.append(SavedLine(x1: d1R.x, y1: d1R.y, x2: d2L.x, y2: d2L.y))
            lines.append(SavedLine(x1: d2R.x, y1: d2R.y, x2: WL_side.x, y2: WL_side.y))
            lines.append(SavedLine(x1: d1L.x, y1: d1L.y, x2: d1Top.x, y2: d1Top.y))
            lines.append(SavedLine(x1: d1Top.x, y1: d1Top.y, x2: d1R.x, y2: d1R.y))
            lines.append(SavedLine(x1: d2L.x, y1: d2L.y, x2: d2Top.x, y2: d2Top.y))
            lines.append(SavedLine(x1: d2Top.x, y1: d2Top.y, x2: d2R.x, y2: d2R.y))
        } else {
            lines.append(SavedLine(x1: WL_center.x, y1: WL_center.y, x2: WL_side.x, y2: WL_side.y))
        }

        let sideDx = HL_side.x - WL_side.x
        let sideDy = HL_side.y - WL_side.y
        let sideCurveNodes = [
            SavedCurveNode(x: WL_side.x, y: WL_side.y,
                           cp1x: WL_side.x, cp1y: WL_side.y,
                           cp2x: WL_side.x + sideDx * 0.1, cp2y: WL_side.y + sideDy * 0.4),
            SavedCurveNode(x: HL_side.x, y: HL_side.y,
                           cp1x: HL_side.x - sideDx * 0.1, cp1y: HL_side.y - sideDy * 0.3,
                           cp2x: HL_side.x, cp2y: HL_side.y)
        ]

        return PatternData(
            points: [
                SavedPoint(id: UUID(), x: WL_center.x, y: WL_center.y, name: "WCB"),
                SavedPoint(id: UUID(), x: WL_side.x,   y: WL_side.y,   name: "WS"),
                SavedPoint(id: UUID(), x: HL_center.x, y: HL_center.y, name: "HCB"),
                SavedPoint(id: UUID(), x: HL_side.x,   y: HL_side.y,   name: "HS"),
            ],
            lines: lines,
            curves: [SavedCurve(nodes: sideCurveNodes)],
            arcs: [], texts: [
                SavedText(x: px(halfHip / 2), y: px(skirtLength / 2), text: "後スカート（子）", fontSize: 14)
            ], notches: [], seamOverrides: [], gradePoints: [])
    }

    private static func generateSkirtFront(_ m: SloperMeasurementsChild) -> PatternData {
        let H = m.hip
        let W = m.waist
        let skirtLength = m.height * 0.30
        let hipLine: CGFloat = 14.0

        let halfHip   = H / 4 - 1.0
        let halfWaist = W / 4 - 1.5
        let dartAmount = max(0, halfHip - halfWaist)
        let dart1 = dartAmount * 0.7

        let WL_center  = CGPoint(x: 0,            y: 0)
        let WL_side    = CGPoint(x: px(halfWaist), y: 0)
        let HL_side    = CGPoint(x: px(halfHip),   y: px(hipLine))
        let HEM_center = CGPoint(x: 0,            y: px(skirtLength))
        let HEM_side   = CGPoint(x: px(halfHip),   y: px(skirtLength))

        var lines: [SavedLine] = []
        lines.append(SavedLine(x1: WL_center.x, y1: WL_center.y, x2: HEM_center.x, y2: HEM_center.y))
        lines.append(SavedLine(x1: HEM_center.x, y1: HEM_center.y, x2: HEM_side.x, y2: HEM_side.y))
        lines.append(SavedLine(x1: HL_side.x, y1: HL_side.y, x2: HEM_side.x, y2: HEM_side.y))

        if dart1 > 0.3 {
            let dX   = px(halfWaist * 0.45)
            let dTop = CGPoint(x: dX, y: px(hipLine * 0.6))
            let dL   = CGPoint(x: dX - px(dart1 / 2), y: 0)
            let dR   = CGPoint(x: dX + px(dart1 / 2), y: 0)
            lines.append(SavedLine(x1: WL_center.x, y1: WL_center.y, x2: dL.x, y2: dL.y))
            lines.append(SavedLine(x1: dR.x, y1: dR.y, x2: WL_side.x, y2: WL_side.y))
            lines.append(SavedLine(x1: dL.x, y1: dL.y, x2: dTop.x, y2: dTop.y))
            lines.append(SavedLine(x1: dTop.x, y1: dTop.y, x2: dR.x, y2: dR.y))
        } else {
            lines.append(SavedLine(x1: WL_center.x, y1: WL_center.y, x2: WL_side.x, y2: WL_side.y))
        }

        let sideDx = HL_side.x - WL_side.x
        let sideDy = HL_side.y - WL_side.y
        let sideCurveNodes = [
            SavedCurveNode(x: WL_side.x, y: WL_side.y,
                           cp1x: WL_side.x, cp1y: WL_side.y,
                           cp2x: WL_side.x + sideDx * 0.1, cp2y: WL_side.y + sideDy * 0.4),
            SavedCurveNode(x: HL_side.x, y: HL_side.y,
                           cp1x: HL_side.x - sideDx * 0.1, cp1y: HL_side.y - sideDy * 0.3,
                           cp2x: HL_side.x, cp2y: HL_side.y)
        ]

        return PatternData(
            points: [
                SavedPoint(id: UUID(), x: WL_center.x, y: WL_center.y, name: "WCF"),
                SavedPoint(id: UUID(), x: WL_side.x,   y: WL_side.y,   name: "WS"),
            ],
            lines: lines,
            curves: [SavedCurve(nodes: sideCurveNodes)],
            arcs: [], texts: [
                SavedText(x: px(halfHip / 2), y: px(skirtLength / 2), text: "前スカート（子）", fontSize: 14)
            ], notches: [], seamOverrides: [], gradePoints: [])
    }
}
