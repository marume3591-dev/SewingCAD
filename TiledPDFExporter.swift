//
//  TiledPDFExporter.swift
//  SewingCAD
//

import AppKit

class TiledPDFExporter {

    // A4サイズ（ポイント）
    static let pageWidth:  CGFloat = 595.28
    static let pageHeight: CGFloat = 841.89

    // 余白（ポイント）
    static let margin: CGFloat = 28.35  // 1cm

    // のりしろ（ポイント）
    static let overlap: CGFloat = 14.175  // 0.5cm

    // 印刷可能領域
    static var printableWidth:  CGFloat { pageWidth  - margin * 2 }
    static var printableHeight: CGFloat { pageHeight - margin * 2 }

    // 1px = 1pt換算（実寸：1cm = 28.35pt、1cm = 37.8px）
    static let pxToPt: CGFloat = 28.35 / 37.8

    static func export(canvasState: CanvasState) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "pattern_tiled.pdf"
            panel.title = "実寸印刷PDFを保存"

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }

                // パターンの実際の範囲を計算（pt単位）
                let bounds = Self.patternBounds(canvasState: canvasState)
                guard bounds.width > 0 && bounds.height > 0 else {
                    print("パターンが空です")
                    return
                }

                // 必要なページ数を計算
                let effectiveWidth  = Self.printableWidth  - Self.overlap
                let effectiveHeight = Self.printableHeight - Self.overlap
                let cols = Int(ceil(bounds.width  / effectiveWidth))
                let rows = Int(ceil(bounds.height / effectiveHeight))
                let totalPages = cols * rows

                print("分割: \(cols)列 × \(rows)行 = \(totalPages)ページ")

                // PDF生成
                let pdfData = NSMutableData()
                var mediaBox = CGRect(x: 0, y: 0,
                                    width: Self.pageWidth,
                                    height: Self.pageHeight)

                guard let consumer = CGDataConsumer(data: pdfData),
                      let context = CGContext(consumer: consumer,
                                            mediaBox: &mediaBox, nil) else { return }

                for row in 0..<rows {
                    for col in 0..<cols {
                        let pageNum = row * cols + col + 1

                        // このページが担当するパターン範囲（pt）
                        let pageOriginX = bounds.minX + CGFloat(col) * effectiveWidth
                        let pageOriginY = bounds.minY + CGFloat(row) * effectiveHeight

                        context.beginPDFPage(nil)

                        // 背景白
                        context.setFillColor(NSColor.white.cgColor)
                        context.fill(CGRect(x: 0, y: 0,
                                          width: Self.pageWidth,
                                          height: Self.pageHeight))

                        // 印刷範囲クリップ
                        context.clip(to: CGRect(x: Self.margin, y: Self.margin,
                                               width: Self.printableWidth,
                                               height: Self.printableHeight))

                        // 座標変換：パターン座標→ページ座標
                        // パターンのpageOrigin部分がmarginに来るよう変換
                        let offsetX = Self.margin - pageOriginX
                        let offsetY = Self.margin - pageOriginY

                        // 1cm方眼を描画
                        Self.drawGrid(context: context,
                                     pageOriginX: pageOriginX,
                                     pageOriginY: pageOriginY,
                                     offsetX: offsetX,
                                     offsetY: offsetY)

                        // パターンを描画
                        Self.drawPattern(context: context,
                                        canvasState: canvasState,
                                        offsetX: offsetX,
                                        offsetY: offsetY)

                        // クリップ解除
                        context.resetClip()

                        // トンボを描画
                        Self.drawCropMarks(context: context)

                        // ページ情報を描画
                        Self.drawPageInfo(context: context,
                                         pageNum: pageNum,
                                         totalPages: totalPages,
                                         col: col, row: row,
                                         cols: cols, rows: rows)

                        // のりしろガイドを描画
                        Self.drawOverlapGuide(context: context)

                        context.endPDFPage()
                    }
                }

                context.closePDF()

                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try (pdfData as Data).write(to: url)
                        print("実寸印刷PDF保存成功: \(url)")
                    } catch {
                        print("保存失敗: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - パターンの範囲計算（pt単位）

    static func patternBounds(canvasState: CanvasState) -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity

        func expand(_ p: CGPoint) {
            let ptX = p.x * pxToPt
            let ptY = p.y * pxToPt
            minX = min(minX, ptX); minY = min(minY, ptY)
            maxX = max(maxX, ptX); maxY = max(maxY, ptY)
        }

        for point in canvasState.points { expand(point.position) }
        for line in canvasState.lines {
            expand(line.startPoint); expand(line.endPoint)
        }
        for curve in canvasState.curves {
            for node in curve.nodes {
                expand(node.point)
                expand(node.controlPoint1)
                expand(node.controlPoint2)
            }
        }
        for arc in canvasState.arcs {
            expand(CGPoint(x: arc.center.x - arc.radius, y: arc.center.y - arc.radius))
            expand(CGPoint(x: arc.center.x + arc.radius, y: arc.center.y + arc.radius))
        }

        guard minX != .infinity else { return .zero }

        // 余白を少し追加（1cm）
        let pad: CGFloat = 28.35
        return CGRect(x: minX - pad, y: minY - pad,
                     width: maxX - minX + pad * 2,
                     height: maxY - minY + pad * 2)
    }

    // MARK: - 1cm方眼

    static func drawGrid(context: CGContext,
                        pageOriginX: CGFloat, pageOriginY: CGFloat,
                        offsetX: CGFloat, offsetY: CGFloat) {
        let gridPt: CGFloat = 28.35  // 1cm = 28.35pt
        context.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.2).cgColor)
        context.setLineWidth(0.3)

        // 縦線
        var x = (ceil(pageOriginX / gridPt) * gridPt) + offsetX
        while x <= Self.margin + Self.printableWidth {
            context.beginPath()
            context.move(to: CGPoint(x: x, y: Self.margin))
            context.addLine(to: CGPoint(x: x, y: Self.margin + Self.printableHeight))
            context.strokePath()
            x += gridPt
        }

        // 横線
        var y = (ceil(pageOriginY / gridPt) * gridPt) + offsetY
        while y <= Self.margin + Self.printableHeight {
            context.beginPath()
            context.move(to: CGPoint(x: Self.margin, y: y))
            context.addLine(to: CGPoint(x: Self.margin + Self.printableWidth, y: y))
            context.strokePath()
            y += gridPt
        }
    }

    // MARK: - パターン描画

    static func drawPattern(context: CGContext,
                           canvasState: CanvasState,
                           offsetX: CGFloat, offsetY: CGFloat) {
        func toPage(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: p.x * pxToPt + offsetX,
                y: p.y * pxToPt + offsetY
            )
        }

        context.setLineWidth(0.7)

        // 線
        context.setStrokeColor(NSColor.black.cgColor)
        for line in canvasState.lines {
            let p1 = toPage(line.startPoint)
            let p2 = toPage(line.endPoint)
            context.beginPath()
            context.move(to: p1)
            context.addLine(to: p2)
            context.strokePath()
        }

        // 曲線
        for curve in canvasState.curves {
            guard curve.nodes.count >= 2 else { continue }
            context.beginPath()
            context.move(to: toPage(curve.nodes[0].point))
            for i in 0..<curve.nodes.count - 1 {
                let from = curve.nodes[i]
                let to = curve.nodes[i + 1]
                context.addCurve(
                    to: toPage(to.point),
                    control1: toPage(from.controlPoint2),
                    control2: toPage(to.controlPoint1)
                )
            }
            context.strokePath()
        }

        // 円弧
        for arc in canvasState.arcs {
            let center = toPage(arc.center)
            let radius = arc.radius * pxToPt
            context.beginPath()
            context.addArc(center: center,
                          radius: radius,
                          startAngle: arc.startAngle * .pi / 180,
                          endAngle: arc.endAngle * .pi / 180,
                          clockwise: false)
            context.strokePath()
        }

        // 縫い代
        if canvasState.showSeamAllowance {
            context.setStrokeColor(NSColor.red.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(0.5)
            let dashPattern: [CGFloat] = [4, 4]
            context.setLineDash(phase: 0, lengths: dashPattern)
            for line in canvasState.lines {
                let p1 = toPage(line.startPoint)
                let p2 = toPage(line.endPoint)
                let dx = p2.x - p1.x, dy = p2.y - p1.y
                let len = sqrt(dx*dx + dy*dy)
                guard len > 0 else { continue }
                let width = canvasState.seamWidth(for: line.id) * 28.35
                let nx = -dy / len * width
                let ny =  dx / len * width
                context.beginPath()
                context.move(to: CGPoint(x: p1.x + nx, y: p1.y + ny))
                context.addLine(to: CGPoint(x: p2.x + nx, y: p2.y + ny))
                context.strokePath()
            }
            context.setLineDash(phase: 0, lengths: [])
        }

        // 点と名前
        context.setFillColor(NSColor.black.cgColor)
        context.setLineWidth(0.5)
        for point in canvasState.points {
            let p = toPage(point.position)
            context.fillEllipse(in: CGRect(x: p.x - 1.5, y: p.y - 1.5,
                                          width: 3, height: 3))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 6),
                .foregroundColor: NSColor.black
            ]
            let str = NSAttributedString(string: point.name, attributes: attrs)
            let ctLine = CTLineCreateWithAttributedString(str)
            context.textPosition = CGPoint(x: p.x + 2, y: p.y + 2)
            CTLineDraw(ctLine, context)
        }

        // ノッチ
        context.setFillColor(NSColor.black.cgColor)
        for notch in canvasState.notches {
            if let line = canvasState.lines.first(where: { $0.id == notch.lineID }) {
                let pos = CGPoint(
                    x: line.startPoint.x + (line.endPoint.x - line.startPoint.x) * notch.t,
                    y: line.startPoint.y + (line.endPoint.y - line.startPoint.y) * notch.t
                )
                let sp = toPage(pos)
                let dx = line.endPoint.x - line.startPoint.x
                let dy = line.endPoint.y - line.startPoint.y
                let len = sqrt(dx*dx + dy*dy)
                guard len > 0 else { continue }
                let nx = -dy/len, ny = dx/len
                let tx = dx/len, ty = dy/len
                let s = notch.size * pxToPt * 2
                let tip   = sp
                let left  = CGPoint(x: sp.x + nx*s - tx*s*0.6,
                                   y: sp.y + ny*s - ty*s*0.6)
                let right = CGPoint(x: sp.x + nx*s + tx*s*0.6,
                                   y: sp.y + ny*s + ty*s*0.6)
                context.beginPath()
                context.move(to: tip)
                context.addLine(to: left)
                context.addLine(to: right)
                context.closePath()
                context.fillPath()
            }
        }

        // テキスト
        for annotation in canvasState.texts {
            let p = toPage(annotation.position)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: annotation.fontSize * pxToPt),
                .foregroundColor: NSColor.black
            ]
            let str = NSAttributedString(string: annotation.text, attributes: attrs)
            let ctLine = CTLineCreateWithAttributedString(str)
            context.textPosition = p
            CTLineDraw(ctLine, context)
        }
    }

    // MARK: - トンボ（貼り合わせマーク）

    static func drawCropMarks(context: CGContext) {
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(0.5)
        let m = Self.margin
        let w = Self.pageWidth
        let h = Self.pageHeight
        let len: CGFloat = 8

        // 四隅にトンボ
        let corners: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
            // 左上
            (CGPoint(x: m - len, y: h - m), CGPoint(x: m, y: h - m),
             CGPoint(x: m, y: h - m + len), CGPoint(x: m, y: h - m)),
            // 右上
            (CGPoint(x: w - m + len, y: h - m), CGPoint(x: w - m, y: h - m),
             CGPoint(x: w - m, y: h - m + len), CGPoint(x: w - m, y: h - m)),
            // 左下
            (CGPoint(x: m - len, y: m), CGPoint(x: m, y: m),
             CGPoint(x: m, y: m - len), CGPoint(x: m, y: m)),
            // 右下
            (CGPoint(x: w - m + len, y: m), CGPoint(x: w - m, y: m),
             CGPoint(x: w - m, y: m - len), CGPoint(x: w - m, y: m))
        ]

        for (p1, p2, p3, p4) in corners {
            context.beginPath()
            context.move(to: p1); context.addLine(to: p2)
            context.strokePath()
            context.beginPath()
            context.move(to: p3); context.addLine(to: p4)
            context.strokePath()
        }
    }

    // MARK: - のりしろガイド

    static func drawOverlapGuide(context: CGContext) {
        let dashPattern: [CGFloat] = [3, 3]
        context.setLineDash(phase: 0, lengths: dashPattern)
        context.setStrokeColor(NSColor.blue.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5)

        let m = Self.margin
        let ov = Self.overlap
        let w = Self.pageWidth
        let h = Self.pageHeight

        // 右端のりしろ線
        context.beginPath()
        context.move(to: CGPoint(x: w - m - ov, y: m))
        context.addLine(to: CGPoint(x: w - m - ov, y: h - m))
        context.strokePath()

        // 下端のりしろ線
        context.beginPath()
        context.move(to: CGPoint(x: m, y: m + ov))
        context.addLine(to: CGPoint(x: w - m, y: m + ov))
        context.strokePath()

        context.setLineDash(phase: 0, lengths: [])
    }

    // MARK: - ページ情報

    static func drawPageInfo(context: CGContext,
                            pageNum: Int, totalPages: Int,
                            col: Int, row: Int,
                            cols: Int, rows: Int) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7),
            .foregroundColor: NSColor.darkGray
        ]

        // ページ番号（左下）
        let pageText = "\(pageNum) / \(totalPages)  [\(col+1)-\(row+1)]"
        let str = NSAttributedString(string: pageText, attributes: attrs)
        let ctLine = CTLineCreateWithAttributedString(str)
        context.textPosition = CGPoint(x: Self.margin, y: Self.margin - 16)
        CTLineDraw(ctLine, context)

        // スケール表示（右下）
        let scaleText = "実寸 1:1  ←5cm→"
        let scaleStr = NSAttributedString(string: scaleText, attributes: attrs)
        let scaleLine = CTLineCreateWithAttributedString(scaleStr)
        context.textPosition = CGPoint(x: Self.pageWidth - Self.margin - 80,
                                      y: Self.margin - 16)
        CTLineDraw(scaleLine, context)

        // 5cmスケールバー（右下）
        let barX = Self.pageWidth - Self.margin - 60
        let barY = Self.margin - 10
        let barLen: CGFloat = 28.35 * 5  // 5cm
        context.setStrokeColor(NSColor.darkGray.cgColor)
        context.setLineWidth(1)
        context.beginPath()
        context.move(to: CGPoint(x: barX, y: barY))
        context.addLine(to: CGPoint(x: barX + barLen, y: barY))
        context.move(to: CGPoint(x: barX, y: barY - 3))
        context.addLine(to: CGPoint(x: barX, y: barY + 3))
        context.move(to: CGPoint(x: barX + barLen, y: barY - 3))
        context.addLine(to: CGPoint(x: barX + barLen, y: barY + 3))
        context.strokePath()
    }
}
