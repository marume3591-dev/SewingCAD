//
//  GradingView.swift
//  SewingCAD
//

import SwiftUI

struct GradingView: View {
    @ObservedObject var canvasState: CanvasState
    let selectedPoint: PatternPoint?

    @State private var newSizeName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("グレーディング")
                .font(.headline)

            Divider()

            // サイズ一覧
            VStack(alignment: .leading, spacing: 6) {
                Text("サイズ").font(.subheadline).foregroundColor(.secondary)
                HStack {
                    ForEach(canvasState.gradingSizes, id: \.self) { size in
                        Button(action: { canvasState.activeGradeSize = size }) {
                            Text(size)
                                .font(.system(size: 12, weight: canvasState.activeGradeSize == size ? .bold : .regular))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(canvasState.activeGradeSize == size ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("新サイズ名", text: $newSizeName).textFieldStyle(.roundedBorder).frame(width: 80)
                    Button("追加") {
                        if !newSizeName.isEmpty && !canvasState.gradingSizes.contains(newSizeName) {
                            canvasState.gradingSizes.append(newSizeName)
                            newSizeName = ""
                        }
                    }.buttonStyle(.bordered).font(.system(size: 12))
                }
            }

            Divider()

            // 選択中の点のオフセット設定
            if let point = selectedPoint {
                VStack(alignment: .leading, spacing: 8) {
                    Text("点: \(point.name)")
                        .font(.subheadline).foregroundColor(.secondary)
                    Text("基準: \(canvasState.activeGradeSize)")
                        .font(.system(size: 11)).foregroundColor(.secondary)

                    ForEach(canvasState.gradingSizes.filter { $0 != canvasState.activeGradeSize }, id: \.self) { size in
                        let binding = gradeBinding(pointID: point.id, size: size)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(size)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(gradeColor(size))
                            HStack(spacing: 4) {
                                Text("ΔX:").font(.system(size: 11)).frame(width: 24, alignment: .trailing)
                                TextField("0", text: binding.dx)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                Text("cm").font(.system(size: 11))
                            }
                            HStack(spacing: 4) {
                                Text("ΔY:").font(.system(size: 11)).frame(width: 24, alignment: .trailing)
                                TextField("0", text: binding.dy)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                Text("cm").font(.system(size: 11))
                            }
                        }
                        .padding(6)
                        .background(gradeColor(size).opacity(0.05))
                        .cornerRadius(6)
                    }
                }
            } else {
                Text("グレーディングツールで\n点を選択してください")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    // MARK: - オフセットバインディング
    private func gradeBinding(pointID: UUID, size: String) -> (dx: Binding<String>, dy: Binding<String>) {
        let dx = Binding<String>(
            get: {
                let v = canvasState.gradePoints.first(where: { $0.pointID == pointID && $0.sizeName == size })?.dx ?? 0
                return String(format: "%.1f", v)
            },
            set: { newVal in
                if let v = Double(newVal) {
                    setGrade(pointID: pointID, size: size, dx: CGFloat(v), dy: nil)
                }
            }
        )
        let dy = Binding<String>(
            get: {
                let v = canvasState.gradePoints.first(where: { $0.pointID == pointID && $0.sizeName == size })?.dy ?? 0
                return String(format: "%.1f", v)
            },
            set: { newVal in
                if let v = Double(newVal) {
                    setGrade(pointID: pointID, size: size, dx: nil, dy: CGFloat(v))
                }
            }
        )
        return (dx, dy)
    }

    private func setGrade(pointID: UUID, size: String, dx: CGFloat?, dy: CGFloat?) {
        if let index = canvasState.gradePoints.firstIndex(where: { $0.pointID == pointID && $0.sizeName == size }) {
            if let dx = dx { canvasState.gradePoints[index].dx = dx }
            if let dy = dy { canvasState.gradePoints[index].dy = dy }
        } else {
            canvasState.gradePoints.append(GradePoint(
                pointID: pointID, sizeName: size,
                dx: dx ?? 0, dy: dy ?? 0
            ))
        }
    }

    private func gradeColor(_ size: String) -> Color {
        let colors: [Color] = [.red, .green, .orange, .purple, .pink]
        let index = (canvasState.gradingSizes.firstIndex(of: size) ?? 0) % colors.count
        return colors[index]
    }
}
