//
//  SettingsView.swift
//  SewingCAD
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var canvasState: CanvasState

    @State private var customWidth: String = ""
    @State private var customHeight: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("設定")
                .font(.headline)
                .padding(.bottom, 4)

            Divider()

            // グリッド
            VStack(alignment: .leading, spacing: 8) {
                Text("グリッド")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Toggle("グリッドを表示", isOn: $canvasState.showGrid)
                    .font(.system(size: 13))
            }

            Divider()

            // 用紙サイズ
            VStack(alignment: .leading, spacing: 8) {
                Text("用紙サイズ")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Picker("", selection: $canvasState.paperSize) {
                    ForEach(PaperSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                if canvasState.paperSize == .custom {
                    HStack {
                        Text("幅:")
                            .font(.system(size: 13))
                        TextField("", text: $customWidth)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .font(.system(size: 13))
                        Text("mm")
                            .font(.system(size: 13))
                        Text("高さ:")
                            .font(.system(size: 13))
                        TextField("", text: $customHeight)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .font(.system(size: 13))
                        Text("mm")
                            .font(.system(size: 13))
                        Button("適用") {
                            if let w = Double(customWidth), let h = Double(customHeight) {
                                canvasState.customPaperWidth = CGFloat(w / 25.4 * 96)
                                canvasState.customPaperHeight = CGFloat(h / 25.4 * 96)
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 12))
                    }
                }
            }

            Divider()

            // 縫い代
            VStack(alignment: .leading, spacing: 8) {
                Text("縫い代")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Toggle("縫い代を表示", isOn: $canvasState.showSeamAllowance)
                    .font(.system(size: 13))
                if canvasState.showSeamAllowance {
                    HStack {
                        Text("幅:")
                            .font(.system(size: 13))
                        TextField("", text: Binding(
                            get: { String(format: "%.1f", canvasState.seamAllowance) },
                            set: { if let v = Double($0) { canvasState.seamAllowance = CGFloat(v) } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.system(size: 13))
                        Text("cm")
                            .font(.system(size: 13))
                    }
                }
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            customWidth = String(format: "%.0f", canvasState.customPaperWidth / 96 * 25.4)
            customHeight = String(format: "%.0f", canvasState.customPaperHeight / 96 * 25.4)
        }
    }
}
