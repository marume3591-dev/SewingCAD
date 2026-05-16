//
//  LineInputView.swift
//  SewingCAD
//

import SwiftUI

struct LineInputView: View {
    let fromPoint: PatternPoint
    let onConfirm: (CGFloat, CGFloat) -> Void  // (lengthCm, angleDeg)
    let onCancel: () -> Void

    @State private var lengthText: String = ""
    @State private var angleText: String = "0"
    @State private var inputMode: InputMode = .lengthAngle

    enum InputMode {
        case lengthAngle   // 長さ＋角度
        case deltaXY       // ΔX・ΔY
    }

    // ΔX・ΔY入力用
    @State private var dxText: String = ""
    @State private var dyText: String = ""

    var previewLength: CGFloat? {
        switch inputMode {
        case .lengthAngle:
            return Double(lengthText).map { CGFloat($0) }
        case .deltaXY:
            if let dx = Double(dxText), let dy = Double(dyText) {
                return CGFloat(sqrt(dx * dx + dy * dy))
            }
            return nil
        }
    }

    var previewAngle: CGFloat? {
        switch inputMode {
        case .lengthAngle:
            return Double(angleText).map { CGFloat($0) }
        case .deltaXY:
            if let dx = Double(dxText), let dy = Double(dyText) {
                var deg = atan2(CGFloat(dy), CGFloat(dx)) * 180 / .pi
                if deg < 0 { deg += 360 }
                return deg
            }
            return nil
        }
    }

    var isValid: Bool {
        guard let l = previewLength, let _ = previewAngle else { return false }
        return l > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("寸法入力で線を引く")
                .font(.headline)

            Text("始点: \(fromPoint.name)  (\(String(format: "%.1f", fromPoint.position.x / 37.8)), \(String(format: "%.1f", fromPoint.position.y / 37.8)) cm)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Divider()

            // 入力モード切替
            Picker("", selection: $inputMode) {
                Text("長さ＋角度").tag(InputMode.lengthAngle)
                Text("ΔX / ΔY").tag(InputMode.deltaXY)
            }
            .pickerStyle(.segmented)

            if inputMode == .lengthAngle {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("長さ:")
                            .frame(width: 50, alignment: .leading)
                        TextField("例: 10.5", text: $lengthText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("cm")
                    }
                    HStack {
                        Text("角度:")
                            .frame(width: 50, alignment: .leading)
                        TextField("例: 45", text: $angleText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("° (0=右, 90=下, 180=左, 270=上)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    // クイック角度ボタン
                    HStack(spacing: 6) {
                        Text("クイック:").font(.system(size: 11)).foregroundColor(.secondary)
                        ForEach([0, 45, 90, 135, 180, 225, 270, 315], id: \.self) { deg in
                            Button("\(deg)°") { angleText = "\(deg)" }
                                .buttonStyle(.bordered)
                                .font(.system(size: 10))
                                .padding(.horizontal, 2)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("ΔX:")
                            .frame(width: 50, alignment: .leading)
                        TextField("例: 5.0", text: $dxText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("cm  (右がプラス)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("ΔY:")
                            .frame(width: 50, alignment: .leading)
                        TextField("例: 3.0", text: $dyText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("cm  (下がプラス)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // プレビュー
            if let l = previewLength, let a = previewAngle, l > 0 {
                Divider()
                HStack(spacing: 20) {
                    Label(String(format: "長さ: %.2f cm", l), systemImage: "ruler")
                    Label(String(format: "角度: %.1f°", a), systemImage: "angle")
                }
                .font(.system(size: 12))
                .foregroundColor(.blue)
            } else if !lengthText.isEmpty || !dxText.isEmpty || !dyText.isEmpty {
                Text("有効な値を入力してください")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            Divider()

            HStack {
                Spacer()
                Button("キャンセル") { onCancel() }
                    .buttonStyle(.bordered)
                Button("確定") {
                    if let l = previewLength, let a = previewAngle {
                        onConfirm(l, a)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
