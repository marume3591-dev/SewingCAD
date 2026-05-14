//
//  MeasurementView.swift
//  SewingCAD
//

import SwiftUI
import CoreData

struct MeasurementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Measurement.createdAt, ascending: true)],
        animation: .default)
    private var measurements: FetchedResults<Measurement>

    @State private var showingAddSheet = false
    @State private var selectedMeasurement: Measurement? = nil
    @State private var showingDeleteAlert = false
    @State private var measurementToDelete: Measurement? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("計測テーブル")
                    .font(.headline)
                Spacer()
                Button(action: {
                    showingAddSheet = true
                }) {
                    Image(systemName: "plus")
                }
            }
            .padding(12)

            Divider()

            // リスト
            List(selection: $selectedMeasurement) {
                ForEach(measurements) { measurement in
                    MeasurementRow(measurement: measurement)
                        .tag(measurement)
                }
                .onDelete(perform: deleteMeasurements)
            }
            .listStyle(.inset)
            .onDeleteCommand {
                if let selected = selectedMeasurement {
                    measurementToDelete = selected
                    showingDeleteAlert = true
                }
            }
            .alert("削除の確認", isPresented: $showingDeleteAlert) {
                Button("削除", role: .destructive) {
                    if let m = measurementToDelete,
                       let index = measurements.firstIndex(of: m) {
                        deleteMeasurements(offsets: IndexSet([index]))
                        selectedMeasurement = nil
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("\(measurementToDelete?.name ?? "")を削除しますか？")
            }
            Divider()

            // 選択中の詳細
            if let m = selectedMeasurement {
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.name ?? "")
                        .font(.headline)
                    HStack(spacing: 16) {
                        MeasurementItem(label: "身長", value: m.height)
                        MeasurementItem(label: "バスト", value: m.bust)
                        MeasurementItem(label: "ウエスト", value: m.waist)
                        MeasurementItem(label: "ヒップ", value: m.hip)
                    }
                    if let note = m.note, !note.isEmpty {
                        Text("備考: \(note)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddMeasurementView()
                .environment(\.managedObjectContext, viewContext)
        }
    }

    private func deleteMeasurements(offsets: IndexSet) {
        offsets.map { measurements[$0] }.forEach(viewContext.delete)
        try? viewContext.save()
    }
}

struct MeasurementRow: View {
    let measurement: Measurement
    var body: some View {
        HStack {
            Text(measurement.name ?? "")
                .font(.system(size: 13))
            Spacer()
            Text(String(format: "B%.0f W%.0f H%.0f",
                       measurement.bust,
                       measurement.waist,
                       measurement.hip))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

struct MeasurementItem: View {
    let label: String
    let value: Double
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(String(format: "%.1f", value))
                .font(.system(size: 13))
        }
    }
}

// 追加シート
struct AddMeasurementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var height = ""
    @State private var bust = ""
    @State private var waist = ""
    @State private var hip = ""
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            // タイトル
            HStack {
                Text("計測データを追加")
                    .font(.headline)
                Spacer()
                Button("キャンセル") { dismiss() }
            }
            .padding(16)

            Divider()

            // フォーム
            VStack(spacing: 12) {
                HStack {
                    Text("名前")
                        .frame(width: 80, alignment: .leading)
                    TextField("例：田中さん", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("身長 (cm)")
                        .frame(width: 80, alignment: .leading)
                    TextField("165", text: $height)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("バスト (cm)")
                        .frame(width: 80, alignment: .leading)
                    TextField("90", text: $bust)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("ウエスト (cm)")
                        .frame(width: 80, alignment: .leading)
                    TextField("70", text: $waist)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("ヒップ (cm)")
                        .frame(width: 80, alignment: .leading)
                    TextField("95", text: $hip)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("備考")
                        .frame(width: 80, alignment: .leading)
                    TextField("メモ", text: $note)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(16)

            Divider()

            // 保存ボタン
            HStack {
                Spacer()
                Button("保存") {
                    saveMeasurement()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 380)
    }

    private func saveMeasurement() {
        let m = Measurement(context: viewContext)
        m.name = name
        m.height = Double(height) ?? 0
        m.bust = Double(bust) ?? 0
        m.waist = Double(waist) ?? 0
        m.hip = Double(hip) ?? 0
        m.note = note
        m.createdAt = Date()
        try? viewContext.save()
        dismiss()
    }
}

#Preview {
    MeasurementView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
