//
//  DXFExporter.swift
//  SewingCAD
//

import AppKit

class DXFExporter {
    static func export(canvasState: CanvasState) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = []
            panel.nameFieldStringValue = "pattern.dxf"
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let dxf = buildDXF(canvasState: canvasState)
                    try? dxf.write(to: url, atomically: true, encoding: .utf8)
                    print("DXF保存成功: \(url)")
                }
            }
        }
    }

    private static func buildDXF(canvasState: CanvasState) -> String {
        // 1px = 1/37.8 cm → DXFはmm単位: 1px = 10/37.8 mm
        let pxToMm: Double = 10.0 / 37.8
        var lines: [String] = []

        func px(_ v: CGFloat) -> String {
            String(format: "%.4f", Double(v) * pxToMm)
        }

        // ─── HEADERセクション ───
        lines += [
            "0", "SECTION",
            "2", "HEADER",
            "9", "$ACADVER",
            "1", "AC1009",
            "9", "$INSUNITS",
            "70", "4",   // 4 = mm
            "0", "ENDSEC",
        ]

        // ─── TABLESセクション ───
        lines += [
            "0", "SECTION",
            "2", "TABLES",
        ]

        // LINETYPEテーブル（DAHSEDを定義）
        lines += [
            "0", "TABLE",
            "2", "LTYPE",
            "70", "2",
            // 実線
            "0", "LTYPE",
            "2", "CONTINUOUS",
            "70", "0",
            "3", "Solid line",
            "72", "65",
            "73", "0",
            "40", "0.0",
            // 破線
            "0", "LTYPE",
            "2", "DASHED",
            "70", "0",
            "3", "Dashed line",
            "72", "65",
            "73", "2",
            "40", "6.0",
            "49", "4.0",
            "49", "-2.0",
            "0", "ENDTAB",
        ]

        // LAYERテーブル
        lines += [
            "0", "TABLE",
            "2", "LAYER",
            "70", "3",
            // 仕上がり線レイヤー
            "0", "LAYER",
            "2", "FINISH",
            "70", "0",
            "62", "7",
            "6", "CONTINUOUS",
            // 縫い代レイヤー
            "0", "LAYER",
            "2", "SEAM",
            "70", "0",
            "62", "5",
            "6", "DASHED",
            // ノッチレイヤー
            "0", "LAYER",
            "2", "NOTCH",
            "70", "0",
            "62", "3",
            "6", "CONTINUOUS",
            "0", "ENDTAB",
        ]

        lines += ["0", "ENDSEC"]

        // ─── ENTITIESセクション ───
        lines += ["0", "SECTION", "2", "ENTITIES"]

        // 点と点名（十字線で表現）
        for point in canvasState.points {
            // 十字線のサイズ: 1mm
            let crossSize: CGFloat = 1.0 / CGFloat(pxToMm)
            // 横線
            lines += [
                "0", "LINE",
                "8", "FINISH",
                "10", px(point.position.x - crossSize),
                "20", px(-point.position.y),
                "30", "0.0",
                "11", px(point.position.x + crossSize),
                "21", px(-point.position.y),
                "31", "0.0",
            ]
            // 縦線
            lines += [
                "0", "LINE",
                "8", "FINISH",
                "10", px(point.position.x),
                "20", px(-point.position.y - crossSize),
                "30", "0.0",
                "11", px(point.position.x),
                "21", px(-point.position.y + crossSize),
                "31", "0.0",
            ]
            // 点名テキスト
            if !point.name.isEmpty {
                lines += [
                    "0", "TEXT",
                    "8", "FINISH",
                    "10", px(point.position.x + crossSize + 1),
                    "20", px(-point.position.y + crossSize),
                    "30", "0.0",
                    "40", "3.0",
                    "1",  point.name,
                ]
            }
        }

        // 直線
        for line in canvasState.lines {
            lines += [
                "0", "LINE",
                "8", "FINISH",
                "10", px(line.startPoint.x),
                "20", px(-line.startPoint.y),
                "30", "0.0",
                "11", px(line.endPoint.x),
                "21", px(-line.endPoint.y),
                "31", "0.0",
            ]
        }

        // 曲線（ポリライン近似・50分割）
        for curve in canvasState.curves {
            guard curve.nodes.count >= 2 else { continue }
            var pts: [CGPoint] = []
            let steps = 50
            for i in 0..<curve.nodes.count - 1 {
                let from = curve.nodes[i]
                let to   = curve.nodes[i + 1]
                for j in 0...steps {
                    let t  = CGFloat(j) / CGFloat(steps)
                    let mt = 1 - t
                    let bx = mt*mt*mt*from.point.x
                           + 3*mt*mt*t*from.controlPoint2.x
                           + 3*mt*t*t*to.controlPoint1.x
                           + t*t*t*to.point.x
                    let by = mt*mt*mt*from.point.y
                           + 3*mt*mt*t*from.controlPoint2.y
                           + 3*mt*t*t*to.controlPoint1.y
                           + t*t*t*to.point.y
                    if j == 0 && i > 0 { continue }
                    pts.append(CGPoint(x: bx, y: by))
                }
            }
            lines += ["0", "POLYLINE", "8", "FINISH", "66", "1", "70", "0"]
            for p in pts {
                lines += ["0", "VERTEX", "8", "FINISH",
                          "10", px(p.x), "20", px(-p.y), "30", "0.0"]
            }
            lines += ["0", "SEQEND"]
        }

        // 円弧
        for arc in canvasState.arcs {
            let startDeg = Double(-arc.endAngle)
            let endDeg   = Double(-arc.startAngle)
            lines += [
                "0", "ARC",
                "8", "FINISH",
                "10", px(arc.center.x),
                "20", px(-arc.center.y),
                "30", "0.0",
                "40", px(arc.radius),
                "50", String(format: "%.4f", startDeg),
                "51", String(format: "%.4f", endDeg),
            ]
        }

        // 縫い代（オフセット線）
        for line in canvasState.lines {
            let width: CGFloat = canvasState.seamWidth(for: line.id)
            let dx  = line.endPoint.x - line.startPoint.x
            let dy  = line.endPoint.y - line.startPoint.y
            let len = sqrt(dx * dx + dy * dy)
            guard len > 0 else { continue }
            let nx = -dy / len * width * 37.8
            let ny =  dx / len * width * 37.8
            lines += [
                "0", "LINE",
                "8", "SEAM",
                "10", px(line.startPoint.x + nx),
                "20", px(-(line.startPoint.y + ny)),
                "30", "0.0",
                "11", px(line.endPoint.x + nx),
                "21", px(-(line.endPoint.y + ny)),
                "31", "0.0",
            ]
        }

        // ノッチ
        for notch in canvasState.notches {
            guard let line = canvasState.lines.first(where: { $0.id == notch.lineID }) else { continue }
            let t: CGFloat = notch.t
            let posX = line.startPoint.x + (line.endPoint.x - line.startPoint.x) * t
            let posY = line.startPoint.y + (line.endPoint.y - line.startPoint.y) * t
            let pos  = CGPoint(x: posX, y: posY)
            let dx  = line.endPoint.x - line.startPoint.x
            let dy  = line.endPoint.y - line.startPoint.y
            let len = sqrt(dx * dx + dy * dy)
            guard len > 0 else { continue }
            let nx: CGFloat = -dy / len
            let ny: CGFloat =  dx / len
            let tx: CGFloat =  dx / len
            let ty: CGFloat =  dy / len
            let sz: CGFloat = notch.size
            let tip   = pos
            let left  = CGPoint(x: pos.x + nx * sz - tx * sz * 0.6,
                                y: pos.y + ny * sz - ty * sz * 0.6)
            let right = CGPoint(x: pos.x + nx * sz + tx * sz * 0.6,
                                y: pos.y + ny * sz + ty * sz * 0.6)
            lines += ["0", "LINE", "8", "NOTCH",
                      "10", px(tip.x),   "20", px(-tip.y),   "30", "0.0",
                      "11", px(left.x),  "21", px(-left.y),  "31", "0.0"]
            lines += ["0", "LINE", "8", "NOTCH",
                      "10", px(left.x),  "20", px(-left.y),  "30", "0.0",
                      "11", px(right.x), "21", px(-right.y), "31", "0.0"]
            lines += ["0", "LINE", "8", "NOTCH",
                      "10", px(right.x), "20", px(-right.y), "30", "0.0",
                      "11", px(tip.x),   "21", px(-tip.y),   "31", "0.0"]
        }

        // テキスト
        for annotation in canvasState.texts {
            let fontSize = Double(annotation.fontSize) * pxToMm
            lines += [
                "0", "TEXT",
                "8", "FINISH",
                "10", px(annotation.position.x),
                "20", px(-annotation.position.y),
                "30", "0.0",
                "40", String(format: "%.4f", fontSize),
                "1",  annotation.text,
            ]
        }

        lines += ["0", "ENDSEC", "0", "EOF"]
        return lines.joined(separator: "\n")
    }
}
