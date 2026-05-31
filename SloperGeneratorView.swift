//
//  SloperGeneratorView.swift
//  SewingCAD
//
//  原型自動生成ダイアログ（女性・男性・子供対応）
//

import SwiftUI

struct SloperGeneratorView: View {
    @ObservedObject var projectManager: ProjectManager
    let onGenerate: (SloperResult) -> Void
    let onCancel: () -> Void

    // 対象選択
    @State private var gender: SloperGender = .female
    @State private var childAge: SloperChildAge = .primary

    // 女性用入力
    @State private var bust:       String = "83"
    @State private var waist:      String = "64"
    @State private var hip:        String = "91"
    @State private var height:     String = "158"
    @State private var backLength: String = ""

    // 男性用入力
    @State private var maleChest:      String = "88"
    @State private var maleWaist:      String = "76"
    @State private var maleHip:        String = "90"
    @State private var maleHeight:     String = "170"
    @State private var maleBackLength: String = ""

    // 子供用入力
    @State private var childChest:  String = "60"
    @State private var childWaist:  String = "55"
    @State private var childHip:    String = "64"
    @State private var childHeight: String = "120"

    // 生成オプション
    @State private var genBodice: Bool = true
    @State private var genSleeve: Bool = true
    @State private var genSkirt:  Bool = true

    // 年齢ごとのデフォルト値
    private var childDefaults: (chest: String, waist: String, hip: String, height: String) {
        switch childAge {
        case .infant:  return ("48", "47", "50",  "80")
        case .toddler: return ("54", "51", "57", "100")
        case .primary: return ("64", "57", "68", "130")
        case .junior:  return ("78", "63", "83", "155")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // タイトル
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.accentColor)
                Text("原型自動生成（文化式）")
                    .font(.headline)
                Spacer()
                Button("キャンセル") { onCancel() }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // 対象選択
                    GroupBox("対象") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                genderButton(.female, label: "女性", icon: "figure.stand.dress")
                                genderButton(.male,   label: "男性", icon: "figure.stand")
                                genderButton(.child,  label: "子供", icon: "figure.child")
                            }
                            if gender == .child {
                                HStack {
                                    Text("年齢:")
                                        .font(.system(size: 13))
                                    Picker("", selection: $childAge) {
                                        ForEach(SloperChildAge.allCases, id: \.self) { age in
                                            Text(age.rawValue).tag(age)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .onChange(of: childAge) { _, newAge in
                                        let d = childDefaults
                                        childChest  = d.chest
                                        childWaist  = d.waist
                                        childHip    = d.hip
                                        childHeight = d.height
                                    }
                                }
                            }
                        }
                    }

                    // 採寸入力
                    GroupBox("採寸入力") {
                        VStack(spacing: 10) {
                            switch gender {
                            case .female:
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
                                if let m = femaleMeasurements {
                                    previewRow(m.bust / 2 + 6, m.bust / 8 + 7, m.bust / 8 + 6.2, m.backLength)
                                }

                            case .male:
                                MeasureField(label: "胸囲",     value: $maleChest,      unit: "cm")
                                MeasureField(label: "ウエスト", value: $maleWaist,      unit: "cm")
                                MeasureField(label: "ヒップ",   value: $maleHip,        unit: "cm")
                                MeasureField(label: "身長",     value: $maleHeight,     unit: "cm")
                                HStack {
                                    MeasureField(label: "背丈", value: $maleBackLength, unit: "cm")
                                    Text("（空欄で自動計算）")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                if let m = maleMeasurements {
                                    previewRow(m.chest / 2 + 8, m.chest / 8 + 8.5, m.chest / 8 + 7, m.backLength)
                                }

                            case .child:
                                MeasureField(label: "胸囲",     value: $childChest,  unit: "cm")
                                MeasureField(label: "ウエスト", value: $childWaist,  unit: "cm")
                                MeasureField(label: "ヒップ",   value: $childHip,    unit: "cm")
                                MeasureField(label: "身長",     value: $childHeight, unit: "cm")
                                if let m = childMeasurements {
                                    previewRow(m.chest / 2 + 4, m.chest / 8 + 4.5, m.chest / 8 + 4, m.backLength)
                                }
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
                            if gender != .male {
                                Toggle("下半身（スカート）", isOn: $genSkirt)
                                    .font(.system(size: 13))
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // 注意書き
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                        Text("生成されるパターンは文化式原型の近似値です。生成後にキャンバスで補正してください。")
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
                    guard let result = buildResult() else { return }
                    onGenerate(result)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGenerate)
            }
            .padding(16)
        }
        .frame(width: 440)
    }

    // MARK: - 計測値の変換

    private var femaleMeasurements: SloperMeasurements? {
        guard let b = Double(bust), let w = Double(waist),
              let h = Double(hip),  let ht = Double(height) else { return nil }
        let bl = Double(backLength) ?? Double(SloperMeasurements.estimatedBackLength(height: CGFloat(ht)))
        return SloperMeasurements(bust: CGFloat(b), waist: CGFloat(w), hip: CGFloat(h),
                                  backLength: CGFloat(bl), height: CGFloat(ht))
    }

    private var maleMeasurements: SloperMeasurementsMale? {
        guard let c = Double(maleChest), let w = Double(maleWaist),
              let h = Double(maleHip),   let ht = Double(maleHeight) else { return nil }
        let bl = Double(maleBackLength) ?? Double(SloperMeasurementsMale.estimatedBackLength(height: CGFloat(ht)))
        return SloperMeasurementsMale(chest: CGFloat(c), waist: CGFloat(w), hip: CGFloat(h),
                                      backLength: CGFloat(bl), height: CGFloat(ht))
    }

    private var childMeasurements: SloperMeasurementsChild? {
        guard let c = Double(childChest), let w = Double(childWaist),
              let h = Double(childHip),   let ht = Double(childHeight) else { return nil }
        return SloperMeasurementsChild(chest: CGFloat(c), waist: CGFloat(w), hip: CGFloat(h),
                                       height: CGFloat(ht), age: childAge)
    }

    private var canGenerate: Bool {
        switch gender {
        case .female: return femaleMeasurements != nil && (genBodice || genSleeve || genSkirt)
        case .male:   return maleMeasurements   != nil && (genBodice || genSleeve)
        case .child:  return childMeasurements  != nil && (genBodice || genSleeve || genSkirt)
        }
    }

    private func buildResult() -> SloperResult? {
        let empty = PatternData(points: [], lines: [], curves: [], arcs: [], texts: [],
                                notches: [], seamOverrides: [], gradePoints: [])
        switch gender {
        case .female:
            guard let m = femaleMeasurements else { return nil }
            var r = SloperGenerator.generate(from: m)
            if !genBodice { r.bodiceBack = empty; r.bodiceFront = empty }
            if !genSleeve { r.sleeve = empty }
            if !genSkirt  { r.skirtBack = empty; r.skirtFront = empty }
            return r
        case .male:
            guard let m = maleMeasurements else { return nil }
            var r = SloperGeneratorMale.generate(from: m)
            if !genBodice { r.bodiceBack = empty; r.bodiceFront = empty }
            if !genSleeve { r.sleeve = empty }
            return r
        case .child:
            guard let m = childMeasurements else { return nil }
            var r = SloperGeneratorChild.generate(from: m)
            if !genBodice { r.bodiceBack = empty; r.bodiceFront = empty }
            if !genSleeve { r.sleeve = empty }
            if !genSkirt  { r.skirtBack = empty; r.skirtFront = empty }
            return r
        }
    }

    // MARK: - UI部品

    private func genderButton(_ g: SloperGender, label: String, icon: String) -> some View {
        Button(action: { gender = g }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 12))
            }
            .frame(width: 80, height: 56)
            .background(gender == g ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(gender == g ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func previewRow(_ mihaaba: CGFloat, _ sehaaba: CGFloat,
                             _ munehaaba: CGFloat, _ bl: CGFloat) -> some View {
        HStack(spacing: 16) {
            previewItem("身幅", value: mihaaba)
            previewItem("背幅", value: sehaaba)
            previewItem("胸幅", value: munehaaba)
            previewItem("背丈", value: bl)
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(6)
    }

    private func previewItem(_ label: String, value: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            Text(String(format: "%.1f", value)).font(.system(size: 12, weight: .medium))
        }
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
