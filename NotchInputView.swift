//
//  NotchInputView.swift
//  SewingCAD
//

import SwiftUI

struct NotchInputView: View {
    let line: PatternLine
    let t: CGFloat
    let onConfirm: (CGFloat) -> Void
    let onCancel: () -> Void

    @State private var sizeText: String = "8"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ノッチ（合いじるし）を追加")
                .font(.headline)

            Text(String(format: "位置: 始点から %.0f%%", t * 100))
                .font(.system(size: 12)).foregroundColor(.secondary)
            Text(String(format: "距離: %.2f cm / %.2f cm",
                       t * line.lengthCm, (1 - t) * line.lengthCm))
                .font(.system(size: 12)).foregroundColor(.secondary)

            Divider()

            // プレビュー（逆三角形）
            HStack {
                Spacer()
                Canvas { context, size in
                    let cx = size.width / 2
                    let cy = size.height / 2
                    let s = CGFloat(Double(sizeText) ?? 8) * 2
                    // 水平線（線のイメージ）
                    var linePath = Path()
                    linePath.move(to: CGPoint(x: cx - 40, y: cy))
                    linePath.addLine(to: CGPoint(x: cx + 40, y: cy))
                    context.stroke(linePath, with: .color(.black), lineWidth: 1.5)
                    // 逆三角形ノッチ（▽）
                    var notchPath = Path()
                    notchPath.move(to: CGPoint(x: cx, y: cy))
                    notchPath.addLine(to: CGPoint(x: cx - s * 0.6, y: cy - s))
                    notchPath.addLine(to: CGPoint(x: cx + s * 0.6, y: cy - s))
                    notchPath.closeSubpath()
                    context.fill(notchPath, with: .color(.black))
                }
                .frame(width: 120, height: 60)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(6)
                Spacer()
            }

            HStack {
                Text("サイズ:").font(.system(size: 13))
                TextField("8", text: $sizeText)
                    .textFieldStyle(.roundedBorder).frame(width: 60)
                Text("px").font(.system(size: 13))
            }

            Divider()

            HStack {
                Spacer()
                Button("キャンセル") { onCancel() }.buttonStyle(.bordered)
                Button("追加") {
                    onConfirm(CGFloat(Double(sizeText) ?? 8))
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}
