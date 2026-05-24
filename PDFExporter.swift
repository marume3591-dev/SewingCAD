//
//  PDFExporter.swift
//  SewingCAD
//

import AppKit
import SwiftUI

class PDFExporter {

    private static let margin:  CGFloat = 28.35   // マージン 1cm
    private static let overlap: CGFloat = 14.17   // のりしろ 0.5cm
    private static let pxToPt:  CGFloat = 28.35 / 37.8  // 1px → pt

    static func export(canvasState: CanvasState, scale: CGFloat, includeSeamAllowance: Bool = false) {

        print("=== PDF Export ===")
        print("paperSize: \(canvasState.paperSize.rawValue)")
        print("includeSeamAllowance: \(includeSeamAllowance)")
        print("seamAllowance: \(canvasState.seamAllowance) cm")

        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "pattern.pdf"

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }

                // ─── 用紙1枚のサイズ ───
                let paperPx  = canvasState.currentPaperSize
                let paperPtW = paperPx.width  * pxToPt
                let paperPtH = paperPx.height * pxToPt

                print("用紙1枚: \(Int(paperPx.width))×\(Int(paperPx.height))px → \(Int(paperPtW))×\(Int(paperPtH))pt")

                // ─── コンテンツの最大座標 ───
                var allPts: [CGPoint] = []
                allPts += canvasState.points.map { $0.position }
                for line in canvasState.lines {
                    allPts.append(line.startPoint)
                    allPts.append(line.endPoint)
                }
                for curve in canvasState.curves { allPts += curve.nodes.map { $0.point } }
                for arc in canvasState.arcs {
                    allPts.append(CGPoint(x: arc.center.x - arc.radius, y: arc.center.y - arc.radius))
                    allPts.append(CGPoint(x: arc.center.x + arc.radius, y: arc.center.y + arc.radius))
                }
                for text in canvasState.texts { allPts.append(text.position) }
                guard !allPts.isEmpty else { print("描画要素なし"); return }

                let contentMaxX = allPts.map { $0.x }.max()!
                let contentMaxY = allPts.map { $0.y }.max()!

                // ─── ページ分割（キャンバスの用紙区切りに合わせる）───
                let cols = max(1, Int(ceil(contentMaxX / paperPx.width)))
                let rows = max(1, Int(ceil(contentMaxY / paperPx.height)))
                let totalPages = cols * rows
                print("分割: \(cols)列 × \(rows)行 = \(totalPages)ページ")

                // ─── PDF生成 ───
                let pdfData = NSMutableData()
                var mediaBox = CGRect(x: 0, y: 0, width: paperPtW, height: paperPtH)
                guard let consumer = CGDataConsumer(data: pdfData),
                      let context  = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
                else { return }

                for row in 0..<rows {
                    for col in 0..<cols {
                        let pageIndex     = row * cols + col + 1
                        let pageOriginXpx = CGFloat(col) * paperPx.width
                        let pageOriginYpx = CGFloat(row) * paperPx.height

                        context.beginPDFPage(nil)
                        context.setFillColor(NSColor.white.cgColor)
                        context.fill(CGRect(x: 0, y: 0, width: paperPtW, height: paperPtH))

                        // ─── 座標変換 ───
                        func toPage(_ p: CGPoint) -> CGPoint {
                            let ptX = margin + (p.x - pageOriginXpx) * pxToPt
                            let ptY = paperPtH - margin - (p.y - pageOriginYpx) * pxToPt
                            return CGPoint(x: ptX, y: ptY)
                        }

                        // このページの範囲（px）
                        let pageMinXpx = pageOriginXpx
                        let pageMaxXpx = pageOriginXpx + paperPx.width
                        let pageMinYpx = pageOriginYpx
                        let pageMaxYpx = pageOriginYpx + paperPx.height

                        func lineIntersectsPage(_ line: PatternLine) -> Bool {
                            let minX = min(line.startPoint.x, line.endPoint.x)
                            let maxX = max(line.startPoint.x, line.endPoint.x)
                            let minY = min(line.startPoint.y, line.endPoint.y)
                            let maxY = max(line.startPoint.y, line.endPoint.y)
                            return maxX > pageMinXpx && minX < pageMaxXpx &&
                                   maxY > pageMinYpx && minY < pageMaxYpx
                        }

                        // クリップ（マージン内）
                        context.saveGState()
                        context.clip(to: CGRect(
                            x: margin, y: margin,
                            width:  paperPtW - margin * 2,
                            height: paperPtH - margin * 2
                        ))

                        // ─── 縫い代（青い破線 ← 画面と同じ色）───
                        if includeSeamAllowance {
                            context.saveGState()
                            // 画面と同じ青色
                            context.setStrokeColor(NSColor.systemBlue.cgColor)
                            context.setLineWidth(0.5)
                            context.setLineDash(phase: 0, lengths: [4, 4])

                            // 直線の縫い代
                            // 線ごとに個別設定(seamOverrides)があればそれを使い、なければデフォルト値
                            for line in canvasState.lines {
                                guard lineIntersectsPage(line) else { continue }
                                let seamCm = canvasState.seamWidth(for: line.id)
                                let seamPt = seamCm * 37.8 * pxToPt
                                let p1 = toPage(line.startPoint)
                                let p2 = toPage(line.endPoint)
                                let dx = p2.x - p1.x, dy = p2.y - p1.y
                                let len = sqrt(dx*dx + dy*dy)
                                guard len > 0 else { continue }
                                // Y軸反転に合わせて法線方向を反転
                                let nx =  dy / len * seamPt
                                let ny = -dx / len * seamPt
                                context.beginPath()
                                context.move(to:    CGPoint(x: p1.x + nx, y: p1.y + ny))
                                context.addLine(to: CGPoint(x: p2.x + nx, y: p2.y + ny))
                                context.strokePath()
                            }

                            // 曲線の縫い代（デフォルト縫い代幅を使用）
                            let defaultSeamPt = canvasState.seamAllowance * 37.8 * pxToPt
                            let steps = 60
                            for curve in canvasState.curves {
                                guard curve.nodes.count >= 2 else { continue }
                                var offsetPts: [CGPoint] = []
                                for i in 0..<curve.nodes.count - 1 {
                                    let from = curve.nodes[i], to = curve.nodes[i + 1]
                                    for j in 0...steps {
                                        let t = CGFloat(j) / CGFloat(steps), mt = 1 - t
                                        let raw = CGPoint(
                                            x: mt*mt*mt*from.point.x + 3*mt*mt*t*from.controlPoint2.x + 3*mt*t*t*to.controlPoint1.x + t*t*t*to.point.x,
                                            y: mt*mt*mt*from.point.y + 3*mt*mt*t*from.controlPoint2.y + 3*mt*t*t*to.controlPoint1.y + t*t*t*to.point.y
                                        )
                                        let pg = toPage(raw)
                                        if offsetPts.isEmpty {
                                            offsetPts.append(pg)
                                        } else {
                                            let prev = offsetPts.last!
                                            let sdx = pg.x - prev.x, sdy = pg.y - prev.y
                                            let slen = sqrt(sdx*sdx + sdy*sdy)
                                            guard slen > 0 else { continue }
                                            // Y軸反転に合わせて法線方向を反転
                                            offsetPts.append(CGPoint(
                                                x: pg.x + ( sdy / slen * defaultSeamPt),
                                                y: pg.y + (-sdx / slen * defaultSeamPt)
                                            ))
                                        }
                                    }
                                }
                                guard offsetPts.count >= 2 else { continue }
                                context.beginPath()
                                context.move(to: offsetPts[0])
                                offsetPts.dropFirst().forEach { context.addLine(to: $0) }
                                context.strokePath()
                            }
                            context.restoreGState()
                        }

                        // ─── 仕上がり線（直線）───
                        context.setStrokeColor(NSColor.black.cgColor)
                        context.setLineWidth(0.5)
                        for line in canvasState.lines {
                            guard lineIntersectsPage(line) else { continue }
                            let p1 = toPage(line.startPoint)
                            let p2 = toPage(line.endPoint)
                            context.beginPath()
                            context.move(to: p1); context.addLine(to: p2)
                            context.strokePath()
                        }

                        // ─── 仕上がり線（曲線）───
                        for curve in canvasState.curves {
                            guard curve.nodes.count >= 2 else { continue }
                            context.beginPath()
                            context.move(to: toPage(curve.nodes[0].point))
                            for i in 0..<curve.nodes.count - 1 {
                                let from = curve.nodes[i], to = curve.nodes[i + 1]
                                context.addCurve(
                                    to: toPage(to.point),
                                    control1: toPage(from.controlPoint2),
                                    control2: toPage(to.controlPoint1)
                                )
                            }
                            context.strokePath()
                        }

                        // ─── 円弧 ───
                        for arc in canvasState.arcs {
                            let c = toPage(arc.center)
                            let r = arc.radius * pxToPt
                            let startRad = -arc.startAngle * .pi / 180
                            let endRad   = -arc.endAngle   * .pi / 180
                            context.beginPath()
                            context.addArc(center: c, radius: r,
                                           startAngle: startRad, endAngle: endRad,
                                           clockwise: false)
                            context.setStrokeColor(NSColor.black.cgColor)
                            context.setLineWidth(0.5)
                            context.strokePath()
                        }

                        // ─── 点と名前（このページの範囲内のみ）───
                        for point in canvasState.points {
                            guard point.position.x >= pageMinXpx && point.position.x < pageMaxXpx &&
                                  point.position.y >= pageMinYpx && point.position.y < pageMaxYpx
                            else { continue }
                            let p = toPage(point.position)
                            context.setFillColor(NSColor.black.cgColor)
                            context.fillEllipse(in: CGRect(x: p.x-1.5, y: p.y-1.5, width: 3, height: 3))
                            let attrs: [NSAttributedString.Key: Any] = [
                                .font: NSFont.systemFont(ofSize: 6),
                                .foregroundColor: NSColor.black
                            ]
                            let ctLine = CTLineCreateWithAttributedString(
                                NSAttributedString(string: point.name, attributes: attrs))
                            context.textPosition = CGPoint(x: p.x + 3, y: p.y + 3)
                            CTLineDraw(ctLine, context)
                        }

                        // ─── テキスト（このページの範囲内のみ）───
                        for annotation in canvasState.texts {
                            guard annotation.position.x >= pageMinXpx && annotation.position.x < pageMaxXpx &&
                                  annotation.position.y >= pageMinYpx && annotation.position.y < pageMaxYpx
                            else { continue }
                            let p = toPage(annotation.position)
                            let attrs: [NSAttributedString.Key: Any] = [
                                .font: NSFont.systemFont(ofSize: annotation.fontSize * pxToPt),
                                .foregroundColor: NSColor.black
                            ]
                            let ctLine = CTLineCreateWithAttributedString(
                                NSAttributedString(string: annotation.text, attributes: attrs))
                            context.textPosition = p
                            CTLineDraw(ctLine, context)
                        }

                        // ─── 寸法ラベル（中点がこのページにある線のみ）───
                        for line in canvasState.lines {
                            guard lineIntersectsPage(line) else { continue }
                            let mid = CGPoint(
                                x: (line.startPoint.x + line.endPoint.x) / 2,
                                y: (line.startPoint.y + line.endPoint.y) / 2
                            )
                            guard mid.x >= pageMinXpx && mid.x < pageMaxXpx &&
                                  mid.y >= pageMinYpx && mid.y < pageMaxYpx
                            else { continue }
                            let midPt = toPage(mid)
                            let attrs: [NSAttributedString.Key: Any] = [
                                .font: NSFont.systemFont(ofSize: 8),
                                .foregroundColor: NSColor.darkGray
                            ]
                            let ctLine = CTLineCreateWithAttributedString(
                                NSAttributedString(
                                    string: String(format: "%.1fcm", line.lengthCm),
                                    attributes: attrs))
                            context.textPosition = CGPoint(x: midPt.x + 2, y: midPt.y + 4)
                            CTLineDraw(ctLine, context)
                        }

                        context.restoreGState()

                        // ─── トンボ ───
                        drawCropMarks(context: context, pageWidth: paperPtW, pageHeight: paperPtH)

                        // ─── のりしろ境界線（グレー破線）───
                        context.setStrokeColor(NSColor.lightGray.cgColor)
                        context.setLineWidth(0.3)
                        context.setLineDash(phase: 0, lengths: [3, 3])
                        if col < cols - 1 {
                            let x = paperPtW - margin - overlap
                            context.beginPath()
                            context.move(to: CGPoint(x: x, y: margin))
                            context.addLine(to: CGPoint(x: x, y: paperPtH - margin))
                            context.strokePath()
                        }
                        if row < rows - 1 {
                            let y = margin + overlap
                            context.beginPath()
                            context.move(to: CGPoint(x: margin, y: y))
                            context.addLine(to: CGPoint(x: paperPtW - margin, y: y))
                            context.strokePath()
                        }
                        context.setLineDash(phase: 0, lengths: [])

                        // ─── ページ番号 ───
                        let label = "\(canvasState.paperSize.rawValue)  \(pageIndex) / \(totalPages)  (列\(col+1)-行\(row+1))"
                        let labelAttrs: [NSAttributedString.Key: Any] = [
                            .font: NSFont.systemFont(ofSize: 7),
                            .foregroundColor: NSColor.darkGray
                        ]
                        let ctLine = CTLineCreateWithAttributedString(
                            NSAttributedString(string: label, attributes: labelAttrs))
                        context.textPosition = CGPoint(x: paperPtW - margin - 80, y: 10)
                        CTLineDraw(ctLine, context)

                        context.endPDFPage()
                    }
                }

                context.closePDF()
                DispatchQueue.global(qos: .userInitiated).async {
                    try? (pdfData as Data).write(to: url)
                    print("PDF保存成功: \(url) (\(totalPages)ページ / \(canvasState.paperSize.rawValue))")
                }
            }
        }
    }

    private static func drawCropMarks(context: CGContext, pageWidth: CGFloat, pageHeight: CGFloat) {
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(0.3)
        let mark: CGFloat = 10
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: margin,             y: pageHeight - margin),
             CGPoint(x: margin - mark,      y: pageHeight - margin),
             CGPoint(x: margin,             y: pageHeight - margin + mark)),
            (CGPoint(x: pageWidth - margin, y: pageHeight - margin),
             CGPoint(x: pageWidth - margin + mark, y: pageHeight - margin),
             CGPoint(x: pageWidth - margin, y: pageHeight - margin + mark)),
            (CGPoint(x: margin,             y: margin),
             CGPoint(x: margin - mark,      y: margin),
             CGPoint(x: margin,             y: margin - mark)),
            (CGPoint(x: pageWidth - margin, y: margin),
             CGPoint(x: pageWidth - margin + mark, y: margin),
             CGPoint(x: pageWidth - margin, y: margin - mark))
        ]
        for (corner, h, v) in corners {
            context.beginPath(); context.move(to: corner); context.addLine(to: h); context.strokePath()
            context.beginPath(); context.move(to: corner); context.addLine(to: v); context.strokePath()
        }
    }
}
