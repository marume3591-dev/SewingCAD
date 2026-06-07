//
//  MeasurementDetailView.swift
//  SewingCAD
//

import SwiftUI
import CoreData

// MARK: - 重要項目（色付き表示）

let highlightedFieldIDs: Set<Int> = [1, 3, 5, 15, 21, 25, 28, 29]

// MARK: - 計測項目定義

struct MeasurementField: Identifiable {
    let id: Int
    let name: String
    let unit: String
    let category: MeasurementCategory
    let description: String
}

enum MeasurementCategory: String, CaseIterable {
    case circumference = "回り寸法"
    case width         = "幅寸法"
    case length        = "丈寸法"
    case other         = "他"
}

let allMeasurementFields: [MeasurementField] = [
    MeasurementField(id:  0, name: "ハイバスト回り",      unit: "cm", category: .circumference, description: "脇の下・胸上部を通る周径（欧米ブラサイズのバンド基準）"),
    MeasurementField(id:  1, name: "バスト回り",          unit: "cm", category: .circumference, description: "バストポイントを通る水平な周径"),
    MeasurementField(id:  2, name: "アンダーバスト回り",  unit: "cm", category: .circumference, description: "アンダーバスト（乳房下縁位）を通る水平な周径"),
    MeasurementField(id:  3, name: "ウエスト回り",        unit: "cm", category: .circumference, description: "胴の細い位置でウエストベルトのおさまりのよい水平な周径"),
    MeasurementField(id:  4, name: "ミドルヒップ回り",    unit: "cm", category: .circumference, description: "ウエストとヒップの中央位置の水平な周径"),
    MeasurementField(id:  5, name: "ヒップ回り",          unit: "cm", category: .circumference, description: "臀部の最も突出した位置を通る水平な周径"),
    MeasurementField(id:  6, name: "腕つけ根回り",        unit: "cm", category: .circumference, description: "前腋点・ショルダーポイント・後腋点を通る周径"),
    MeasurementField(id:  7, name: "上腕回り",            unit: "cm", category: .circumference, description: "上腕の最も太い位置の周径"),
    MeasurementField(id:  8, name: "肘回り",              unit: "cm", category: .circumference, description: "肘点を通る肘の最も太い位置の周径"),
    MeasurementField(id:  9, name: "手首回り",            unit: "cm", category: .circumference, description: "手首点を通る手首の最も太い位置の周径"),
    MeasurementField(id: 10, name: "手のひら回り",        unit: "cm", category: .circumference, description: "親指を手のひらに軽くつけ指のつけ根の最も太い位置の周径"),
    MeasurementField(id: 11, name: "頭回り",              unit: "cm", category: .circumference, description: "眉間点を通り後頭部の最も突出した位置を通る周径"),
    MeasurementField(id: 12, name: "首つけ根回り",        unit: "cm", category: .circumference, description: "バックネック・サイドネック・フロントネックポイントを通る周径"),
    MeasurementField(id: 13, name: "大腿回り",            unit: "cm", category: .circumference, description: "臀溝の下で大腿の最も太い位置の周径"),
    MeasurementField(id: 14, name: "下腿回り",            unit: "cm", category: .circumference, description: "ふくらはぎの最も太い位置の周径"),
    MeasurementField(id: 15, name: "背肩幅",              unit: "cm", category: .width,         description: "左ショルダーポイントからバックネックを通り右ショルダーポイントまでの長さ"),
    MeasurementField(id: 16, name: "背幅",                unit: "cm", category: .width,         description: "左の後腋点から右の後腋点までの体表の長さ"),
    MeasurementField(id: 17, name: "胸幅",                unit: "cm", category: .width,         description: "左の前腋点から右の前腋点までの体表の長さ"),
    MeasurementField(id: 18, name: "バストポイント間隔",  unit: "cm", category: .width,         description: "左右のバストポイント間の長さ"),
    MeasurementField(id: 19, name: "身長",                unit: "cm", category: .length,        description: "頭頂点から床面までの長さ"),
    MeasurementField(id: 20, name: "総丈",                unit: "cm", category: .length,        description: "バックネックポイントから床面までの長さ"),
    MeasurementField(id: 21, name: "背丈",                unit: "cm", category: .length,        description: "後ろ正中でバックネックポイントからウエストまでの長さ"),
    MeasurementField(id: 22, name: "後ろ丈",              unit: "cm", category: .length,        description: "サイドネックポイントから肩甲骨の突出点を通りウエストまでの長さ"),
    MeasurementField(id: 23, name: "乳下り",              unit: "cm", category: .length,        description: "サイドネックポイントからバストポイントまでの長さ"),
    MeasurementField(id: 24, name: "前丈",                unit: "cm", category: .length,        description: "サイドネックポイントからバストポイントを通りウエストまでの長さ"),
    MeasurementField(id: 25, name: "袖丈",                unit: "cm", category: .length,        description: "ショルダーポイントから手首点までの長さ"),
    MeasurementField(id: 26, name: "ウエスト高",          unit: "cm", category: .length,        description: "ウエストから床面までの長さ"),
    MeasurementField(id: 27, name: "ヒップ高",            unit: "cm", category: .length,        description: "臀突点から床面までの長さ"),
    MeasurementField(id: 28, name: "腰丈",                unit: "cm", category: .length,        description: "ウエスト高からヒップ高を引いた長さ"),
    MeasurementField(id: 29, name: "股上丈",              unit: "cm", category: .length,        description: "ウエスト高から股下丈を引いた長さ"),
    MeasurementField(id: 30, name: "股下丈",              unit: "cm", category: .length,        description: "股の位置から床面までの長さ"),
    MeasurementField(id: 31, name: "膝丈",                unit: "cm", category: .length,        description: "前面でウエストから膝蓋骨の下縁までの長さ"),
    MeasurementField(id: 32, name: "股上前後長",          unit: "cm", category: .other,         description: "前ウエストから股をくぐらせ後ろウエストまでの長さ"),
    MeasurementField(id: 33, name: "体重",                unit: "kg", category: .other,         description: "計測用下着着用での身体の重さ"),
]

// MARK: - カップサイズ計算

struct BraSize {
    let bandSize: Int
    let cupLabel: String
    var jpSize: String { "\(bandSize)\(cupLabel)" }

    static func calculate(highBust: Double, bust: Double) -> BraSize? {
        guard highBust > 0, bust > 0 else { return nil }
        let band = Int(round(highBust / 5) * 5)
        let diff = bust - highBust
        let cup: String
        switch diff {
        case ..<7.5:    cup = "AA"
        case 7.5..<10:  cup = "A"
        case 10..<12.5: cup = "B"
        case 12.5..<15: cup = "C"
        case 15..<17.5: cup = "D"
        case 17.5..<20: cup = "E"
        case 20..<22.5: cup = "F"
        case 22.5..<25: cup = "G"
        default:        cup = "H以上"
        }
        return BraSize(bandSize: band, cupLabel: cup)
    }
}

// MARK: - メインビュー

struct MeasurementDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MeasurementProfile.createdAt, ascending: true)],
        animation: .default)
    private var profiles: FetchedResults<MeasurementProfile>

    @State private var selectedProfile: MeasurementProfile? = nil
    @State private var showingAddProfile = false
    @State private var showingDeleteAlert = false
    @State private var profileToDelete: MeasurementProfile? = nil

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("計測テーブル").font(.headline)
                Spacer()
                Button(action: { showingAddProfile = true }) {
                    Image(systemName: "plus")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            if profiles.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 36)).foregroundColor(.secondary)
                    Text("「+」ボタンで人物を追加してください")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VSplitView {
                    // 人物リスト（上）
                    List(selection: $selectedProfile) {
                        ForEach(profiles) { profile in
                            profileRow(profile).tag(profile)
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 80, maxHeight: 160)

                    // 計測データ（下）
                    if let profile = selectedProfile {
                        MeasurementEntryEditor(profile: profile)
                    } else {
                        VStack {
                            Spacer()
                            Text("上のリストから人物を選択してください")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddProfile) {
            AddProfileView().environment(\.managedObjectContext, viewContext)
        }
        .alert("削除の確認", isPresented: $showingDeleteAlert) {
            Button("削除", role: .destructive) {
                if let p = profileToDelete {
                    viewContext.delete(p)
                    try? viewContext.save()
                    if selectedProfile == p { selectedProfile = nil }
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(profileToDelete?.name ?? "")を削除しますか？")
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: MeasurementProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name ?? "").font(.system(size: 12, weight: .medium))
                Text(profile.summaryText).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { profileToDelete = profile; showingDeleteAlert = true }) {
                Image(systemName: "trash").font(.system(size: 10)).foregroundColor(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 計測項目エディタ

struct MeasurementEntryEditor: View {
    @ObservedObject var profile: MeasurementProfile
    @Environment(\.managedObjectContext) private var viewContext

    // ウィンドウを開くたびに回り寸法からスタート
    @State private var selectedCategory: MeasurementCategory = .circumference

    // 即時反映のためにローカルキャッシュを持つ
    @State private var localValues: [Int: Double] = [:]

    private var braSize: BraSize? {
        BraSize.calculate(
            highBust: localValues[0] ?? profile.value(for: 0),
            bust:     localValues[1] ?? profile.value(for: 1)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // プロフィールヘッダー
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name ?? "").font(.system(size: 14, weight: .bold))
                    if let note = profile.note, !note.isEmpty {
                        Text(note).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let bra = braSize {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("ブラサイズ").font(.system(size: 9)).foregroundColor(.secondary)
                        Text(bra.jpSize)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            // サンプルデータボタン
            HStack(spacing: 6) {
                Text("サンプル:").font(.system(size: 11)).foregroundColor(.secondary)
                ForEach(SampleBodyData.all, id: \.label) { sample in
                    Button(action: {
                        // ローカルキャッシュに即時反映
                        for (fieldID, value) in sample.values {
                            localValues[fieldID] = value
                            profile.setValue(value, for: fieldID)
                        }
                        try? viewContext.save()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: sample.icon).font(.system(size: 11))
                            Text(sample.label).font(.system(size: 11))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: {
                    for field in allMeasurementFields {
                        localValues[field.id] = 0
                        profile.setValue(0, for: field.id)
                    }
                    try? viewContext.save()
                }) {
                    Text("クリア").font(.system(size: 11)).foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)

            Divider()

            // カテゴリタブ
            Picker("", selection: $selectedCategory) {
                ForEach(MeasurementCategory.allCases, id: \.self) { cat in
                    Text(cat.rawValue).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10).padding(.vertical, 6)

            Divider()

            // 項目リスト
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(allMeasurementFields.filter { $0.category == selectedCategory }) { field in
                        MeasurementFieldRow(
                            profile: profile,
                            field: field,
                            localValues: $localValues
                        )
                        Divider().padding(.leading, 10)
                    }
                }
            }

            Divider()

            HStack {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("フィールドからカーソルを外すと自動保存されます")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .onAppear {
            // 表示時に全値をローカルキャッシュに読み込む
            selectedCategory = .circumference
            for field in allMeasurementFields {
                localValues[field.id] = profile.value(for: field.id)
            }
        }
        .onChange(of: profile) { _, newProfile in
            selectedCategory = .circumference
            localValues = [:]
            for field in allMeasurementFields {
                localValues[field.id] = newProfile.value(for: field.id)
            }
        }
    }
}

// MARK: - 1項目の入力行

struct MeasurementFieldRow: View {
    @ObservedObject var profile: MeasurementProfile
    let field: MeasurementField
    @Binding var localValues: [Int: Double]
    @Environment(\.managedObjectContext) private var viewContext
    @FocusState private var isFocused: Bool

    private var isHighlighted: Bool { highlightedFieldIDs.contains(field.id) }

    // テキストフィールドの文字列はローカルキャッシュから生成
    private var displayText: String {
        let v = localValues[field.id] ?? 0
        return v > 0 ? String(format: "%.1f", v) : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // No.バッジ
                Text(String(format: "%02d", field.id))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(isHighlighted ? Color.accentColor : Color.secondary.opacity(0.5))
                    .cornerRadius(3)

                // 項目名
                Text(field.name)
                    .font(.system(size: 13, weight: isHighlighted ? .semibold : .regular))
                    .foregroundColor(isHighlighted ? .accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 入力欄
                TextField("—", text: Binding(
                    get: { displayText },
                    set: { newText in
                        if let v = Double(newText) {
                            localValues[field.id] = v
                        } else if newText.isEmpty {
                            localValues[field.id] = 0
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        // フォーカスが外れたらCoreDataに保存
                        let v = localValues[field.id] ?? 0
                        profile.setValue(v, for: field.id)
                        try? viewContext.save()
                    }
                }

                Text(field.unit)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }

            // 説明文
            Text(field.description)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(isHighlighted
                    ? Color.accentColor.opacity(0.06)
                    : (localValues[field.id] ?? 0) > 0 ? Color.clear : Color.clear)
    }
}

// MARK: - プロフィール追加シート

struct AddProfileView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("人物を追加").font(.headline)
                Spacer()
                Button("キャンセル") { dismiss() }
            }
            .padding(16)
            Divider()
            VStack(spacing: 12) {
                HStack {
                    Text("名前").frame(width: 60, alignment: .leading)
                    TextField("例：田中さん", text: $name).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("備考").frame(width: 60, alignment: .leading)
                    TextField("メモ", text: $note).textFieldStyle(.roundedBorder)
                }
            }
            .padding(16)
            Divider()
            HStack {
                Spacer()
                Button("追加") {
                    let p = MeasurementProfile(context: viewContext)
                    p.id = UUID(); p.name = name; p.note = note; p.createdAt = Date()
                    try? viewContext.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent).disabled(name.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 340)
    }
}

// MARK: - MeasurementProfile 拡張

extension MeasurementProfile {
    func value(for fieldID: Int) -> Double {
        guard let entries = entries as? Set<MeasurementEntry> else { return 0 }
        return entries.first(where: { $0.fieldID == Int16(fieldID) })?.value ?? 0
    }

    func setValue(_ value: Double, for fieldID: Int) {
        guard let ctx = managedObjectContext else { return }
        if let entries = entries as? Set<MeasurementEntry>,
           let existing = entries.first(where: { $0.fieldID == Int16(fieldID) }) {
            existing.value = value
        } else {
            let entry = MeasurementEntry(context: ctx)
            entry.fieldID = Int16(fieldID)
            entry.value   = value
            entry.profile = self
        }
    }

    var summaryText: String {
        let b  = value(for: 1)
        let w  = value(for: 3)
        let h  = value(for: 5)
        let ht = value(for: 19)
        var parts: [String] = []
        if ht > 0 { parts.append(String(format: "%.0fcm", ht)) }
        if b  > 0 { parts.append(String(format: "B%.0f", b)) }
        if w  > 0 { parts.append(String(format: "W%.0f", w)) }
        if h  > 0 { parts.append(String(format: "H%.0f", h)) }
        return parts.isEmpty ? "未入力" : parts.joined(separator: " ")
    }
}

// MARK: - サンプルデータ定義

struct SampleBodyData {
    let label: String
    let icon: String
    let values: [Int: Double]

    static let female = SampleBodyData(
        label: "女性平均", icon: "figure.stand.dress",
        values: [
             0: 80.0,  1: 83.0,  2: 72.0,  3: 64.0,  4: 87.0,
             5: 91.0,  6: 38.0,  7: 27.0,  8: 23.0,  9: 15.5,
            10: 19.0, 11: 55.0, 12: 36.0, 13: 52.0, 14: 34.0,
            15: 38.0, 16: 33.0, 17: 31.0, 18: 18.0, 19: 158.0,
            20: 133.0, 21: 38.0, 22: 40.0, 23: 24.0, 24: 42.0,
            25: 52.0, 26: 93.0, 27: 78.0, 28: 20.0, 29: 27.0,
            30: 68.0, 31: 57.0, 32: 68.0, 33: 54.0,
        ]
    )

    static let male = SampleBodyData(
        label: "男性平均", icon: "figure.stand",
        values: [
             0: 93.0,  1: 92.0,  2: 84.0,  3: 79.0,  4: 90.0,
             5: 94.0,  6: 44.0,  7: 32.0,  8: 27.0,  9: 17.0,
            10: 22.0, 11: 57.0, 12: 40.0, 13: 57.0, 14: 37.0,
            15: 44.0, 16: 38.0, 17: 36.0, 18: 20.0, 19: 171.0,
            20: 145.0, 21: 44.0, 22: 46.0, 23: 26.0, 24: 46.0,
            25: 58.0, 26: 101.0, 27: 85.0, 28: 22.0, 29: 30.0,
            30: 74.0, 31: 63.0, 32: 74.0, 33: 67.0,
        ]
    )

    static let child = SampleBodyData(
        label: "子供(7歳)", icon: "figure.child",
        values: [
             0: 60.0,  1: 61.0,  2: 56.0,  3: 54.0,  4: 62.0,
             5: 65.0,  6: 27.0,  7: 18.0,  8: 15.0,  9: 12.0,
            10: 14.0, 11: 52.0, 12: 27.0, 13: 36.0, 14: 24.0,
            15: 28.0, 16: 24.0, 17: 22.0, 18: 13.0, 19: 122.0,
            20: 101.0, 21: 28.0, 22: 30.0, 23: 18.0, 24: 30.0,
            25: 38.0, 26: 69.0, 27: 58.0, 28: 14.0, 29: 20.0,
            30: 50.0, 31: 42.0, 32: 52.0, 33: 22.0,
        ]
    )

    static let all: [SampleBodyData] = [.female, .male, .child]
}
