//
//  SloperGeneratorView.swift
//  SewingCAD
//
//  原型自動生成ダイアログ
//

import SwiftUI

struct SloperGeneratorView: View {
    @ObservedObject var projectManager: ProjectManager
    let onGenerate: (SloperResult) -> Void
    let onCancel: () -> Void

    // 計測値の入力
    @State private var bust:       String = "83"
    @State private var waist:      String = "64"
    @State private var hip:        String = "91"
    @State private var height:     String = "158"
    @State private var backLength: String = ""   // 空欄なら自動計算

    // 生成オプション
    @State private var genBodice: Bool = true
    @State private var genSleeve: Bool = true
    @State private var genSkirt:  Bool = true

    private var measurements: SloperMeasurements? {
        guard let b = Double(bust), let w = Double(waist),
              let h = Double(hip),  let ht = Double(height) else { return nil }
        let bl = Double(backLength) ?? Double(SloperMeasurements.estimatedBackLength(height: CGFloat(ht)))
        return SloperMeasurements(
            bust: CGFloat(b), waist: CGFloat(w), hip: CGFloat(h),
            backLength: CGFloat(bl), height: CGFloat(ht)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // タイトル
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.accentColor)
                Text("原型自動生成（新文化式）")
                    .font(.headline)
                Spacer()
                Button("キャンセル") { onCancel() }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // 採寸入力
                    GroupBox("採寸入力") {
                        VStack(spacing: 10) {
                            MeasureField(label: "バスト",   value: $bust,       unit: "cm")
                            MeasureField(label: "ウエスト", value: $waist,      unit: "cm")
                            MeasureField(label: "ヒップ",   value: $hip,        unit: "cm")
                            MeasureField(label: "身長",     value: $height,     unit: "cm")
                            HStack {
                                MeasureField(label: "背丈", value: $backLength, unit: "cm")
                                Text("（空欄で自動計算）")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            // 自動計算プレビュー
                            if let m = measurements {
                                HStack(spacing: 16) {
                                    previewItem("身幅", value: m.bust / 2 + 6.0)
                                    previewItem("背幅", value: m.bust / 8 + 7.0)
                                    previewItem("胸幅", value: m.bust / 8 + 6.2)
                                    previewItem("背丈", value: m.backLength)
                                }
                                .padding(8)
                                .background(Color.accentColor.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                    }

                    // 生成パーツ選択
                    GroupBox("生成するパーツ") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("上半身（後ろ身頃・前身頃）", isOn: $genBodice)
                                .font(.system(size: 13))
                            Toggle("袖", isOn: $genSleeve)
                                .font(.system(size: 13))
                            Toggle("下半身（後ろスカート・前スカート）", isOn: $genSkirt)
                                .font(.system(size: 13))
                        }
                        .padding(.vertical, 4)
                    }

                    // 注意書き
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                        Text("生成されるパターンは新文化式原型の近似値です。実際の型紙と差異が出る場合があります。生成後にキャンバスで補正してください。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }

            Divider()

            // 生成ボタン
            HStack {
                Spacer()
                Button("生成する") {
                    guard let m = measurements else { return }
                    var result = SloperGenerator.generate(from: m)
                    // 不要なパーツを空にする
                    if !genBodice {
                        result = SloperResult(
                            bodiceBack: emptyPattern(), bodiceFront: emptyPattern(),
                            sleeve: result.sleeve, skirtBack: result.skirtBack, skirtFront: result.skirtFront)
                    }
                    if !genSleeve {
                        result = SloperResult(
                            bodiceBack: result.bodiceBack, bodiceFront: result.bodiceFront,
                            sleeve: emptyPattern(), skirtBack: result.skirtBack, skirtFront: result.skirtFront)
                    }
                    if !genSkirt {
                        result = SloperResult(
                            bodiceBack: result.bodiceBack, bodiceFront: result.bodiceFront,
                            sleeve: result.sleeve, skirtBack: emptyPattern(), skirtFront: emptyPattern())
                    }
                    onGenerate(result)
                }
                .buttonStyle(.borderedProminent)
                .disabled(measurements == nil || (!genBodice && !genSleeve && !genSkirt))
            }
            .padding(16)
        }
        .frame(width: 420)
        // 計測テーブルから値を読み込む
        .onAppear { loadFromMeasurement() }
    }

    private func loadFromMeasurement() {
        // ProjectManagerから現在選択中の計測データがあれば自動入力
        // （今後の拡張ポイント）
    }

    private func previewItem(_ label: String, value: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            Text(String(format: "%.1f", value)).font(.system(size: 12, weight: .medium))
        }
    }

    private func emptyPattern() -> PatternData {
        PatternData(points: [], lines: [], curves: [], arcs: [], texts: [],
                    notches: [], seamOverrides: [], gradePoints: [])
    }
}

// MARK: - 採寸入力フィールド

struct MeasureField: View {
    let label: String
    @Binding var value: String
    let unit: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 70, alignment: .leading)
            TextField("", text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .font(.system(size: 13))
            Text(unit)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
}
