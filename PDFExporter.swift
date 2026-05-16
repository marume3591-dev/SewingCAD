//
//  PDFExporter.swift
//  SewingCAD
//

import AppKit
import SwiftUI

enum PDFOutputMode: String, CaseIterable {
    case finishedLine = "仕上がり線のみ"
    case withSeam     = "縫い代込み"
}

class PDFExporter {

    // MARK: - メイン出力
    static func export(canvasState: CanvasState, scale: CGFloat, mode: PDFOutputMode = .finishedLine) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "pattern.pdf"
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = buildPDF(canvasState: canvasState, mode: mode)
                    try? data.write(to: url)
                    print("PDF保存成功: \(url)")
                }
            }
        }
    }

    // MARK: - PDF構築（A4複数ページ分割）
    static func buildPDF(canvasState: CanvasState, mode: PDFOutputMode) -> Data {
        // 1cm = 28.35pt
        let pxToPt: CGFloat = 28.35 / 37.8
        let margin: CGFloat = 28.35       // 1cm余白
        let overlap: CGFloat = 14.175     // 0.5cm のりしろ（貼り合わせ用）

        // A4ページサイズ（pt）
        let pageW: CGFloat = 595.28
        let pageH: CGFloat = 841.89
        let drawW = pageW - margin * 2   // 描画可能幅
        let drawH = pageH - margin * 2   // 描画可能高さ

        // パターン全体のバウンディングボックスを計算
        var allPoints: [CGPoint] = []
        canvasState.points.forEach { allPoints.append($0.position) }
        canvasState.lines.forEach { allPoints.append($0.startPoint); allPoints.append($0.endPoint) }
        canvasState.curves.forEach { $0.nodes.forEach { allPoints.append($0.point) } }
        canvasState.arcs.forEach {
            allPoints.append(CGPoint(x: $0.center.x - $0.radius, y: $0.center.y - $0.radius))
            allPoints.append(CGPoint(x: $0.center.x + $0.radius, y: $0.center.y + $0.radius))
        }

        guard !allPoints.isEmpty else {
            // 空の場合は白紙1ページ
            return buildEmptyPDF(pageW: pageW, pageH: pageH)
        }

        let minX = allPoints.map { $0.x }.min()! - 37.8  // 1cm余裕
        let minY = allPoints.map { $0.y }.min()! - 37.8
        let maxX = allPoints.map { $0.x }.max()! + 37.8
        let maxY = allPoints.map { $0.y }.max()! + 37.8
        let patternW = (maxX - minX) * pxToPt
        let patternH = (maxY - minY) * pxToPt

        // 何ページ必要か計算（のりしろ考慮）
        let effectiveW = drawW - overlap
        let effectiveH = drawH - overlap
        let cols = Int(ceil(patternW / effectiveW))
        let rows = Int(ceil(patternH / effectiveH))

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let consumer = CGDataConsumer(data: pdfData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        // 座標変換：px → pt、Y軸反転
        func toPage(_ p: CGPoint, offsetX: CGFloat, offsetY: CGFloat) -> CGPoint {
            CGPoint(
                x: margin + (p.x - minX) * pxToPt - offsetX,
                y: pageH - margin - (p.y - minY) * pxToPt + offsetY
            )
        }

        for row in 0..<rows {
            for col in 0..<cols {
                let offsetX = CGFloat(col) * effectiveW
                let offsetY = CGFloat(row) * effectiveH

                context.beginPDFPage(nil)

                // 白背景
                context.setFillColor(NSColor.white.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: pageW, height: pageH))

                // クリップ領域（余白内）
                context.saveGState()
                context.clip(to: CGRect(x: margin - overlap/2, y: margin - overlap/2,
                                       width: drawW + overlap, height: drawH + overlap))

                // 線を描画
                drawLines(context: context, canvasState: canvasState,
                         mode: mode, pxToPt: pxToPt, toPage: { toPage($0, offsetX: offsetX, offsetY: offsetY) })

                // 曲線を描画
                drawCurves(context: context, canvasState: canvasState,
                          pxToPt: pxToPt, toPage: { toPage($0, offsetX: offsetX, offsetY: offsetY) })

                // 円弧を描画
                drawArcs(context: context, canvasState: canvasState,
                        pxToPt: pxToPt, toPage: { toPage($0, offsetX: offsetX, offsetY: offsetY) })

                // ノッチを描画
                drawNotches(context: context, canvasState: canvasState,
                           pxToPt: pxToPt, toPage: { toPage($0, offsetX: offsetX, offsetY: offsetY) })

                // 点と名前を描画
                drawPoints(context: context, canvasState: canvasState,
                          toPage: { toPage($0, offsetX: offsetX, offsetY: offsetY) })

                // テキストを描画
                drawTexts(context: context, canvasState: canvasState,
                         pxToPt: pxToPt, toPage: { toPage($0, offsetX: offsetX, offsetY: offsetY) })

                context.restoreGState()

                // ページ枠線
                context.setStrokeColor(NSColor.lightGray.cgColor)
                context.setLineWidth(0.5)
                context.stroke(CGRect(x: margin, y: margin, width: drawW, height: drawH))

                // のりしろ線（破線）
                context.setStrokeColor(NSColor.gray.cgColor)
                context.setLineDash(phase: 0, lengths: [4, 4])
                context.setLineWidth(0.3)
                let glueRect = CGRect(x: margin - overlap/2, y: margin - overlap/2,
                                     width: drawW + overlap, height: drawH + overlap)
                context.stroke(glueRect)
                context.setLineDash(phase: 0, lengths: [])

                // ページ番号とページ位置
                let pageNum = row * cols + col + 1
                let totalPages = rows * cols
                let pageLabel = "P\(pageNum)/\(totalPages)  [\(col+1)-\(row+1)]"
                drawText(context: context, text: pageLabel,
                        at: CGPoint(x: margin + 4, y: margin + 4), fontSize: 7)

                // スケールバー（各ページ右下）
                drawScaleBar(context: context, pageW: pageW, pageH: pageH, margin: margin)

                context.endPDFPage()
            }
        }

        context.closePDF()
        return pdfData as Data
    }

    // MARK: - 線の描画
    private static func drawLines(context: CGContext, canvasState: CanvasState,
                                  mode: PDFOutputMode, pxToPt: CGFloat,
                                  toPage: (CGPoint) -> CGPoint) {
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(0.5)

        for line in canvasState.lines {
            let p1 = toPage(line.startPoint)
            let p2 = toPage(line.endPoint)
            context.beginPath()
            context.move(to: p1)
            context.addLine(to: p2)
            context.strokePath()

            // 寸法表示
            let mid = CGPoint(x: (p1.x + p2.x) / 2 + 2, y: (p1.y + p2.y) / 2 + 2)
            drawText(context: context, text: String(format: "%.1fcm", line.lengthCm),
                    at: mid, fontSize: 5, color: NSColor.gray)
        }

        // 縫い代込みモード
        if mode == .withSeam {
            context.setStrokeColor(NSColor.red.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(0.3)
            let dash: [CGFloat] = [3, 3]
            context.setLineDash(phase: 0, lengths: dash)

            for line in canvasState.lines {
                let width = canvasState.seamWidth(for: line.id)
                let dx = line.endPoint.x - line.startPoint.x
                let dy = line.endPoint.y - line.startPoint.y
                let len = sqrt(dx*dx + dy*dy)
                guard len > 0 else { continue }
                let nx = -dy / len * width * 37.8 * pxToPt
                let ny =  dx / len * width * 37.8 * pxToPt
                // Y軸が反転しているのでnyの符号を反転
                let sp1 = toPage(line.startPoint)
                let sp2 = toPage(line.endPoint)
                let op1 = CGPoint(x: sp1.x + nx, y: sp1.y - ny)
                let op2 = CGPoint(x: sp2.x + nx, y: sp2.y - ny)
                context.beginPath()
                context.move(to: op1)
                context.addLine(to: op2)
                context.strokePath()
            }
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    // MARK: - 曲線の描画
    private static func drawCurves(context: CGContext, canvasState: CanvasState,
                                   pxToPt: CGFloat, toPage: (CGPoint) -> CGPoint) {
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(0.5)
        for curve in canvasState.curves {
            guard curve.nodes.count >= 2 else { continue }
            context.beginPath()
            context.move(to: toPage(curve.nodes[0].point))
            for i in 0..<curve.nodes.count - 1 {
                let from = curve.nodes[i], to = curve.nodes[i+1]
                context.addCurve(to: toPage(to.point),
                                control1: toPage(from.controlPoint2),
                                control2: toPage(to.controlPoint1))
            }
            context.strokePath()
        }
    }

    // MARK: - 円弧の描画
    private static func drawArcs(context: CGContext, canvasState: CanvasState,
                                 pxToPt: CGFloat, toPage: (CGPoint) -> CGPoint) {
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(0.5)
        for arc in canvasState.arcs {
            let center = toPage(arc.center)
            let radius = arc.radius * pxToPt
            context.beginPath()
            context.addArc(center: center, radius: radius,
                          startAngle: arc.startAngle * .pi / 180,
                          endAngle: arc.endAngle * .pi / 180,
                          clockwise: true)
            context.strokePath()
        }
    }

    // MARK: - ノッチの描画
    private static func drawNotches(context: CGContext, canvasState: CanvasState,
                                    pxToPt: CGFloat, toPage: (CGPoint) -> CGPoint) {
        context.setFillColor(NSColor.black.cgColor)
        for notch in canvasState.notches {
            guard let line = canvasState.lines.first(where: { $0.id == notch.lineID }) else { continue }
            let pos = CGPoint(
                x: line.startPoint.x + (line.endPoint.x - line.startPoint.x) * notch.t,
                y: line.startPoint.y + (line.endPoint.y - line.startPoint.y) * notch.t
            )
            let screenPos = toPage(pos)
            let dx = line.endPoint.x - line.startPoint.x
            let dy = line.endPoint.y - line.startPoint.y
            let len = sqrt(dx*dx + dy*dy)
            guard len > 0 else { continue }
            let nx = -dy / len
            let ny =  dx / len
            let tx = dx / len
            let ty = dy / len
            let s = notch.size * pxToPt * 1.5
            // 逆三角形
            var path = CGMutablePath()
            path.move(to: screenPos)
            path.addLine(to: CGPoint(x: screenPos.x + nx*s - tx*s*0.6,
                                    y: screenPos.y - ny*s + ty*s*0.6))
            path.addLine(to: CGPoint(x: screenPos.x + nx*s + tx*s*0.6,
                                    y: screenPos.y - ny*s - ty*s*0.6))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        }
    }

    // MARK: - 点の描画
    private static func drawPoints(context: CGContext, canvasState: CanvasState,
                                   toPage: (CGPoint) -> CGPoint) {
        context.setFillColor(NSColor.black.cgColor)
        for point in canvasState.points {
            let p = toPage(point.position)
            context.fillEllipse(in: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
            drawText(context: context, text: point.name,
                    at: CGPoint(x: p.x + 2, y: p.y + 2), fontSize: 6)
        }
    }

    // MARK: - テキストの描画
    private static func drawTexts(context: CGContext, canvasState: CanvasState,
                                  pxToPt: CGFloat, toPage: (CGPoint) -> CGPoint) {
        for annotation in canvasState.texts {
            let p = toPage(annotation.position)
            drawText(context: context, text: annotation.text,
                    at: p, fontSize: annotation.fontSize * pxToPt)
        }
    }

    // MARK: - スケールバー
    private static func drawScaleBar(context: CGContext, pageW: CGFloat, pageH: CGFloat, margin: CGFloat) {
        let barLength: CGFloat = 28.35 * 5  // 5cm = 141.75pt
        let x = pageW - margin - barLength
        let y = margin + 10
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1)
        context.beginPath()
        context.move(to: CGPoint(x: x, y: y))
        context.addLine(to: CGPoint(x: x + barLength, y: y))
        context.move(to: CGPoint(x: x, y: y - 3))
        context.addLine(to: CGPoint(x: x, y: y + 3))
        context.move(to: CGPoint(x: x + barLength, y: y - 3))
        context.addLine(to: CGPoint(x: x + barLength, y: y + 3))
        context.strokePath()
        drawText(context: context, text: "5cm",
                at: CGPoint(x: x + barLength/2 - 8, y: y + 5), fontSize: 7)
    }

    // MARK: - テキスト描画ヘルパー
    private static func drawText(context: CGContext, text: String, at point: CGPoint,
                                 fontSize: CGFloat, color: NSColor = .black) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(str)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    // MARK: - 空PDF
    private static func buildEmptyPDF(pageW: CGFloat, pageH: CGFloat) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let consumer = CGDataConsumer(data: data),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        ctx.beginPDFPage(nil)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }
}
