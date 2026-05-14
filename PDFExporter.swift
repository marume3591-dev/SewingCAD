//
//  PDFExporter.swift
//  SewingCAD
//

import AppKit
import SwiftUI

class PDFExporter {
    static func export(canvasState: CanvasState, scale: CGFloat) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "pattern.pdf"

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }

                // A4サイズ（ポイント単位: 1pt = 1/72 inch）
                let pageWidth: CGFloat = 595.28
                let pageHeight: CGFloat = 841.89

                // 1cm = 37.8px, 1cm = 28.35pt
                // なので 1px = 28.35 / 37.8 pt
                let pxToPt: CGFloat = 28.35 / 37.8

                let pdfData = NSMutableData()
                var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

                guard let consumer = CGDataConsumer(data: pdfData),
                      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }

                context.beginPDFPage(nil)
                context.setFillColor(NSColor.white.cgColor)
                context.fill(mediaBox)

                let margin: CGFloat = 28.35 // 1cm margin

                // 座標変換（px → pt、Y軸反転）
                func toPage(_ p: CGPoint) -> CGPoint {
                    CGPoint(
                        x: margin + p.x * pxToPt,
                        y: pageHeight - margin - p.y * pxToPt
                    )
                }

                // 線を描画
                context.setStrokeColor(NSColor.black.cgColor)
                context.setLineWidth(0.5)
                for line in canvasState.lines {
                    let p1 = toPage(line.startPoint)
                    let p2 = toPage(line.endPoint)
                    context.beginPath()
                    context.move(to: p1)
                    context.addLine(to: p2)
                    context.strokePath()
                }

                // 曲線を描画
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
                    context.setStrokeColor(NSColor.black.cgColor)
                    context.setLineWidth(0.5)
                    context.strokePath()
                }

                // 円弧を描画
                for arc in canvasState.arcs {
                    let screenCenter = toPage(arc.center)
                    let screenRadius = arc.radius * pxToPt
                    let startRad = arc.startAngle * .pi / 180
                    let endRad = arc.endAngle * .pi / 180
                    context.beginPath()
                    context.addArc(center: screenCenter,
                                  radius: screenRadius,
                                  startAngle: CGFloat(startRad),
                                  endAngle: CGFloat(endRad),
                                  clockwise: true)
                    context.setStrokeColor(NSColor.black.cgColor)
                    context.setLineWidth(0.5)
                    context.strokePath()
                }

                // 点と名前を描画
                for point in canvasState.points {
                    let p = toPage(point.position)
                    context.setFillColor(NSColor.black.cgColor)
                    context.fillEllipse(in: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 6),
                        .foregroundColor: NSColor.black
                    ]
                    let str = NSAttributedString(string: point.name, attributes: attrs)
                    let ctLine = CTLineCreateWithAttributedString(str)
                    context.textPosition = CGPoint(x: p.x + 2, y: p.y + 2)
                    CTLineDraw(ctLine, context)
                }

                // テキストを描画
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

                // 寸法表示
                for line in canvasState.lines {
                    let length = line.lengthCm
                    let mid = CGPoint(
                        x: (line.startPoint.x + line.endPoint.x) / 2,
                        y: (line.startPoint.y + line.endPoint.y) / 2
                    )
                    let midPage = toPage(mid)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 5),
                        .foregroundColor: NSColor.gray
                    ]
                    let str = NSAttributedString(string: String(format: "%.1fcm", length), attributes: attrs)
                    let ctLine = CTLineCreateWithAttributedString(str)
                    context.textPosition = CGPoint(x: midPage.x + 2, y: midPage.y + 2)
                    CTLineDraw(ctLine, context)
                }

                context.endPDFPage()
                context.closePDF()

                DispatchQueue.global(qos: .userInitiated).async {
                    try? (pdfData as Data).write(to: url)
                    print("PDF保存成功: \(url)")
                }
            }
        }
    }
}
