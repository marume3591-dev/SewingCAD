//
//  LineSplitView.swift
//  SewingCAD
//

import SwiftUI

struct LineSplitView: View {
    let line: PatternLine
    let onSplit: (CGFloat) -> Void
    let onCancel: () -> Void

    @State private var splitMethod: SplitMethod = .distance
    @State private var distanceValue: String = ""
    @State private var ratioNumerator: String = "1"
    @State private var ratioDenominator: String = "2"

    enum SplitMethod {
        case distance
        case ratio
    }

    var splitPoint: CGFloat? {
        switch splitMethod {
        case .distance:
            if let d = Double(distanceValue) {
                let t = CGFloat(d) / line.lengthCm
                if t > 0 && t < 1 { return t }
            }
        case .ratio:
            if let n = Double(ratioNumerator), let d = Double(ratioDenominator), d > 0 {
                let t = CGFloat(n / d)
                if t > 0 && t < 1 { return t }
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("線を分割")
                .font(.headline)

            Text(String(format: "線の長さ: %.2f cm", line.lengthCm))
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Divider()

            // 分割方法
            VStack(alignment: .leading, spacing: 12) {
                // 距離で指定
                HStack {
                    Button(action: { splitMethod = .distance }) {
                        Image(systemName: splitMethod == .distance ? "circle.fill" : "circle")
                    }
                    .buttonStyle(.plain)
                    Text("距離で指定")
                        .font(.system(size: 13))
                    TextField("例: 3.5", text: $distanceValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .font(.system(size: 13))
                        .disabled(splitMethod != .distance)
                    Text("cm")
                        .font(.system(size: 13))
                }

                // 比率で指定
                HStack {
                    Button(action: { splitMethod = .ratio }) {
                        Image(systemName: splitMethod == .ratio ? "circle.fill" : "circle")
                    }
                    .buttonStyle(.plain)
                    Text("比率で指定")
                        .font(.system(size: 13))
                    TextField("1", text: $ratioNumerator)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 40)
                        .font(.system(size: 13))
                        .disabled(splitMethod != .ratio)
                    Text("/")
                        .font(.system(size: 13))
                    TextField("2", text: $ratioDenominator)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 40)
                        .font(.system(size: 13))
                        .disabled(splitMethod != .ratio)
                }
            }

            // プレビュー
            if let t = splitPoint {
                let d = t * line.lengthCm
                Text(String(format: "分割位置: 始点から %.2f cm / %.2f cm", d, line.lengthCm - d))
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
            } else {
                Text("有効な値を入力してください")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            Divider()

            HStack {
                Spacer()
                Button("キャンセル") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                Button("OK") {
                    if let t = splitPoint {
                        onSplit(t)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(splitPoint == nil)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
